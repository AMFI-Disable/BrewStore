# Changelog

## 1.0.0 (Production Release)

Complete transformation into the unified Mac Application & Package Manager, combining Homebrew package management, Mac App Store integration, cache cleaning, architecture intelligence, background daemon controls, and machine blueprint replication.

### The 5 Core Pillars
- **Pillar 1: Unified App Inventory & Dual-Store Management**:
  - Aggregated Homebrew Cask, Formula, Mac App Store (MAS), and unmanaged standalone application inventory.
  - Configurable default source recommendation preference (`.homebrew` vs `.macAppStore`) in General Settings.
  - Automatic `_MASReceipt` scanning with 1-click conversion from Mac App Store to Homebrew cask while preserving local app configurations.
  - One-click global software update engine (`upgradeAllSoftware`) reconciling both stores.
- **Pillar 2: Per-App Storage Breakdown & Non-Destructive Cache Cleaner**:
  - Exact real-time disk breakdown for every installed application: Binary size, Cache/Logs size, and Application Support data.
  - Dedicated "Clean Caches" action with safety confirmation dialog.
  - Safe routing of all cache purges through `BrewStoreTrashExecutor` directly to `~/.Trash`, keeping user preferences, databases, and login sessions intact.
- **Pillar 3: Architecture & Binary Inspector (Apple Silicon vs. Rosetta 2)**:
  - Deep Mach-O binary inspection determining native architectures (`arm64`, `x86_64`, or `universal`).
  - Visual status pill badges in package lists and detail screens (`ARM64 Native`, `Universal`, `Rosetta 2`).
  - Prominent Apple Silicon migration alert banner with 1-click "Migrate All to Apple Silicon" to reclaim performance and battery life.
- **Pillar 4: Background Daemons & macOS Login Items Hub**:
  - Unified `ServicesView` managing Homebrew background daemons alongside user/system `LaunchAgents` and macOS Login Items.
  - Real-time service search, status indicators (Loaded, Running, Disabled), PID counters, and enable/disable toggle controls.
  - Safe Trash removal for obsolete or orphaned LaunchAgent plists with strict path validation.
- **Pillar 5: Complete Mac Setup, Transfer & Blueprint Engine**:
  - Comprehensive machine blueprint capturing Homebrew packages, taps, pinned versions, Mac App Store applications, and settings.
  - Idempotent 1-command bootstrap bash script export for effortless setup of new or wiped Macs.
  - Native in-app blueprint restore ("Bootstrap This Mac") and enhanced Brewfile import/export with `mas` entry support.

### Granular Developer Cache Cleaner (Option A)
- Specialized disk analyzer scanning major developer tooling caches:
  - Xcode DerivedData, Archives, iOS DeviceSupport, and CoreSimulator caches.
  - Docker layer caches, OrbStack data stores.
  - Package manager caches: npm `_cacache`, Yarn, pnpm content store, Cargo registry & git db, CocoaPods, Gradle, and Homebrew bottle downloads.
- Select All / Deselect All controls with individual target selection and 1-click purge to `~/.Trash`.

### Menu Bar Companion & ⌘K Command Palette (Option B)
- **Menu Bar Extra**:
  - Persistent lightweight menu bar helper with real-time CPU percentage and memory RSS telemetry for background services.
  - Header warning badge detecting active Rosetta 2 Intel apps with direct navigation to native migration.
  - Quick-access Tools menu for developer caches, blueprint export, and unmanaged app adoption.
- **⌘K Command Palette**:
  - Raycast-style modal launcher accessible anywhere via `⌘K`.
  - Interactive category filter pills (`All`, `Actions & Maintenance`, `Background Services`, `Packages & Casks`, `Navigation`).
  - Contextual preview footer with keyboard shortcut indicators and arrow-key auto-scrolling navigation.

### Bug Fixes & Quality Assurance
- **Crash Fixes**: Resolved fatal index out-of-bounds crash in `CommandPaletteView` by ensuring strict index validation (`filteredItems.indices.contains(selectedIndex)`).
- **Stuck State Fixes**:
  - Unified Re-Scan button in `DiskStorageView` refreshing both Homebrew and developer caches simultaneously while maintaining proper operating lock states.
  - Guarded empty target selections in `DeveloperCacheManager` and `AppStorageInspector` to avoid stuck indeterminate progress states.
- **User Experience Polish**:
  - Full-width tap targets on cache item rows for easy selection toggling.
  - Dedicated failure state reporting distinguishing true errors from empty cache states.
  - Smooth keyboard arrow navigation with active `ScrollViewReader` tracking.
- **Panel Shifting Fixes**:
  - Stabilized global search popover height (fixed at 420pt) to eliminate vertical window jumping during typing.
  - Added scanning placeholder skeletons to prevent abrupt layout shifts when developer caches load.
  - Removed high-frequency animation thrashing during streaming console drawer logging.
- **Editor's Choice Full-Screen Ratio**:
  - Removed artificial 63% ratio constraint in `EditorialHeroView`, enabling hero cards and review quotes to expand across the full width of the window in fullscreen mode.
  - Expanded review quote limit to 3 lines with unbounded horizontal width.

### Verification & Test Suite
- Expanded automated unit test suite from 19 to **339 tests across 47 test suites with 0 failures (100% passing)**.
- Full SwiftLint strict compliance with **0 violations across all 199 source files**.
- Ad-hoc signed release DMG (`website/downloads/brewstore-1.0.0.dmg`) with verified SHA-256 checksum.
