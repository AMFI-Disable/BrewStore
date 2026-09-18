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
                targetPath = Self.findFormulaBinaryPath(
                    id: package.id,
                    name: package.name,
                    cellarURL: package.cellarURL()
                )
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
        } else if fileOutput.contains("x86_64") || fileOutput.contains("i386") || fileOutput.contains("Intel 80386") {
            return .intel
        }
        return .unknown
    }

    nonisolated static func inspectAppBundleArchitecture(at appPath: String) -> BinaryArchitectureType {
        let macosDir = (appPath as NSString).appendingPathComponent("Contents/MacOS")
        let infoPlistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        if let infoDict = NSDictionary(contentsOfFile: infoPlistPath),
           let exeName = infoDict["CFBundleExecutable"] as? String {
            let execPath = (macosDir as NSString).appendingPathComponent(exeName)
            if FileManager.default.fileExists(atPath: execPath) {
                return inspectBinaryArchitecture(at: execPath)
            }
        }

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: macosDir) else {
            return .unknown
        }
        let candidate = files.first(where: {
            !$0.hasPrefix(".") && FileManager.default.isExecutableFile(atPath: (macosDir as NSString).appendingPathComponent($0))
        }) ?? files.first(where: { !$0.hasPrefix(".") })

        guard let chosen = candidate else { return .unknown }
        let execPath = (macosDir as NSString).appendingPathComponent(chosen)
        return inspectBinaryArchitecture(at: execPath)
    }

    nonisolated static func findFormulaBinaryPath(id: String, name: String, cellarURL: URL? = nil) -> String? {
        let optCandidates = [
            "/opt/homebrew/opt/\(id)/bin",
            "/usr/local/opt/\(id)/bin",
            "/opt/homebrew/opt/\(name)/bin",
            "/usr/local/opt/\(name)/bin"
        ]
        for optDir in optCandidates {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: optDir) {
                if files.contains(name) {
                    return (optDir as NSString).appendingPathComponent(name)
                }
                if files.contains(id) {
                    return (optDir as NSString).appendingPathComponent(id)
                }
                if let first = files.first {
                    return (optDir as NSString).appendingPathComponent(first)
                }
            }
        }

        let standardCandidates = [
            "/opt/homebrew/bin/\(name)",
            "/opt/homebrew/bin/\(id)",
            "/usr/local/bin/\(name)",
            "/usr/local/bin/\(id)"
        ]
        for path in standardCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        if let cellar = cellarURL {
            if let versionDirs = try? FileManager.default.contentsOfDirectory(atPath: cellar.path) {
                for versionDir in versionDirs {
                    let binDir = cellar.appendingPathComponent(versionDir).appendingPathComponent("bin")
                    if let files = try? FileManager.default.contentsOfDirectory(atPath: binDir.path) {
                        if files.contains(name) {
                            return binDir.appendingPathComponent(name).path
                        }
                        if files.contains(id) {
                            return binDir.appendingPathComponent(id).path
                        }
                        if let first = files.first {
                            return binDir.appendingPathComponent(first).path
                        }
                    }
                }
            }
        }

        return nil
    }
}
