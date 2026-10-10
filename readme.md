# 🍺 BrewStore

<div align="center">

**The Undisputed #1 Native macOS Package Manager & Homebrew Companion**  
*Lightning-fast, native SwiftUI GUI & CLI companion for casks, formulae, background services, multi-version link management, and security audits.*

[![Platform: macOS Sonoma+](https://img.shields.io/badge/platform-macOS%2014%2B%20(Sonoma%20%2F%20Sequoia%20%2F%20Tahoe)-blue.svg?style=flat-square&logo=apple)](https://apple.com)
[![Swift: 5.10+](https://img.shields.io/badge/Swift-5.10%2B-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![Release: v1.0.0](https://img.shields.io/badge/release-v1.0.0-blue.svg?style=flat-square&logo=github)](https://github.com/AMFI-Disable/BrewStore/releases)
[![Tests: 345 / 345 Passed](https://img.shields.io/badge/tests-339%20%2F%20339%20Passed%20(100%25)-success.svg?style=flat-square&logo=checkmarx)](#-automated-tests--quality-assurance)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](license)
[![Pricing: Free & Open-Source](https://img.shields.io/badge/price-100%25%20Free%20%26%20Open%20Source-success.svg?style=flat-square)](#why-brewstore-over-caskhub--taphouse-pro)
[![Zero Telemetry](https://img.shields.io/badge/privacy-Zero%20Telemetry%20%2F%20100%25%20Local-purple.svg?style=flat-square)](#privacy--security-first)

---

## 🌐 Select Language / 选择语言 / 言語を選択 / Idioma / Langue / Sprache

**[English](readme.md)** •
**[简体中文](readme.zh-cn.md)** •
**[繁體中文](readme.zh-tw.md)** •
**[日本語](readme.ja.md)** •
**[Español](readme.es.md)** •
**[Français](readme.fr.md)** •
**[Deutsch](readme.de.md)**

---

### 🧭 Quick Directing Links

[🍺 Homebrew Cask](#option-1-official-homebrew-cask-recommended) •
[✨ Feature Highlights](#-feature-highlights) •
[⌨️ Keyboard Shortcuts](#power-keyboard-shortcuts) •
[💻 CLI Companion](#-brewstore-cli-companion) •
[🛡️ Safety & Reliability](#safety-first-architecture) •
[📊 Comparison Matrix](#why-brewstore-over-caskhub--taphouse-pro) •
[🧪 Test Suite](#-automated-tests--quality-assurance) •
[🗺️ Roadmap](#roadmap)

</div>

---

## 📖 What is BrewStore?

**BrewStore** is the definitive desktop application for macOS package management. Built from the ground up in native **SwiftUI** and **AppKit**, it bridges the raw flexibility of Homebrew’s CLI with the elegance, discoverability, and fluid ergonomics of an Apple Design Award-winning App Store experience.

Whether you're a software engineer orchestrating multiple runtimes, a designer configuring creative tools, or a power user auditing system daemons, BrewStore delivers:

- **Instant Discoverability**: Search across 10,000+ formulae and casks in under 20ms using local in-memory tokenized indices.
- **Preview-First Dry-Run Safety**: Inspect cascaded reverse dependencies and orphan impacts before any removal or update is committed.
- **Time Machine Snapshots**: Automatic pre-mutation rollback points with visual diffs so you can revert any botched command instantly.
- **Enterprise-Grade Service Management**: Inspect real-time CPU percentages, memory RSS, and active listening ports for all background daemons.
- **Multi-Provider Git Sync**: Synchronize and back up your `~/Brewfile` to GitHub, GitLab, Codeberg, Forgejo, or self-hosted Gitea repositories.

---

## ⚡ Architecture & Subsystems

```text
+-----------------------------------------------------------------------------------------+
|                                    BrewStore GUI Layer                                  |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | ⌘K Power Launcher |  | Spotlight Carousel |  | Dependency Canvas |  | Menu Bar  |   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | Version Pinning   |  | Community Showdown |  | Mirror Benchmark  |  | Wishlist  |   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                              BrewStore Core Engine                                      |
|   * FastCacheEngine (Sub-20ms Local Index)     * PackagePinningManager (Atomic State)   |
|   * SnapshotManager (Rollback Time Machine)    * UninstallCoordinator (Preview Gate)    |
|   * LockCoordinationManager (PID Safe Guard)   * ServiceTelemetryMonitor (CPU/RAM/Port) |
|   * MirrorLatencyBenchmarkEngine               * GitServiceManager (GitHub/GitLab/FOSS) |
|   * DockLifecycleManager (Scene & Status)      * TapHealthManager (Audit & CI Status)   |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                              Underlying System Bridges                                  |
|   * Homebrew CLI Engine (/opt/homebrew or /usr/local)                                   |
|   * Mac App Store Bridge (mas-cli receipt scanning & updates)                           |
|   * macOS LaunchAgent Daemon (com.amfi-disable.brewstore.autoupdate.plist)              |
|   * macOS Security LocalAuthentication (Touch ID / Biometrics)                          |
+-----------------------------------------------------------------------------------------+
```

---

## ✨ Feature Highlights

### 👑 The 5 Pillars of the Complete Mac App Manager

1. **🏬 Unified Dual-Store App Management & Homebrew Preference**
   - Seamlessly unifies Homebrew Casks, CLI Formulae, Mac App Store apps (`mas-cli`), and external unmanaged apps in a single searchable inventory.
   - Automatically detects dual-store apps and recommends Homebrew for faster updates, CLI scriptability, and zero Apple ID password prompts.
   - Built-in App Store receipt detection (`Contents/_MASReceipt/receipt`) with 1-click non-destructive conversion to Homebrew management.

2. **🧹 Per-App Storage & Leftover Cache Cleaner**
   - Precise 3-column storage breakdown in package details: **Binary Size**, **Caches & Logs**, and **Application Data**.
   - Dedicated **Clean Caches** button routes all temporary files safely to `~/.Trash`, clearing gigabytes of bloated cache while keeping user login sessions, application databases, and settings completely intact.

3. **🍎 Apple Silicon Native & Rosetta 2 Migration Inspector**
   - Visual architecture capsule badges on every package row: `ARM64 Native` (green), `Universal` (blue), and `Rosetta 2` (warning orange).
   - High-visibility alert banner detecting legacy Intel x86_64 apps running under Rosetta 2 emulation, with 1-click **Migrate All to Apple Silicon** to reclaim CPU cycles and battery life.

4. **⚙️ Login Items & macOS LaunchAgent Daemon Management**
   - Consolidates Homebrew services, user LaunchAgents (`~/Library/LaunchAgents`), system LaunchAgents (`/Library/LaunchAgents`), and macOS Login Items in a unified `ServicesView`.
   - Real-time CPU usage, Resident Set Size (RSS) memory telemetry, listening ports, and status toggles via `launchctl` with safe Trash removal.

5. **🚀 Complete Mac Setup & Blueprint Transfer Engine**
   - Comprehensive **Mac Blueprint** export capturing all Homebrew packages, taps, Mac App Store apps (`mas "<name>", id: <id>`), pinned versions, and app preferences.
   - Generates an idempotent, 1-command bootstrap shell script and provides native in-app restoration in `MultiMachineSyncView` to clone your Mac environment in minutes.

### 🛍️ 6. Modern App Store Experience for Homebrew

- **Curated Spotlight & Editorial Stories**: Discover top-tier macOS utilities with handcrafted editorial narratives, release breakdowns, and developer highlights.
- **Community Showdown & Tournament Brackets**: Zero-server community brackets powered by GitHub Discussions. Vote for your favorite tools and follow seasonal matchups.
- **Developer Toolkits & Stacks**: One-click installation bundles for Full-Stack Web, Swift/iOS, DevOps, Rust, Data Science, and Machine Learning.
- **Personal Wishlist & Bookmarking**: Star packages and keep a curated wishlist that stays isolated from system state.

### 🛡️ 7. Safety-First Architecture & Rollback Time Machine <a id="safety-first-architecture"></a>

- **Atomic Version Pinning**: Pin mission-critical packages directly from detail pages, action menus, or the context menu. Automatic rollback handles CLI errors cleanly with immediate UI feedback.
- **Preview-First Dry-Run Uninstalls**: Every package removal and `autoremove` passes through a non-destructive preview modal detailing reverse-dependency warnings and orphaned packages.
- **1-Click Snapshot Rollbacks**: BrewStore automatically creates system state snapshots prior to destructive mutations, allowing instant Time Machine rollbacks with full diff visualization.
- **Proactive Lock Coordination**: Detects concurrent Homebrew processes and provides graceful queueing and timeouts, preventing database locks and corrupted taps.

### 🌐 8. Mirror Speed Benchmark & CDN Switcher

- **Live Latency Benchmarking**: Ping and measure download speeds across Official Fastly CDN, USTC (University of Science and Technology of China), TUNA (Tsinghua University), and Aliyun mirrors.
- **1-Click Switcher**: Apply high-speed mirrors globally across `HOMEBREW_API_DOMAIN` and `HOMEBREW_BOTTLE_DOMAIN` with a single tap.

### 💻 9. Menu Bar Companion & Terminal CLI

- **Zero-Distortion Menu Bar Popover**: Check pending updates, trigger one-click upgrades, monitor active services, and access quick maintenance tools with rigid window geometry.
- **Full Terminal CLI (`brewstore`)**: Run audits, switch tool versions, manage Mac App Store apps, clean caches, and adopt unmanaged applications directly from terminal shell environments.

### 🔄 10. Multi-Provider Git Cloud Sync

- Sync your packages, taps, and cask configurations directly to a `~/Brewfile`.
- First-class support for **GitHub Gists**, **GitLab Snippets**, **Codeberg**, **Forgejo**, and custom self-hosted **Gitea** instances with encrypted personal access tokens.

---

## ⚡ Installation

### Option 1: Official Homebrew Cask (Recommended)

Install BrewStore and the terminal CLI companion directly through Homebrew:

```bash
brew tap AMFI-Disable/brewstore
brew install --cask brewstore
```

To update in the future:

```bash
brew upgrade --cask brewstore
```

---

### Option 2: Build from Source

```bash
# Clone repository
git clone https://github.com/AMFI-Disable/BrewStore.git
cd BrewStore

# Generate Xcode project via XcodeGen
xcodegen generate

# Build Release Configuration
xcodebuild -scheme BrewStore -configuration Release -destination 'platform=macOS' build

# Run Full Automated Test Suite (345 tests)
xcodebuild test -scheme BrewStore -destination 'platform=macOS'
```

---

## ⌨️ Power Keyboard Shortcuts <a id="power-keyboard-shortcuts"></a>

BrewStore is designed for keyboard-first efficiency:

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| <kbd>⌘ K</kbd> | **Command Palette** | Global quick-launcher for commands (`> upgrade all`, `> cleanup`, `> benchmark`), navigation, and package search |
| <kbd>⌘ R</kbd> | **Refresh Catalog** | Reload local packages, remote indices, service states, and update counts |
| <kbd>⌘ F</kbd> | **Search** | Instantly focus search field in current section |
| <kbd>⌘ ,</kbd> | **Settings** | Open preferences, mirror benchmark switcher, auto-update schedule, and cloud sync |
| <kbd>⌘ 1</kbd> | **Discover** | Jump to Storefront Spotlight, curated picks, and trending apps |
| <kbd>⌘ 2</kbd> | **Installed** | View all locally installed formulae and casks |
| <kbd>⌘ 3</kbd> | **Updates** | View outdated packages, estimated installation times, and update buttons |
| <kbd>⌘ 4</kbd> | **Services** | Monitor and manage background daemons and runtime telemetry |
| <kbd>⌘ 5</kbd> | **Dependencies** | Open Interactive Dependency Canvas 2.0 graph |
| <kbd>⌘ 6</kbd> | **Wishlist** | View saved and starred packages |
| <kbd>⌘ 7</kbd> | **Toolkits** | Open developer stack bundles |
| <kbd>⌘ 8</kbd> | **Maintenance** | Access Doctor, disk cache cleaners, and orphan leaf removal |

---

## 💻 `brewstore` CLI Companion

BrewStore packages a standalone CLI utility accessible directly from `/opt/homebrew/bin/brewstore` or `/usr/local/bin/brewstore`:

```bash
# Adopt unmanaged apps in /Applications into Homebrew casks
brewstore adopt [--all]

# Switch active tool runtime versions (Cellar link management)
brewstore switch node 20
brewstore switch python 3.12
brewstore switch postgresql 16

# Run comprehensive security CVE audits & hardening score (0–100)
brewstore audit

# Check and upgrade Mac App Store applications
brewstore mas list
brewstore mas upgrade

# Check toolchain health, orphaned packages, and disk consumption
brewstore health

# Free disk space (cleanup cache bottles and autoremove unused dependencies)
brewstore clean

# Launch the native GUI app
brewstore launch
```

---

## 🌟 Why BrewStore Over CaskHub & Taphouse Pro ($19.99) <a id="why-brewstore-over-caskhub--taphouse-pro"></a>

| Feature Vertical | **BrewStore** | **Taphouse Pro** ($19.99) | **CaskHub** |
| :--- | :---: | :---: | :---: |
| **Pricing & License** | **100% Free & MIT Open-Source** | $19.99 Commercial / Proprietary | Free |
| **Telemetry & Privacy** | **Zero Telemetry / 100% Local** | Third-party tracking | Unknown |
| **Automated Test Coverage** | **345 XCTest Methods (100% Pass)** | Undisclosed | Minimal |
| **Per-App Storage & Cache Cleaner** | **✅ Non-Destructive (~/.Trash)** | ❌ No | ❌ No |
| **Apple Silicon vs Rosetta 2** | **✅ Auto-Detect & 1-Click Migrate** | ❌ No | ❌ No |
| **macOS LaunchAgents & Login Items** | **✅ Full Telemetry & PID/RAM** | ⚠️ Services only | ❌ No |
| **1-Command Mac Blueprint Engine** | **✅ Formulae, Casks, MAS & Prefs** | ❌ No | ❌ No |
| **Dual-Store Unified Inventory** | **✅ Homebrew + MAS Recommended** | ❌ No | ❌ No |
| **Preview-First Uninstall Gate** | **✅ Cascaded Impact Warnings** | ❌ No | ❌ No |
| **1-Click Snapshot Rollback** | **✅ Automatic Pre-Mutation Diff** | ⚠️ View only | ❌ No |
| **Atomic Version Pinning** | **✅ 1-Click Pin with Rollback** | ⚠️ Formulas only | ❌ No |
| **Background Services Telemetry** | **✅ Live CPU, RAM & Ports** | ⚠️ Status only | ❌ No |
| **Mirror Latency Benchmark** | **✅ Fastly, USTC, TUNA, Aliyun** | ❌ No | ❌ No |
| **Multi-Provider Git Sync** | **✅ GitHub, GitLab, Codeberg, Gitea** | ❌ GitHub only | ❌ No |
| **Interactive Dependency Canvas** | **✅ Bidirectional Graph** | ⚠️ Static tree | ❌ No |
| **Menu Bar Companion** | **✅ Non-Distorting Extra** | ⚠️ Basic | ❌ No |
| **Terminal CLI Companion** | **✅ Included (`brewstore` binary)** | ❌ No | ❌ No |
| **Cold Launch Speed** | **⚡ &lt;20ms (Tokenized Cache)** | 🐢 2–3s | 🐢 2–3s |

---

## 🧪 Automated Tests & Quality Assurance

BrewStore maintains a comprehensive, automated test suite covering all business logic, synchronization coordinators, security boundaries, and user interactions.

```bash
# Execute test suite via Xcodebuild
xcodegen generate
xcodebuild test -scheme BrewStore -destination "platform=macOS"
```

### Verified Test Suites (345 / 345 Passing)

- `AppStorageInspectorTests`: Non-destructive per-app cache cleaning, exact size breakdown (Binary vs Caches vs Data), and Trash safety.
- `AppleSiliconMigrationTests`: Rosetta 2 emulation detection, native ARM64 migration candidates, and architecture mapping.
- `BackgroundItemsManagerTests`: User and system LaunchAgent plists, launchctl execution, and Login Items parsing.
- `MacBlueprintEngineTests`: Enhanced Brewfile MAS parsing, bootstrap script generation, and Blueprint restoration.
- `UnifiedAppManagerTests`: Dual-store inventory merging, Homebrew recommendation preferences, and 1-click global upgrades.
- `SidebarDestinationSelectionTests`: Strict isolation of authentic destinations from non-selectable accessibility headings.
- `MenuBarDistortionPreventionTests`: Rigid popover geometry, window size locking, and resize animation suppression.
- `PackagePinningSynchronizationTests`: Atomic state consistency between pinning manager, Homebrew state, and failure rollbacks.
- `SpotlightCarouselTargetingTests`: Race-condition suppression and pick-bound wishlist interactions.
- `UninstallCoordinatorTests`: Preview-first dry-run gates and reverse-dependency warning calculations.
- `TapHealthManagerTests`: Official and third-party tap status checks and branch monitoring.
- `SpeedTestManagerTests`: CDN ping parsing, clamping, and live update duration estimations.
- `TCCPermissionManagerTests`: Accessibility and system extension privilege detection.
- `BrewStoreLockManagerTests`: PID lock tracking, timeout handling, and stale lock eviction.
- `CellarScannerTests`: Multi-version Cellar discovery and symlink switching.
- `MASReceiptScannerTests`: Mac App Store bundle receipts and version resolution.
- `ExecutionSecurityBoundaryTests`: Shell sanitization, path escape prevention, and argument injection defense.

---

## 🛡️ Privacy & Security First <a id="privacy--security-first"></a>

- **Zero Telemetry**: BrewStore contains zero tracking analytics, zero Google/Firebase SDKs, and zero telemetry beacons.
- **Local Execution**: All command executions run strictly through your local Homebrew binary (`/opt/homebrew` on Apple Silicon or `/usr/local` on Intel).
- **Biometric Authorization**: Sensitive operations leverage Apple's native `LocalAuthentication` framework for Touch ID and Apple Watch authorization.
- **Ad-Hoc & Hardened Signing**: Full compliance with macOS runtime security guidelines.

---

## 🗺️ Roadmap <a id="roadmap"></a>

- [x] **v1.0.0**: Native SwiftUI redesign, FastCache engine, ⌘K command palette, and interactive dependency graph.
- [x] **v1.0.5**: Multi-Provider Git sync (GitLab, Codeberg, Forgejo, Gitea) and Community Showdown bracket tournament engine.
- [x] **v1.1.0**:
  - [x] Preview-First Dry-Run Uninstall & Autoremove Coordinator with reverse-dependency impact warnings.
  - [x] Atomic Package Pinning Manager with live progress states and rollback safety.
  - [x] Menu Bar Companion stabilization with rigid geometry and zero-distortion window locking.
  - [x] Accessible non-selectable sidebar group headings.
  - [x] Carousel interaction pause and pick-keyed wishlist binding.
  - [x] Automated Tap Health audits and CI tracking.
  - [x] 276 automated regression tests passing with 0 failures.
- [ ] **v1.2.0**:
  - [ ] P2P Local Network Bottle Caching for multi-Mac offices and home labs.
  - [ ] Containerized Sandbox Dry-Runs via Apple Virtualization Framework.
  - [ ] Custom tap creation wizard for indie developers.

---

## 🤝 Contributing

Contributions are warmly welcomed! Please read our [Contributing Guidelines](docs/contributing.md) and [Security Policy](security.md) before submitting pull requests.

1. Fork the repository.
2. Create your feature branch (`git checkout -b feature/amazing-feature`).
3. Commit your changes (`git commit -m 'feat: Add amazing feature'`).
4. Push to the branch (`git push origin feature/amazing-feature`).
5. Open a Pull Request.

---

## 📄 License

BrewStore is licensed under the [MIT License](license). Open source, libre, and proudly independent.
