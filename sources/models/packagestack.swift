import Foundation

enum BundleType: String, CaseIterable, Identifiable, Codable {
    case all = "All Bundles"
    case formulae = "Formulae Bundles"
    case casks = "Cask Bundles"
    case hybrid = "Full Environments"
    case custom = "Custom Bundles"

    var id: String {
        rawValue
    }
}

enum BundlePricingTier: String, CaseIterable, Identifiable, Codable {
    case freeFOSS = "100% Free & FOSS"
    case allowedFreemium = "Freemium (Bitwarden)"

    var id: String {
        rawValue
    }

    var badgeColor: String {
        switch self {
        case .freeFOSS: "green"
        case .allowedFreemium: "blue"
        }
    }
}

struct BrewStoreStack: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var description: String
    var icon: String
    var bundleType: BundleType
    var pricingTier: BundlePricingTier
    var formulae: [String]
    var casks: [String]
    var isCustom: Bool

    var totalCount: Int {
        formulae.count + casks.count
    }

    func installedCount(in installedPackages: [BrewStorePackage]) -> Int {
        let installedIDs = Set(installedPackages.filter(\.isInstalled).map(\.id))
        let formulaMatches = formulae.filter { installedIDs.contains($0) }.count
        let caskMatches = casks.filter { installedIDs.contains($0) }.count
        return formulaMatches + caskMatches
    }

    func isFullyInstalled(in installedPackages: [BrewStorePackage]) -> Bool {
        installedCount(in: installedPackages) >= totalCount
    }

    func missingPackages(in installedPackages: [BrewStorePackage]) -> (formulae: [String], casks: [String]) {
        let installedIDs = Set(installedPackages.filter(\.isInstalled).map(\.id))
        let missingFormulae = formulae.filter { !installedIDs.contains($0) }
        let missingCasks = casks.filter { !installedIDs.contains($0) }
        return (missingFormulae, missingCasks)
    }

    func exportToBrewfile() -> String {
        var lines = [
            "# BrewStore Bundle: \(name)",
            "# Pricing: \(pricingTier.rawValue)",
            "# Generated: \(Date().formatted(date: .abbreviated, time: .shortened))",
            ""
        ]

        if !formulae.isEmpty {
            lines.append("# --- Formulae (CLI & Backend) ---")
            for formula in formulae {
                lines.append("brew \"\(formula)\"")
            }
            lines.append("")
        }

        if !casks.isEmpty {
            lines.append("# --- Casks (macOS GUI Applications) ---")
            for cask in casks {
                lines.append("cask \"\(cask)\"")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Curated 100% Free & FOSS Formulae Bundles

    static let cliSupercharger = BrewStoreStack(
        id: "cli-supercharger",
        name: "Modern Terminal Essentials",
        description: "Modern command-line tools: fuzzy finding, syntax highlighting, directory jumping, and fast search.",
        icon: "terminal.fill",
        bundleType: .formulae,
        pricingTier: .freeFOSS,
        formulae: ["fzf", "ripgrep", "bat", "eza", "fd", "zoxide", "btop", "jq"],
        casks: [],
        isCustom: false
    )

    static let rustSystems = BrewStoreStack(
        id: "rust-systems",
        name: "Rust & Systems Engineering",
        description: "Complete modern systems engineering toolchain with LLVM compilers, high-speed binary installer, and WebAssembly toolkits.",
        icon: "gearshape.2.fill",
        bundleType: .formulae,
        pricingTier: .freeFOSS,
        formulae: ["rust", "cargo-binstall", "llvm", "cmake", "ninja", "wasm-pack"],
        casks: [],
        isCustom: false
    )

    static let pythonAI = BrewStoreStack(
        id: "python-ai",
        name: "Modern Python & AI Core",
        description: "Modern Python toolchain with fast package management (uv), linting (ruff), dependency tracking (poetry), and ffmpeg.",
        icon: "brain.head.profile",
        bundleType: .formulae,
        pricingTier: .freeFOSS,
        formulae: ["python@3.12", "uv", "ruff", "poetry", "ffmpeg"],
        casks: [],
        isCustom: false
    )

    static let goCloud = BrewStoreStack(
        id: "go-cloud",
        name: "Go & Cloud-Native Suite",
        description: "Kubernetes cluster administration, Helm charts, terminal UI, and local container orchestration tools.",
        icon: "cloud.fill",
        bundleType: .formulae,
        pricingTier: .freeFOSS,
        formulae: ["go", "k9s", "helm", "kubernetes-cli", "minikube"],
        casks: [],
        isCustom: false
    )

    static let macMaintenance = BrewStoreStack(
        id: "macos-maintenance",
        name: "macOS Cleanup & Maintenance",
        description: "Reclaim gigabytes of disk space with Mole, audit App Store apps, monitor processes, and display system specs.",
        icon: "trash.circle.fill",
        bundleType: .formulae,
        pricingTier: .freeFOSS,
        formulae: ["mole", "mas", "tree", "htop", "fastfetch"],
        casks: [],
        isCustom: false
    )

    static let securityCrypto = BrewStoreStack(
        id: "security-crypto",
        name: "Security & Encryption Tools",
        description: "Audited public key cryptography, age file encryption, secrets management, and network vulnerability scanning.",
        icon: "lock.shield.fill",
        bundleType: .formulae,
        pricingTier: .freeFOSS,
        formulae: ["gnupg", "age", "age-plugin-yubikey", "sops", "nmap"],
        casks: [],
        isCustom: false
    )

    // MARK: - Curated 100% Free & FOSS Cask Bundles

    static let macEssentials = BrewStoreStack(
        id: "mac-essentials",
        name: "Modern Mac Essentials",
        description: "Productivity launcher, window snapping, HDR video player, archive extractor, FOSS uninstaller, and password vault.",
        icon: "macwindow.on.rectangle",
        bundleType: .casks,
        pricingTier: .allowedFreemium,
        formulae: [],
        casks: ["raycast", "rectangle", "iina", "keka", "pearcleaner", "keepingyouawake", "bitwarden"],
        isCustom: false
    )

    static let creativeMedia = BrewStoreStack(
        id: "creative-media",
        name: "FOSS Creative & Media Studio",
        description: "100% Free & open-source 3D animation, vector art, photo editing, broadcasting, audio mastering, and media transcoding.",
        icon: "paintpalette.fill",
        bundleType: .casks,
        pricingTier: .freeFOSS,
        formulae: [],
        casks: ["blender", "gimp", "inkscape", "obs", "audacity", "handbrake", "vlc"],
        isCustom: false
    )

    static let privacySecurity = BrewStoreStack(
        id: "privacy-security",
        name: "Privacy & Security Tools",
        description: "Private messaging, secure password managers, and client-side file encryption.",
        icon: "shield.lefthalf.filled",
        bundleType: .casks,
        pricingTier: .allowedFreemium,
        formulae: [],
        casks: ["bitwarden", "tor-browser", "signal", "keepassxc", "cryptomator"],
        isCustom: false
    )

    static let knowledgeOffice = BrewStoreStack(
        id: "knowledge-office",
        name: "Notes, Office & Documents",
        description: "Note-taking, document editing, diagramming, and e-book management.",
        icon: "book.fill",
        bundleType: .casks,
        pricingTier: .freeFOSS,
        formulae: [],
        casks: ["logseq", "drawio", "libreoffice", "zotero", "calibre"],
        isCustom: false
    )

    // MARK: - Full Hybrid Environments

    static let webDev = BrewStoreStack(
        id: "web-dev",
        name: "Full-Stack Modern Web Dev",
        description: "High-performance Node runtime, fast package manager, GPU terminal, Rust code editor, plain-text API client, and DB explorer.",
        icon: "chevron.left.forwardslash.chevron.right",
        bundleType: .hybrid,
        pricingTier: .freeFOSS,
        formulae: ["node", "pnpm", "git", "redis"],
        casks: ["visual-studio-code", "zed", "ghostty", "bruno", "dbeaver-community"],
        isCustom: false
    )

    static let dataScience = BrewStoreStack(
        id: "data-science",
        name: "Data Science & Scientific ML",
        description: "Python 3.12, R runtime, Jupyter interactive notebooks, fast package resolver, and universal database querying.",
        icon: "chart.xyaxis.line",
        bundleType: .hybrid,
        pricingTier: .freeFOSS,
        formulae: ["python@3.12", "r", "git", "uv"],
        casks: ["jupyterlab", "visual-studio-code", "dbeaver-community"],
        isCustom: false
    )

    static let nativeMacDev = BrewStoreStack(
        id: "native-mac-dev",
        name: "Native macOS & Swift Development",
        description: "Linter, formatter, clean build output formatter, Carthage, and SF Symbols for native Apple platform engineers.",
        icon: "swift",
        bundleType: .hybrid,
        pricingTier: .freeFOSS,
        formulae: ["swiftlint", "swiftformat", "xcbeautify", "carthage"],
        casks: ["sf-symbols"],
        isCustom: false
    )

    static let cloudDevOps = BrewStoreStack(
        id: "cloud-devops",
        name: "Cloud & DevOps Infrastructure",
        description: "Declarative infrastructure as code, cloud CLIs, Docker engine, and terminal Kubernetes management.",
        icon: "server.rack",
        bundleType: .hybrid,
        pricingTier: .freeFOSS,
        formulae: ["terraform", "awscli", "azure-cli", "docker", "k9s"],
        casks: [],
        isCustom: false
    )

    static let modernAI = BrewStoreStack(
        id: "modern-ai-llm",
        name: "Modern AI & LLM Engineering",
        description: "Local large language model runners, Python package tooling (uv), command-line AI assistants, and media processing.",
        icon: "sparkles",
        bundleType: .formulae,
        pricingTier: .freeFOSS,
        formulae: ["ollama", "uv", "ffmpeg", "mods", "aichat", "python@3.12"],
        casks: [],
        isCustom: false
    )

    static let defaultStacks: [BrewStoreStack] = [
        .cliSupercharger,
        .rustSystems,
        .pythonAI,
        .modernAI,
        .goCloud,
        .cloudDevOps,
        .nativeMacDev,
        .macMaintenance,
        .securityCrypto,
        .macEssentials,
        .creativeMedia,
        .privacySecurity,
        .knowledgeOffice,
        .webDev,
        .dataScience
    ]
}

@MainActor
final class BrewStoreStackManager: ObservableObject {
    static let shared = BrewStoreStackManager()

    @Published var customStacks: [BrewStoreStack] = []

    private let storageKey = "BrewStoreCustomStacks"

    init() {
        loadCustomStacks()
    }

    var allStacks: [BrewStoreStack] {
        BrewStoreStack.defaultStacks + customStacks
    }

    func stacks(for type: BundleType) -> [BrewStoreStack] {
        if type == .all {
            allStacks
        } else if type == .custom {
            customStacks
        } else {
            allStacks.filter { $0.bundleType == type }
        }
    }

    func addCustomStack(name: String, description: String, icon: String, formulae: [String], casks: [String]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let bundleType: BundleType = if casks.isEmpty, !formulae.isEmpty {
            .formulae
        } else if formulae.isEmpty, !casks.isEmpty {
            .casks
        } else {
            .hybrid
        }

        let newStack = BrewStoreStack(
            id: UUID().uuidString,
            name: trimmedName,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon.isEmpty ? "shippingbox.fill" : icon,
            bundleType: bundleType,
            pricingTier: .freeFOSS,
            formulae: formulae,
            casks: casks,
            isCustom: true
        )
        customStacks.append(newStack)
        saveCustomStacks()
    }

    func deleteCustomStack(_ stack: BrewStoreStack) {
        customStacks.removeAll { $0.id == stack.id }
        saveCustomStacks()
    }

    private func loadCustomStacks() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([BrewStoreStack].self, from: data) else { return }
        customStacks = decoded
    }

    private func saveCustomStacks() {
        guard let data = try? JSONEncoder().encode(customStacks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
