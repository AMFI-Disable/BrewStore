import Foundation

struct BrewStoreEditorialPick: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let badge: String
    let headline: String
    let review: String
    let kind: BrewPackageKind
    let systemImage: String
    let accentColorName: String
    let tags: [String]

    static let allPicks: [BrewStoreEditorialPick] = [
        // MARK: - Cask GUI Picks

        BrewStoreEditorialPick(
            id: "raycast",
            name: "Raycast",
            badge: "Editor's Choice",
            headline: "Keyboard-driven application launcher, window manager, and snippet tool",
            review: "Raycast extends macOS search with keyboard navigation, clipboard history, window layout controls, script execution, and community extensions.",
            kind: .cask,
            systemImage: "sparkles",
            accentColorName: "purple",
            tags: ["Productivity", "Launcher", "Must-Have"]
        ),
        BrewStoreEditorialPick(
            id: "orbstack",
            name: "OrbStack",
            badge: "Must-Have",
            headline: "Lightweight Docker container and Linux VM engine for macOS",
            review: "Container runtime that starts quickly, minimizes memory overhead, and bridges macOS networking and file systems natively.",
            kind: .cask,
            systemImage: "shippingbox.fill",
            accentColorName: "blue",
            tags: ["Development", "Containers", "Docker"]
        ),
        BrewStoreEditorialPick(
            id: "ghostty",
            name: "Ghostty",
            badge: "Staff Favorite",
            headline: "Fast, GPU-accelerated terminal emulator",
            review: "Engineered with native macOS UI conventions and GPU rendering, Ghostty delivers clean typography, smooth scrolling, and fast startup.",
            kind: .cask,
            systemImage: "terminal.fill",
            accentColorName: "orange",
            tags: ["Terminal", "Development", "CLI"]
        ),
        BrewStoreEditorialPick(
            id: "tableplus",
            name: "TablePlus",
            badge: "Database Client",
            headline: "Native macOS database management GUI",
            review: "A native macOS database client with inline editing, multi-tab workflows, and support for PostgreSQL, MySQL, SQLite, Redis, and ClickHouse.",
            kind: .cask,
            systemImage: "cylinder.split.1x2.fill",
            accentColorName: "indigo",
            tags: ["Database", "SQL", "GUI"]
        ),
        BrewStoreEditorialPick(
            id: "zed",
            name: "Zed",
            badge: "Code Editor",
            headline: "Lightweight collaborative code editor with native rendering",
            review: "Crafted in Rust with GPU rendering, Zed minimizes input latency, provides native language servers, and enables real-time pair programming.",
            kind: .cask,
            systemImage: "chevron.left.forwardslash.chevron.right",
            accentColorName: "cyan",
            tags: ["Editor", "Rust", "Collaboration"]
        ),
        BrewStoreEditorialPick(
            id: "visual-studio-code",
            name: "Visual Studio Code",
            badge: "Versatile Editor",
            headline: "Extensible code editor and developer ecosystem",
            review: "Rich ecosystem of language extensions, debugging tools, Git integration, and remote development capabilities.",
            kind: .cask,
            systemImage: "curlybraces",
            accentColorName: "blue",
            tags: ["Editor", "IDE", "Development"]
        ),
        BrewStoreEditorialPick(
            id: "iina",
            name: "IINA",
            badge: "Media Favorite",
            headline: "Modern media player built specifically for macOS",
            review: "Powered by mpv, IINA plays virtually any video or audio format with native Picture-in-Picture, gesture controls, dark mode, and subtitle searching.",
            kind: .cask,
            systemImage: "play.tv.fill",
            accentColorName: "teal",
            tags: ["Media", "Video", "Player"]
        ),
        BrewStoreEditorialPick(
            id: "obsidian",
            name: "Obsidian",
            badge: "Knowledge Hub",
            headline: "Extensible Markdown notes and knowledge base",
            review: "A private, offline-first notes system backed by plain text Markdown files with bidirectional graph linking, canvas diagrams, and hundreds of community plugins.",
            kind: .cask,
            systemImage: "book.pages.fill",
            accentColorName: "purple",
            tags: ["Notes", "Markdown", "Productivity"]
        ),
        BrewStoreEditorialPick(
            id: "blender",
            name: "Blender",
            badge: "3D Powerhouse",
            headline: "Open-source 3D creation suite with Metal GPU acceleration",
            review: "Complete modeling, rigging, animation, simulation, rendering, compositing, and motion tracking workstation with full Apple Metal acceleration.",
            kind: .cask,
            systemImage: "cube.transparent.fill",
            accentColorName: "orange",
            tags: ["3D", "Design", "Graphics"]
        ),
        BrewStoreEditorialPick(
            id: "obs",
            name: "OBS Studio",
            badge: "Streaming Standard",
            headline: "Free and open source software for video recording and live streaming",
            review: "Equipped with high-performance real-time video/audio capturing and mixing, custom transitions, and native Apple Silicon hardware encoders.",
            kind: .cask,
            systemImage: "record.circle.fill",
            accentColorName: "red",
            tags: ["Video", "Streaming", "Recording"]
        ),
        BrewStoreEditorialPick(
            id: "docker",
            name: "Docker Desktop",
            badge: "DevOps Essential",
            headline: "Industry-standard containerization platform for macOS",
            review: "Container platform providing multi-architecture image building, Docker Compose, Kubernetes integration, and container volume management.",
            kind: .cask,
            systemImage: "shippingbox.and.arrow.backward.fill",
            accentColorName: "blue",
            tags: ["Containers", "DevOps", "Cloud"]
        ),

        // MARK: - Formula CLI Picks

        BrewStoreEditorialPick(
            id: "ripgrep",
            name: "Ripgrep",
            badge: "CLI Gold Standard",
            headline: "Fast recursive code search across large projects",
            review: "Ripgrep respects .gitignore files by default, skips hidden files, and leverages Rust's regex engine to search millions of lines of code in milliseconds.",
            kind: .formula,
            systemImage: "magnifyingglass",
            accentColorName: "green",
            tags: ["CLI", "Search", "Utilities"]
        ),
        BrewStoreEditorialPick(
            id: "starship",
            name: "Starship",
            badge: "Power Tool",
            headline: "Cross-shell prompt customized for developer contexts",
            review: "Displays shell status, active Git branches, runtime versions, and execution time with low latency.",
            kind: .formula,
            systemImage: "star.fill",
            accentColorName: "yellow",
            tags: ["Shell", "Zsh", "Prompt"]
        ),
        BrewStoreEditorialPick(
            id: "bat",
            name: "Bat",
            badge: "Modern UNIX",
            headline: "A cat clone with syntax highlighting and Git integration",
            review: "Replaces traditional cat with colored syntax highlighting, line numbers, git modification markers, and automatic paging support.",
            kind: .formula,
            systemImage: "doc.text.magnifyingglass",
            accentColorName: "pink",
            tags: ["CLI", "Viewer", "Rust"]
        ),
        BrewStoreEditorialPick(
            id: "eza",
            name: "Eza",
            badge: "Modern UNIX",
            headline: "A modern, maintained replacement for ls with file icons and Git",
            review: "Brings color-coded permissions, recursive tree views, file size formatting, and inline Git status badges to your file listings.",
            kind: .formula,
            systemImage: "folder.badge.gearshape",
            accentColorName: "cyan",
            tags: ["CLI", "Filesystem", "Rust"]
        ),
        BrewStoreEditorialPick(
            id: "zoxide",
            name: "Zoxide",
            badge: "Smart Navigation",
            headline: "A smarter cd command that learns your directory habits",
            review: "Zoxide remembers which directories you use most frequently, allowing you to jump straight to any project with just a few keystrokes.",
            kind: .formula,
            systemImage: "arrow.triangle.turn.up.right.diamond.fill",
            accentColorName: "mint",
            tags: ["CLI", "Shell", "Navigation"]
        ),
        BrewStoreEditorialPick(
            id: "fd",
            name: "Fd",
            badge: "Fast Search",
            headline: "A simple, fast and user-friendly alternative to find",
            review: "Provides intuitive syntax, colorized terminal output, regex pattern matching, and parallel directory traversal out of the box.",
            kind: .formula,
            systemImage: "doc.badge.gearshape",
            accentColorName: "green",
            tags: ["CLI", "Search", "Find"]
        ),
        BrewStoreEditorialPick(
            id: "btop",
            name: "Btop",
            badge: "System Monitor",
            headline: "Modern resource monitor showing usage of CPU, memory, disks and network",
            review: "Stunning TUI resource monitor with live graphs, process filtering, temperature sensors, and customizable color themes.",
            kind: .formula,
            systemImage: "gauge.with.needle.fill",
            accentColorName: "purple",
            tags: ["CLI", "Monitoring", "System"]
        ),
        BrewStoreEditorialPick(
            id: "neovim",
            name: "Neovim",
            badge: "Modal Editor",
            headline: "Vim-fork focused on extensibility, Lua plugins, and LSP",
            review: "Extensible modal terminal text editor with built-in Language Server Protocol (LSP) client, Treesitter syntax tree parsing, and Lua scripting.",
            kind: .formula,
            systemImage: "character.cursor.ibeam",
            accentColorName: "teal",
            tags: ["Editor", "Vim", "Terminal"]
        ),
        BrewStoreEditorialPick(
            id: "git-delta",
            name: "Delta",
            badge: "Git Power Tool",
            headline: "A syntax-highlighting pager for git, diff, and grep output",
            review: "Transforms raw git diffs into beautiful side-by-side or unified views with full syntax highlighting, line numbers, and inline word changes.",
            kind: .formula,
            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
            accentColorName: "orange",
            tags: ["Git", "Diff", "Terminal"]
        ),
        BrewStoreEditorialPick(
            id: "postgresql@16",
            name: "PostgreSQL 16",
            badge: "Database Standard",
            headline: "Reliable open-source relational database",
            review: "Full ACID compliance, robust indexing (B-Tree, GIN, GiST), JSONB support, and powerful full-text search engine for production applications.",
            kind: .formula,
            systemImage: "server.rack",
            accentColorName: "blue",
            tags: ["Database", "SQL", "Backend"]
        ),
        BrewStoreEditorialPick(
            id: "redis",
            name: "Redis",
            badge: "Fast Cache & Store",
            headline: "In-memory data structure store used as database, cache, and message broker",
            review: "Sub-millisecond latency caching and pub/sub messaging engine supporting strings, hashes, lists, sets, and geospatial indexes.",
            kind: .formula,
            systemImage: "bolt.fill",
            accentColorName: "red",
            tags: ["Cache", "Database", "NoSQL"]
        )
    ]

    static func pick(for id: String) -> BrewStoreEditorialPick? {
        allPicks.first { $0.id == id }
    }
}
