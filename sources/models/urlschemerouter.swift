import Foundation
import SwiftUI

enum BrewStoreURLRoute: Equatable {
    case package(id: String, kind: BrewPackageKind?)
    case install(id: String, kind: BrewPackageKind?)
    case search(query: String)
    case doctor
    case adopt
    case security
    case settings
    case taps
    case services
    case stacks
    case stories
    case open
}

@MainActor
final class BrewStoreURLSchemeRouter: ObservableObject {
    static let shared = BrewStoreURLSchemeRouter()

    @Published var activeRoute: BrewStoreURLRoute?

    func handle(url: URL) {
        guard let route = Self.parse(url: url) else { return }
        self.activeRoute = route
    }

    nonisolated static func parse(url: URL) -> BrewStoreURLRoute? {
        guard let scheme = url.scheme?.lowercased(), scheme == "brewstore" else { return nil }

        let host = url.host?.lowercased() ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        func queryValue(for names: [String]) -> String? {
            for name in names {
                if let val = queryItems.first(where: { $0.name.lowercased() == name.lowercased() })?.value, !val.isEmpty {
                    return val
                }
            }
            return nil
        }

        let kindParam: BrewPackageKind? = {
            if let k = queryValue(for: ["kind", "type"])?.lowercased() {
                if k == "cask" || k == "app" {
                    return .cask
                }
                if k == "formula" || k == "cli" {
                    return .formula
                }
            }
            return nil
        }()

        switch host {
        case "package", "view":
            let pkgID = queryValue(for: ["id", "name", "pkg"]) ?? pathComponents.first
            if let pkgID, !pkgID.isEmpty {
                return .package(id: pkgID, kind: kindParam)
            }
            return nil

        case "open":
            let pkgID = queryValue(for: ["id", "name", "pkg"]) ?? pathComponents.first
            if let pkgID, !pkgID.isEmpty {
                return .package(id: pkgID, kind: kindParam)
            }
            return .open

        case "install", "add":
            let pkgID = queryValue(for: ["id", "name", "pkg"]) ?? pathComponents.first
            if let pkgID, !pkgID.isEmpty {
                return .install(id: pkgID, kind: kindParam)
            }
            return nil

        case "search", "find":
            let query = queryValue(for: ["q", "query", "term"]) ?? pathComponents.first ?? ""
            return .search(query: query)

        case "doctor", "diagnose", "diagnostics":
            return .doctor

        case "adopt", "migration":
            return .adopt

        case "security", "cve", "audit":
            return .security

        case "settings", "preferences":
            return .settings

        case "taps", "tap":
            return .taps

        case "services", "daemons":
            return .services

        case "stacks", "toolkits":
            return .stacks

        case "stories", "editorial":
            return .stories

        default:
            // Fallback for direct host names e.g. brewstore://docker -> package(docker)
            if !host.isEmpty, host != "localhost" {
                return .package(id: host, kind: kindParam)
            }
            return nil
        }
    }
}
