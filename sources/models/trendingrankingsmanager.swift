import Foundation

struct TrendingBadge: Hashable, Codable {
    let title: String
    let icon: String
    let colorName: String
}

enum TrendingRankingsManager {
    static let top10FormulaeIDs: Set<String> = [
        "openssl@3", "git", "python@3.12", "node", "ripgrep", "wget", "curl", "cmake", "gh", "ffmpeg"
    ]

    static let top10CaskIDs: Set<String> = [
        "visual-studio-code", "google-chrome", "docker", "iterm2", "raycast", "spotify", "slack", "vlc", "notion", "telegram"
    ]

    static func badge(for package: BrewStorePackage) -> TrendingBadge? {
        let lower = package.id.lowercased()

        if top10FormulaeIDs.contains(lower) {
            return TrendingBadge(title: "Top 10 Formula", icon: "flame.fill", colorName: "orange")
        }
        if top10CaskIDs.contains(lower) {
            return TrendingBadge(title: "Top 10 App", icon: "trophy.fill", colorName: "blue")
        }
        if package.isPinned {
            return TrendingBadge(title: "Pinned Version", icon: "pin.fill", colorName: "yellow")
        }
        if package.kind == .cask, package.isInstalled {
            return TrendingBadge(title: "Installed Cask", icon: "checkmark.circle.fill", colorName: "green")
        }
        if lower.hasPrefix("font-") {
            return TrendingBadge(title: "Font Asset", icon: "textformat", colorName: "purple")
        }

        return nil
    }
}
