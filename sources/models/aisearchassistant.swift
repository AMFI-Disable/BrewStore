import Foundation

struct AIPackageRecommendation: Identifiable, Hashable {
    let id: String
    let packageID: String
    let name: String
    let kind: BrewPackageKind
    let confidence: Double // 0.0 to 1.0
    let headline: String
    let reason: String
    let useCase: String
    let commandRecipe: String?
    let tags: [String]
}

enum AISearchKindFilter: String, CaseIterable, Identifiable {
    case all = "All Types"
    case cask = "Casks (Apps)"
    case formula = "Formulae (CLI)"

    var id: String {
        rawValue
    }
}

@MainActor
final class BrewStoreAIAssistant: ObservableObject {
    @Published var recommendations: [AIPackageRecommendation] = []
    @Published var isAnalyzing = false
    @Published var analyzedQuery: String = ""
    @Published var educationalNote: String?
    @Published var detectedFilter: BrewPackageKind?

    /// Curated Intent Knowledge Base
    private static let knowledgeBase: [(triggers: [String], recommendations: [(id: String, name: String, kind: BrewPackageKind, headline: String, reason: String, useCase: String, recipe: String?, tags: [String])])] = [
        // Web Browsers
        (
            triggers: ["browser", "web browser", "chrome alternative", "safari alternative", "surf web", "internet", "cask browser"],
            recommendations: [
                (id: "google-chrome", name: "Google Chrome", kind: .cask, headline: "World's most popular web browser", reason: "Fast, secure browser with extensive extension ecosystem and Google sync.", useCase: "General browsing and web application development.", recipe: "open -a 'Google Chrome'", tags: ["GUI", "Browser", "Google"]),
                (id: "firefox", name: "Firefox", kind: .cask, headline: "Privacy-first open-source browser", reason: "Non-profit open-source engine with strong tracking protection and customization.", useCase: "Private web browsing and standards-compliant web testing.", recipe: "open -a Firefox", tags: ["GUI", "Browser", "FOSS"]),
                (id: "brave-browser", name: "Brave Browser", kind: .cask, headline: "Fast Chromium browser with built-in ad blocker", reason: "Blocks trackers and ads by default for faster page load times.", useCase: "Speed-focused, ad-free daily browsing.", recipe: "open -a 'Brave Browser'", tags: ["GUI", "Browser", "Privacy"]),
                (id: "arc", name: "Arc", kind: .cask, headline: "Modern spatial browser with spaces and split views", reason: "Innovative UI designed for power users with spaces, tabs sidebar, and easel.", useCase: "Organized multitasking and research.", recipe: "open -a Arc", tags: ["GUI", "Browser", "Productivity"]),
                (id: "tor-browser", name: "Tor Browser", kind: .cask, headline: "Anonymous browsing over the Tor network", reason: "Multi-layered onion routing defending against network surveillance and traffic analysis.", useCase: "Maximum anonymity and censorship circumvention.", recipe: "open -a 'Tor Browser'", tags: ["GUI", "Browser", "Tor", "Security"])
            ]
        ),
        // Code Editors & IDEs
        (
            triggers: ["code editor", "ide", "editor", "write code", "text editor", "vs code", "neovim", "programming editor"],
            recommendations: [
                (id: "visual-studio-code", name: "Visual Studio Code", kind: .cask, headline: "The universal code editor", reason: "Unmatched extension ecosystem, built-in Git, debugging, and terminal support.", useCase: "Full-stack software engineering across all languages.", recipe: "code .", tags: ["GUI", "Editor", "Microsoft"]),
                (id: "cursor", name: "Cursor", kind: .cask, headline: "AI-first code editor fork of VS Code", reason: "Integrated AI pair programmer with codebase indexing and multi-file editing.", useCase: "AI-assisted application development.", recipe: "cursor .", tags: ["GUI", "Editor", "AI"]),
                (id: "neovim", name: "Neovim", kind: .formula, headline: "Vim-fork focused on extensibility and Lua plugins", reason: "Fast terminal text editor with LSP, treesitter, and asynchronous plugins.", useCase: "Keyboard-driven modal coding inside the terminal.", recipe: "nvim .", tags: ["CLI", "Editor", "Lua", "Vim"]),
                (id: "zed", name: "Zed", kind: .cask, headline: "High-performance multiplayer code editor written in Rust", reason: "GPU-accelerated native macOS rendering with instant startup and zero lag.", useCase: "Fast code editing and collaborative pair programming.", recipe: "zed .", tags: ["GUI", "Editor", "Rust"])
            ]
        ),
        // Programming Languages & Runtimes
        (
            triggers: ["python", "node", "nodejs", "javascript", "typescript", "rust", "golang", "go language", "java", "openjdk", "ruby", "compiler", "runtime"],
            recommendations: [
                (id: "python@3.12", name: "Python 3.12", kind: .formula, headline: "Modern Python programming language runtime", reason: "Optimized CPython interpreter for scripting, data science, and backend APIs.", useCase: "Scripting, machine learning, and automation scripts.", recipe: "python3.12 -m venv .venv && source .venv/bin/activate", tags: ["CLI", "Python", "Language"]),
                (id: "node", name: "Node.js", kind: .formula, headline: "JavaScript runtime built on Chrome's V8 engine", reason: "Standard runtime for running JavaScript outside the browser and executing npm packages.", useCase: "Web development, build tools, and backend servers.", recipe: "node -v && npm init -y", tags: ["CLI", "JavaScript", "Node"]),
                (id: "rust", name: "Rust", kind: .formula, headline: "Safe, fast, and concurrent systems programming language", reason: "Memory-safe without garbage collection; powers modern Unix CLI tools.", useCase: "High-performance systems software and CLI binaries.", recipe: "cargo new my_app && cd my_app && cargo run", tags: ["CLI", "Rust", "Language"]),
                (id: "go", name: "Go", kind: .formula, headline: "Fast, reliable, and scalable programming language", reason: "Compiled language created by Google with built-in concurrency (goroutines).", useCase: "Microservices, cloud infrastructure, and DevOps tools.", recipe: "go mod init my_app && go run main.go", tags: ["CLI", "Go", "Cloud"])
            ]
        ),
        // Window Management & Productivity
        (
            triggers: ["window manager", "tiling", "organize windows", "split screen", "raycast", "alfred", "mac customization", "productivity"],
            recommendations: [
                (id: "aerospace", name: "AeroSpace", kind: .cask, headline: "i3-like tiling window manager for macOS", reason: "Keyboard-driven virtual workspaces without disabling System Integrity Protection.", useCase: "Automatic tiling of windows into clean grids and workspaces.", recipe: "open -a AeroSpace", tags: ["GUI", "Tiling", "WindowManager"]),
                (id: "raycast", name: "Raycast", kind: .cask, headline: "Spotlight replacement and launcher", reason: "Calculations, clipboard history, window management, and extensions in one keystroke.", useCase: "System-wide navigation and rapid app launching.", recipe: "open -a Raycast", tags: ["GUI", "Launcher", "Productivity"]),
                (id: "rectangle", name: "Rectangle", kind: .cask, headline: "Move and resize windows using keyboard shortcuts", reason: "Simple, lightweight snap-to-edge window manager for macOS.", useCase: "Snapping windows to halves, thirds, and quadrants.", recipe: "open -a Rectangle", tags: ["GUI", "Windows", "FOSS"]),
                (id: "stats", name: "Stats", kind: .cask, headline: "macOS system monitoring menu bar app", reason: "Live CPU, GPU, RAM, disk, network, and battery usage charts in your menu bar.", useCase: "Monitoring hardware resource utilization.", recipe: "open -a Stats", tags: ["GUI", "Menu Bar", "Monitor"])
            ]
        ),
        // System Cleaner & Optimization (Mole)
        (
            triggers: ["cleaner", "clean my mac", "cleanmymac", "disk cleaner", "cache cleaner", "mac cleaner", "uninstall apps", "free disk space"],
            recommendations: [
                (id: "mole", name: "Mole", kind: .formula, headline: "Modern macOS system and cache cleaner CLI", reason: "Best lightweight, privacy-respecting alternative to CleanMyMac for Homebrew.", useCase: "Deep cleaning system caches, logs, Xcode derived data, and orphaned files.", recipe: "mole clean --all", tags: ["CLI", "Cleaner", "Mole", "FOSS"]),
                (id: "appcleaner", name: "AppCleaner", kind: .cask, headline: "Thoroughly uninstall macOS applications and leftover files", reason: "Finds and deletes hidden preference files and caches when dragging an app to trash.", useCase: "Complete application removal without leaving leftovers.", recipe: "open -a AppCleaner", tags: ["GUI", "Cleaner", "Uninstall"])
            ]
        ),
        // Video / Audio Transcoding & Media
        (
            triggers: ["convert video", "transcode", "mkv to mp4", "hevc", "av1", "audio", "video encoder", "compress video", "subtitles", "media", "video player"],
            recommendations: [
                (id: "ffmpeg", name: "FFmpeg", kind: .formula, headline: "Universal multimedia conversion powerhouse", reason: "Industry standard CLI supporting every audio and video codec with hardware acceleration.", useCase: "Batch converting, trimming, and re-encoding video/audio files.", recipe: "ffmpeg -i input.mkv -c:v copy -c:a aac output.mp4", tags: ["CLI", "Video", "Audio", "Conversion"]),
                (id: "handbrake", name: "HandBrake", kind: .cask, headline: "Open-source GUI video transcoder", reason: "Native macOS GUI with optimized Apple Silicon presets for iPad, iPhone, and Apple TV.", useCase: "Visual batch queue transcoding with subtitles and chapter markers.", recipe: "open -a HandBrake", tags: ["GUI", "Video", "Apple Silicon"]),
                (id: "iina", name: "IINA", kind: .cask, headline: "Modern native macOS media player", reason: "Plays virtually every video and audio format smoothly with native PiP and HDR.", useCase: "High-definition media playback and previewing converted files.", recipe: "iina video.mp4", tags: ["GUI", "Player", "Media"]),
                (id: "yt-dlp", name: "yt-dlp", kind: .formula, headline: "Feature-rich command-line audio/video downloader", reason: "Downloads videos and extracts audio streams with metadata from thousands of sites.", useCase: "Archiving and downloading online media.", recipe: "yt-dlp -f 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4' <URL>", tags: ["CLI", "Downloader", "Media"])
            ]
        ),
        // Image Processing & 3D
        (
            triggers: ["image conversion", "heic to png", "heic to jpg", "batch resize", "compress photos", "vector", "3d", "photoshop alternative", "image editor"],
            recommendations: [
                (id: "imagemagick", name: "ImageMagick", kind: .formula, headline: "Bitmap image manipulation and batch converter", reason: "Converts HEIC, WebP, PNG, JPEG, SVG, and PDF images quickly from the terminal.", useCase: "Automated batch resizing, format conversion, and watermarking.", recipe: "magick mogrify -format png *.heic", tags: ["CLI", "Images", "Batch"]),
                (id: "blender", name: "Blender", kind: .cask, headline: "Complete 3D graphics and animation suite", reason: "Free open-source 3D workstation with full Apple Metal GPU acceleration.", useCase: "3D modeling, sculpting, rigging, and photorealistic rendering.", recipe: "open -a Blender", tags: ["GUI", "3D", "Graphics"]),
                (id: "inkscape", name: "Inkscape", kind: .cask, headline: "Professional vector graphics editor", reason: "Full SVG compliance with path operations, node editing, and EPS/PDF exports.", useCase: "Illustrations, icon design, and vector drawing.", recipe: "open -a Inkscape", tags: ["GUI", "Vector", "Design"])
            ]
        ),
        // Terminal & Shell Enhancement
        (
            triggers: ["fast terminal", "gpu terminal", "better terminal", "zsh prompt", "shell prompt", "terminal font", "fast cd", "fast find", "replace cat", "replace ls", "terminal"],
            recommendations: [
                (id: "ghostty", name: "Ghostty", kind: .cask, headline: "Fast GPU-accelerated terminal emulator", reason: "Subpixel font rendering, instant startup, and smooth scrolling tailored for macOS.", useCase: "Fast and responsive daily command-line environment.", recipe: "open -a Ghostty", tags: ["GUI", "Terminal", "GPU"]),
                (id: "starship", name: "Starship", kind: .formula, headline: "Fast cross-shell prompt", reason: "Renders Git status, runtime versions, and system context in under 5ms.", useCase: "Informative, clean shell prompt across Zsh, Bash, and Fish.", recipe: "eval \"$(starship init zsh)\"", tags: ["CLI", "Shell", "Prompt"]),
                (id: "zoxide", name: "Zoxide", kind: .formula, headline: "Smarter cd that learns your navigation habits", reason: "Jumps to your most-frequently accessed directories in a single command (`z project`).", useCase: "Fast filesystem navigation.", recipe: "eval \"$(zoxide init zsh)\" && z <directory>", tags: ["CLI", "Navigation", "Rust"]),
                (id: "bat", name: "Bat", kind: .formula, headline: "Cat clone with syntax highlighting and Git diffs", reason: "Provides color-coded syntax formatting, line numbers, and paging for code files.", useCase: "Viewing code and config files in the terminal.", recipe: "bat src/main.rs", tags: ["CLI", "Viewer", "Rust"])
            ]
        ),
        // Fast Code Search & Git
        (
            triggers: ["search code", "fast grep", "find files", "git diff", "git viewer", "diff tool", "regex search", "git"],
            recommendations: [
                (id: "ripgrep", name: "Ripgrep", kind: .formula, headline: "Fast recursive codebase search", reason: "Searches millions of lines in milliseconds while automatically respecting .gitignore.", useCase: "Instant regex pattern search across massive repositories.", recipe: "rg --hidden -i 'search_term' .", tags: ["CLI", "Search", "Rust"]),
                (id: "fd", name: "Fd", kind: .formula, headline: "Intuitive, fast alternative to find", reason: "User-friendly syntax, colorized output, and parallel traversal for finding files.", useCase: "Finding files and folders by pattern.", recipe: "fd -e swift .", tags: ["CLI", "Search", "Find"]),
                (id: "git-delta", name: "Delta", kind: .formula, headline: "Syntax-highlighting pager for Git diffs", reason: "Transforms terminal diffs into side-by-side formatted views with syntax colors.", useCase: "Reviewing Git commits and pull request diffs in the terminal.", recipe: "git config --global core.pager delta", tags: ["CLI", "Git", "Diff"])
            ]
        ),
        // Containers, VMs & Kubernetes
        (
            triggers: ["docker alternative", "run containers", "linux vm", "kubernetes", "k8s", "container runtime", "docker desktop", "docker"],
            recommendations: [
                (id: "orbstack", name: "OrbStack", kind: .cask, headline: "Fast Docker engine and Linux VMs", reason: "Uses 1/10th the memory and CPU of Docker Desktop with 2-second startup times.", useCase: "Running Docker containers and Linux distributions natively on macOS.", recipe: "orb start", tags: ["GUI", "Containers", "Fast"]),
                (id: "k9s", name: "K9s", kind: .formula, headline: "Terminal-based Kubernetes UI", reason: "Real-time navigation, pod observation, logs, and cluster management from your terminal.", useCase: "Monitoring and managing Kubernetes clusters.", recipe: "k9s", tags: ["CLI", "Kubernetes", "DevOps"]),
                (id: "kubernetes-cli", name: "kubectl", kind: .formula, headline: "Kubernetes command-line control tool", reason: "The official control plane CLI for orchestrating Kubernetes clusters.", useCase: "Deploying and managing container workloads.", recipe: "kubectl get pods -A", tags: ["CLI", "Kubernetes", "Cloud"])
            ]
        ),
        // Databases & SQL
        (
            triggers: ["database client", "sql gui", "postgres gui", "redis gui", "sqlite editor", "run postgres", "run redis", "database daemon", "database"],
            recommendations: [
                (id: "tableplus", name: "TablePlus", kind: .cask, headline: "Native macOS multi-database GUI client", reason: "Inline spreadsheet-style editing for PostgreSQL, MySQL, SQLite, Redis, and ClickHouse.", useCase: "Querying, inspecting, and editing production and local databases.", recipe: "open -a TablePlus", tags: ["GUI", "Database", "SQL"]),
                (id: "postgresql@16", name: "PostgreSQL 16", kind: .formula, headline: "Reliable open-source relational database", reason: "ACID-compliant, JSONB-supported database engine running as a managed background service.", useCase: "Local application development and relational data storage.", recipe: "brew services start postgresql@16 && psql postgres", tags: ["CLI", "Database", "Service"]),
                (id: "redis", name: "Redis", kind: .formula, headline: "In-memory caching and key-value store", reason: "Sub-millisecond latency data structures running as a background service.", useCase: "Session storage, caching, and pub/sub message queues.", recipe: "brew services start redis && redis-cli ping", tags: ["CLI", "Cache", "Service"])
            ]
        ),
        // Local AI & LLMs
        (
            triggers: ["local ai", "run llm", "chat with llama", "deepseek local", "mistral mac", "ollama", "gguf", "ai models", "ai"],
            recommendations: [
                (id: "ollama", name: "Ollama", kind: .formula, headline: "Run open-source LLMs locally on macOS", reason: "Simple installation and execution of Llama 3, DeepSeek, Mistral, and Gemma models.", useCase: "Running private, offline AI models with zero API subscription fees.", recipe: "ollama run llama3", tags: ["CLI", "AI", "LLM"]),
                (id: "lm-studio", name: "LM Studio", kind: .cask, headline: "Graphical discovery and chat interface for local LLMs", reason: "Discover, download, and converse with GGUF models using Apple Silicon GPU acceleration.", useCase: "Interactive local AI chat and model experimentation.", recipe: "open -a 'LM Studio'", tags: ["GUI", "AI", "Metal"])
            ]
        ),
        // Privacy, Security & Secrets
        (
            triggers: ["password manager", "vpn", "encrypt files", "gpg", "ssh key", "wireguard", "tor", "privacy", "secrets", "security"],
            recommendations: [
                (id: "age", name: "Age", kind: .formula, headline: "Simple, modern, and secure file encryption", reason: "Replaces complicated GPG setups with clean command syntax and SSH key support.", useCase: "Encrypting backup archives and confidential documents.", recipe: "age -r age1... secret.tar.gz > secret.tar.gz.age", tags: ["CLI", "Security", "Encryption"]),
                (id: "bitwarden-cli", name: "Bitwarden CLI", kind: .formula, headline: "Command-line access to Bitwarden password vault", reason: "Retrieve passwords, TOTP tokens, and secure notes directly in scripts and terminals.", useCase: "Automated credential injection and secret retrieval.", recipe: "bw login && bw get password github.com", tags: ["CLI", "Passwords", "Vault"]),
                (id: "wireguard-tools", name: "WireGuard Tools", kind: .formula, headline: "Fast and lightweight VPN tunnel configuration", reason: "Modern cryptography with minimal CPU overhead and battery drain.", useCase: "Connecting to secure private networks.", recipe: "sudo wg-quick up wg0", tags: ["CLI", "VPN", "Privacy"])
            ]
        )
    ]

    func analyze(query: String, manager: HomebrewManager, manualKindFilter: AISearchKindFilter = .all) {
        let rawTrimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTrimmed.isEmpty else {
            recommendations = []
            analyzedQuery = ""
            educationalNote = nil
            detectedFilter = nil
            return
        }

        isAnalyzing = true
        analyzedQuery = rawTrimmed
        educationalNote = nil

        var workingQuery = rawTrimmed.lowercased()
        var forcedKind: BrewPackageKind?

        // Manual filter takes precedence if not .all
        switch manualKindFilter {
        case .cask: forcedKind = .cask
        case .formula: forcedKind = .formula
        case .all: break
        }

        // Automatic syntax detection: "cask:...", "formula:...", "type:cask", "cask ...", "formula ..."
        if workingQuery.hasPrefix("cask:") || workingQuery.hasPrefix("casks:") {
            forcedKind = .cask
            workingQuery = workingQuery.replacingOccurrences(of: "^casks?:\\s*", with: "", options: .regularExpression)
        } else if workingQuery.hasPrefix("formula:") || workingQuery.hasPrefix("formulae:") {
            forcedKind = .formula
            workingQuery = workingQuery.replacingOccurrences(of: "^formula(e)?:\\s*", with: "", options: .regularExpression)
        } else if workingQuery.hasPrefix("type:cask") {
            forcedKind = .cask
            workingQuery = workingQuery.replacingOccurrences(of: "^type:cask\\s*", with: "", options: .regularExpression)
        } else if workingQuery.hasPrefix("type:formula") {
            forcedKind = .formula
            workingQuery = workingQuery.replacingOccurrences(of: "^type:formula\\s*", with: "", options: .regularExpression)
        } else if workingQuery.hasPrefix("cask ") {
            forcedKind = .cask
            workingQuery = String(workingQuery.dropFirst(5))
        } else if workingQuery.hasPrefix("formula ") {
            forcedKind = .formula
            workingQuery = String(workingQuery.dropFirst(8))
        }

        self.detectedFilter = forcedKind

        // Educational inquiries detection
        if workingQuery.contains("what is a cask") || workingQuery.contains("cask vs formula") || workingQuery.contains("what is formula") {
            self.educationalNote = "💡 **Casks vs Formulae**: In Homebrew, **Casks** are full graphical macOS desktop apps installed into `/Applications` (e.g. VS Code, Chrome, Ghostty). **Formulae** are command-line tools, libraries, compilers, and background services installed into the Cellar (e.g. git, python, ffmpeg, nginx)."
        } else if workingQuery.contains("how to tap") || workingQuery.contains("what is a tap") {
            self.educationalNote = "🚰 **Homebrew Taps**: A Tap is a third-party Git repository containing custom formulae and casks not in the default official core (e.g. `brew tap homebrew/cask-fonts` for fonts, or `brew tap nikitabobko/tap` for AeroSpace)."
        } else if workingQuery.contains("how to pin") || workingQuery.contains("what is pin") {
            self.educationalNote = "📌 **Package Pinning**: Pinning a formula (`brew pin <name>`) locks its version so `brew upgrade` will never automatically upgrade or overwrite it."
        }

        let queryWords = Set(workingQuery.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })

        var scoredRecommendations: [AIPackageRecommendation] = []
        var seenIDs = Set<String>()

        // 1. Check curated knowledge base
        for entry in Self.knowledgeBase {
            var matchScore = 0.0

            for trigger in entry.triggers {
                let triggerWords = Set(trigger.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
                let intersection = queryWords.intersection(triggerWords)

                if workingQuery.contains(trigger) {
                    matchScore += 1.0
                } else if !intersection.isEmpty {
                    matchScore += Double(intersection.count) / Double(triggerWords.count) * 0.75
                }
            }

            if matchScore > 0.3 {
                let confidence = min(1.0, matchScore)
                for rec in entry.recommendations {
                    if let forcedKind, rec.kind != forcedKind {
                        continue
                    }
                    guard !seenIDs.contains(rec.id) else { continue }
                    seenIDs.insert(rec.id)

                    let item = AIPackageRecommendation(
                        id: UUID().uuidString,
                        packageID: rec.id,
                        name: rec.name,
                        kind: rec.kind,
                        confidence: confidence,
                        headline: rec.headline,
                        reason: rec.reason,
                        useCase: rec.useCase,
                        commandRecipe: rec.recipe,
                        tags: rec.tags
                    )
                    scoredRecommendations.append(item)
                }
            }
        }

        // 2. Check local installed/catalog packages for deep fuzzy & exact matches
        let cleanedQuery = workingQuery.trimmingCharacters(in: .whitespaces)
        if !cleanedQuery.isEmpty {
            for pkg in manager.packages {
                if let forcedKind, pkg.kind != forcedKind {
                    continue
                }
                guard !seenIDs.contains(pkg.id) else { continue }

                let lowerID = pkg.id.lowercased()
                let lowerName = pkg.name.lowercased()
                let lowerDesc = pkg.description.lowercased()

                var score = 0.0
                var reason = ""

                if lowerID == cleanedQuery || lowerName == cleanedQuery {
                    score = 0.98
                    reason = "Exact match for package '\(pkg.id)' in your Homebrew catalog."
                } else if lowerID.hasPrefix(cleanedQuery) || lowerName.hasPrefix(cleanedQuery) {
                    score = 0.90
                    reason = "Package name begins with '\(cleanedQuery)'."
                } else if lowerID.contains(cleanedQuery) || lowerName.contains(cleanedQuery) {
                    score = 0.85
                    reason = "Package identifier contains '\(cleanedQuery)'."
                } else if lowerDesc.contains(cleanedQuery) {
                    score = 0.75
                    reason = "Matched description: '\(pkg.description)'"
                } else {
                    let descWords = Set(lowerDesc.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
                    let overlap = queryWords.intersection(descWords)
                    if !overlap.isEmpty {
                        score = 0.60 + (Double(overlap.count) * 0.05)
                        reason = "Matched terms: \(overlap.joined(separator: ", "))"
                    }
                }

                if score >= 0.60 {
                    seenIDs.insert(pkg.id)
                    let kindTag = pkg.kind == .cask ? "macOS App (Cask)" : "CLI Package (Formula)"
                    let statusTag = pkg.isInstalled
                        ? "Installed"
                        : pkg.tap.map { "Available (\($0))" } ?? "Available"
                    let fallbackRecipe = pkg.kind == .cask ? "open -a '\(pkg.name)'" : "\(pkg.id) --help"

                    let item = AIPackageRecommendation(
                        id: UUID().uuidString,
                        packageID: pkg.id,
                        name: pkg.name,
                        kind: pkg.kind,
                        confidence: min(0.99, score),
                        headline: pkg.description.isEmpty ? "\(pkg.name) — \(kindTag)" : pkg.description,
                        reason: reason,
                        useCase: "Version \(pkg.version) · \(statusTag)",
                        commandRecipe: fallbackRecipe,
                        tags: [pkg.kind == .cask ? "Cask" : "Formula", pkg.isInstalled ? "Installed" : "Catalog"]
                    )
                    scoredRecommendations.append(item)
                    if scoredRecommendations.count >= 24 {
                        break
                    }
                }
            }
        }

        self.recommendations = scoredRecommendations.sorted { $0.confidence > $1.confidence }
        self.isAnalyzing = false
    }
}
