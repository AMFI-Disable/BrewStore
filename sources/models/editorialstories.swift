import Foundation

struct BrewStoreStory: Identifiable, Hashable, Codable {
    let id: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let gradientColors: [String]
    let readTimeMinutes: Int
    let bodyMarkdown: String
    let featuredPackageIDs: [String]

    static func story(containingPackageID packageID: String) -> BrewStoreStory? {
        allStories.first { story in
            story.featuredPackageIDs.contains {
                $0.localizedCaseInsensitiveCompare(packageID) == .orderedSame
            }
        }
    }

    static let allStories: [BrewStoreStory] = [
        BrewStoreStory(
            id: "terminal-mastery",
            eyebrow: "DEEP DIVE",
            title: "Modernize Your Terminal Workflow",
            subtitle: "Transform your default macOS terminal into a responsive, GPU-accelerated environment.",
            gradientColors: ["#0f172a", "#1e293b", "#334155"],
            readTimeMinutes: 4,
            bodyMarkdown: """
            The command line is the heart of modern development on macOS. With the right combination of GPU rendering, intelligent auto-suggestions, and modern Rust replacements for standard UNIX utilities, you can achieve low latency, native typography, and clear context.

            ### 1. The Rendering Engine: Ghostty
            Ghostty brings native macOS typography, subpixel rendering, and GPU acceleration. It starts quickly and supports high refresh rate displays.

            ### 2. Context at a Glance: Starship Prompt
            Instead of a static `$` or `%`, Starship detects your current directory, showing your active Git branch, uncommitted diffs, Node/Python runtime versions, and AWS context—all in under 5 milliseconds.

            ### 3. Modern UNIX Replacements
            * **Ripgrep (`rg`)**: Search millions of lines of code in milliseconds while respecting `.gitignore`.
            * **Bat**: Syntax-highlighted `cat` replacement with line numbers and Git modification gutters.
            * **Eza**: Modern `ls` with tree views, Git status indicators, and file metadata.
            * **Zoxide**: Smarter `cd` that learns your navigation habits and jumps directly to frequently used folders.
            * **Btop**: Modern, interactive visual system monitor with real-time CPU, GPU, memory, and disk usage.
            """,
            featuredPackageIDs: ["ghostty", "starship", "ripgrep", "bat", "eza", "zoxide", "btop"]
        ),
        BrewStoreStory(
            id: "developer-starter-pack",
            eyebrow: "MUST-HAVE SETUP",
            title: "The Modern Mac Developer Starter Pack",
            subtitle: "Essential GUI and command-line tools for a productive macOS workflow.",
            gradientColors: ["#1e1b4b", "#312e81", "#4338ca"],
            readTimeMinutes: 5,
            bodyMarkdown: """
            Setting up a new Mac or refreshing your workstation? These carefully curated tools make everyday development fast, reliable, and battery-friendly.

            ### The Command Center: Raycast
            Raycast replaces Spotlight with an extensible launcher. Manage windows, inspect clipboard history, execute custom scripts, and control Homebrew directly from your keyboard.

            ### Low-Overhead Containers: OrbStack
            OrbStack runs Docker containers and Linux virtual machines natively with fast startup and a lightweight memory footprint.

            ### Responsive Code Editing: Zed & VS Code
            * **Zed**: Built in Rust, Zed focuses on low input latency and real-time collaboration.
            * **Visual Studio Code**: Versatile IDE with extensive extensions for every language.

            ### Native Database Inspection: TablePlus
            A fast, native macOS GUI client supporting PostgreSQL, MySQL, SQLite, Redis, and ClickHouse with inline editing and multi-tab queries.
            """,
            featuredPackageIDs: ["raycast", "orbstack", "zed", "visual-studio-code", "tableplus", "docker", "obsidian", "neovim"]
        ),
        BrewStoreStory(
            id: "database-workflow",
            eyebrow: "POWER TOOLS",
            title: "A Modern Database Setup",
            subtitle: "From robust relational databases to in-memory caching engines and GUI inspectors.",
            gradientColors: ["#064e3b", "#065f46", "#047857"],
            readTimeMinutes: 3,
            bodyMarkdown: """
            Managing local databases should never be a chore. Homebrew and BrewStore allow you to run isolated database daemons and connect them directly with native Mac GUI inspectors.

            ### Core Engines: PostgreSQL & Redis
            Run production-grade databases locally as managed background services with quick startup, LaunchAgent persistence, and real-time log tailing.

            ### Native Visual Management: TablePlus
            Pair your database daemons with TablePlus for inline spreadsheet-style data edits, query execution plans, and fast CSV imports/exports.
            """,
            featuredPackageIDs: ["postgresql@16", "redis", "tableplus", "sqlite"]
        ),
        BrewStoreStory(
            id: "privacy-security-hardening",
            eyebrow: "SECURITY FOCUS",
            title: "Privacy, Encryption & Security Essentials",
            subtitle: "Protect your secrets, encrypt your files, and secure your network connections.",
            gradientColors: ["#3f1d38", "#581c87", "#3b0764"],
            readTimeMinutes: 4,
            bodyMarkdown: """
            Security doesn't have to get in the way of productivity. With modern open-source cryptography and network privacy utilities, you can protect your development credentials and private communication.

            ### Asymmetric Encryption: Age & GnuPG
            * **Age**: A modern, simple, and secure file encryption tool designed to replace legacy PGP setups with clean SSH-key compatibility.
            * **GnuPG**: The standard for signing Git commits and verifying software packages.

            ### Secrets Management & Network Privacy
            * **Bitwarden CLI**: Access credentials, tokens, and SSH keys right from your terminal without opening a browser.
            * **WireGuard Tools**: Fast, modern VPN tunnels that operate with minimal battery impact.
            * **Tor**: Route traffic through the anonymous onion network for censorship resistance.
            """,
            featuredPackageIDs: ["age", "gnupg", "bitwarden-cli", "wireguard-tools", "tor"]
        ),
        BrewStoreStory(
            id: "creative-creator-suite",
            eyebrow: "CREATOR TOOLKIT",
            title: "The Creative Designer & Media Suite",
            subtitle: "Industry-grade 3D modeling, vector design, screen recording, and video transcoding.",
            gradientColors: ["#701a75", "#831843", "#881337"],
            readTimeMinutes: 5,
            bodyMarkdown: """
            Turn your Mac into an open-source creative production workstation. Whether you are producing 3D animations, recording screencasts, or transcoding 4K footage, these tools deliver professional performance.

            ### 3D Modeling & Vector Design
            * **Blender**: Industry-standard 3D modeling, sculpting, animation, and Metal GPU rendering.
            * **Inkscape**: Powerful vector graphics editor supporting SVG, DXF, and PDF exports.

            ### Media Production & Playback
            * **OBS Studio**: Real-time video/audio capturing and live streaming with native Apple Silicon hardware encoding.
            * **HandBrake**: High-efficiency batch video encoder supporting AV1, HEVC, and H.264.
            * **IINA**: Modern macOS video player with Picture-in-Picture and HDR support.
            """,
            featuredPackageIDs: ["blender", "inkscape", "obs", "handbrake", "iina", "ffmpeg"]
        ),
        BrewStoreStory(
            id: "rust-cli-revolution",
            eyebrow: "RUST ECOSYSTEM",
            title: "Modern Rust Command-Line Utilities",
            subtitle: "How Rust is rebuilding foundational UNIX tools for multicore performance.",
            gradientColors: ["#7c2d12", "#9a3412", "#c2410c"],
            readTimeMinutes: 4,
            bodyMarkdown: """
            Over the last five years, open-source engineers have rebuilt foundational command-line tools in Rust. The results include memory safety, colored outputs, and native Unicode/regex acceleration.

            ### The Essentials
            * **Ripgrep (`rg`)**: High-speed recursive file search with automatic `.gitignore` parsing.
            * **Fd (`fd`)**: Simple, fast, and user-friendly alternative to `find`.
            * **Delta (`delta`)**: Syntax-highlighting pager for git, diff, and grep output.
            * **Dust (`dust`)**: Visual, intuitive replacement for `du` showing exactly what is consuming your disk space.
            * **Hyperfine (`hyperfine`)**: Command-line benchmarking tool with statistical analysis and outlier detection.
            """,
            featuredPackageIDs: ["ripgrep", "fd", "git-delta", "dust", "hyperfine", "bat", "eza"]
        ),
        BrewStoreStory(
            id: "cloud-native-devops",
            eyebrow: "CLOUD & DEVOPS",
            title: "Cloud Native & Kubernetes Mastery",
            subtitle: "Deploy, manage, and run containerized cloud infrastructure from macOS.",
            gradientColors: ["#0c4a6e", "#075985", "#0369a1"],
            readTimeMinutes: 5,
            bodyMarkdown: """
            Modern cloud development requires managing multi-cloud Kubernetes clusters, deploying Infrastructure as Code, and debugging container logs in real time.

            ### Containers & Kubernetes
            * **Kubernetes CLI (`kubectl`)**: The primary control plane for managing K8s clusters.
            * **Helm**: Package manager for Kubernetes applications and Helm charts.
            * **K9s**: Terminal-based UI to navigate, observe, and manage Kubernetes clusters in real time.
            * **Terraform**: Declarative Infrastructure as Code (IaC) tool for AWS, GCP, and Azure.
            * **Minikube**: Local single-node Kubernetes cluster tailored for learning and fast local iterations.
            """,
            featuredPackageIDs: ["kubernetes-cli", "helm", "k9s", "terraform", "minikube", "docker"]
        ),
        BrewStoreStory(
            id: "local-ai-sandbox",
            eyebrow: "AI & ML",
            title: "Local AI & LLM Sandbox on Apple Silicon",
            subtitle: "Run open-source large language models natively on Unified Memory without cloud fees.",
            gradientColors: ["#14532d", "#15803d", "#166534"],
            readTimeMinutes: 4,
            bodyMarkdown: """
            Apple Silicon chips feature Unified Memory Architecture (UMA) and powerful Neural Engines, making Mac Studio and MacBook Pro machines prime hardware for running local AI models with fast performance.

            ### Local LLMs & Inference Engines
            * **Ollama**: Run Llama 3, Mistral, Gemma, and DeepSeek locally with a single terminal command.
            * **LM Studio**: Native macOS graphical interface for discovering, downloading, and chatting with local GGUF models.
            * **Python 3.12**: The foundational programming environment for PyTorch, MLX, and AI agent frameworks.
            * **FFmpeg**: Essential for local audio transcription, Whisper pipelines, and video datasets.
            """,
            featuredPackageIDs: ["ollama", "lm-studio", "python@3.12", "ffmpeg"]
        )
    ]
}
