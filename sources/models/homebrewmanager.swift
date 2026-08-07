import Foundation
import Combine
import JuicerKit

@MainActor
final class HomebrewManager: ObservableObject {
    @Published private(set) var brewPath: String?
    @Published private(set) var packages: [BrewStorePackage] = []
    @Published private(set) var services: [BrewStoreService] = []
    @Published private(set) var taps: [BrewStoreTap] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isOperating = false
    @Published private(set) var isBootstrapping = false
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var outputLog = ""

    private let executor: CommandExecutor

    init(executor: CommandExecutor = .shared) {
        self.executor = executor
        detectHomebrew()
    }

    var isAvailable: Bool { brewPath != nil }

    func detectHomebrew() {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".linuxbrew/bin/brew").path
        ]
        brewPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    func refresh() {
        detectHomebrew()
        guard let brewPath else {
            errorMessage = nil
            statusMessage = "Homebrew is not installed."
            return
        }

        guard !isLoading, !isOperating else { return }
        isLoading = true
        errorMessage = nil
        statusMessage = "Refreshing Homebrew data…"

        Task.detached(priority: .userInitiated) { [executor, brewPath] in
            let installedCasks = Self.parseInstalledIDs(executor.run(executablePath: brewPath, arguments: ["list", "--cask", "--versions"]).standardOutput)
            let installedFormulae = Self.parseInstalledIDs(executor.run(executablePath: brewPath, arguments: ["list", "--formula", "--versions"]).standardOutput)
            let outdated = executor.run(executablePath: brewPath, arguments: ["outdated", "--json=v2"]).standardOutput.data(using: .utf8) ?? Data()
            let caskOutdated = HomebrewJSONParser.identifiers(fromOutdated: outdated, kind: .cask)
            let formulaOutdated = HomebrewJSONParser.identifiers(fromOutdated: outdated, kind: .formula)
            let casks = executor.run(executablePath: brewPath, arguments: ["info", "--json=v2", "--cask"], timeout: 90)
            let formulae = executor.run(executablePath: brewPath, arguments: ["info", "--json=v2", "--formula"], timeout: 90)
            let serviceResult = executor.run(executablePath: brewPath, arguments: ["services", "list", "--json"])
            let tapResult = executor.run(executablePath: brewPath, arguments: ["tap"])

            let caskPackages = HomebrewJSONParser.packages(from: Data(casks.standardOutput.utf8), kind: .cask, installedIDs: installedCasks, outdatedIDs: caskOutdated)
            let formulaPackages = HomebrewJSONParser.packages(from: Data(formulae.standardOutput.utf8), kind: .formula, installedIDs: installedFormulae, outdatedIDs: formulaOutdated)
            let allResults = [casks, formulae, serviceResult, tapResult]
            let failed = allResults.first(where: { !$0.succeeded })

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.packages = caskPackages + formulaPackages
                self.services = HomebrewJSONParser.services(from: Data(serviceResult.standardOutput.utf8))
                self.taps = HomebrewJSONParser.taps(from: tapResult.standardOutput)
                self.isLoading = false
                if let failed, self.packages.isEmpty {
                    self.errorMessage = failed.standardError.isEmpty ? "Homebrew returned an unexpected response." : failed.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.statusMessage = "Refresh failed."
                } else {
                    self.statusMessage = "Updated \(self.packages.count) packages."
                }
            }
        }
    }

    func perform(package: BrewStorePackage, action: PackageAction, completion: ((Bool) -> Void)? = nil) {
        guard let brewPath, !isOperating else { return }
        isOperating = true
        errorMessage = nil
        statusMessage = "Running \(action.title.lowercased()) for \(package.name)…"
        let arguments: [String]
        switch action {
        case .install: arguments = ["install", package.kind.brewFlag, package.id]
        case .upgrade: arguments = ["upgrade", package.kind.brewFlag, package.id]
        case .uninstall: arguments = ["uninstall", package.kind.brewFlag, package.id]
        }

        Task.detached(priority: .userInitiated) { [executor, brewPath, arguments, action, packageName = package.name] in
            let result = executor.run(executablePath: brewPath, arguments: arguments, timeout: 900, category: action == .uninstall ? .destructiveMutation : .reversibleMutation)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isOperating = false
                if result.succeeded {
                    self.statusMessage = "Completed \(action.title.lowercased()) for \(packageName)."
                    self.refresh()
                } else {
                    self.errorMessage = result.standardError.isEmpty ? "Homebrew could not complete the operation." : result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.statusMessage = "Operation failed."
                }
                completion?(result.succeeded)
            }
        }
    }

    func perform(service: BrewStoreService, action: ServiceAction) {
        guard let brewPath, !isOperating else { return }
        isOperating = true
        let arguments = ["services", action.rawValue, service.name]
        Task.detached(priority: .userInitiated) { [executor, brewPath, arguments] in
            let result = executor.run(executablePath: brewPath, arguments: arguments, timeout: 120, category: .reversibleMutation)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isOperating = false
                self.statusMessage = result.succeeded ? "Service operation completed." : "Service operation failed."
                self.errorMessage = result.succeeded ? nil : result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.succeeded { self.refresh() }
            }
        }
    }

    func addTap(_ name: String) {
        runTapCommand(["tap", name])
    }

    func removeTap(_ tap: BrewStoreTap) {
        runTapCommand(["untap", tap.name])
    }

    func bootstrapHomebrew() {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        statusMessage = "Running the official Homebrew installer…"
        errorMessage = nil
        outputLog = ""

        // The URL and command are fixed application constants; no user-provided value enters the shell.
        let script = "NONINTERACTIVE=1 /bin/bash -c \"$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        Task.detached(priority: .userInitiated) { [executor] in
            let result = executor.run(executablePath: "/bin/bash", arguments: ["-c", script], timeout: 1_800, category: .privilegedOrUnsupported, maximumOutputBytes: 2_000_000)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isBootstrapping = false
                self.outputLog = [result.standardOutput, result.standardError]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                if result.succeeded {
                    self.detectHomebrew()
                    self.statusMessage = self.isAvailable ? "Homebrew is ready." : "Installation finished. Restart BrewStore if Homebrew is not detected yet."
                } else {
                    self.errorMessage = result.standardError.isEmpty ? "Homebrew installation did not complete." : result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.statusMessage = "Homebrew installation failed."
                }
            }
        }
    }

    private func runTapCommand(_ arguments: [String]) {
        guard let brewPath, !isOperating else { return }
        isOperating = true
        Task.detached(priority: .userInitiated) { [executor, brewPath, arguments] in
            let result = executor.run(executablePath: brewPath, arguments: arguments, timeout: 300, category: .reversibleMutation)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isOperating = false
                self.errorMessage = result.succeeded ? nil : result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                self.statusMessage = result.succeeded ? "Tap operation completed." : "Tap operation failed."
                if result.succeeded { self.refresh() }
            }
        }
    }

    nonisolated private static func parseInstalledIDs(_ output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { line in
            let value = line.split(separator: " ").first.map(String.init)
            return value?.isEmpty == false ? value : nil
        })
    }
}

enum PackageAction: Equatable {
    case install
    case upgrade
    case uninstall

    var title: String {
        switch self {
        case .install: return "Install"
        case .upgrade: return "Upgrade"
        case .uninstall: return "Uninstall"
        }
    }
}

enum ServiceAction: String {
    case start
    case stop
    case restart
}
