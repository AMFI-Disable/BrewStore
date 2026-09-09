import Combine
import Foundation
import SwiftUI

enum BrewStoreActionReviewKind: Equatable {
    case install(packages: [BrewStorePackage])
    case upgrade(packages: [BrewStorePackage])
    case adopt(items: [ScannedAppItem])
    case brewfileImport(entries: [ImportedBrewfileEntry], taps: [String])
    case settingsReset(options: Set<BrewStoreResetOption>)
    case wishlistCollectionDelete(collection: BrewStoreCollection)

    var title: String {
        switch self {
        case let .install(pkgs):
            pkgs.count == 1 ? "Review Installation" : "Review Batch Installation"
        case let .upgrade(pkgs):
            pkgs.count == 1 ? "Review Update" : "Review Batch Update"
        case let .adopt(items):
            items.count == 1 ? "Review App Adoption" : "Review Batch App Adoption"
        case .brewfileImport:
            "Review Brewfile Import"
        case .settingsReset:
            "Review Settings Reset"
        case .wishlistCollectionDelete:
            "Review Collection Deletion"
        }
    }

    var confirmationTitle: String {
        switch self {
        case let .install(pkgs):
            return pkgs.count == 1 ? "Install \(pkgs[0].name)" : "Install \(pkgs.count) Packages"
        case let .upgrade(pkgs):
            return pkgs.count == 1 ? "Upgrade \(pkgs[0].name)" : "Upgrade \(pkgs.count) Packages"
        case let .adopt(items):
            return items.count == 1 ? "Adopt \(items[0].appName)" : "Adopt \(items.count) Applications"
        case let .brewfileImport(entries, _):
            let count = entries.filter { !$0.isInstalled }.count
            return "Import & Install \(count) Packages"
        case let .settingsReset(opts):
            return "Reset \(opts.count) Option\(opts.count == 1 ? "" : "s")"
        case .wishlistCollectionDelete:
            return "Delete Collection"
        }
    }

    var icon: String {
        switch self {
        case .install: "arrow.down.circle.fill"
        case .upgrade: "arrow.triangle.2.circlepath.circle.fill"
        case .adopt: "arrow.down.app.fill"
        case .brewfileImport: "doc.badge.plus"
        case .settingsReset: "arrow.counterclockwise.circle.fill"
        case .wishlistCollectionDelete: "trash.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .install: .blue
        case .upgrade: .orange
        case .adopt: .blue
        case .brewfileImport: .blue
        case .settingsReset: .orange
        case .wishlistCollectionDelete: .red
        }
    }

    var isDestructive: Bool {
        switch self {
        case .install, .upgrade, .adopt, .brewfileImport: false
        case let .settingsReset(opts):
            opts.contains { $0.tier == .danger || $0.tier == .dangerDanger }
        case .wishlistCollectionDelete: true
        }
    }
}

struct BrewStoreActionReviewItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let badgeText: String?
    let badgeColor: Color
    let command: String?

    init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        badgeText: String? = nil,
        badgeColor: Color = .secondary,
        command: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.badgeText = badgeText
        self.badgeColor = badgeColor
        self.command = command
    }
}

struct BrewStoreActionReviewRequest: Identifiable {
    let id = UUID()
    let kind: BrewStoreActionReviewKind
    let title: String
    let subtitle: String
    let confirmationTitle: String
    let isDestructive: Bool
    let accentColor: Color
    let items: [BrewStoreActionReviewItem]
    let notes: [String]
    let commandPreview: String?
    fileprivate let onConfirmAction: () -> Void
    fileprivate let onCancelAction: (() -> Void)?

    init(
        kind: BrewStoreActionReviewKind,
        title: String? = nil,
        subtitle: String,
        confirmationTitle: String? = nil,
        isDestructive: Bool? = nil,
        accentColor: Color? = nil,
        items: [BrewStoreActionReviewItem],
        notes: [String] = [],
        commandPreview: String? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = title ?? kind.title
        self.subtitle = subtitle
        self.confirmationTitle = confirmationTitle ?? kind.confirmationTitle
        self.isDestructive = isDestructive ?? kind.isDestructive
        self.accentColor = accentColor ?? kind.accentColor
        self.items = items
        self.notes = notes
        self.commandPreview = commandPreview
        self.onConfirmAction = onConfirm
        self.onCancelAction = onCancel
    }
}

@MainActor
final class BrewStoreActionReviewCoordinator: ObservableObject {
    static let shared = BrewStoreActionReviewCoordinator()

    @Published var pendingReview: BrewStoreActionReviewRequest?

    init() {}

    // MARK: - Direct Install Review

    func requestInstall(
        package: BrewStorePackage,
        manager: HomebrewManager,
        onConfirm: @escaping () -> Void
    ) {
        requestInstall(packages: [package], manager: manager, onConfirm: onConfirm)
    }

    func requestInstall(
        packages: [BrewStorePackage],
        manager _: HomebrewManager,
        onConfirm: @escaping () -> Void
    ) {
        guard !packages.isEmpty else { return }

        let items: [BrewStoreActionReviewItem] = packages.map { pkg in
            let cmd = "brew install \(pkg.kind == .cask ? "--cask " : "")\(pkg.id)"
            let desc = pkg.description.isEmpty ? pkg.displayKind : pkg.description
            return BrewStoreActionReviewItem(
                id: "\(pkg.kind.rawValue):\(pkg.id)",
                title: pkg.name,
                subtitle: "\(pkg.version.isEmpty ? "" : "v\(pkg.version) • ")\(desc)",
                icon: pkg.kind == .cask ? "app.fill" : "terminal.fill",
                badgeText: pkg.kind == .cask ? "Cask" : "Formula",
                badgeColor: pkg.kind == .cask ? .blue : .green,
                command: cmd
            )
        }

        let cmdPreview: String
        if packages.count == 1 {
            cmdPreview = items.first?.command ?? ""
        } else {
            let caskIDs = packages.filter { $0.kind == .cask }.map(\.id)
            let formulaIDs = packages.filter { $0.kind == .formula }.map(\.id)
            var cmds: [String] = []
            if !caskIDs.isEmpty {
                cmds.append("brew install --cask \(caskIDs.joined(separator: " "))")
            }
            if !formulaIDs.isEmpty {
                cmds.append("brew install \(formulaIDs.joined(separator: " "))")
            }
            cmdPreview = cmds.joined(separator: "\n")
        }

        let subtitle = packages.count == 1
            ? "Review package details and planned Homebrew installation before downloading."
            : "Review \(packages.count) packages to be installed onto your Mac."

        var notes: [String] = []
        let dependenciesCount = packages.flatMap(\.dependencies).count
        if dependenciesCount > 0 {
            notes.append("Installation may also pull up to \(dependenciesCount) direct dependencies required for execution.")
        }

        pendingReview = BrewStoreActionReviewRequest(
            kind: .install(packages: packages),
            subtitle: subtitle,
            items: items,
            notes: notes,
            commandPreview: cmdPreview,
            onConfirm: onConfirm
        )
    }

    // MARK: - Upgrade Review

    func requestUpgrade(
        package: BrewStorePackage,
        manager: HomebrewManager,
        onConfirm: @escaping () -> Void
    ) {
        requestUpgrade(packages: [package], manager: manager, onConfirm: onConfirm)
    }

    func requestUpgrade(
        packages: [BrewStorePackage],
        manager _: HomebrewManager,
        onConfirm: @escaping () -> Void
    ) {
        guard !packages.isEmpty else { return }

        let items: [BrewStoreActionReviewItem] = packages.map { pkg in
            let fromVer = pkg.installedVersion ?? "current"
            let toVer = pkg.version.isEmpty ? "latest" : pkg.version
            let cmd = "brew upgrade \(pkg.id)"
            return BrewStoreActionReviewItem(
                id: "\(pkg.kind.rawValue):\(pkg.id)",
                title: pkg.name,
                subtitle: "v\(fromVer) → v\(toVer)",
                icon: pkg.kind == .cask ? "app.fill" : "terminal.fill",
                badgeText: "Update Available",
                badgeColor: .orange,
                command: cmd
            )
        }

        let cmdPreview: String = if packages.count == 1 {
            items.first?.command ?? ""
        } else {
            "brew upgrade \(packages.map(\.id).joined(separator: " "))"
        }

        let subtitle = packages.count == 1
            ? "Review version transition before updating \(packages[0].name)."
            : "Review version updates for \(packages.count) packages."

        let est = BrewStoreUpdateEstimator.estimate(for: packages)
        let notes: [String] = [
            "Estimated total time: ~\(est.formattedEstimate).",
            est.detailedSummary
        ]

        pendingReview = BrewStoreActionReviewRequest(
            kind: .upgrade(packages: packages),
            subtitle: subtitle,
            items: items,
            notes: notes,
            commandPreview: cmdPreview,
            onConfirm: onConfirm
        )
    }

    // MARK: - App Adoption Review

    func requestAdopt(
        item: ScannedAppItem,
        manager: HomebrewManager,
        onConfirm: @escaping () -> Void
    ) {
        requestAdopt(items: [item], manager: manager, onConfirm: onConfirm)
    }

    func requestAdopt(
        items: [ScannedAppItem],
        manager _: HomebrewManager,
        onConfirm: @escaping () -> Void
    ) {
        guard !items.isEmpty else { return }

        let reviewItems: [BrewStoreActionReviewItem] = items.compactMap { (item: ScannedAppItem) -> BrewStoreActionReviewItem? in
            guard let cask = item.matchedCask else { return nil }
            let cmd = "brew install --cask --adopt \(cask.id)"
            let installedVer = item.installedVersion.map { "Installed: \(BrewStorePackage.formatDisplayVersion($0)) • " } ?? ""
            let latestVer = "Cask: \(cask.displayVersion)"
            return BrewStoreActionReviewItem(
                id: item.id,
                title: item.appName,
                subtitle: "\(installedVer)\(latestVer)\nPath: \(item.appPath)",
                icon: "app.fill",
                badgeText: item.matchConfidence.rawValue,
                badgeColor: item.matchConfidence.isVerifiedSafe ? .green : .orange,
                command: cmd
            )
        }

        let caskTokens = items.compactMap { $0.matchedCask?.id }
        let cmdPreview = "brew install --cask --adopt \(caskTokens.joined(separator: " "))"

        let subtitle = items.count == 1
            ? "Review Homebrew Caskroom adoption details for \(items[0].appName)."
            : "Review \(items.count) applications to be adopted into Homebrew management."

        let notes: [String] = [
            "Adopting links your existing app with Homebrew without overwriting any app data or settings.",
            "Future updates for adopted apps will be handled automatically through BrewStore.",
            "Rollback is safe: unlinking or uninstalling via Homebrew leaves your application settings intact."
        ]

        pendingReview = BrewStoreActionReviewRequest(
            kind: .adopt(items: items),
            subtitle: subtitle,
            items: reviewItems,
            notes: notes,
            commandPreview: cmdPreview,
            onConfirm: onConfirm
        )
    }

    // MARK: - Brewfile Import Review

    func requestBrewfileImport(
        entries: [ImportedBrewfileEntry],
        taps: [String],
        onConfirm: @escaping () -> Void
    ) {
        let missing = entries.filter { !$0.isInstalled && $0.isSelected }
        guard !missing.isEmpty else { return }

        let items: [BrewStoreActionReviewItem] = missing.map { entry in
            BrewStoreActionReviewItem(
                id: "\(entry.kind.rawValue):\(entry.rawName)",
                title: entry.rawName,
                subtitle: entry.matchedPackage?.description ?? "Package listed in Brewfile bundle",
                icon: entry.kind == .cask ? "app.fill" : "terminal.fill",
                badgeText: entry.kind.rawValue,
                badgeColor: entry.kind == .cask ? .blue : .green,
                command: "brew install \(entry.kind == .cask ? "--cask " : "")\(entry.rawName)"
            )
        }

        var notes: [String] = []
        if !taps.isEmpty {
            notes.append("Will automatically tap \(taps.count) repository/repositories: \(taps.joined(separator: ", ")).")
        }
        notes.append("Existing installed software in the Brewfile will be left intact.")

        pendingReview = BrewStoreActionReviewRequest(
            kind: .brewfileImport(entries: entries, taps: taps),
            subtitle: "Review \(missing.count) missing packages to install from your Brewfile.",
            items: items,
            notes: notes,
            commandPreview: "brew bundle --file=Brewfile",
            onConfirm: onConfirm
        )
    }

    // MARK: - Settings Reset Review

    func requestSettingsReset(
        options: Set<BrewStoreResetOption>,
        onConfirm: @escaping () -> Void
    ) {
        guard !options.isEmpty else { return }

        let sorted = options.sorted { a, b in
            if a.tier != b.tier {
                return a.tier.rawValue < b.tier.rawValue
            }
            return a.rawValue < b.rawValue
        }

        let items: [BrewStoreActionReviewItem] = sorted.map { opt in
            BrewStoreActionReviewItem(
                id: opt.id,
                title: opt.rawValue,
                subtitle: opt.description,
                icon: opt.icon,
                badgeText: opt.tier.rawValue,
                badgeColor: opt.tier.badgeColor,
                command: nil
            )
        }

        let isDestructive = options.contains { $0.tier == .danger || $0.tier == .dangerDanger }
        var notes: [String] = []
        if isDestructive {
            notes.append("Warning: Selected options include Homebrew system modifications or package removals.")
        } else {
            notes.append("Your installed software binaries will remain safe on disk.")
        }

        pendingReview = BrewStoreActionReviewRequest(
            kind: .settingsReset(options: options),
            subtitle: "Review the \(options.count) reset operation\(options.count == 1 ? "" : "s") before execution.",
            items: items,
            notes: notes,
            onConfirm: onConfirm
        )
    }

    // MARK: - Wishlist Collection Deletion Review

    func requestWishlistCollectionDelete(
        collection: BrewStoreCollection,
        onConfirm: @escaping () -> Void
    ) {
        let items = [
            BrewStoreActionReviewItem(
                id: collection.id.uuidString,
                title: collection.title,
                subtitle: "\(collection.packageIDs.count) package\(collection.packageIDs.count == 1 ? "" : "s") grouped • \(collection.description.isEmpty ? "Custom Collection" : collection.description)",
                icon: "folder.fill",
                badgeText: "Collection",
                badgeColor: .red,
                command: nil
            )
        ]

        let notes = [
            "Deleting this collection does NOT uninstall any software.",
            "All packages in this collection will remain installed on your Mac."
        ]

        pendingReview = BrewStoreActionReviewRequest(
            kind: .wishlistCollectionDelete(collection: collection),
            subtitle: "Are you sure you want to delete '\(collection.title)'?",
            items: items,
            notes: notes,
            onConfirm: onConfirm
        )
    }

    // MARK: - Lifecycle

    func confirm() {
        guard let request = pendingReview else { return }
        pendingReview = nil
        request.onConfirmAction()
    }

    func cancel() {
        guard let request = pendingReview else { return }
        pendingReview = nil
        request.onCancelAction?()
    }
}
