import Foundation

enum BrewStoreAlternativeRecommendationManager {
    static let curatedAlternatives: [String: [String]] = [
        "docker": ["orbstack", "colima", "podman"],
        "docker-desktop": ["orbstack", "colima", "podman"],
        "orbstack": ["docker", "colima", "podman"],
        "colima": ["orbstack", "docker", "podman"],
        "podman": ["docker", "orbstack", "colima"],

        "visual-studio-code": ["cursor", "zed", "sublime-text", "neovim"],
        "cursor": ["visual-studio-code", "zed", "sublime-text"],
        "zed": ["visual-studio-code", "cursor", "sublime-text"],
        "sublime-text": ["visual-studio-code", "cursor", "zed"],

        "neovim": ["helix", "emacs", "kakoune", "micro"],
        "helix": ["neovim", "kakoune", "emacs", "micro"],
        "emacs": ["neovim", "helix", "kakoune"],

        "iterm2": ["alacritty", "kitty", "warp", "wezterm", "ghostty"],
        "alacritty": ["iterm2", "kitty", "warp", "wezterm", "ghostty"],
        "kitty": ["alacritty", "iterm2", "warp", "wezterm", "ghostty"],
        "warp": ["iterm2", "alacritty", "kitty", "wezterm"],
        "wezterm": ["alacritty", "kitty", "iterm2", "ghostty"],

        "ripgrep": ["fd", "bat", "the_silver_searcher"],
        "the_silver_searcher": ["ripgrep", "fd", "bat"],
        "fd": ["ripgrep", "bat", "fzf"],
        "bat": ["ripgrep", "fd", "eza"],
        "eza": ["lsd", "bat", "tree"],
        "lsd": ["eza", "bat", "tree"],
        "fzf": ["fd", "ripgrep", "fzy"],

        "postman": ["insomnia", "httpie", "bruno"],
        "insomnia": ["postman", "bruno", "httpie"],
        "bruno": ["insomnia", "postman", "httpie"],
        "httpie": ["curl", "postman", "insomnia"],

        "raycast": ["alfred", "sol"],
        "alfred": ["raycast", "sol"],

        "google-chrome": ["brave-browser", "firefox", "arc", "zen-browser"],
        "brave-browser": ["google-chrome", "firefox", "arc", "zen-browser"],
        "firefox": ["google-chrome", "brave-browser", "arc", "zen-browser"],
        "arc": ["zen-browser", "brave-browser", "google-chrome"],
        "zen-browser": ["arc", "firefox", "brave-browser"],

        "vlc": ["iina", "mpv"],
        "iina": ["vlc", "mpv"],
        "mpv": ["iina", "vlc"],

        "ffmpeg": ["yt-dlp", "handbrake"],
        "yt-dlp": ["ffmpeg", "aria2"],
        "handbrake": ["ffmpeg", "yt-dlp"],

        "postgresql@16": ["mysql", "sqlite", "mariadb"],
        "postgresql@14": ["postgresql@16", "mysql", "sqlite"],
        "postgresql": ["mysql", "sqlite", "mariadb"],
        "mysql": ["postgresql@16", "mariadb", "sqlite"],
        "redis": ["memcached", "keydb"],
        "nginx": ["caddy", "apache2", "traefik"],
        "caddy": ["nginx", "traefik", "apache2"]
    ]

    static func findAlternatives(for package: BrewStorePackage, in allPackages: [BrewStorePackage]) -> [BrewStorePackage] {
        let packageMap = Dictionary(allPackages.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let lowerID = package.id.lowercased()

        // 1. Direct curated match
        if let directList = curatedAlternatives[lowerID] {
            let matched = directList.compactMap { packageMap[$0.lowercased()] }
            if !matched.isEmpty {
                return matched
            }
        }

        // 2. Keyword heuristic based on tokens in description
        let stopWords: Set<String> = ["a", "an", "the", "for", "and", "or", "in", "to", "of", "with", "is", "by", "on", "as", "fast", "simple", "modern"]
        let tokens = Set(package.description.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0) })

        if !tokens.isEmpty {
            let scored = allPackages.filter { $0.id != package.id && $0.kind == package.kind }.compactMap { candidate -> (pkg: BrewStorePackage, score: Int)? in
                let candidateTokens = Set(candidate.description.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
                let intersection = tokens.intersection(candidateTokens)
                if !intersection.isEmpty {
                    return (candidate, intersection.count)
                }
                return nil
            }
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map(\.pkg)

            if !scored.isEmpty {
                return Array(scored)
            }
        }

        // 3. Fallback: same kind packages with similar names
        return allPackages
            .filter { $0.id != package.id && $0.kind == package.kind && $0.name.prefix(1).lowercased() == package.name.prefix(1).lowercased() }
            .prefix(4)
            .map { $0 }
    }
}
