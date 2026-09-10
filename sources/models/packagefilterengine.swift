import Foundation

enum PackageLicenseFilter: String, CaseIterable, Identifiable {
    case all = "All Licenses"
    case openSource = "Free & Open Source (FOSS)"
    case proprietary = "Proprietary / Freeware"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .all: "tag"
        case .openSource: "lock.open.fill"
        case .proprietary: "lock.fill"
        }
    }
}

enum PackageEditorialFilter: String, CaseIterable, Identifiable {
    case all = "All Packages"
    case editorsPick = "Editor's Picks"
    case official = "Official Taps (core & cask)"
    case thirdParty = "Third-Party Taps"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .editorsPick: "star.fill"
        case .official: "checkmark.seal.fill"
        case .thirdParty: "cube.transparent"
        }
    }
}

enum PackageTimeframeFilter: String, CaseIterable, Identifiable {
    case days7 = "7-Day Installs"
    case days30 = "30-Day Installs"
    case days90 = "90-Day Installs"
    case days365 = "365-Day Installs"

    var id: String {
        rawValue
    }

    var multiplier: Double {
        switch self {
        case .days7: 7.0 / 30.0
        case .days30: 1.0
        case .days90: 3.0
        case .days365: 12.0
        }
    }
}

enum PackageSortOption: String, CaseIterable, Identifiable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case mostPopular = "Most Popular"
    case highGrowth = "Growth Velocity"
    case largestDisk = "Estimated Disk Size"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .nameAsc: "arrow.up"
        case .nameDesc: "arrow.down"
        case .mostPopular: "flame.fill"
        case .highGrowth: "chart.line.uptrend.xyaxis"
        case .largestDisk: "internaldrive"
        }
    }
}

enum PackageGroupingOption: String, CaseIterable, Identifiable {
    case none = "No Grouping"
    case category = "Category"
    case tap = "Tap / Provider"
    case status = "Status (Installed / Available)"
    case license = "License"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .none: "rectangle.grid.1x2"
        case .category: "folder.fill"
        case .tap: "square.3.layers.3d.down.forward"
        case .status: "checkmark.circle"
        case .license: "tag.fill"
        }
    }
}

enum BrewStorePackageFilterEngine {
    /// Known proprietary casks / non-FOSS packages
    private static let proprietaryIdentifiers: Set<String> = [
        "microsoft-edge", "google-chrome", "slack", "discord", "spotify",
        "zoom", "dropbox", "1password", "notion", "figma", "sublime-text",
        "postman", "docker-desktop", "adobe-creative-cloud", "raycast", "alfred"
    ]

    static func isProprietary(package: BrewStorePackage) -> Bool {
        if proprietaryIdentifiers.contains(package.id.lowercased()) {
            return true
        }
        if package.kind == .formula {
            // Standard Homebrew Core formulae are almost exclusively open-source
            return false
        }
        return false
    }

    static func filterAndSort(
        packages: [BrewStorePackage],
        query: String,
        kind: BrewPackageKind?,
        tap: String,
        pinnedOnly: Bool,
        updatesOnly: Bool,
        license: PackageLicenseFilter,
        editorial: PackageEditorialFilter,
        sort: PackageSortOption,
        pinnedIDs: Set<String>? = nil
    ) -> [BrewStorePackage] {
        let filtered = packages.filter { pkg in
            // Kind filter
            if let targetKind = kind, pkg.kind != targetKind {
                return false
            }
            // Updates filter
            if updatesOnly, !pkg.isOutdated {
                return false
            }
            // Tap filter
            if tap != "All Taps", pkg.tap != tap {
                return false
            }
            // Pinned filter
            if pinnedOnly {
                let isPinned = pkg.isPinned || (pinnedIDs?.contains(pkg.id.lowercased()) ?? false)
                if !isPinned {
                    return false
                }
            }
            // License filter
            if license == .openSource, isProprietary(package: pkg) {
                return false
            }
            if license == .proprietary, !isProprietary(package: pkg) {
                return false
            }
            // Editorial filter
            if editorial == .editorsPick, TrendingRankingsManager.badge(for: pkg) == nil {
                return false
            }
            if editorial == .official, !(pkg.tap?.hasPrefix("homebrew/") ?? true) {
                return false
            }
            if editorial == .thirdParty, pkg.tap?.hasPrefix("homebrew/") ?? true {
                return false
            }
            // Search query with fuzzy scoring
            if !query.isEmpty {
                let s = BrewStoreFuzzySearchEngine.bestScore(query: query, targets: [pkg.name, pkg.id, pkg.description])
                if s == 0 {
                    return false
                }
            }
            return true
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty, sort == .nameAsc {
            return filtered.sorted { p1, p2 in
                let s1 = BrewStoreFuzzySearchEngine.bestScore(query: trimmedQuery, targets: [p1.name, p1.id, p1.description])
                let s2 = BrewStoreFuzzySearchEngine.bestScore(query: trimmedQuery, targets: [p2.name, p2.id, p2.description])
                if s1 != s2 {
                    return s1 > s2
                }
                return p1.name.localizedCaseInsensitiveCompare(p2.name) == .orderedAscending
            }
        }

        // Sorting
        switch sort {
        case .nameAsc:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .mostPopular:
            return filtered.sorted {
                let score0 = TrendingRankingsManager.badge(for: $0) != nil ? 1 : 0
                let score1 = TrendingRankingsManager.badge(for: $1) != nil ? 1 : 0
                if score0 != score1 {
                    return score0 > score1
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .highGrowth:
            return filtered.sorted {
                let badge0 = TrendingRankingsManager.badge(for: $0)
                let badge1 = TrendingRankingsManager.badge(for: $1)
                return (badge0 != nil) && (badge1 == nil)
            }
        case .largestDisk:
            return filtered.sorted {
                let size0 = BrewStoreBottleFootprintEstimator.estimateFootprint(for: $0).estimatedCellarFootprintMB
                let size1 = BrewStoreBottleFootprintEstimator.estimateFootprint(for: $1).estimatedCellarFootprintMB
                return size0 > size1
            }
        }
    }

    static func groupPackages(_ packages: [BrewStorePackage], by grouping: PackageGroupingOption) -> [(title: String, packages: [BrewStorePackage])] {
        switch grouping {
        case .none:
            return [("All Packages", packages)]
        case .tap:
            let dict = Dictionary(grouping: packages, by: { $0.tap ?? "homebrew/core" })
            return dict.keys.sorted().map { (title: $0, packages: dict[$0] ?? []) }
        case .status:
            let installed = packages.filter(\.isInstalled)
            let available = packages.filter { !$0.isInstalled }
            var result: [(title: String, packages: [BrewStorePackage])] = []
            if !installed.isEmpty {
                result.append(("Installed (\(installed.count))", installed))
            }
            if !available.isEmpty {
                result.append(("Available (\(available.count))", available))
            }
            return result
        case .license:
            let foss = packages.filter { !isProprietary(package: $0) }
            let proprietary = packages.filter { isProprietary(package: $0) }
            var result: [(title: String, packages: [BrewStorePackage])] = []
            if !foss.isEmpty {
                result.append(("Free & Open Source (FOSS) (\(foss.count))", foss))
            }
            if !proprietary.isEmpty {
                result.append(("Proprietary / Freeware (\(proprietary.count))", proprietary))
            }
            return result
        case .category:
            let dict = Dictionary(grouping: packages, by: { $0.kind == .cask ? "macOS GUI Applications" : "CLI Formulae & Tools" })
            return dict.keys.sorted().map { (title: $0, packages: dict[$0] ?? []) }
        }
    }
}
