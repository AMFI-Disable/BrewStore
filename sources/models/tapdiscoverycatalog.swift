import Foundation

struct CuratedTap: Identifiable, Hashable, Codable {
    let id: String // e.g. "homebrew/cask-fonts"
    let name: String
    let category: String
    let description: String
    let website: String
    let featuredPackages: [String]
    let isOfficial: Bool
}

@MainActor
final class BrewStoreTapDiscoveryCatalog: ObservableObject {
    static let shared = BrewStoreTapDiscoveryCatalog()

    static let curatedTaps: [CuratedTap] = [
        CuratedTap(
            id: "homebrew/cask-fonts",
            name: "Homebrew Cask Fonts",
            category: "Typography",
            description: "Over 1,800 open-source programming ligatures, icon fonts, and system typography.",
            website: "https://github.com/Homebrew/homebrew-cask-fonts",
            featuredPackages: ["font-jetbrains-mono", "font-fira-code", "font-hack-nerd-font", "font-sf-mono"],
            isOfficial: true
        ),
        CuratedTap(
            id: "nikitabobko/tap",
            name: "AeroSpace Tiling Window Manager",
            category: "Window Management",
            description: "i3-like tiling window manager for macOS with keyboard-driven multi-monitor workspaces.",
            website: "https://github.com/nikitabobko/AeroSpace",
            featuredPackages: ["aerospace"],
            isOfficial: false
        ),
        CuratedTap(
            id: "hashicorp/tap",
            name: "HashiCorp Official Tools",
            category: "Cloud & DevOps",
            description: "Terraform, Vault, Consul, Nomad, and Packer infrastructure automation packages.",
            website: "https://github.com/hashicorp/homebrew-tap",
            featuredPackages: ["terraform", "vault", "consul", "nomad", "packer"],
            isOfficial: false
        ),
        CuratedTap(
            id: "supabase/tap",
            name: "Supabase Local CLI",
            category: "Databases & Backend",
            description: "Local Postgres database runner, edge functions engine, and schema migration suite.",
            website: "https://github.com/supabase/homebrew-tap",
            featuredPackages: ["supabase"],
            isOfficial: false
        ),
        CuratedTap(
            id: "d12frosted/emacs-plus",
            name: "Emacs Plus",
            category: "Developer Tools",
            description: "GNU Emacs packages with native macOS modern icons, native compilation, and pure GTK.",
            website: "https://github.com/d12frosted/homebrew-emacs-plus",
            featuredPackages: ["emacs-plus@29", "emacs-plus@30"],
            isOfficial: false
        ),
        CuratedTap(
            id: "cloudflare/cloudflare",
            name: "Cloudflare Developer Suite",
            category: "Networking & Cloud",
            description: "Cloudflare Tunnel (cloudflared), Wrangler workers CLI, and zero trust edge tools.",
            website: "https://github.com/cloudflare/homebrew-cloudflare",
            featuredPackages: ["cloudflared"],
            isOfficial: false
        ),
        CuratedTap(
            id: "felixkratz/formulae",
            name: "SketchyBar & JankyBorders",
            category: "macOS Customization",
            description: "Ultra-customizable menu bar replacement and window border highlighter for macOS.",
            website: "https://github.com/FelixKratz/homebrew-formulae",
            featuredPackages: ["sketchybar", "borders"],
            isOfficial: false
        ),
        CuratedTap(
            id: "oven-sh/bun",
            name: "Bun Runtime",
            category: "Developer Tools",
            description: "Incredibly fast all-in-one JavaScript & TypeScript runtime, bundler, and package manager.",
            website: "https://github.com/oven-sh/homebrew-bun",
            featuredPackages: ["bun"],
            isOfficial: false
        ),
        CuratedTap(
            id: "koekeishiya/formulae",
            name: "Yabai & Skhd Window Automation",
            category: "Window Management",
            description: "Tiling window management and modal hotkey daemon for macOS with accessibility APIs.",
            website: "https://github.com/koekeishiya/homebrew-formulae",
            featuredPackages: ["yabai", "skhd"],
            isOfficial: false
        ),
        CuratedTap(
            id: "railwaycat/emacsmacport",
            name: "Emacs Mac Port",
            category: "Developer Tools",
            description: "GNU Emacs with macOS GUI features (smooth scrolling, touch gestures, native clipboard).",
            website: "https://github.com/railwaycat/homebrew-emacsmacport",
            featuredPackages: ["emacs-mac"],
            isOfficial: false
        ),
        CuratedTap(
            id: "derailed/k9s",
            name: "K9s Kubernetes UI",
            category: "Cloud & DevOps",
            description: "Fast terminal-based UI to interact with, observe, and manage Kubernetes clusters.",
            website: "https://github.com/derailed/homebrew-k9s",
            featuredPackages: ["k9s"],
            isOfficial: false
        ),
        CuratedTap(
            id: "homebrew/cask-versions",
            name: "Homebrew Cask Versions",
            category: "System & Compatibility",
            description: "Alternate, legacy, beta, and nightly versions of popular macOS desktop applications.",
            website: "https://github.com/Homebrew/homebrew-cask-versions",
            featuredPackages: ["visual-studio-code-insiders", "google-chrome-canary", "sublime-text-dev"],
            isOfficial: true
        )
    ]

    var allCategories: [String] {
        Array(Set(Self.curatedTaps.map(\.category))).sorted()
    }
}
