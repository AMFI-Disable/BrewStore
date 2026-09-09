import Foundation

enum BrewPackageKind: String, CaseIterable, Identifiable, Codable {
    case cask = "Apps"
    case formula = "Formulae"

    var id: String {
        rawValue
    }

    var brewFlag: String {
        self == .cask ? "--cask" : "--formula"
    }
}

struct BrewStorePackage: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let homepage: String
    let version: String
    let kind: BrewPackageKind
    let applicationNames: [String]
    var isInstalled: Bool
    var isOutdated: Bool
    var isPinned: Bool
    var tap: String?
    var dependencies: [String]
    var dependents: [String]
    var caveats: String?
    var installedVersion: String?

    var displayKind: String {
        kind == .cask ? "Application" : "Command-line formula"
    }

    static func formatDisplayVersion(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") || v.hasPrefix("V") {
            v.removeFirst()
        }
        if v.contains(",") {
            let components = v.components(separatedBy: ",")
            if let primary = components.first, !primary.isEmpty {
                return "v\(primary)"
            }
        }
        return "v\(v)"
    }

    var displayVersion: String {
        Self.formatDisplayVersion(version)
    }

    var displayInstalledVersion: String? {
        guard let installedVersion, !installedVersion.isEmpty else { return nil }
        return Self.formatDisplayVersion(installedVersion)
    }

    init(
        id: String,
        name: String,
        description: String,
        homepage: String,
        version: String,
        kind: BrewPackageKind,
        applicationNames: [String] = [],
        isInstalled: Bool = false,
        isOutdated: Bool = false,
        isPinned: Bool = false,
        tap: String? = nil,
        dependencies: [String] = [],
        dependents: [String] = [],
        caveats: String? = nil,
        installedVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.homepage = homepage
        self.version = version
        self.kind = kind
        self.applicationNames = applicationNames
        self.isInstalled = isInstalled
        self.isOutdated = isOutdated
        self.isPinned = isPinned
        self.tap = tap
        self.dependencies = dependencies
        self.dependents = dependents
        self.caveats = caveats
        self.installedVersion = installedVersion
    }

    func cellarURL(prefix: String? = nil) -> URL? {
        guard kind == .formula && isInstalled else { return nil }
        let basePrefix = prefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let candidate = URL(fileURLWithPath: basePrefix).appendingPathComponent("Cellar", isDirectory: true).appendingPathComponent(id, isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}

struct BrewStoreService: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let status: String
    let user: String?
    let file: String?
    var isRunning: Bool {
        status.lowercased().contains("started") || status.lowercased().contains("running")
    }

    var isError: Bool {
        status.lowercased().contains("error")
    }

    func logURL(prefix: String? = nil) -> URL? {
        let basePrefix = prefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let candidates = [
            URL(fileURLWithPath: basePrefix).appendingPathComponent("var/log/\(name).log"),
            URL(fileURLWithPath: basePrefix).appendingPathComponent("var/log/\(name)/\(name).log"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/homebrew.mxcl.\(name).log"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(name).log")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates.first
    }

    func configURL(prefix: String? = nil) -> URL? {
        let basePrefix = prefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let candidates = [
            URL(fileURLWithPath: basePrefix).appendingPathComponent("etc/\(name)/\(name).conf"),
            URL(fileURLWithPath: basePrefix).appendingPathComponent("etc/\(name).conf"),
            URL(fileURLWithPath: basePrefix).appendingPathComponent("etc/\(name)/config"),
            URL(fileURLWithPath: basePrefix).appendingPathComponent("etc/\(name)")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

struct BrewStoreTap: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    var isOfficial: Bool {
        name.hasPrefix("homebrew/")
    }
}

enum BrewStoreSection: String, CaseIterable, Identifiable {
    // Storefront
    case discover = "Discover"
    case showdown = "Community Picks"
    case allApps = "All Applications"
    case allFormulae = "All CLI Tools"
    case stories = "Stories"
    case toolkits = "Toolkits"
    case categories = "Categories"

    // Library
    case installed = "Installed"
    case adoption = "Adoption & Replacements"
    case topology = "Dependencies"
    case wishlist = "Wishlist"
    case services = "Services"
    case taps = "Taps"
    case creator = "Creator Studio"

    // System
    case updates = "Updates"
    case backups = "Backups"
    case settings = "Settings"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .discover: "sparkles"
        case .showdown: "trophy.fill"
        case .allApps: "macwindow.on.rectangle"
        case .allFormulae: "terminal.fill"
        case .stories: "book.pages.fill"
        case .toolkits: "square.stack.3d.up.fill"
        case .categories: "square.grid.2x2.fill"
        case .installed: "shippingbox.fill"
        case .adoption: "arrow.down.app.fill"
        case .topology: "point.3.connected.trianglepath.dotted"
        case .wishlist: "star.fill"
        case .services: "gearshape.2.fill"
        case .taps: "square.3.layers.3d.down.forward"
        case .creator: "hammer.circle.fill"
        case .updates: "arrow.triangle.2.circlepath"
        case .backups: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }
}

enum BrewStoreHub: String, CaseIterable, Identifiable {
    case storefront = "Storefront"
    case myMac = "My Mac"
    case environment = "Environment"
    case health = "Health & Maintenance"
    case settings = "Settings"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .storefront: "storefront.fill"
        case .myMac: "shippingbox.fill"
        case .environment: "bolt.horizontal.fill"
        case .health: "heart.text.square.fill"
        case .settings: "gearshape.fill"
        }
    }

    var defaultSection: BrewStoreSection {
        switch self {
        case .storefront: .discover
        case .myMac: .installed
        case .environment: .services
        case .health: .backups
        case .settings: .settings
        }
    }

    var subSections: [BrewStoreSection] {
        switch self {
        case .storefront:
            [.discover, .allApps, .allFormulae, .stories, .toolkits, .categories, .showdown]
        case .myMac:
            [.installed, .updates, .wishlist, .adoption, .topology]
        case .environment:
            [.services, .taps, .creator]
        case .health:
            [.backups]
        case .settings:
            [.settings]
        }
    }
}

extension BrewStoreSection {
    var hub: BrewStoreHub {
        switch self {
        case .discover, .showdown, .allApps, .allFormulae, .stories, .toolkits, .categories:
            .storefront
        case .installed, .updates, .wishlist, .adoption, .topology:
            .myMac
        case .services, .taps, .creator:
            .environment
        case .backups:
            .health
        case .settings:
            .settings
        }
    }
}
