import Foundation

/// Compares software versions to detect breaking major version upgrades.
enum BrewStoreVersionComparator {
    /// Determines whether updating from `installed` to `latest` represents a major version bump.
    static func isMajorUpgrade(installed: String?, latest: String?) -> Bool {
        guard let installed = cleanVersion(installed),
              let latest = cleanVersion(latest)
        else {
            return false
        }

        guard let installedMajor = extractMajor(installed),
              let latestMajor = extractMajor(latest)
        else {
            return false
        }

        return latestMajor > installedMajor
    }

    /// Formats a concise summary of the major version change (e.g. "v15 → v16").
    static func majorUpgradeSummary(installed: String?, latest: String?) -> String? {
        guard isMajorUpgrade(installed: installed, latest: latest),
              let installed = cleanVersion(installed),
              let latest = cleanVersion(latest),
              let instMajor = extractMajor(installed),
              let latMajor = extractMajor(latest)
        else {
            return nil
        }

        return "v\(instMajor) → v\(latMajor)"
    }

    // MARK: - Internal Helpers

    private static func cleanVersion(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return nil }

        if v.hasPrefix("v") || v.hasPrefix("V") {
            v.removeFirst()
        }
        if let commaIndex = v.firstIndex(of: ",") {
            v = String(v[..<commaIndex])
        }
        return v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMajor(_ version: String) -> Int? {
        let components = version.components(separatedBy: CharacterSet(charactersIn: ".-_"))
        for comp in components {
            // Take digits from the component
            let digits = comp.prefix { $0.isNumber }
            if !digits.isEmpty, let num = Int(digits) {
                return num
            }
        }
        return nil
    }
}
