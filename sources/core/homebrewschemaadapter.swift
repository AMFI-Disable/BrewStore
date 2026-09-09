import Foundation

enum HomebrewSchemaAdapter {
    /// Coerces any JSON value into a string, whether it is a String, Int, Double, or array of Strings.
    static func coerceToString(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let str = value as? String {
            return str
        }
        if let arr = value as? [Any], let first = arr.first {
            return coerceToString(first)
        }
        if let num = value as? NSNumber {
            return num.stringValue
        }
        return nil
    }

    /// Coerces any JSON value into an array of strings.
    static func coerceToStringArray(_ value: Any?) -> [String] {
        guard let value else { return [] }
        if let arr = value as? [Any] {
            return arr.compactMap { coerceToString($0) }
        }
        if let str = coerceToString(value) {
            return [str]
        }
        return []
    }

    /// Resiliently extracts a package list from JSON, recovering partial items even if some elements contain unexpected types.
    static func resilientlyParsePackages(from jsonData: Data, kind: BrewPackageKind) -> [[String: Any]] {
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) else {
            return []
        }

        if let array = root as? [[String: Any]] {
            return array
        }

        // Sometimes Homebrew wraps outputs in a root object with "formulae" or "casks" keys
        if let dict = root as? [String: Any] {
            if kind == .formula, let formulae = dict["formulae"] as? [[String: Any]] {
                return formulae
            }
            if kind == .cask, let casks = dict["casks"] as? [[String: Any]] {
                return casks
            }
            if let list = dict["packages"] as? [[String: Any]] {
                return list
            }
        }

        return []
    }

    /// Parses a Homebrew version string to evaluate compatibility.
    static func parseSemanticVersion(_ versionOutput: String) -> (major: Int, minor: Int, patch: Int)? {
        // e.g. "Homebrew 5.0.7-99-gd61f229" or "4.3.1"
        let pattern = #"(\d+)\.(\d+)(?:\.(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(versionOutput.startIndex ..< versionOutput.endIndex, in: versionOutput)
        guard let match = regex.firstMatch(in: versionOutput, range: range) else { return nil }

        guard let majorRange = Range(match.range(at: 1), in: versionOutput),
              let major = Int(versionOutput[majorRange]),
              let minorRange = Range(match.range(at: 2), in: versionOutput),
              let minor = Int(versionOutput[minorRange])
        else {
            return nil
        }

        var patch = 0
        if match.numberOfRanges > 3, let patchRange = Range(match.range(at: 3), in: versionOutput) {
            patch = Int(versionOutput[patchRange]) ?? 0
        }

        return (major, minor, patch)
    }

    /// Validates whether the Homebrew version is compatible with BrewStore features.
    static func isVersionCompatible(_ versionOutput: String) -> Bool {
        guard let semver = parseSemanticVersion(versionOutput) else {
            return true // Unknown version format; assume compatible to prevent false alarms
        }
        // BrewStore is tested on Homebrew 4.x and 5.x
        return semver.major >= 4
    }
}
