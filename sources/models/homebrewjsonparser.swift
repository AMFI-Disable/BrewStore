import Foundation

enum HomebrewJSONParser {
    static func packages(
        from data: Data,
        kind: BrewPackageKind,
        installedIDs: Set<String>,
        outdatedIDs: Set<String>,
        pinnedIDs: Set<String> = []
    ) -> [BrewStorePackage] {
        var entries: [[String: Any]] = []

        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let key = kind == .cask ? "casks" : "formulae"
            if let list = root[key] as? [[String: Any]] {
                entries = list
            }
        } else if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            entries = array
        }

        guard !entries.isEmpty else { return [] }

        return entries.compactMap { entry in
            let token = (entry["token"] as? String) ?? (entry["name"] as? String) ?? ((entry["name"] as? [String])?.first)
            guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

            let name: String = if let names = entry["name"] as? [String] {
                names.first ?? token
            } else if let strName = entry["name"] as? String {
                strName
            } else {
                token
            }

            let versions = entry["versions"] as? [String: Any]
            let version = ((entry["version"] as? String) ?? (versions?["stable"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var applicationNames: [String] = []
            if let artifacts = entry["artifacts"] as? [[String: Any]] {
                for artifact in artifacts {
                    if let apps = artifact["app"] as? [String] {
                        applicationNames.append(contentsOf: apps)
                    } else if let app = artifact["app"] as? String {
                        applicationNames.append(app)
                    }
                }
            }

            var dependencies: [String] = []
            if let directDeps = entry["dependencies"] as? [String] {
                dependencies.append(contentsOf: directDeps)
            } else if let dependsOn = entry["depends_on"] as? [String: Any] {
                if let formulae = dependsOn["formula"] as? [String] {
                    dependencies.append(contentsOf: formulae)
                }
                if let casks = dependsOn["cask"] as? [String] {
                    dependencies.append(contentsOf: casks)
                }
            }

            let tap = entry["tap"] as? String
            let caveats = entry["caveats"] as? String

            var installedVersion: String?
            if let installedList = entry["installed"] as? [[String: Any]], let first = installedList.first {
                installedVersion = first["version"] as? String
            } else if let installedStr = entry["installed"] as? String {
                installedVersion = installedStr
            }

            return BrewStorePackage(
                id: token,
                name: name,
                description: entry["desc"] as? String ?? "",
                homepage: entry["homepage"] as? String ?? "",
                version: version,
                kind: kind,
                applicationNames: applicationNames,
                isInstalled: installedIDs.contains(token) || installedIDs.contains(token.lowercased()),
                isOutdated: outdatedIDs.contains(token) || outdatedIDs.contains(token.lowercased()),
                isPinned: pinnedIDs.contains(token) || pinnedIDs.contains(token.lowercased()),
                tap: tap,
                dependencies: dependencies,
                caveats: caveats,
                installedVersion: installedVersion
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func identifiers(fromOutdated data: Data, kind: BrewPackageKind) -> Set<String> {
        var result = Set<String>()
        func addIdentifier(_ raw: String?) {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
            let lower = raw.lowercased()
            result.insert(lower)
            if let lastComponent = lower.components(separatedBy: "/").last, !lastComponent.isEmpty {
                result.insert(lastComponent)
            }
        }

        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let key = kind == .cask ? "casks" : "formulae"
            if let entries = root[key] as? [[String: Any]] {
                for entry in entries {
                    addIdentifier((entry["name"] as? String) ?? (entry["token"] as? String) ?? (entry["formula"] as? String) ?? (entry["cask"] as? String))
                }
            }
        } else if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for entry in array {
                addIdentifier((entry["name"] as? String) ?? (entry["token"] as? String) ?? (entry["formula"] as? String) ?? (entry["cask"] as? String))
            }
        }
        return result
    }

    static func pinnedIdentifiers(from output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    static func services(from data: Data) -> [BrewStoreService] {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let name = entry["name"] as? String, !name.isEmpty else { return nil }
            return BrewStoreService(
                id: name,
                name: name,
                status: entry["status"] as? String ?? "unknown",
                user: entry["user"] as? String,
                file: entry["file"] as? String
            )
        }.sorted { $0.name < $1.name }
    }

    static func taps(from output: String) -> [BrewStoreTap] {
        output.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { BrewStoreTap(id: $0, name: $0) }
    }
}
