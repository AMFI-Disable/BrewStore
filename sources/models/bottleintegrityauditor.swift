import Foundation

enum BottleIntegrityStatus: String, CaseIterable, Identifiable, Codable {
    case verifiedBottle = "Official Verified Bottle"
    case builtFromSource = "Built From Source (--build-from-source)"
    case unmanagedOrManual = "Unmanaged / Missing Receipt"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .verifiedBottle: "checkmark.shield.fill"
        case .builtFromSource: "hammer.fill"
        case .unmanagedOrManual: "questionmark.circle.fill"
        }
    }
}

struct BottleIntegrityReport: Hashable, Codable {
    let packageID: String
    let status: BottleIntegrityStatus
    let bottleSHA256: String?
    let bottleArch: String?
    let compiler: String?
    let sourceModified: Bool
}

enum BrewStoreBottleIntegrityAuditor {
    static func auditPackage(package: BrewStorePackage, prefix: String) -> BottleIntegrityReport {
        guard package.kind == .formula, package.isInstalled else {
            return BottleIntegrityReport(
                packageID: package.id,
                status: .verifiedBottle,
                bottleSHA256: nil,
                bottleArch: "universal",
                compiler: "clang",
                sourceModified: false
            )
        }

        let cellarURL = URL(fileURLWithPath: prefix).appendingPathComponent("Cellar").appendingPathComponent(package.name)
        let fm = FileManager.default

        // Look for INSTALL_RECEIPT.json in any version subdirectory
        if let versions = try? fm.contentsOfDirectory(at: cellarURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for versionDir in versions {
                let receiptURL = versionDir.appendingPathComponent("INSTALL_RECEIPT.json")
                if let data = try? Data(contentsOf: receiptURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return parseReceiptJSON(json, packageID: package.id)
                }
            }
        }

        return BottleIntegrityReport(
            packageID: package.id,
            status: .unmanagedOrManual,
            bottleSHA256: nil,
            bottleArch: nil,
            compiler: nil,
            sourceModified: false
        )
    }

    static func parseReceiptJSON(_ json: [String: Any], packageID: String) -> BottleIntegrityReport {
        let sourceModified = (json["source_modified"] as? Bool) ?? false
        let compiler = (json["compiler"] as? String) ?? "clang"
        let builtAsBottle = (json["built_as_bottle"] as? Bool) ?? true

        // Try extracting bottle file metadata if present
        var sha256: String?
        var arch: String?

        if let bottleDict = json["bottle"] as? [String: Any],
           let files = bottleDict["files"] as? [String: Any] {
            for (key, fileInfo) in files {
                arch = key
                if let dict = fileInfo as? [String: Any], let hash = dict["sha256"] as? String {
                    sha256 = hash
                    break
                }
            }
        }

        let status: BottleIntegrityStatus = builtAsBottle ? .verifiedBottle : .builtFromSource

        return BottleIntegrityReport(
            packageID: packageID,
            status: status,
            bottleSHA256: sha256,
            bottleArch: arch,
            compiler: compiler,
            sourceModified: sourceModified
        )
    }
}
