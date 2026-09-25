import Foundation

// MARK: - Models

enum VersionJumpType: String, Codable, Hashable, Sendable {
    case major = "Major Upgrade"
    case minor = "Minor Update"
    case patch = "Patch Release"
    case unknown = "Upstream Change"

    var badgeColor: String {
        switch self {
        case .major: "red"
        case .minor: "blue"
        case .patch: "green"
        case .unknown: "secondary"
        }
    }
}

enum DiffLineType: Hashable, Sendable {
    case added
    case removed
    case unchanged
    case header

    var prefix: String {
        switch self {
        case .added: "+"
        case .removed: "-"
        case .unchanged: " "
        case .header: "@"
        }
    }
}

struct DiffLine: Identifiable, Hashable, Sendable {
    let id = UUID()
    let type: DiffLineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

struct DependencyDelta: Hashable, Sendable {
    let added: [String]
    let removed: [String]
    let unchanged: [String]

    var hasChanges: Bool {
        !added.isEmpty || !removed.isEmpty
    }
}

struct UpgradeDiffManifest: Hashable, Sendable {
    let packageID: String
    let packageName: String
    let kind: BrewPackageKind
    let installedVersion: String
    let upstreamVersion: String
    let versionJump: VersionJumpType
    let dependencyDelta: DependencyDelta
    let caveatsDelta: String?
    let localManifestPath: String?
    let rawLocalContent: String?
    let rawRemoteContent: String?
    let diffLines: [DiffLine]
    let rubySourcePath: String?
    let tap: String?

    var hasDiff: Bool {
        !diffLines.isEmpty
    }

    var addedLinesCount: Int {
        diffLines.filter { $0.type == .added }.count
    }

    var removedLinesCount: Int {
        diffLines.filter { $0.type == .removed }.count
    }
}

// MARK: - Upgrade Diff Engine

@MainActor
final class UpgradeDiffEngine: ObservableObject {
    static let shared = UpgradeDiffEngine()

    @Published var activeManifest: UpgradeDiffManifest?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let fileManager: FileManager
    private let commandExecutor: BrewStoreCommandExecutor

    init(
        fileManager: FileManager = .default,
        commandExecutor: BrewStoreCommandExecutor = .shared
    ) {
        self.fileManager = fileManager
        self.commandExecutor = commandExecutor
    }

    // MARK: - Generation API

    func generateUpgradeDiff(for package: BrewStorePackage, prefix: String) async -> UpgradeDiffManifest? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let result = await Task.detached(priority: .userInitiated) { [fileManager, commandExecutor] in
            Self.buildDiffManifest(
                package: package,
                prefix: prefix,
                fileManager: fileManager,
                executor: commandExecutor
            )
        }.value

        self.activeManifest = result
        return result
    }

    // MARK: - Core Analysis Heuristics

    nonisolated static func buildDiffManifest(
        package: BrewStorePackage,
        prefix: String,
        fileManager: FileManager,
        executor: BrewStoreCommandExecutor
    ) -> UpgradeDiffManifest? {
        // 1. Resolve Local Manifest
        var localRubyContent: String?
        var localManifestPath: String?
        var localDependencies: Set<String> = []
        var installedVersion = package.version

        let cellarBase = URL(fileURLWithPath: "\(prefix)/Cellar/\(package.id)")
        if let versionDirs = try? fileManager.contentsOfDirectory(atPath: cellarBase.path) {
            let versions = versionDirs.filter { !$0.hasPrefix(".") }.sorted()
            if let chosenVersion = versions.last {
                installedVersion = chosenVersion
                let versionDir = cellarBase.appendingPathComponent(chosenVersion)
                let rubyPath = versionDir.appendingPathComponent(".brew/\(package.id).rb").path
                if fileManager.fileExists(atPath: rubyPath),
                   let content = try? String(contentsOfFile: rubyPath, encoding: .utf8) {
                    localRubyContent = content
                    localManifestPath = rubyPath
                }

                // Check INSTALL_RECEIPT.json for runtime dependencies
                let receiptPath = versionDir.appendingPathComponent("INSTALL_RECEIPT.json").path
                if let receiptData = try? Data(contentsOf: URL(fileURLWithPath: receiptPath)),
                   let json = try? JSONSerialization.jsonObject(with: receiptData) as? [String: Any],
                   let runtimeDeps = json["runtime_dependencies"] as? [[String: Any]] {
                    for dep in runtimeDeps {
                        if let depName = dep["full_name"] as? String {
                            localDependencies.insert(depName)
                        }
                    }
                }
            }
        }

        // 2. Fetch Upstream Info from Homebrew
        var upstreamVersion = installedVersion
        var remoteDependencies: Set<String> = []
        var caveatsText: String?
        var rubySourcePath: String?
        var tapName: String?

        let brewPath = "\(prefix)/bin/brew"
        let isExecutable = fileManager.isExecutableFile(atPath: brewPath)
        let actualBrew = isExecutable ? brewPath : (fileManager.isExecutableFile(atPath: "/opt/homebrew/bin/brew") ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew")

        let infoResult = executor.run(
            executablePath: actualBrew,
            arguments: ["info", "--json=v2", package.id],
            timeout: 8,
            category: .readOnly
        )

        if infoResult.succeeded, let data = infoResult.standardOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let formulae = json["formulae"] as? [[String: Any]], let first = formulae.first {
                if let versions = first["versions"] as? [String: Any], let stable = versions["stable"] as? String {
                    upstreamVersion = stable
                }
                if let deps = first["dependencies"] as? [String] {
                    remoteDependencies.formUnion(deps)
                }
                if let bDeps = first["build_dependencies"] as? [String] {
                    remoteDependencies.formUnion(bDeps)
                }
                caveatsText = first["caveats"] as? String
                rubySourcePath = first["ruby_source_path"] as? String
                tapName = first["tap"] as? String
            } else if let casks = json["casks"] as? [[String: Any]], let first = casks.first {
                if let ver = first["version"] as? String {
                    upstreamVersion = ver
                }
                if let deps = first["depends_on"] as? [String: Any], let formulaDeps = deps["formula"] as? [String] {
                    remoteDependencies.formUnion(formulaDeps)
                }
                caveatsText = first["caveats"] as? String
                rubySourcePath = first["ruby_source_path"] as? String
                tapName = first["tap"] as? String
            }
        }

        // 3. Resolve Remote Ruby Content
        var rawRemoteContent: String?
        if let rubySourcePath {
            let remoteURLString = resolveRemoteRawURL(rubySourcePath: rubySourcePath, tap: tapName)
            if let remoteURL = URL(string: remoteURLString),
               let remoteData = try? Data(contentsOf: remoteURL),
               let fetched = String(data: remoteData, encoding: .utf8) {
                rawRemoteContent = fetched
            }
        }

        // Fallback: If remote file could not be fetched over network, synthesize representation
        if rawRemoteContent == nil {
            rawRemoteContent = synthesizeRubyManifest(
                packageID: package.id,
                name: package.name,
                version: upstreamVersion,
                dependencies: Array(remoteDependencies).sorted(),
                caveats: caveatsText
            )
        }

        // If local ruby file was missing, synthesize from installed state
        if localRubyContent == nil {
            localRubyContent = synthesizeRubyManifest(
                packageID: package.id,
                name: package.name,
                version: installedVersion,
                dependencies: Array(localDependencies).sorted(),
                caveats: nil
            )
        }

        // 4. Compute Semantic Diffs
        let versionJump = computeVersionJump(from: installedVersion, to: upstreamVersion)

        let addedDeps = Array(remoteDependencies.subtracting(localDependencies)).sorted()
        let removedDeps = Array(localDependencies.subtracting(remoteDependencies)).sorted()
        let unchangedDeps = Array(localDependencies.intersection(remoteDependencies)).sorted()
        let depDelta = DependencyDelta(added: addedDeps, removed: removedDeps, unchanged: unchangedDeps)

        // 5. Compute Line-by-Line Diff
        let oldLines = (localRubyContent ?? "").components(separatedBy: .newlines)
        let newLines = (rawRemoteContent ?? "").components(separatedBy: .newlines)
        let diffLines = computeDiff(oldLines: oldLines, newLines: newLines)

        return UpgradeDiffManifest(
            packageID: package.id,
            packageName: package.name,
            kind: package.kind,
            installedVersion: installedVersion,
            upstreamVersion: upstreamVersion,
            versionJump: versionJump,
            dependencyDelta: depDelta,
            caveatsDelta: caveatsText,
            localManifestPath: localManifestPath,
            rawLocalContent: localRubyContent,
            rawRemoteContent: rawRemoteContent,
            diffLines: diffLines,
            rubySourcePath: rubySourcePath,
            tap: tapName
        )
    }

    // MARK: - Diff Computation Algorithm (LCS)

    nonisolated static func computeDiff(oldLines: [String], newLines: [String]) -> [DiffLine] {
        let n = oldLines.count
        let m = newLines.count

        if n == 0 {
            return newLines.enumerated().map { index, line in
                DiffLine(type: .added, content: line, oldLineNumber: nil, newLineNumber: index + 1)
            }
        }
        if m == 0 {
            return oldLines.enumerated().map { index, line in
                DiffLine(type: .removed, content: line, oldLineNumber: index + 1, newLineNumber: nil)
            }
        }

        // Truncate comparison bounds if excessively large
        let maxLines = 1500
        let limitedOld = Array(oldLines.prefix(maxLines))
        let limitedNew = Array(newLines.prefix(maxLines))
        let limN = limitedOld.count
        let limM = limitedNew.count

        var dp = Array(repeating: Array(repeating: 0, count: limM + 1), count: limN + 1)
        for i in 1...limN {
            for j in 1...limM {
                if limitedOld[i - 1] == limitedNew[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [DiffLine] = []
        var i = limN
        var j = limM

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && limitedOld[i - 1] == limitedNew[j - 1] {
                result.append(DiffLine(type: .unchanged, content: limitedOld[i - 1], oldLineNumber: i, newLineNumber: j))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                result.append(DiffLine(type: .added, content: limitedNew[j - 1], oldLineNumber: nil, newLineNumber: j))
                j -= 1
            } else if i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j]) {
                result.append(DiffLine(type: .removed, content: limitedOld[i - 1], oldLineNumber: i, newLineNumber: nil))
                i -= 1
            }
        }

        return result.reversed()
    }

    // MARK: - SemVer Jump Calculation

    nonisolated static func computeVersionJump(from oldVersion: String, to newVersion: String) -> VersionJumpType {
        if oldVersion == newVersion {
            return .unknown
        }

        let oldParts = extractNumericComponents(oldVersion)
        let newParts = extractNumericComponents(newVersion)

        guard !oldParts.isEmpty, !newParts.isEmpty else {
            return .unknown
        }

        let oldMajor = oldParts[0]
        let newMajor = newParts[0]

        if newMajor > oldMajor {
            return .major
        } else if newMajor < oldMajor {
            return .unknown
        }

        let oldMinor = oldParts.count > 1 ? oldParts[1] : 0
        let newMinor = newParts.count > 1 ? newParts[1] : 0

        if newMinor > oldMinor {
            return .minor
        }

        let oldPatch = oldParts.count > 2 ? oldParts[2] : 0
        let newPatch = newParts.count > 2 ? newParts[2] : 0

        if newPatch > oldPatch {
            return .patch
        }

        return .unknown
    }

    private nonisolated static func extractNumericComponents(_ version: String) -> [Int] {
        let clean = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = clean.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" || $0 == "," })
        return parts.compactMap { Int($0) }
    }

    private nonisolated static func resolveRemoteRawURL(rubySourcePath: String, tap: String?) -> String {
        let tapLower = (tap ?? "homebrew/core").lowercased()
        if tapLower.contains("cask") {
            return "https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/\(rubySourcePath)"
        } else if tapLower == "homebrew/core" {
            return "https://raw.githubusercontent.com/Homebrew/homebrew-core/master/\(rubySourcePath)"
        } else if let slash = tapLower.firstIndex(of: "/") {
            let user = String(tapLower[..<slash])
            let repo = String(tapLower[tapLower.index(after: slash)...])
            let fullRepo = repo.hasPrefix("homebrew-") ? repo : "homebrew-\(repo)"
            return "https://raw.githubusercontent.com/\(user)/\(fullRepo)/master/\(rubySourcePath)"
        }
        return "https://raw.githubusercontent.com/Homebrew/homebrew-core/master/\(rubySourcePath)"
    }

    private nonisolated static func synthesizeRubyManifest(
        packageID: String,
        name: String,
        version: String,
        dependencies: [String],
        caveats: String?
    ) -> String {
        var lines: [String] = []
        let className = name.prefix(1).uppercased() + name.dropFirst()
        lines.append("class \(className) < Formula")
        lines.append("  desc \"\(name) formula specification\"")
        lines.append("  version \"\(version)\"")
        lines.append("")
        for dep in dependencies {
            lines.append("  depends_on \"\(dep)\"")
        }
        if let caveats, !caveats.isEmpty {
            lines.append("")
            lines.append("  def caveats")
            lines.append("    <<~EOS")
            for cLine in caveats.components(separatedBy: .newlines) {
                lines.append("      \(cLine)")
            }
            lines.append("    EOS")
            lines.append("  end")
        }
        lines.append("end")
        return lines.joined(separator: "\n")
    }
}
