import Foundation

enum BrewStoreSidebarGroup: String, CaseIterable, Identifiable {
    case storefront = "Storefront"
    case packageLibrary = "Package Library"
    case developerAndCreator = "Developer & Creator"
    case systemAndMaintenance = "System & Maintenance"

    var id: String {
        rawValue
    }

    var accessibilityIdentifier: String {
        switch self {
        case .storefront: "Sidebar.Section.Storefront"
        case .packageLibrary: "Sidebar.Section.PackageLibrary"
        case .developerAndCreator: "Sidebar.Section.DeveloperAndCreator"
        case .systemAndMaintenance: "Sidebar.Section.SystemAndMaintenance"
        }
    }
}

enum BrewStoreSidebarDestinationRegistry {
    /// All authentic navigation destinations
    static let selectableDestinations: [BrewStoreSection] = BrewStoreSection.allCases

    /// Set of raw values for valid destinations
    static let validDestinationRawValues: Set<String> = Set(selectableDestinations.map(\.rawValue))

    /// Set of section IDs for valid destinations
    static let validDestinationIDs: Set<String> = Set(selectableDestinations.map(\.id))

    /// Non-selectable sidebar group labels
    static let groupHeaderTitles: Set<String> = Set(BrewStoreSidebarGroup.allCases.map(\.rawValue))

    /// Accessibility identifiers corresponding to group headers
    static let groupHeaderAccessibilityIDs: Set<String> = Set(BrewStoreSidebarGroup.allCases.map(\.accessibilityIdentifier))

    /// Returns true ONLY if the provided identifier represents an actual selectable destination
    static func isSelectableDestination(identifier: String) -> Bool {
        validDestinationRawValues.contains(identifier) || validDestinationIDs.contains(identifier)
    }

    /// Returns true if the identifier or title belongs to a non-selectable group heading
    static func isGroupHeader(identifier: String) -> Bool {
        groupHeaderTitles.contains(identifier) || groupHeaderAccessibilityIDs.contains(identifier)
    }

    /// Safely resolves a proposed selection, returning the section if valid or nil if it's a group header or invalid
    static func resolveSelection(from identifier: String) -> BrewStoreSection? {
        guard !isGroupHeader(identifier: identifier) else { return nil }
        return BrewStoreSection(rawValue: identifier)
    }
}
