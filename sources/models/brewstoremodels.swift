import Foundation

enum BrewPackageKind: String, CaseIterable, Identifiable, Codable {
    case cask = "Apps"
    case formula = "Formulae"

    var id: String { rawValue }
    var brewFlag: String { self == .cask ? "--cask" : "--formula" }
}

struct BrewStorePackage: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let description: String
    let homepage: String
    let version: String
    let kind: BrewPackageKind
    let applicationNames: [String]
    var isInstalled: Bool
    var isOutdated: Bool

    var displayKind: String { kind == .cask ? "Application" : "Command-line formula" }
}

struct BrewStoreService: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let status: String
    let user: String?
    let file: String?
}

struct BrewStoreTap: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

enum BrewStoreSection: String, CaseIterable, Identifiable {
    case apps = "Apps"
    case formulae = "Formulae"
    case updates = "Updates"
    case services = "Services"
    case taps = "Taps"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .apps: return "shippingbox.fill"
        case .formulae: return "terminal.fill"
        case .updates: return "arrow.triangle.2.circlepath"
        case .services: return "gearshape.2.fill"
        case .taps: return "square.3.layers.3d.down.forward"
        case .settings: return "gearshape.fill"
        }
    }
}
