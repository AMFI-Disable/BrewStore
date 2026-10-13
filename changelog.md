# Changelog

All notable changes, features, and architectural capabilities of BrewStore are documented in this file.

---

## [Unreleased]

### Added

- Automated offline quality checks in GitHub Actions CI (`ci.yml`), including Ruby YAML verification, lowercase filename validation, and strict commit message conventions.

### Changed

- Standardized repository references and URLs to `AMFI-Disable/BrewStore` across documentation, source code, and formula manifests.
- Standardized asset catalog metadata filenames to lowercase (`contents.json`).
- Updated copyright notices and human-readable metadata to `AMFI-Disable`.
- Enhanced release download routing to official GitHub Releases and Homebrew Tap.

---

## [1.0.0] - Production Release (Inaugural Release)

BrewStore transforms Homebrew into a beautiful, native, high-performance macOS App Store and system management ecosystem. Designed exclusively for macOS (Apple Silicon & Intel), BrewStore combines visual software discovery, dual-store package reconciliation (Homebrew & Mac App Store), granular developer cache cleaning, Mach-O architecture intelligence, background daemon controls, time-machine rollback snapshots, multi-machine dotfiles sync, and an embedded CLI companion.

Below is the comprehensive page-by-page and component-by-component directory of every feature included in this release.

---

### Table Of Contents

1. [Storefront Hub](#1-storefront-hub)
   - [Discover (`/discover`)](#discover-discover)
   - [Community Picks / Showdown (`/showdown`)](#community-picks--showdown-showdown)
   - [All Applications (`/allApps`)](#all-applications-allapps)
   - [All CLI Tools (`/allFormulae`)](#all-cli-tools-allformulae)
   - [Editorial Stories (`/stories`)](#editorial-stories-stories)
   - [Toolkits & Developer Stacks (`/toolkits`)](#toolkits--developer-stacks-toolkits)
   - [Categories Grid (`/categories`)](#categories-grid-categories)
2. [Package Library & My Mac Hub](#2-package-library--my-mac-hub)
   - [Installed Software Wall (`/installed`)](#installed-software-wall-installed)
   - [Adoption & Replacements (`/adoption`)](#adoption--replacements-adoption)
   - [Dependency Topology & Visual Graph (`/topology`)](#dependency-topology--visual-graph-topology)
   - [Wishlist & Bookmarks (`/wishlist`)](#wishlist--bookmarks-wishlist)
   - [Updates & Outdated Packages (`/updates`)](#updates--outdated-packages-updates)
3. [Environment Hub](#3-environment-hub)
   - [Background Services & Daemons (`/services`)](#background-services--daemons-services)
   - [Taps & Third-Party Repositories (`/taps`)](#taps--third-party-repositories-taps)
   - [Creator Studio & Scaffolding (`/creator`)](#creator-studio--scaffolding-creator)
4. [Health & Maintenance Hub](#4-health--maintenance-hub)
   - [Time-Machine Snapshots & Rollback (`/backups` -> Snapshots)](#time-machine-snapshots--rollback-backups---snapshots)
   - [Multi-Machine Git Sync & Dotfiles (`/backups` -> Sync)](#multi-machine-git-sync--dotfiles-backups---sync)
   - [Granular Developer Cache Cleaner (`/backups` -> Storage)](#granular-developer-cache-cleaner-backups---storage)
   - [Per-App Storage Inspector (`/backups` -> App Breakdown)](#per-app-storage-inspector-backups---app-breakdown)
   - [Health Score & Doctor Diagnostics (`/backups` -> Doctor)](#health-score--doctor-diagnostics-backups---doctor)
   - [CVE Security Vulnerability Scanner (`/backups` -> Security)](#cve-security-vulnerability-scanner-backups---security)
5. [Settings Hub](#5-settings-hub)
   - [General Settings](#general-settings)
   - [Appearance & Themes](#appearance--themes)
   - [Features & Modular Toggles](#features--modular-toggles)
   - [Network, Mirrors & Latency Benchmark](#network-mirrors--latency-benchmark)
   - [Snapshots, Brewfile & Cloud Git Sync](#snapshots-brewfile--cloud-git-sync)
   - [Doctor, Automation & Maintenance](#doctor-automation--maintenance)
   - [Storage, Privacy & Safety Guards](#storage-privacy--safety-guards)
   - [CLI Companion & Shell Completions](#cli-companion--shell-completions)
   - [Factory Reset & Cache Purge](#factory-reset--cache-purge)
6. [Global Overlays, System Tools & Menus](#6-global-overlays-system-tools--menus)
   - [Action Console Drawer (`⌥~`)](#action-console-drawer-)
   - [⌘K Universal Command Palette](#k-universal-command-palette)
   - [Persistent 340px Menu Bar Companion](#persistent-340px-menu-bar-companion)
   - [AI Package Discovery Assistant](#ai-package-discovery-assistant)
   - [Shell Environment Assistant & PATH Doctor](#shell-environment-assistant--path-doctor)
   - [Universal Package Detail Modal & Overlay](#universal-package-detail-modal--overlay)
   - [First-Run Guided Onboarding Wizard](#first-run-guided-onboarding-wizard)
7. [Embedded Developer CLI Companion (`brewstore`)](#7-embedded-developer-cli-companion-brewstore)
8. [Architecture, Security Boundaries & Safety Guarantees](#8-architecture-security-boundaries--safety-guarantees)
9. [Verification, Test Suite & Strict Linting](#9-verification-test-suite--strict-linting)

---

### 1. Storefront Hub

#### Discover (`/discover`)

- **Editorial Hero Carousel (`EditorialHeroView`)**:
  - Full-bleed, auto-scrolling and manually interactive spotlight carousel showcasing featured applications, notable open-source releases, and major ecosystem updates.
  - Adaptive responsive layout expanding across the full width of the window in fullscreen mode, without artificial aspect-ratio truncation.
  - Multi-line editorial quote callouts with glassmorphic typography and direct installation actions.
- **Spotlight Cards & Curated Shelves**:
  - Four curated collection shelves: *Essential Developer Tools*, *Must-Have Mac Utilities*, *Creative & Design Powerhouses*, and *Trending CLI Utilities*.
  - Dynamic high-resolution cards displaying package icons, category badges, star ratings, and download volume.
- **Horizontal Quick-Filter Bar**:
  - Scrollable category tag pills (Development, Utilities, Terminal, Security, Design, Media) allowing instant catalog slicing without leaving the discover view.
- **Interactive Action Pills (`AppStoreActionButton`)**:
  - Dual-state action button with native Apple App Store styling:
    - **GET**: Initiates download and background installation.
    - **Progress Ring**: Radial progress indicator reflecting active download and compile states with an inline click-to-cancel target.
    - **OPEN / INSTALLED**: Launches installed macOS Casks directly via `NSWorkspace` or opens a contextual management popover for CLI Formulae.
    - **UPDATE**: Highlights pending upstream version upgrades with 1-click update triggering.
- **Non-Destructive Quick-Look Overlay (`DetailModalOverlay`)**:
  - Clicking any card presents a floating, blurred-backdrop quick-look modal displaying full package details, README summaries, and dependencies without losing the user's scroll position.

#### Community Picks / Showdown (`/showdown`)

- **Head-to-Head Showdowns**:
  - Curated developer debates and direct comparisons pitting leading software against each other:
    - *Terminal Emulators*: Ghostty vs. Alacritty vs. Kitty
    - *Modal Editors*: Neovim vs. Helix
    - *AI Terminals*: Warp vs. iTerm2
    - *Containers*: OrbStack vs. Docker Desktop
    - *Modern CLI Replacements*: Bat vs. Cat, Eza vs. Ls, Ripgrep vs. Grep
- **Live Community Telemetry & Voting**:
  - GitHub star count tracking, fork statistics, and community upvoting engine.
  - User-driven voting buttons allowing developers to vote for their daily drivers and view live percentage breakdowns.
- **Side-by-Side Comparison Matrix**:
  - Detailed feature matrix comparing memory footprint (RSS), cold-start launch latency, binary architecture (Apple Silicon vs. Intel), license (MIT, Apache, GPL, Commercial), and maintenance activity (days since last release).
- **1-Click Showdown Install**:
  - Direct GET/Install triggers located inside comparison cards for rapid testing and benchmarking.

#### All Applications (`/allApps`)

- **Complete Cask Catalog Browser**:
  - Search and browse through 4,500+ macOS GUI applications packaged as Homebrew Casks.
- **Real-Time Local Icon Extraction (`AppIconResolver`)**:
  - Dynamic Mach-O bundle inspector that automatically resolves crisp, high-resolution app icons directly from `/Applications` and `~/Applications` for all installed apps, falling back to CDN assets for uninstalled packages.
- **Multi-Facet Filtering**:
  - Filter simultaneously by Category, Installation Status (Installed / Available), Architecture (Apple Silicon Native / Universal / Rosetta), and License type.
- **Multi-Mode Sorting**:
  - Instant sorting by 30-day install popularity, alphabetical name, recently added, and on-disk package size.
- **Batch Selection Mode**:
  - Multi-select checkboxes enabling one-click batch installation of multiple GUI apps at once.

#### All CLI Tools (`/allFormulae`)

- **Complete Formula Catalog**:
  - Search and browse through 7,500+ command-line tools, language runtimes, compilers, libraries, and utilities.
- **Pre-Compiled Bottle Availability Indicators**:
  - Visual badges indicating binary bottle support across macOS releases (`arm64_sequoia`, `arm64_sonoma`, `x86_64`).
- **Dependency Counters**:
  - Direct and transitive dependency counters displayed on every card, warning users about complex or heavy dependency chains prior to installation.
- **Quick-Install with Console Streaming**:
  - Trigger CLI formula installations with live, real-time command output streaming directly into the Action Console Drawer.

#### Editorial Stories (`/stories`)

- **Magazine-Style Layout (`StoriesFeedView`)**:
  - Curated, long-form developer articles, setup guides, and ecosystem deep-dives (e.g., *"Modern Rust Systems Programming on Apple Silicon"*, *"Hardening macOS Workstations for Security Engineers"*).
- **Rich Interactive Story Reader (`StoryDetailView`)**:
  - Native markdown reader supporting full-bleed hero artwork, formatted callout boxes, and syntax-highlighted shell commands.
- **Inline One-Click Package Installers**:
  - Packages referenced within article prose feature embedded interactive action pills, allowing readers to install tools without leaving the narrative.
- **Related Toolkit Deep-Links**:
  - Story footers include direct links to pre-configured developer toolkits and bundles related to the article topic.

#### Toolkits & Developer Stacks (`/toolkits`)

- **Curated Turnkey Stacks (`StacksView`)**:
  - Complete, opinionated developer environments ready for single-click deployment:
    - *Full-Stack Web Developer* (Node.js, pnpm, Bun, Visual Studio Code, Docker/OrbStack, Postman)
    - *Rust Systems Programmer* (Rustup, Cargo-binstall, Mold, Alacritty, Helix)
    - *Python Data Science & AI* (Miniconda, JupyterLab, UV, PyTorch dependencies)
    - *DevOps & Cloud Engineer* (Terraform, Kubectl, Helm, AWS CLI, K9s)
    - *macOS Power User* (Raycast, Rectangle, Bartender alternative, Maccy)
    - *Security & Reverse Engineering* (Wireshark, Ghidra, Nmap, Binwalk)
- **Batch Stack Installer**:
  - 1-Click *"Install Missing Packages"* button that analyzes current machine state, skips already installed tools, and installs all missing packages in optimal dependency order.
- **Granular Package Toggles**:
  - Expandable stack checklists allowing users to deselect specific tools before executing the batch installation.
- **Custom Toolkit Creator**:
  - Assemble, name, and export custom stacks to share with teams or use for bootstrapping new team members.

#### Categories Grid (`/categories`)

- **12 Dedicated Category Hubs (`CategoriesGridView`)**:
  - Visual grid covering Development, Utilities, Productivity, Design & Graphics, Audio & Video, Security & Privacy, Networking & Cloud, Science & Math, System Tools, Communication, Gaming, and Education.
- **Live Inventory Counters**:
  - Real-time counters showing total available packages and currently installed packages in each category.
- **Seamless Filter Navigation**:
  - Clicking any category navigates directly to a pre-filtered catalog view with instant search capability.

---

### 2. Package Library & My Mac Hub

#### Installed Software Wall (`/installed`)

- **Unified Tri-Source Inventory**:
  - Aggregates software from three distinct ecosystems into one unified library:
    1. Homebrew Casks (`/Applications`, `~/Applications`)
    2. Homebrew Formulae (`/opt/homebrew/Cellar` or `/usr/local/Cellar`)
    3. Mac App Store (MAS) applications detected via `_MASReceipt` scanning.
- **Mach-O Architecture Badges (`PackageArchitectureBadge`)**:
  - Visual status pill indicators reflecting true binary architecture:
    - `ARM64 Native` (Emerald green): Optimized for Apple Silicon.
    - `Universal` (Blue): Fat binary containing both ARM64 and x86_64 slices.
    - `Rosetta 2 (Intel)` (Amber): Legacy x86_64 binary running under translation.
- **Installed vs. Upstream Version Tracking**:
  - Real-time comparison between currently installed versions and the latest upstream versions available in Homebrew or the App Store.
- **Universal Context Menu (`PackageContextMenu`)**:
  - Right-click or action menu on any row:
    - *Show in Finder* / *Reveal in Cellar*
    - *Copy Install Command* (`brew install ...`)
    - *Pin Version* (prevents accidental upgrades)
    - *Clean App Caches*
    - *Export Package Definition*
    - *Uninstall with Residual Cleaner*
- **Multi-Select Batch Operations**:
  - Multi-row selection supporting Batch Upgrade, Batch Uninstall, and Batch Version Pinning.
- **Flexible Sorting & Filtering**:
  - Sort by Application Name, Disk Space Footprint, Installation Date, and Package Source.

#### Adoption & Replacements (`/adoption`)

- **Unmanaged Standalone App Scanner (`AppAdoptionView`)**:
  - Scans `/Applications` and `~/Applications` for standalone applications installed via manual DMG drag-and-drop, PKG installers, or direct web downloads.
- **1-Click Homebrew Adoption**:
  - Matches unmanaged bundle identifiers and executable names to official Homebrew Cask tokens.
  - Adopts unmanaged apps into Homebrew management with 1 click, enabling automated future updates without touching or deleting user application support files, settings, or credentials.
- **Mac App Store to Cask Migration**:
  - Scans `_MASReceipt` directories in `/Applications/*.app/Contents/_MASReceipt/` and identifies MAS applications that possess an equivalent or superior Homebrew Cask.
  - Offers a 1-click conversion process that installs the Cask version while preserving existing application data.
- **Rosetta 2 Intel App Detector (`AppleSiliconMigrationManager`)**:
  - Scans all installed GUI applications and CLI binaries to identify legacy Intel (`x86_64`) software running under Rosetta 2 emulation.
  - Displays a dedicated alert banner with a 1-click *"Migrate All to Apple Silicon"* action to upgrade to native ARM64 builds, reclaiming CPU performance and battery life.
- **Modern App Replacements Engine (`AppReplacementView`)**:
  - Curated engine suggesting modern, memory-safe, high-performance replacements for aging macOS software and traditional UNIX utilities:
    - *Ghostty / Alacritty* replacing Terminal.app / iTerm2
    - *Neovim / Helix* replacing Vim / Nano
    - *Bat* replacing Cat (syntax highlighting, git integration)
    - *Eza* replacing Ls (colorized icons, git status, tree view)
    - *Ripgrep* replacing Grep (multithreaded regex search)
    - *Fd* replacing Find (intuitive syntax, gitignore-aware)
    - *Zoxide* replacing Cd (smart directory jumping)
    - *Duf* replacing Df (visual disk usage tables)
    - *Bottom / Htop* replacing Top (interactive process graphs)

#### Dependency Topology & Visual Graph (`/topology`)

- **Interactive Dependency DAG (`DependencyTopologyView`, `DependencyGraphView`)**:
  - Interactive directed acyclic graph mapping the full hierarchy of direct and transitive dependencies across all installed formulae.
- **Reverse Dependency Inspector ("Why is this installed?")**:
  - Select any installed library (e.g. `openssl@3`, `icu4c`, `glib`) to see the exact chain of top-level formulae that require it, eliminating mystery packages.
- **Orphaned Dependency Detection (`DependencyDoctorManager`)**:
  - Identifies unneeded leaf libraries that were originally installed as dependencies but are no longer required by any active formula (`brew autoremove` candidates).
  - Provides a 1-click safe removal action to reclaim disk space.
- **Circular Dependency & Conflict Audit**:
  - Detects duplicate linked versions, unlinked keg conflicts, and cyclic dependency trees before they cause runtime compilation errors.

#### Wishlist & Bookmarks (`/wishlist`)

- **Personal Package Bookmarking (`WishlistView`)**:
  - Save interesting packages and tools to a persistent wishlist for later review.
- **Live Status Tracking**:
  - Wishlisted items automatically reflect real-time status: Available for install, Already Installed, or Pending Update.
- **Export & Sharing**:
  - 1-Click export of the entire wishlist as a standard `Brewfile` or shareable markdown checklist.

#### Updates & Outdated Packages (`/updates`)

- **Unified Update Control Center**:
  - Consolidates pending updates for Homebrew Formulae, Homebrew Casks, and Mac App Store applications into a single view.
- **"Update All Software" Engine**:
  - 1-Click global upgrade reconciling both Homebrew (`brew upgrade`) and Mac App Store (`mas upgrade`) in an automated, sequentially safe pipeline.
- **Changelog & Git Commit Diff Preview**:
  - Preview release notes and Homebrew formula git commit history before committing to an update.
- **Ignored Updates & Pinning Manager (`PackagePinningManager`)**:
  - Pin specific formulae (`brew pin <formula>`) or mark Casks as ignored to prevent automated upgrades from breaking mission-critical legacy toolchains.

---

### 3. Environment Hub

#### Background Services & Daemons (`/services`)

- **Triple-Domain Service Management (`ServicesView`)**:
  - Full visibility and control over:
    1. Homebrew background daemons (`brew services`)
    2. User LaunchAgents (`~/Library/LaunchAgents`)
    3. System LaunchDaemons (`/Library/LaunchDaemons`)
- **Real-Time Service Telemetry (`ServiceTelemetry`)**:
  - Displays live CPU percentage, Memory RSS usage, Process ID (PID), exit status codes, and load states.
  - Visual status dots: Green (Running), Amber (Starting/Degraded), Red (Error/Exited), Gray (Stopped).
- **1-Click Daemon Controls**:
  - Individual and batch controls for *Start*, *Stop*, *Restart*, and *Toggle Run at Login*.
- **Live Service Log Viewer (`ServiceLogView`)**:
  - Embedded real-time log drawer streaming `stdout` and `stderr` directly from `/var/log` or `~/Library/Logs`.
  - Auto-scroll, text filtering, regex search, and copy-to-clipboard functionality.
- **Orphaned Plist Cleaner**:
  - Scans for invalid or orphaned launch agent property lists pointing to nonexistent executables and routes them safely to `~/.Trash`.

#### Taps & Third-Party Repositories (`/taps`)

- **Active Tap Registry (`TapsView`)**:
  - Complete list of all configured Homebrew git taps, showing local clone paths, remote URLs, total packages provided, and branch status.
- **Tap Discovery Catalog (`TapDiscoveryView`)**:
  - Curated directory of verified official and community taps:
    - `homebrew/cask-versions` (Beta, nightly, and legacy versions of apps)
    - `homebrew/cask-fonts` (Hundreds of open-source and developer fonts)
    - `hashicorp/tap`, `cloudflare/cloudflare`, `mongodb/brew`
- **Tap Health & Connectivity Diagnostics (`TapHealthManager`)**:
  - Tests remote git connectivity, fetch latency, and stale remote HEAD branches.
  - 1-Click repair for broken git remotes and outdated repository configurations.
- **Custom Tap Addition**:
  - Add third-party or private taps with support for custom git URLs and private GitHub Personal Access Token authentication.

#### Creator Studio & Scaffolding (`/creator`)

- **Developer Authoring Workshop (`CreatorStudioView`)**:
  - Integrated development environment for authoring, linting, and testing custom Homebrew Formulae and Casks.
- **Ruby DSL Scaffolding Generator (`CreatorRepoManager`)**:
  - Automated Ruby template generator for CLI binaries, GitHub releases, DMG/ZIP cask apps, and Go/Rust/Node projects.
- **Automated Checksum Calculation**:
  - 1-Click SHA-256 calculation for local or remote archive files (tarballs, zip files, DMGs).
- **Live Formula Linter (`brew audit`)**:
  - Integrates `brew audit --strict` and `brew style` directly into the editor, reporting style violations, deprecated DSL tags, and missing descriptions.
- **Isolated Testing Sandbox**:
  - Test install, test audit, and uninstall custom formulae in an isolated local sandbox before publishing them to a tap.

---

### 4. Health & Maintenance Hub

#### Time-Machine Snapshots & Rollback (`/backups` -> Snapshots)

- **Automated State Snapshots (`SnapshotManager`)**:
  - Automatically captures full environment snapshots (all formulae, casks, taps, and pin states) before major batch operations or upgrades.
  - Manual *"Create Snapshot"* button with custom naming and timestamp tags.
- **3-Way Visual State Diffing**:
  - Compares any historical snapshot against the live machine state:
    - **Added**: Packages present today that were absent in the snapshot.
    - **Missing**: Packages present in the snapshot that have been removed.
    - **Identical**: Packages preserved with identical versions.
- **1-Click System Rollback Engine (`SnapshotRollbackManager`)**:
  - Reverts the workstation to any historical snapshot by installing missing packages and removing unwanted additions in a single automated rollback sequence.
- **Brewfile Export & Lockfile Generator (`LockfileGenerator`)**:
  - Generates standard `Brewfile` and version-locked `Brewfile.lock.json` with architecture metadata (`arm64_sequoia`, etc.).

#### Multi-Machine Git Sync & Dotfiles (`/backups` -> Sync)

- **Multi-Provider Git Cloud Sync (`GitServiceManager`, `MultiMachineSyncView`)**:
  - Seamless backup and synchronization of Brewfiles across:
    - **GitHub** (Personal Repositories & Private Gists)
    - **GitLab** (Projects & Personal Snippets)
    - **Codeberg** (Gitea-powered open forge)
    - **Forgejo / Gitea (Self-Hosted)** (Private self-hosted Git servers)
    - **Local Directory / Symlinked Dotfiles Repo**
- **Token Persistence & Blob Hash Verification**:
  - Automatically persists Gist and Snippet IDs in `UserDefaults` to prevent duplicate backup creation.
  - Performs `GET /contents/Brewfile` blob SHA verification on Forgejo/Gitea prior to `PUT` updates, preventing file replacement collisions.
- **Automated Lifecycle Sync (`DotfilesAutoSyncManager`)**:
  - Optional background auto-sync that automatically commits and pushes updated Brewfiles to the remote repository whenever a package is installed, updated, or uninstalled.
- **Mac Blueprint Engine (`MacTransferManager`)**:
  - Captures complete machine setup (Homebrew packages, taps, Mac App Store apps, shell preferences).
  - Generates an idempotent, 1-command `bootstrap.sh` bash script to automatically set up a brand-new or wiped Mac from scratch in minutes.

#### Granular Developer Cache Cleaner (`/backups` -> Storage)

- **Developer Tooling Cache Analyzer (`DeveloperCacheManager`, `DiskStorageView`)**:
  - Deep scanning across major developer toolchain caches:
    - **Xcode**: DerivedData, Archives, iOS DeviceSupport, and CoreSimulator caches.
    - **Docker & OrbStack**: Container layer caches, buildkit cache, and dangling images.
    - **Package Managers**: npm `_cacache`, Yarn cache, pnpm content store, Cargo registry & git index, CocoaPods cache, Gradle cache, and Homebrew bottle download cache (`brew --cache`).
- **Checklist Controls with Select All / Deselect All**:
  - Granular checkboxes with full-row tap targets, item counts, and calculated reclaimable gigabytes.
- **Non-Destructive Trash Protocol (`BrewStoreTrashExecutor`)**:
  - All cache purges route safely through `BrewStoreTrashExecutor` to `~/.Trash`, ensuring no irreversible `rm -rf` operations take place.

#### Per-App Storage Inspector (`/backups` -> App Breakdown)

- **Exact Per-App Disk Usage Breakdown (`AppStorageInspectorManager`)**:
  - Inspects every installed application to display a three-part storage breakdown:
    1. **Application Binary**: The `.app` bundle size in `/Applications`.
    2. **Caches & Logs**: Temporary cache data in `~/Library/Caches` and `~/Library/Logs`.
    3. **Application Support & Containers**: Data stores in `~/Library/Application Support` and `~/Library/Containers`.
- **1-Click "Clean Caches" Action**:
  - Purges application caches without touching user databases, login credentials, or preferences.
- **Residual Leftover Scanner (`AppRemovalScanner`)**:
  - When uninstalling an application, automatically scans for orphaned preference files (`~/Library/Preferences/*.plist`), application support directories, and crash logs to perform a truly clean uninstall.

#### Health Score & Doctor Diagnostics (`/backups` -> Doctor)

- **macOS & Homebrew Health Score (`HealthScoreView`, `HealthOptimizer`)**:
  - Visual 0-100% health meter evaluating package hygiene, unlinked kegs, broken symlinks, outdated packages, and security advisories.
- **Intelligent `brew doctor` Parser (`DoctorParser`, `DoctorRemediationManager`)**:
  - Executes `brew doctor` and transforms cryptic terminal output into structured, severity-ranked cards with clear explanations.
- **1-Click Automated Remediation**:
  - Single-click automated fixes for common system issues:
    - Re-linking unlinked formulae (`brew link --overwrite`)
    - Cleaning stale lock files
    - Pruning broken symlinks (`brew cleanup --prune=all`)
    - Correcting permission anomalies on `/opt/homebrew/share`
- **Bottle Integrity Auditor (`BottleIntegrityAuditor`)**:
  - Verifies cryptographic SHA-256 signatures of installed bottles to detect corrupted or tampered local binaries.

#### CVE Security Vulnerability Scanner (`/backups` -> Security)

- **Real-Time Vulnerability Database (`CVESecurityScanner`, `CVESecurityView`)**:
  - Scans all installed packages against the NIST National Vulnerability Database (NVD), Open Source Vulnerabilities (OSV), and GitHub Advisory Database.
- **CVSS Severity Ranking**:
  - Displays color-coded vulnerability badges: Critical, High, Medium, and Low with official CVSS base scores.
- **Actionable Remediation Guidance**:
  - Provides direct upgrade paths and patch advisories for vulnerable packages, with 1-click update buttons.

---

### 5. Settings Hub

#### General Settings

- **Default Package Source Recommendation**:
  - Configure whether BrewStore prefers Homebrew Casks or Mac App Store apps when both sources offer the same software.
- **Launch at Login**:
  - Configure BrewStore and its lightweight Menu Bar companion to launch automatically upon macOS login.
- **Update Frequency & Notification Badges**:
  - Set automated background update check intervals (Hourly, Daily, Weekly) and dock icon badge preferences.

#### Appearance & Themes

- **6 Handcrafted Themes (`BrewStoreTheme`, `ThemeVibrancyManager`)**:
  1. *System Default* (Adapts dynamically to macOS Light/Dark mode)
  2. *Dark Mode* (Modern deep charcoal glass)
  3. *Light Mode* (Clean, high-contrast daylight aesthetic)
  4. *OLED Pure Black* (Ultra-high-contrast true black for Pro Display XDR & MacBook OLED/Mini-LED displays)
  5. *Midnight Navy* (Sophisticated deep blue developer palette)
  6. *Monokai Pro* (Vibrant developer theme inspired by classic code editors)
- **Translucency & Vibrancy Controls**:
  - Adjustable NSVisualEffectView glassmorphic material intensity.
- **Layout & Density Modes**:
  - Toggle between Standard Spacious rows and Compact Information-Dense rows.

#### Features & Modular Toggles

- **AI Search Assistant Toggle**: Enable or disable the natural-language search assistant.
- **Rosetta 2 Migration Banner**: Toggle the Apple Silicon alert banner for legacy Intel applications.
- **CoreSpotlight Indexing**: Enable macOS Spotlight indexing for all installed packages.
- **Menu Bar Extra**: Enable or disable the persistent menu bar helper.
- **Action Console Drawer**: Toggle visibility of the streaming bottom terminal drawer.

#### Network, Mirrors & Latency Benchmark

- **Homebrew Bottle Mirror Selector (`MirrorManager`)**:
  - Switch between official Homebrew GitHub servers and leading regional university mirrors:
    - *Official Homebrew (GitHub GHCR)*
    - *USTC (University of Science and Technology of China)*
    - *TUNA (Tsinghua University)*
    - *Aliyun (Alibaba Cloud)*
- **Real-Time Speed & Latency Benchmark (`SpeedTestManager`, `MirrorBenchmarkView`)**:
  - Built-in ping and download speed test utility measuring latency and transfer throughput to every mirror, recommending the fastest provider.
- **HTTP / HTTPS Proxy Configuration**:
  - Support for custom proxy routing (`ALL_PROXY`, `HTTP_PROXY`, `HTTPS_PROXY`).

#### Snapshots, Brewfile & Cloud Git Sync

- **Automated Snapshot Scheduling**:
  - Configure auto-snapshots prior to uninstallation and upgrades.
- **Cloud Git Authentication Manager (`GitHubAccountManager`, `GitServiceManager`)**:
  - Securely store and validate Personal Access Tokens for GitHub, GitLab, Codeberg, and Forgejo.
  - Boosts GitHub API rate limit from 60 to 5,000 requests per hour.

#### Doctor, Automation & Maintenance

- **Automated Maintenance Routines**:
  - Schedule automated background `brew cleanup` routines to purge old bottle downloads older than 30 days.
- **Log Retention Policies**:
  - Configure automated rotation and cleanup of BrewStore operation logs.

#### Storage, Privacy & Safety Guards

- **Protected Root Safety Validator (`PathSafetyValidator`, `ExecutionSecurityBoundary`)**:
  - Hardened security validator strictly preventing accidental modification or deletion of protected macOS system directories (`/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/private`).
- **Trash Confirmation Dialogs**:
  - Configurable safety prompts before moving files to `~/.Trash`.

#### CLI Companion & Shell Completions

- **1-Click Symlink Installer (`CLIToolManager`)**:
  - Automatically symlinks the embedded `brewstore` executable to `~/.local/bin/brewstore`.
- **Automated Shell Completion Installation**:
  - Generates and installs native auto-completions for Zsh (`_brewstore`), Bash (`brewstore.bash`), and Fish (`brewstore.fish`).

#### Factory Reset & Cache Purge

- **Granular Reset Manager (`ResetManager`, `ResetViewSheet`)**:
  - Safe, selective reset utility allowing users to:
    - Clear image and icon caches
    - Reset Homebrew catalog API cache
    - Reset user preferences to defaults
    - Perform complete clean slate application reset

---

### 6. Global Overlays, System Tools & Menus

#### Action Console Drawer (`⌥~`)

- **Persistent Sliding Console (`ActionConsoleDrawer`)**:
  - Bottom terminal drawer accessible via `⌥~` or toolbar icon, streaming real-time stdout and stderr output during all package operations.
- **ANSI Color & Control Sequence Rendering**:
  - Full support for ANSI color codes, text bolding, and terminal progress carriage returns.
- **Process Timing & Cancellation**:
  - Displays live elapsed operation timers and provides a 1-click process termination button to safely kill hanging subprocesses.
- **Log Export**:
  - 1-Click copy-to-clipboard or export log file for troubleshooting.

#### ⌘K Universal Command Palette

- **Raycast-Style Launcher (`CommandPaletteView`)**:
  - System-wide modal search accessible anywhere via `⌘K`.
- **Fuzzy Search Across 12,000+ Items (`FuzzySearchEngine`)**:
  - Lightning-fast sub-millisecond search querying:
    - All Formulae and Casks
    - Background services and daemons
    - Maintenance actions (*Clean Caches*, *Run Doctor*, *Check Updates*)
    - Navigation destinations and settings pages
- **Category Filter Pills**:
  - Filter results instantly by *All*, *Actions & Maintenance*, *Background Services*, *Packages & Casks*, and *Navigation*.
- **Keyboard-First Navigation**:
  - Full arrow-key navigation with active scroll tracking, Return to execute, and Escape to dismiss.

#### Persistent 340px Menu Bar Companion

- **Real-Time Telemetry (`MenuBarExtraView`)**:
  - Compact 340px menu bar extra monitoring active background Homebrew daemons with live CPU % and Memory RSS readouts.
- **Active Rosetta 2 Warning Badge**:
  - Prominently alerts users if legacy Intel software is actively executing on an Apple Silicon Mac.
- **Quick Maintenance Menu**:
  - Instant access to *Clean Developer Caches*, *Check for Software Updates*, *Export Blueprint*, and *Toggle Action Console*.

#### AI Package Discovery Assistant

- **Natural Language Query Engine (`AISearchView`, `AISearchAssistant`)**:
  - Enter conversational queries (e.g., *"I need a modern video player that supports subtitle sync and hardware acceleration"* or *"Find me a lightweight alternative to Postman"*).
- **Semantic Intent Analysis**:
  - Parses intent, queries the catalog, and returns curated recommendations with reasoned feature comparisons.

#### Shell Environment Assistant & PATH Doctor

- **Environment Diagnostic (`ShellConfigView`, `ShellConfigAssistant`)**:
  - Scans `~/.zshrc`, `~/.bashrc`, and `~/.config/fish/config.fish`.
  - Verifies presence of official Homebrew `PATH` exports (`/opt/homebrew/bin` on Apple Silicon, `/usr/local/bin` on Intel) and compiler flags.
- **1-Click Auto-Repair with Backup**:
  - Automatically appends missing environment initialization commands while safely generating a timestamped backup of the user's original shell configuration.

#### Universal Package Detail Modal & Overlay

- **Comprehensive Package Inspector (`PackageDetailView`)**:
  - Displays package title, tap origin, version, author homepage, license, and GitHub repository links.
  - Mach-O binary architecture pill (`ARM64 Native`, `Universal`, `Rosetta 2`).
  - Disk size on filesystem, download bottle size, and Homebrew 30-day/90-day install analytics.
  - Caveats and post-installation instructions.
  - Direct and reverse dependency lists.
  - 1-Click Cellar reveal, version pinning toggle, and complete uninstall.

#### First-Run Guided Onboarding Wizard

- **Automated Homebrew Detection (`HomebrewSetupView`)**:
  - Automatically detects whether Homebrew and Xcode Command Line Tools are present.
  - Provides a guided, 1-click automated installer that fetches and executes the official Homebrew installation script with live progress reporting.

---

### 7. Embedded Developer CLI Companion (`brewstore`)

BrewStore embeds a standalone, highly capable command-line utility located inside its application bundle at `Contents/Resources/bin/brewstore`:

```sh
brewstore <subcommand> [options]
```

- `brewstore adopt`: Scans `/Applications` and adopts unmanaged standalone applications into Homebrew Casks.
- `brewstore switch`: Inspects and toggles binary architectures between Apple Silicon (`arm64`) and Rosetta 2 (`x86_64`).
- `brewstore audit`: Audits all installed Casks and Formulae for known CVE security vulnerabilities.
- `brewstore mas`: Scans `_MASReceipt` directories and reconciles Mac App Store applications.
- `brewstore health`: Runs system diagnostics, checks Homebrew health score, and suggests automated repairs.
- `brewstore clean`: Performs safe cache cleaning and removes orphaned bottle downloads.
- `brewstore devclean`: Granularly purges developer caches (Xcode DerivedData, Docker layers, npm, cargo, etc.).
- `brewstore blueprint`: Exports complete system blueprint and generates the idempotent `bootstrap.sh` script.
- `brewstore completions`: Emits shell auto-completion scripts for `zsh`, `bash`, and `fish`.
- `brewstore install-cli`: Automatically creates the `~/.local/bin/brewstore` symlink.
- `brewstore version`: Prints BrewStore version, build number, and active architecture.

---

### 8. Architecture, Security Boundaries & Safety Guarantees

- **Mach-O Binary Inspection (`CellarScanner`, `BrewStoreSecurityInspector`)**:
  - Dynamically reads Mach-O headers (`MH_MAGIC_64`, `FAT_CIGAM`) across `/opt/homebrew/opt/*/bin`, `/usr/local/bin`, and `/Applications/*.app` to determine true hardware compatibility.
- **Protected Root Safety Boundaries (`ExecutionSecurityBoundary`, `PathSafetyValidator`)**:
  - Strict filesystem safety checks preventing any destructive operation from targeting root, system libraries, or user home directories.
- **Non-Destructive Trash Protocol (`BrewStoreTrashExecutor`)**:
  - All uninstalls, residual sweeps, and cache cleanups route exclusively through the macOS Trash API (`FileManager.trashItem`), guaranteeing that no files are permanently destroyed without user consent.
- **Process Stability & Hang Prevention (`CommandExecutor`)**:
  - Subprocess execution registers `terminationHandler` before `process.run()`, backed by pipe EOF dispatch group detection to guarantee zero UI hangs or frozen terminal tasks.

---

### 9. Verification, Test Suite & Strict Linting

- **382 Automated Unit Tests across 52 Test Suites**:
  - 100% test pass rate covering command execution, JSON schema parsing, binary inspection, Git sync, cache cleaning, and UI navigation.
- **Strict SwiftLint Compliance**:
  - 0 warnings and 0 errors across all 214 Swift source files running under `swiftlint lint --strict`.
- **macOS Human Interface Guidelines (HIG)**:
  - Adheres strictly to macOS design patterns: native sidebars, translucent toolbars, keyboard navigation, and VoiceOver accessibility identifiers across every interactive component.

---
*BrewStore — The Native Mac Application & Package Manager.*
