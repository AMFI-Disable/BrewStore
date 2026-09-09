import Foundation

struct CellarInstalledRecord: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let version: String
    let kind: BrewPackageKind
    let dependencies: [String]
    let tap: String?
}

enum CellarScanner {
    static func scanInstalledFormulae(cellarPath: String) -> [CellarInstalledRecord] {
        let fileManager = FileManager.default
        guard let formulaDirs = try? fileManager.contentsOfDirectory(atPath: cellarPath) else { return [] }
        var records: [CellarInstalledRecord] = []

        for formulaName in formulaDirs {
            guard !formulaName.hasPrefix(".") else { continue }
            let formulaPath = (cellarPath as NSString).appendingPathComponent(formulaName)
            guard let versionDirs = try? fileManager.contentsOfDirectory(atPath: formulaPath) else { continue }
            let validVersions = versionDirs.filter { !$0.hasPrefix(".") }
            guard let latestVersion = validVersions.sorted().last else { continue }

            var deps: [String] = []
            var tap: String?

            let receiptPath = ((formulaPath as NSString).appendingPathComponent(latestVersion) as NSString).appendingPathComponent("INSTALL_RECEIPT.json")
            if let receiptData = try? Data(contentsOf: URL(fileURLWithPath: receiptPath)),
               let json = try? JSONSerialization.jsonObject(with: receiptData) as? [String: Any] {
                if let runtimeDeps = json["runtime_dependencies"] as? [[String: Any]] {
                    deps = runtimeDeps.compactMap { $0["full_name"] as? String }
                }
                if let source = json["source"] as? [String: Any] {
                    tap = source["tap"] as? String
                }
            }

            records.append(CellarInstalledRecord(
                id: formulaName,
                name: formulaName,
                version: latestVersion,
                kind: .formula,
                dependencies: deps,
                tap: tap
            ))
        }
        return records
    }

    static func scanInstalledCasks(caskroomPath: String) -> [CellarInstalledRecord] {
        let fileManager = FileManager.default
        guard let caskDirs = try? fileManager.contentsOfDirectory(atPath: caskroomPath) else { return [] }
        var records: [CellarInstalledRecord] = []

        for caskName in caskDirs {
            guard !caskName.hasPrefix(".") else { continue }
            let caskPath = (caskroomPath as NSString).appendingPathComponent(caskName)
            guard let versionDirs = try? fileManager.contentsOfDirectory(atPath: caskPath) else { continue }
            let validVersions = versionDirs.filter { !$0.hasPrefix(".") && $0 != ".metadata" }
            guard let latestVersion = validVersions.sorted().last else { continue }

            records.append(CellarInstalledRecord(
                id: caskName,
                name: caskName,
                version: latestVersion,
                kind: .cask,
                dependencies: [],
                tap: nil
            ))
        }
        return records
    }

    static func scanAllInstalled(prefix: String) -> (formulae: [CellarInstalledRecord], casks: [CellarInstalledRecord]) {
        let cellar = (prefix as NSString).appendingPathComponent("Cellar")
        let caskroom = (prefix as NSString).appendingPathComponent("Caskroom")
        let formulae = scanInstalledFormulae(cellarPath: cellar)
        let casks = scanInstalledCasks(caskroomPath: caskroom)
        return (formulae, casks)
    }

    static func toAuthoritativeMap(_ records: [CellarInstalledRecord]) -> [String: String] {
        var map = [String: String]()
        for record in records {
            map[record.id.lowercased()] = record.version
        }
        return map
    }
}
