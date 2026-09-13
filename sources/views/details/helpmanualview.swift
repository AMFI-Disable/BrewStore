import AppKit
import SwiftUI

struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let subtitle: String
    let sections: [HelpSection]
}

struct HelpSection: Identifiable, Hashable {
    let id = UUID()
    let heading: String
    let paragraphs: [String]
    let tip: String?
    let codeSnippet: String?
}

struct HelpManualView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopicID: String = "getting-started"
    @State private var searchQuery = ""

    static let topics: [HelpTopic] = [
        HelpTopic(
            id: "getting-started",
            title: "Getting Started",
            icon: "sparkles",
            subtitle: "Introduction to BrewStore, Discovery, and Casks vs Formulae",
            sections: [
                HelpSection(
                    heading: "Welcome to BrewStore",
                    paragraphs: [
                        "BrewStore is a native macOS App Store interface for Homebrew, bringing modern visual discovery, safe application management, and background health monitoring to your Mac.",
                        "You can discover curated apps, install CLI utilities with a single click, read editorial deep-dive stories, and deploy complete developer toolkits."
                    ],
                    tip: "Press ⌘K at any time from anywhere in the app to open the Quick Open command palette.",
                    codeSnippet: nil
                ),
                HelpSection(
                    heading: "Casks vs Formulae",
                    paragraphs: [
                        "• Casks (macOS Apps): Full graphical applications installed directly into your /Applications folder (e.g. Visual Studio Code, Docker, Raycast, iTerm2).",
                        "• Formulae (CLI Packages): Command-line tools, compilers, libraries, and background services installed into Homebrew's Cellar (e.g. git, node, python, nginx)."
                    ],
                    tip: "BrewStore automatically resolves installed app icons for casks directly from your local system.",
                    codeSnippet: nil
                ),
                HelpSection(
                    heading: "1-Click App Store Action Button",
                    paragraphs: [
                        "Package rows and product pages feature a dynamic App Store action pill:",
                        "• GET: Downloads and installs the package.",
                        "• Progress Ring: Shows active execution with an inline click-to-cancel button.",
                        "• OPEN / INSTALLED: Opens installed casks or provides an action menu with Cellar reveal, Pinning, and Uninstall options.",
                        "• UPDATE: Highlights pending version upgrades."
                    ],
                    tip: nil,
                    codeSnippet: nil
                )
            ]
        ),
        HelpTopic(
            id: "v1-changelog",
            title: "What's New in v1.0.0",
            icon: "sparkles.rectangle.stack.fill",
            subtitle: "Exhaustive directory of all features across every page",
            sections: [
                HelpSection(
                    heading: "Storefront: Discover, Showdowns & Toolkits",
                    paragraphs: [
                        "• Discover: Editorial Hero spotlight carousel with adaptive full-screen width, curated shelves, category tags, and instant GET action pills.",
                        "• Community Picks: Head-to-head showdowns (Ghostty vs Alacritty, Neovim vs Helix, OrbStack vs Docker) with live voting and spec comparison matrix.",
                        "• All Applications & CLI Tools: Full directories of 4,500+ Casks and 7,500+ Formulae with real-time app icon extraction and bottle status.",
                        "• Stories & Toolkits: Curated editorial guides with inline package installers, plus turnkey developer stacks with 1-click batch installation."
                    ],
                    tip: nil,
                    codeSnippet: nil
                ),
                HelpSection(
                    heading: "Library: Installed, Adoption & Dependencies",
                    paragraphs: [
                        "• Installed Wall: Tri-source inventory (Homebrew Casks, Formulae, Mac App Store apps) with Mach-O architecture badges (ARM64, Universal, Rosetta 2).",
                        "• Adoption & Replacements: 1-Click adoption of unmanaged DMG/PKG apps into Homebrew, MAS-to-Cask conversion, and modern CLI tool suggestions.",
                        "• Topology & Dependencies: Interactive visual DAG graph and 'Why is this installed?' reverse dependency inspector.",
                        "• Updates & Wishlist: Centralized update reconciler and personal package bookmark collection."
                    ],
                    tip: nil,
                    codeSnippet: nil
                ),
                HelpSection(
                    heading: "Environment: Daemons, Taps & Creator Studio",
                    paragraphs: [
                        "• Services & Daemons: Triple-domain management of Homebrew daemons, user LaunchAgents, and LaunchDaemons with live CPU/RAM telemetry and log streaming.",
                        "• Taps & Health: Tap registry, discovery of official/community taps, and connection health diagnostics.",
                        "• Creator Studio: Scaffolding Ruby DSL manifests, automatic SHA-256 calculation, and strict brew audit linting in an isolated test sandbox."
                    ],
                    tip: nil,
                    codeSnippet: nil
                ),
                HelpSection(
                    heading: "Health & Maintenance: Snapshots, Sync, Cache & Doctor",
                    paragraphs: [
                        "• Time-Machine Snapshots: Pre-operation state capture with 3-way visual diffing and 1-click system rollback.",
                        "• Multi-Machine Git Sync: Brewfile backup across GitHub, GitLab, Codeberg, Forgejo/Gitea, Gists, and automated bootstrap.sh script generation.",
                        "• Developer Cache Cleaner: Granular cleaning for Xcode, Docker, npm, Yarn, Cargo, Gradle, and Homebrew caches safely to ~/.Trash.",
                        "• Doctor & Security: Health score 0-100%, 1-click automated repairs, and real-time CVE vulnerability scanning with CVSS ratings."
                    ],
                    tip: nil,
                    codeSnippet: nil
                ),
                HelpSection(
                    heading: "Global Overlays, CLI & Menu Bar Companion",
                    paragraphs: [
                        "• Action Console Drawer (⌥~): Real-time ANSI color terminal output streaming for all Homebrew actions.",
                        "• ⌘K Command Palette: Raycast-style universal launcher searching packages, services, actions, and settings.",
                        "• Menu Bar Extra: 340px companion with live daemon telemetry, Rosetta 2 alert, and quick maintenance.",
                        "• Developer CLI: Embedded 'brewstore' command-line companion with shell auto-completions."
                    ],
                    tip: "View the complete documentation in changelog.md in the project root.",
                    codeSnippet: "brewstore version"
                )
            ]
        ),
        HelpTopic(
            id: "services",
            title: "Background Services",
            icon: "gearshape.2.fill",
            subtitle: "Managing Homebrew daemons and viewing logs",
            sections: [
                HelpSection(
                    heading: "Controlling Services",
                    paragraphs: [
                        "Homebrew allows formulae such as databases (PostgreSQL, Redis, MySQL) and web servers (Nginx, Caddy) to run in the background as macOS LaunchAgents.",
                        "The Services view displays real-time status dots (Green for running, Yellow/Red for errors) with 1-click Start, Stop, and Restart controls."
                    ],
                    tip: "You can also manage running services quickly from the 340px Menu Bar companion.",
                    codeSnippet: "brew services list"
                ),
                HelpSection(
                    heading: "Log Files & Configuration",
                    paragraphs: [
                        "BrewStore automatically resolves standard log file locations in your Homebrew prefix (/var/log/ or ~/Library/Logs/) so you can diagnose service startup issues."
                    ],
                    tip: nil,
                    codeSnippet: nil
                )
            ]
        ),
        HelpTopic(
            id: "app-cleaner",
            title: "App Cleaner & Safety",
            icon: "trash.circle.fill",
            subtitle: "Scanning leftover files and protected path validation",
            sections: [
                HelpSection(
                    heading: "Residual File Scanning",
                    paragraphs: [
                        "When removing a Cask, standard uninstallers often leave behind megabytes or gigabytes of caches, container data, and preference plists.",
                        "BrewStore includes a built-in App Cleaner that scans ~/Library/Application Support, ~/Library/Caches, ~/Library/Containers, and ~/Library/Preferences for orphaned bundle files."
                    ],
                    tip: "All candidate files are moved safely to the macOS Trash, never deleted permanently.",
                    codeSnippet: nil
                ),
                HelpSection(
                    heading: "Protected Root Safety Validator",
                    paragraphs: [
                        "To protect your operating system, BrewStore enforces strict path validation: system directories (/System, /Library, /usr, /bin, /private) and intermediate symbolic links are strictly shielded from removal."
                    ],
                    tip: nil,
                    codeSnippet: nil
                )
            ]
        ),
        HelpTopic(
            id: "snapshots",
            title: "Time-Machine & Snapshots",
            icon: "clock.arrow.circlepath",
            subtitle: "3-Way visual diffing and GitHub Gist cloud backups",
            sections: [
                HelpSection(
                    heading: "Time-Machine Brewfile Snapshots",
                    paragraphs: [
                        "BrewStore records automated and manual snapshots of your complete environment (all formulae, casks, and taps).",
                        "The Snapshots view provides an interactive 3-way visual diff (Added, Missing, Identical) comparing any historical snapshot against your current live machine."
                    ],
                    tip: "Enable 'Auto-Snapshot before uninstallation' in Settings to ensure you can always roll back accidental removals.",
                    codeSnippet: nil
                ),
                HelpSection(
                    heading: "GitHub Gist Cloud Sync",
                    paragraphs: [
                        "Connect your GitHub Personal Access Token in Settings to back up your environment to a private Gist in the cloud with 1 click. Connecting your account also increases your Homebrew API rate limit to 5,000 requests/hour."
                    ],
                    tip: nil,
                    codeSnippet: nil
                )
            ]
        ),
        HelpTopic(
            id: "doctor",
            title: "Doctor & Auto-Repair",
            icon: "stethoscope",
            subtitle: "Diagnosing conflicts and 1-click system repairs",
            sections: [
                HelpSection(
                    heading: "Homebrew Doctor Diagnostics",
                    paragraphs: [
                        "Homebrew Doctor scans your local macOS setup for unlinked formula kegs, missing Xcode command line tools, permission mismatches, and broken symlinks."
                    ],
                    tip: "Run Doctor from Settings (or ⌥⌘D) to see parsed issues categorized by severity.",
                    codeSnippet: "brew doctor"
                ),
                HelpSection(
                    heading: "1-Click Auto-Fix Assistant",
                    paragraphs: [
                        "BrewStore parses diagnostic messages to identify safe automated repair commands (e.g. brew cleanup, brew link --overwrite).",
                        "Issues that require administrator privileges (sudo) or terminal interaction are clearly flagged."
                    ],
                    tip: nil,
                    codeSnippet: nil
                )
            ]
        ),
        HelpTopic(
            id: "creator-studio",
            title: "Creator Studio & Scaffolding",
            icon: "hammer.circle.fill",
            subtitle: "Personal taps, SHA-256 calculation, and Ruby formula scaffolding",
            sections: [
                HelpSection(
                    heading: "Personal Tap Management",
                    paragraphs: [
                        "Creator Studio lets developers manage custom third-party Homebrew repositories directly.",
                        "You can connect your GitHub account to auto-detect your homebrew-* tap repositories, track GitHub star counts, and monitor local installs."
                    ],
                    tip: "You can also use Creator Studio offline without connecting a GitHub account.",
                    codeSnippet: "brew tap username/custom-tap"
                ),
                HelpSection(
                    heading: "Formula & Cask Scaffolding",
                    paragraphs: [
                        "Quickly generate official Homebrew Ruby manifests for your software releases with automated SHA-256 checksum calculation, URL validation, and recipe linting."
                    ],
                    tip: nil,
                    codeSnippet: nil
                )
            ]
        ),
        HelpTopic(
            id: "shortcuts",
            title: "Keyboard Shortcuts",
            icon: "command",
            subtitle: "Complete cheat sheet for navigation and operations",
            sections: [
                HelpSection(
                    heading: "Navigation & Section Shortcuts",
                    paragraphs: [
                        "• ⌘1 — Discover Storefront",
                        "• ⌘2 — Editorial Stories",
                        "• ⌘3 — Developer Toolkits & Stacks",
                        "• ⌘4 — Category Hub",
                        "• ⌘5 — Installed Library Wall",
                        "• ⌘6 — Updates & Outdated Packages",
                        "• ⌘7 — Background Services",
                        "• ⌘8 — Taps & Repositories",
                        "• ⌘9 — Time-Machine Snapshots",
                        "• ⌘, — Settings Control Center"
                    ],
                    tip: nil,
                    codeSnippet: nil
                ),
                HelpSection(
                    heading: "Action & Maintenance Shortcuts",
                    paragraphs: [
                        "• ⌘K — Quick Open Command Palette",
                        "• ⌘R — Refresh All Packages & Catalogs",
                        "• ⌥⌘U — Upgrade All Outdated Packages",
                        "• ⌥⌘R — Fetch Latest Metadata (brew update)",
                        "• ⌥⌘K — Clean Disk Cache (brew cleanup)",
                        "• ⌥⌘D — Run Homebrew Doctor Diagnostics",
                        "• ⌘O — Import Brewfile",
                        "• ⌘S — Export Brewfile",
                        "• ⌘? — Open BrewStore Help Manual"
                    ],
                    tip: "All shortcuts work system-wide while BrewStore is the active application.",
                    codeSnippet: nil
                )
            ]
        )
    ]

    private var selectedTopic: HelpTopic {
        filteredTopics.first { $0.id == selectedTopicID } ?? filteredTopics.first ?? Self.topics.first ?? HelpTopic(
            id: "help",
            title: "Help",
            icon: "questionmark",
            subtitle: "",
            sections: []
        )
    }

    private var filteredTopics: [HelpTopic] {
        if searchQuery.isEmpty {
            return Self.topics
        }
        return Self.topics.filter { topic in
            topic.title.localizedCaseInsensitiveContains(searchQuery) ||
                topic.subtitle.localizedCaseInsensitiveContains(searchQuery) ||
                topic.sections.contains { sec in
                    sec.heading.localizedCaseInsensitiveContains(searchQuery) ||
                        sec.paragraphs.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
                }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredTopics, selection: $selectedTopicID) { topic in
                HStack(spacing: 10) {
                    Image(systemName: topic.icon)
                        .font(.body)
                        .foregroundStyle(.tint)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.title).font(.headline)
                        Text(topic.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
                .tag(topic.id)
            }
            .listStyle(.sidebar)
            .searchable(text: $searchQuery, prompt: "Search Help Manual")
            .onChange(of: searchQuery) {
                if let firstMatch = filteredTopics.first {
                    selectedTopicID = firstMatch.id
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            .navigationTitle("Help Manual")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    HStack(spacing: 14) {
                        Image(systemName: selectedTopic.icon)
                            .font(.system(size: 32))
                            .foregroundStyle(.tint)
                            .padding(12)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedTopic.title).font(.largeTitle.bold())
                            Text(selectedTopic.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Divider()

                    // Sections
                    ForEach(selectedTopic.sections) { sec in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(sec.heading).font(.title3.bold())

                            ForEach(sec.paragraphs, id: \.self) { p in
                                Text(LocalizedStringKey(p))
                                    .font(.body)
                                    .lineSpacing(4)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }

                            if let code = sec.codeSnippet {
                                HStack {
                                    Text(code)
                                        .font(.caption.monospaced().bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                        .textSelection(.enabled)
                                    Spacer()
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(code, forType: .string)
                                    }
                                    .controlSize(.small)
                                }
                                .padding(.top, 2)
                            }

                            if let tip = sec.tip {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundStyle(.yellow)
                                    Text(LocalizedStringKey(tip))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                .padding(.top, 4)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
                .padding(28)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 780, minHeight: 540)
    }
}
