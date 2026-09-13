import Foundation

struct HomebrewPrefix: Identifiable, Hashable, Codable {
    let id: String // path, e.g. "/opt/homebrew"
    let name: String
    let brewExecutablePath: String
    let architecture: BinaryArchitectureType
    let isAvailable: Bool
    var isActive: Bool

    var description: String {
        "\(name) · \(id)"
    }
}

@MainActor
final class BrewStorePrefixManager: ObservableObject {
    static let shared = BrewStorePrefixManager()

    @Published var availablePrefixes: [HomebrewPrefix] = []
    @Published var activePrefix: HomebrewPrefix?

    init() {
        refreshPrefixes(currentActivePath: nil)
    }

    func refreshPrefixes(currentActivePath: String?) {
        self.availablePrefixes = Self.discoverPrefixes(currentActiveBrewPath: currentActivePath)
        self.activePrefix = availablePrefixes.first(where: \.isActive) ?? availablePrefixes.first(where: \.isAvailable)
    }

    func switchPrefix(to prefix: HomebrewPrefix, manager: HomebrewManager) {
        guard prefix.isAvailable else { return }
        manager.setActiveBrewPath(prefix.brewExecutablePath)
        refreshPrefixes(currentActivePath: prefix.brewExecutablePath)
    }

    nonisolated static func discoverPrefixes(currentActiveBrewPath: String?) -> [HomebrewPrefix] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [(id: String, name: String, brewPath: String, fallbackArch: BinaryArchitectureType)] = [
            ("/opt/homebrew", "Apple Silicon (ARM64)", "/opt/homebrew/bin/brew", .appleSilicon),
            ("/usr/local", "Intel (x86_64 Rosetta)", "/usr/local/bin/brew", .intel),
            (homeDir.appendingPathComponent(".homebrew").path, "User Homebrew (~/.homebrew)", homeDir.appendingPathComponent(".homebrew/bin/brew").path, .appleSilicon),
            (homeDir.appendingPathComponent(".linuxbrew").path, "Custom Prefix (~/.linuxbrew)", homeDir.appendingPathComponent(".linuxbrew/bin/brew").path, .unknown)
        ]

        var prefixes: [HomebrewPrefix] = []
        for cand in candidates {
            let isAvailable = FileManager.default.isExecutableFile(atPath: cand.brewPath)
            let detectedArch: BinaryArchitectureType = if isAvailable {
                BrewStoreSecurityInspector.inspectBinaryArchitecture(at: cand.brewPath)
            } else {
                cand.fallbackArch
            }
            let finalArch = detectedArch == .unknown ? cand.fallbackArch : detectedArch
            let isActive = (currentActiveBrewPath != nil) ? (currentActiveBrewPath == cand.brewPath) : (isAvailable && prefixes.isEmpty)

            prefixes.append(HomebrewPrefix(
                id: cand.id,
                name: cand.name,
                brewExecutablePath: cand.brewPath,
                architecture: finalArch,
                isAvailable: isAvailable,
                isActive: isActive
            ))
        }

        return prefixes
    }
}
