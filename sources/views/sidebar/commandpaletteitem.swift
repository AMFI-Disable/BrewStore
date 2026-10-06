import AppKit
import SwiftUI

enum PaletteCategory: String, CaseIterable {
    case actions = "Actions & Maintenance"
    case services = "Background Services"
    case packages = "Packages & Casks"
    case navigation = "Navigation"
}

struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let category: PaletteCategory
    let shortcut: String?
    let isInstalled: Bool?
    let kind: BrewPackageKind?
    let package: BrewStorePackage?
    let service: BrewStoreService?
    let commandSnippet: String?
    let impactBadge: String?
    let execute: () -> Void

    init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        category: PaletteCategory,
        shortcut: String?,
        isInstalled: Bool?,
        kind: BrewPackageKind?,
        package: BrewStorePackage?,
        service: BrewStoreService?,
        commandSnippet: String? = nil,
        impactBadge: String? = nil,
        execute: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.shortcut = shortcut
        self.isInstalled = isInstalled
        self.kind = kind
        self.package = package
        self.service = service
        self.commandSnippet = commandSnippet
        self.impactBadge = impactBadge
        self.execute = execute
    }

    init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        category: PaletteCategory,
        shortcut: String?,
        isInstalled: Bool?,
        kind: BrewPackageKind?,
        package: BrewStorePackage?,
        service: BrewStoreService?,
        execute: @escaping () -> Void
    ) {
        self.init(
            id: id,
            title: title,
            subtitle: subtitle,
            icon: icon,
            category: category,
            shortcut: shortcut,
            isInstalled: isInstalled,
            kind: kind,
            package: package,
            service: service,
            commandSnippet: nil,
            impactBadge: nil,
            execute: execute
        )
    }
}
