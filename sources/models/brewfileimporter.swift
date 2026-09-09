import Foundation

enum ImportedEntryKind: String, Codable {
    case formula = "Formula"
    case cask = "Cask"
    case tap = "Tap"
    case mas = "Mac App Store"
}

struct ImportedBrewfileEntry: Identifiable, Hashable {
    let id: String
    let rawName: String
    let kind: ImportedEntryKind
    let matchedPackage: BrewStorePackage?
    let isInstalled: Bool
    let isOutdated: Bool
    var isSelected: Bool = true
}

struct BrewfileImportSummary: Hashable {
    let taps: [String]
    let entries: [ImportedBrewfileEntry]

    var formulae: [ImportedBrewfileEntry] {
        entries.filter { $0.kind == .formula }
    }

    var casks: [ImportedBrewfileEntry] {
        entries.filter { $0.kind == .cask }
    }

    var masApps: [ImportedBrewfileEntry] {
        entries.filter { $0.kind == .mas }
    }

    var missingEntries: [ImportedBrewfileEntry] {
        entries.filter { !$0.isInstalled && ($0.matchedPackage != nil || $0.kind == .mas) }
    }

    var installedCount: Int {
        entries.filter(\.isInstalled).count
    }

    var missingCount: Int {
        missingEntries.count
    }
}

@MainActor
final class BrewStoreBrewfileImporter: ObservableObject {
    static let shared = BrewStoreBrewfileImporter()

    @Published var importSummary: BrewfileImportSummary?
    @Published var isImporting = false
    @Published var errorMessage: String?

    func parseBrewfile(content: String, manager: HomebrewManager) -> BrewfileImportSummary {
        let lines = content.components(separatedBy: .newlines)
        var taps: [String] = []
        var entries: [ImportedBrewfileEntry] = []

        let installedMap = Dictionary(
            manager.packages.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("tap ") {
                let name = extractPackageName(from: line, prefix: "tap ")
                if !name.isEmpty {
                    taps.append(name)
                }
            } else if line.hasPrefix("brew ") {
                let name = extractPackageName(from: line, prefix: "brew ")
                if !name.isEmpty {
                    let matched = installedMap[name.lowercased()]
                    let isInst = matched?.isInstalled == true
                    let isOut = matched?.isOutdated == true

                    entries.append(ImportedBrewfileEntry(
                        id: "brew:\(name)",
                        rawName: name,
                        kind: .formula,
                        matchedPackage: matched,
                        isInstalled: isInst,
                        isOutdated: isOut,
                        isSelected: !isInst
                    ))
                }
            } else if line.hasPrefix("cask ") {
                let name = extractPackageName(from: line, prefix: "cask ")
                if !name.isEmpty {
                    let matched = installedMap[name.lowercased()]
                    let isInst = matched?.isInstalled == true
                    let isOut = matched?.isOutdated == true

                    entries.append(ImportedBrewfileEntry(
                        id: "cask:\(name)",
                        rawName: name,
                        kind: .cask,
                        matchedPackage: matched,
                        isInstalled: isInst,
                        isOutdated: isOut,
                        isSelected: !isInst
                    ))
                }
            } else if line.hasPrefix("mas ") {
                let (name, idVal) = extractMASInfo(from: line)
                if !name.isEmpty {
                    let isInst = BrewStoreMASManager.shared.installedApps.contains(where: {
                        if let idVal, $0.id == idVal {
                            return true
                        }
                        return $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                    })
                    entries.append(ImportedBrewfileEntry(
                        id: "mas:\(idVal ?? name)",
                        rawName: name,
                        kind: .mas,
                        matchedPackage: nil,
                        isInstalled: isInst,
                        isOutdated: false,
                        isSelected: !isInst
                    ))
                }
            }
        }

        let summary = BrewfileImportSummary(taps: taps, entries: entries)
        self.importSummary = summary
        return summary
    }

    func parseBrewfile(from url: URL, manager: HomebrewManager) -> BrewfileImportSummary? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "Failed to read file at \(url.lastPathComponent)"
            return nil
        }
        return parseBrewfile(content: content, manager: manager)
    }

    func installSelectedMissing(manager: HomebrewManager, entries: [ImportedBrewfileEntry], taps: [String] = []) {
        // Configure missing taps first
        let installedTapNames = Set(manager.taps.map { $0.name.lowercased() })
        for tap in taps where !installedTapNames.contains(tap.lowercased()) {
            manager.tap(name: tap)
        }

        let toInstall = entries.filter {
            $0.isSelected && !$0.isInstalled && ($0.kind == .cask || $0.kind == .formula)
        }.map { entry -> BrewStorePackage in
            entry.matchedPackage ?? BrewStorePackage(
                id: entry.rawName,
                name: entry.rawName,
                description: "Imported from Brewfile",
                homepage: "",
                version: "",
                kind: entry.kind == .cask ? .cask : .formula,
                isInstalled: false,
                isOutdated: false
            )
        }
        if !toInstall.isEmpty {
            manager.batchPerform(packages: toInstall, action: .install)
        }

        // Install missing MAS apps
        let missingMAS = entries.filter { $0.isSelected && !$0.isInstalled && $0.kind == .mas }
        for entry in missingMAS {
            let idStr = entry.id.components(separatedBy: ":").last ?? entry.id
            BrewStoreMASManager.shared.installApp(id: idStr, name: entry.rawName)
        }
    }

    private func extractPackageName(from line: String, prefix: String) -> String {
        var cleanLine = line
        if let hashIdx = cleanLine.firstIndex(of: "#") {
            cleanLine = String(cleanLine[..<hashIdx])
        }
        cleanLine = cleanLine.trimmingCharacters(in: .whitespaces)

        if cleanLine.hasPrefix(prefix) {
            cleanLine = String(cleanLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }

        if let firstQuote = cleanLine.firstIndex(of: "\"") ?? cleanLine.firstIndex(of: "'") {
            let quoteChar = cleanLine[firstQuote]
            let afterFirst = cleanLine[cleanLine.index(after: firstQuote)...]
            if let secondQuote = afterFirst.firstIndex(of: quoteChar) {
                return String(afterFirst[..<secondQuote])
            }
        }

        let tokens = cleanLine.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        return tokens.first(where: { !$0.isEmpty }) ?? ""
    }

    private func extractMASInfo(from line: String) -> (name: String, id: String?) {
        let rest = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
        guard let firstQuote = rest.firstIndex(of: "\"") else { return ("", nil) }
        let afterFirst = rest[rest.index(after: firstQuote)...]
        guard let secondQuote = afterFirst.firstIndex(of: "\"") else { return ("", nil) }
        let name = String(afterFirst[..<secondQuote])
        let afterSecond = afterFirst[afterFirst.index(after: secondQuote)...]
        if let idRange = afterSecond.range(of: "id:") {
            let idStr = afterSecond[idRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, idStr.isEmpty ? nil : idStr)
        }
        return (name, nil)
    }
}
