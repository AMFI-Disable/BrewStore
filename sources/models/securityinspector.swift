import Foundation

enum BinaryArchitectureType: String, Hashable, Codable {
    case universal2 = "Universal 2 (Apple Silicon & Intel)"
    case appleSilicon = "Apple Silicon Native (arm64)"
    case intel = "Intel x86_64 (Rosetta 2)"
    case unknown = "CLI Script / Unknown"

    var badgeColor: String {
        switch self {
        case .appleSilicon, .universal2: "green"
        case .intel: "orange"
        case .unknown: "secondary"
        }
    }
}

struct PackageSecurityReport: Identifiable, Hashable {
    let id: String // package id
    let architecture: BinaryArchitectureType
    let architectureDetail: String
    let codeSignAuthority: String
    let isHardenedRuntime: Bool
    let isQuarantined: Bool
    let targetPath: String?
}

@MainActor
final class BrewStoreSecurityInspector: ObservableObject {
    @Published var report: PackageSecurityReport?
    @Published var isInspecting = false
    @Published var statusMessage: String?

    func inspect(package: BrewStorePackage, manager _: HomebrewManager) {
        isInspecting = true
        statusMessage = nil

        Task.detached(priority: .userInitiated) { [package] in
            var targetPath: String?

            if package.kind == .cask {
                for name in package.applicationNames {
                    let path = "/Applications/\(name).app"
                    if FileManager.default.fileExists(atPath: path) {
                        targetPath = path
                        break
                    }
                }
                if targetPath == nil {
                    let fallback = "/Applications/\(package.name).app"
                    if FileManager.default.fileExists(atPath: fallback) {
                        targetPath = fallback
                    }
                }
            } else {
                // Formula binary
                let path = "/opt/homebrew/bin/\(package.name)"
                if FileManager.default.fileExists(atPath: path) {
                    targetPath = path
                } else {
                    let usrPath = "/usr/local/bin/\(package.name)"
                    if FileManager.default.fileExists(atPath: usrPath) {
                        targetPath = usrPath
                    }
                }
            }

            guard let validPath = targetPath else {
                await MainActor.run { [weak self] in
                    self?.report = PackageSecurityReport(
                        id: package.id,
                        architecture: .unknown,
                        architectureDetail: "Application or binary not found in standard system paths.",
                        codeSignAuthority: "Not installed locally",
                        isHardenedRuntime: false,
                        isQuarantined: false,
                        targetPath: nil
                    )
                    self?.isInspecting = false
                }
                return
            }

            // 1. Inspect Architecture with /usr/bin/file
            let fileResult = BrewStoreCommandExecutor.shared.run(
                executablePath: "/usr/bin/file",
                arguments: ["-b", validPath],
                timeout: 10,
                category: .readOnly
            )
            let fileOutput = fileResult.standardOutput

            var arch: BinaryArchitectureType = .unknown
            if fileOutput.contains("arm64") && fileOutput.contains("x86_64") {
                arch = .universal2
            } else if fileOutput.contains("arm64") {
                arch = .appleSilicon
            } else if fileOutput.contains("x86_64") {
                arch = .intel
            }

            // 2. Inspect Codesign with /usr/bin/codesign
            let signResult = BrewStoreCommandExecutor.shared.run(
                executablePath: "/usr/bin/codesign",
                arguments: ["-dv", "--verbose=2", validPath],
                timeout: 10,
                category: .readOnly
            )
            let signOutput = signResult.standardError.isEmpty ? signResult.standardOutput : signResult.standardError

            var authority = "Ad-Hoc / Self-Signed"
            var hardened = false
            for line in signOutput.components(separatedBy: .newlines) {
                if line.contains("Authority=") {
                    authority = line.replacingOccurrences(of: "Authority=", with: "").trimmingCharacters(in: .whitespaces)
                    break
                }
                if line.contains("runtime") || line.contains("hardened") {
                    hardened = true
                }
            }

            // 3. Inspect Quarantine with /usr/bin/xattr
            let xattrResult = BrewStoreCommandExecutor.shared.run(
                executablePath: "/usr/bin/xattr",
                arguments: ["-p", "com.apple.quarantine", validPath],
                timeout: 10,
                category: .readOnly
            )
            let isQuarantined = (xattrResult.terminationStatus == 0)

            let rep = PackageSecurityReport(
                id: package.id,
                architecture: arch,
                architectureDetail: fileOutput.trimmingCharacters(in: .whitespacesAndNewlines),
                codeSignAuthority: authority,
                isHardenedRuntime: hardened,
                isQuarantined: isQuarantined,
                targetPath: validPath
            )

            await MainActor.run { [weak self] in
                self?.report = rep
                self?.isInspecting = false
            }
        }
    }

    func removeQuarantine(package: BrewStorePackage, manager: HomebrewManager) {
        guard let path = report?.targetPath, report?.isQuarantined == true else { return }

        Task.detached(priority: .userInitiated) { [path] in
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: "/usr/bin/xattr",
                arguments: ["-d", "com.apple.quarantine", path],
                timeout: 15,
                category: .reversibleMutation
            )

            await MainActor.run { [weak self] in
                self?.statusMessage = "Gatekeeper quarantine attribute removed successfully."
                self?.inspect(package: package, manager: manager)
            }
        }
    }

    nonisolated static func inspectBinaryArchitecture(at path: String) -> BinaryArchitectureType {
        let fileResult = BrewStoreCommandExecutor.shared.run(
            executablePath: "/usr/bin/file",
            arguments: ["-b", path],
            timeout: 10,
            category: .readOnly
        )
        let fileOutput = fileResult.standardOutput

        if fileOutput.contains("arm64"), fileOutput.contains("x86_64") {
            return .universal2
        } else if fileOutput.contains("arm64") {
            return .appleSilicon
        } else if fileOutput.contains("x86_64") {
            return .intel
        }
        return .unknown
    }

    nonisolated static func inspectAppBundleArchitecture(at appPath: String) -> BinaryArchitectureType {
        let macosDir = (appPath as NSString).appendingPathComponent("Contents/MacOS")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: macosDir), let first = files.first else {
            return .unknown
        }
        let execPath = (macosDir as NSString).appendingPathComponent(first)
        return inspectBinaryArchitecture(at: execPath)
    }
}
