import Foundation

struct VersionMember: Identifiable, Hashable, Codable {
    let packageID: String
    let displayName: String
    let version: String
    let isInstalled: Bool
    let isActiveLinked: Bool

    var id: String {
        packageID
    }
}

struct VersionFamily: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let baseIdentifier: String
    let members: [VersionMember]

    var activeMember: VersionMember? {
        members.first(where: \.isActiveLinked)
    }

    var installedMembers: [VersionMember] {
        members.filter(\.isInstalled)
    }

    var hasMultipleInstalled: Bool {
        installedMembers.count > 1
    }
}

@MainActor
final class BrewStoreVersionLinkManager: ObservableObject {
    static let shared = BrewStoreVersionLinkManager()

    @Published var families: [VersionFamily] = []
    @Published var isSwitching = false
    @Published var statusMessage = ""

    nonisolated static let knownFamilyBases: [(name: String, base: String)] = [
        ("Node.js", "node"),
        ("Python", "python"),
        ("OpenJDK (Java)", "openjdk"),
        ("PostgreSQL", "postgresql"),
        ("PHP", "php"),
        ("Ruby", "ruby"),
        ("Go", "go"),
        ("GCC", "gcc"),
        ("LLVM / Clang", "llvm")
    ]

    func refresh(packages: [BrewStorePackage]) {
        self.families = Self.parseVersionFamilies(packages: packages)
    }

    func switchVersion(to member: VersionMember, in family: VersionFamily, manager: HomebrewManager) {
        guard let brewPath = manager.brewPath, !isSwitching else { return }
        isSwitching = true
        statusMessage = "Switching active \(family.name) to \(member.displayName)…"

        Task.detached(priority: .userInitiated) { [weak self] in
            // Unlink all installed members of the family first
            for other in family.installedMembers {
                _ = BrewStoreCommandExecutor.shared.run(
                    executablePath: brewPath,
                    arguments: ["unlink", other.packageID],
                    timeout: 20,
                    category: .reversibleMutation
                )
            }

            // Link the target member
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["link", "--overwrite", member.packageID],
                timeout: 30,
                category: .reversibleMutation
            )

            await MainActor.run { [weak self] in
                self?.isSwitching = false
                self?.statusMessage = "Activated \(member.displayName)."
                manager.refresh()
            }
        }
    }

    nonisolated static func parseVersionFamilies(packages: [BrewStorePackage]) -> [VersionFamily] {
        var families: [VersionFamily] = []

        for (name, base) in knownFamilyBases {
            // Match packages starting with "base" or "base@"
            let matchingPackages = packages.filter { pkg in
                let lower = pkg.id.lowercased()
                return lower == base || lower.hasPrefix("\(base)@")
            }.sorted { $0.id < $1.id }

            guard !matchingPackages.isEmpty else { continue }

            let members: [VersionMember] = matchingPackages.map { pkg in
                let isLinked = pkg.isInstalled && !pkg.isPinned // In Homebrew, installed unpinned / active
                return VersionMember(
                    packageID: pkg.id,
                    displayName: pkg.name.isEmpty ? pkg.id : pkg.name,
                    version: pkg.installedVersion ?? pkg.version,
                    isInstalled: pkg.isInstalled,
                    isActiveLinked: isLinked
                )
            }

            families.append(VersionFamily(
                id: base,
                name: name,
                baseIdentifier: base,
                members: members
            ))
        }

        return families
    }
}
