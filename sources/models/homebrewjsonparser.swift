import Foundation

enum HomebrewJSONParser {
    static func packages(from data: Data, kind: BrewPackageKind, installedIDs: Set<String>, outdatedIDs: Set<String>) -> [BrewStorePackage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let key = kind == .cask ? "casks" : "formulae"
        guard let entries = root[key] as? [[String: Any]] else { return [] }

        return entries.compactMap { entry in
            let token = (entry["token"] as? String) ?? (entry["name"] as? String)
            guard let token, !token.isEmpty else { return nil }

            let name: String
            if let names = entry["name"] as? [String] {
                name = names.first ?? token
            } else {
                name = token
            }

            let versions = entry["versions"] as? [String: Any]
            let version = (entry["version"] as? String) ?? (versions?["stable"] as? String) ?? ""
            var applicationNames: [String] = []
            if let artifacts = entry["artifacts"] as? [[String: Any]] {
                for artifact in artifacts {
                    if let apps = artifact["app"] as? [String] { applicationNames.append(contentsOf: apps) }
                }
            }

            return BrewStorePackage(
                id: token,
                name: name,
                description: entry["desc"] as? String ?? "",
                homepage: entry["homepage"] as? String ?? "",
                version: version,
                kind: kind,
                applicationNames: applicationNames,
                isInstalled: installedIDs.contains(token),
                isOutdated: outdatedIDs.contains(token)
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func identifiers(fromOutdated data: Data, kind: BrewPackageKind) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root[kind == .cask ? "casks" : "formulae"] as? [[String: Any]] else { return [] }
        return Set(entries.compactMap { $0["name"] as? String })
    }

    static func services(from data: Data) -> [BrewStoreService] {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any] ] else { return [] }
        return entries.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
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
