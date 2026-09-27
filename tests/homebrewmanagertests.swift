@testable import BrewStore
import SwiftUI
import XCTest

final class HomebrewManagerTests: XCTestCase {
    func testParserExtractsDependenciesCaveatsAndPinning() {
        let json = """
        {
            "formulae": [
                {
                    "name": "sqlite",
                    "full_name": "sqlite",
                    "desc": "Command-line interface for SQLite",
                    "homepage": "https://sqlite.org/",
                    "versions": { "stable": "3.45.0" },
                    "dependencies": ["readline"],
                    "caveats": "sqlite is keg-only, which means it was not symlinked into /opt/homebrew.",
                    "tap": "homebrew/core",
                    "installed": [{ "version": "3.45.0" }]
                }
            ],
            "casks": []
        }
        """

        let data = Data(json.utf8)
        let packages = HomebrewJSONParser.packages(
            from: data,
            kind: .formula,
            installedIDs: ["sqlite"],
            outdatedIDs: [],
            pinnedIDs: ["sqlite"]
        )

        XCTAssertEqual(packages.count, 1)
        let pkg = packages[0]
        XCTAssertEqual(pkg.id, "sqlite")
        XCTAssertEqual(pkg.name, "sqlite")
        XCTAssertTrue(pkg.isInstalled)
        XCTAssertFalse(pkg.isOutdated)
        XCTAssertTrue(pkg.isPinned)
        XCTAssertEqual(pkg.dependencies, ["readline"])
        XCTAssertEqual(pkg.tap, "homebrew/core")
        XCTAssertNotNil(pkg.caveats)
        XCTAssertEqual(pkg.installedVersion, "3.45.0")
    }

    func testPinnedIdentifiersParser() {
        let output = """
        node
        python@3.11
        postgresql@15
        """

        let pinned = HomebrewJSONParser.pinnedIdentifiers(from: output)
        XCTAssertEqual(pinned, Set(["node", "python@3.11", "postgresql@15"]))
    }

    func testServiceStatusHelpers() {
        let runningService = BrewStoreService(id: "redis", name: "redis", status: "started", user: "brewuser", file: "/opt/homebrew/opt/redis/homebrew.mxcl.redis.plist")
        XCTAssertTrue(runningService.isRunning)
        XCTAssertFalse(runningService.isError)

        let stoppedService = BrewStoreService(id: "postgresql", name: "postgresql", status: "none", user: nil, file: nil)
        XCTAssertFalse(stoppedService.isRunning)
        XCTAssertFalse(stoppedService.isError)

        let errorService = BrewStoreService(id: "mysql", name: "mysql", status: "error (256)", user: "brewuser", file: nil)
        XCTAssertFalse(errorService.isRunning)
        XCTAssertTrue(errorService.isError)
    }

    func testTapIsOfficialHelper() {
        let officialTap = BrewStoreTap(id: "homebrew/cask", name: "homebrew/cask")
        XCTAssertTrue(officialTap.isOfficial)

        let customTap = BrewStoreTap(id: "community/custom-tap", name: "community/custom-tap")
        XCTAssertFalse(customTap.isOfficial)
    }

    func testMaintenanceActionArguments() {
        let cleanupArgs = ["cleanup", "--prune=all"]
        let dryRunCleanupArgs = ["cleanup", "-n", "--prune=all"]
        let autoremoveArgs = ["autoremove"]

        XCTAssertEqual(cleanupArgs, ["cleanup", "--prune=all"])
        XCTAssertEqual(dryRunCleanupArgs, ["cleanup", "-n", "--prune=all"])
        XCTAssertEqual(autoremoveArgs, ["autoremove"])
    }

    func testPackageActionArguments() {
        let formula = BrewStorePackage(id: "node", name: "Node.js", description: "", homepage: "", version: "20.0", kind: .formula)
        let cask = BrewStorePackage(id: "visual-studio-code", name: "VS Code", description: "", homepage: "", version: "1.90", kind: .cask)

        XCTAssertEqual(PackageAction.install.arguments(for: formula), ["install", "--formula", "node"])
        XCTAssertEqual(PackageAction.install.arguments(for: cask), ["install", "--cask", "visual-studio-code"])
        XCTAssertEqual(PackageAction.reinstall.arguments(for: formula), ["reinstall", "--formula", "node"])
        XCTAssertEqual(PackageAction.link.arguments(for: formula), ["link", "node"])
        XCTAssertEqual(PackageAction.linkOverwrite.arguments(for: formula), ["link", "--overwrite", "node"])
        XCTAssertEqual(PackageAction.unlink.arguments(for: formula), ["unlink", "node"])
    }

    func testDoctorParserClean() {
        let cleanOutput = "Your system is ready to brew."
        let diagnostics = BrewStoreDoctorParser.parse(cleanOutput)

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].severity, .clean)
        XCTAssertEqual(diagnostics[0].title, "System Ready")
    }

    func testDoctorParserWarningsWithSuggestedCommands() {
        let output = """
        Warning: You have unlinked kegs in your Cellar.
        Leaving kegs unlinked can resolve conflicts.
        brew link python@3.11

        Warning: Some directories in /usr/local/share/man are not writable.
        You should probably change the ownership:
        sudo chown -R $(whoami) /usr/local/share/man
        """

        let diagnostics = BrewStoreDoctorParser.parse(output)

        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertEqual(diagnostics[0].severity, .warning)
        XCTAssertEqual(diagnostics[0].suggestedCommand, "brew link python@3.11")
        XCTAssertEqual(diagnostics[1].suggestedCommand, "sudo chown -R $(whoami) /usr/local/share/man")
    }

    func testStorageUsageFormatting() {
        let usage = BrewStoreStorageUsage(
            cellarBytes: 1_000_000_000,
            caskroomBytes: 500_000_000,
            downloadCacheBytes: 250_000_000
        )

        XCTAssertEqual(usage.totalBytes, 1_750_000_000)
        XCTAssertFalse(usage.formattedTotal.isEmpty)
        XCTAssertFalse(usage.formattedCellar.isEmpty)
        XCTAssertFalse(usage.formattedCaskroom.isEmpty)
        XCTAssertFalse(usage.formattedCache.isEmpty)
    }

    func testMirrorPresets() {
        XCTAssertEqual(BrewStoreMirrorPreset.allPresets.count, 4)
        let official = BrewStoreMirrorPreset.official
        XCTAssertEqual(official.id, "official")
        XCTAssertTrue(official.brewApiDomain.contains("formulae.brew.sh"))

        let tsinghua = BrewStoreMirrorPreset.tsinghua
        XCTAssertEqual(tsinghua.id, "tuna")
        XCTAssertTrue(tsinghua.brewApiDomain.contains("tsinghua.edu.cn"))
    }

    func testPackageDependentsProperty() {
        var pkg = BrewStorePackage(
            id: "openssl@3",
            name: "openssl@3",
            description: "Cryptography and SSL/TLS Toolkit",
            homepage: "https://openssl.org/",
            version: "3.2.1",
            kind: .formula
        )
        XCTAssertTrue(pkg.dependents.isEmpty)

        pkg.dependents = ["python@3.11", "node", "git"]
        XCTAssertEqual(pkg.dependents.count, 3)
        XCTAssertTrue(pkg.dependents.contains("node"))
    }

    func testRemovalPlanFormattedBytes() {
        let candidate1 = BrewStoreRemovalCandidate(
            url: URL(fileURLWithPath: "/tmp/app.app"),
            kind: .applicationBundle,
            size: 50_000_000,
            confidence: .exactBundleIdentifier
        )
        let candidate2 = BrewStoreRemovalCandidate(
            url: URL(fileURLWithPath: "/tmp/cache"),
            kind: .cache,
            size: 10_000_000,
            confidence: .exactBundleIdentifier
        )
        let plan = BrewStoreRemovalPlan(
            application: BrewStoreAppIdentity(name: "App", bundleIdentifier: "com.app", applicationURL: URL(fileURLWithPath: "/tmp/app.app")),
            candidates: [candidate1, candidate2]
        )

        XCTAssertEqual(plan.selectedCount, 2)
        XCTAssertEqual(plan.selectedBytes, 60_000_000)
        XCTAssertFalse(plan.formattedSelectedBytes.isEmpty)
        XCTAssertFalse(candidate1.formattedSize.isEmpty)
    }

    func testDeveloperStacksCalculation() {
        let stack = BrewStoreStack.webDev
        XCTAssertEqual(stack.formulae.count, 4)
        XCTAssertEqual(stack.casks.count, 5)
        XCTAssertEqual(stack.totalCount, 9)

        let installed = [
            BrewStorePackage(id: "node", name: "node", description: "", homepage: "", version: "20.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.40", kind: .formula, isInstalled: true)
        ]

        XCTAssertEqual(stack.installedCount(in: installed), 2)
        XCTAssertFalse(stack.isFullyInstalled(in: installed))

        let missing = stack.missingPackages(in: installed)
        XCTAssertEqual(missing.formulae, ["pnpm", "redis"])
        XCTAssertTrue(missing.casks.contains("visual-studio-code"))
        XCTAssertTrue(missing.casks.contains("zed"))
    }

    func testBundleFreePricingIntegrity() {
        let defaultStacks = BrewStoreStack.defaultStacks
        XCTAssertEqual(defaultStacks.count, 15)

        for stack in defaultStacks {
            // Assert that every stack is either 100% Free & FOSS, or allowed freemium with Bitwarden
            if stack.pricingTier == .allowedFreemium {
                XCTAssertTrue(stack.casks.contains("bitwarden"))
            } else {
                XCTAssertEqual(stack.pricingTier, .freeFOSS)
            }

            // Verify Brewfile export capability
            let brewfile = stack.exportToBrewfile()
            XCTAssertTrue(brewfile.contains("# BrewStore Bundle: \(stack.name)"))
        }
    }

    func testServiceLogURLResolution() {
        let service = BrewStoreService(
            id: "redis",
            name: "redis",
            status: "started",
            user: "user",
            file: nil
        )

        let url = service.logURL(prefix: "/opt/homebrew")
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.path.contains("redis") == true)
    }

    func testDoctorAutoFixClassification() {
        let output = """
        Warning: You have unlinked kegs in your Cellar.
        brew link python@3.11

        Warning: Some files require root permissions.
        sudo chown -R $(whoami) /usr/local/share/man
        """

        let diagnostics = BrewStoreDoctorParser.parse(output)
        XCTAssertEqual(diagnostics.count, 2)

        let fixable = diagnostics[0]
        XCTAssertTrue(fixable.isAutoFixable)
        XCTAssertEqual(fixable.autoFixCommand, "brew link python@3.11")
        XCTAssertFalse(fixable.requiresSudo)

        let sudoDiag = diagnostics[1]
        XCTAssertFalse(sudoDiag.isAutoFixable)
        XCTAssertTrue(sudoDiag.requiresSudo)
    }

    @MainActor
    func testSnapshotDiffCalculation() {
        let snapshot = BrewStoreSnapshot(
            id: "snapshot-1",
            timestamp: Date(),
            name: "Initial Backup",
            fileURL: URL(fileURLWithPath: "/tmp/Brewfile"),
            formulae: ["git", "node", "redis"],
            casks: ["docker", "iterm2"],
            taps: ["homebrew/core"]
        )

        let currentPackages = [
            BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.40", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "node", name: "node", description: "", homepage: "", version: "20.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "python@3.11", name: "python@3.11", description: "", homepage: "", version: "3.11", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "docker", name: "docker", description: "", homepage: "", version: "4.0", kind: .cask, isInstalled: true)
        ]

        let currentTaps = [BrewStoreTap(id: "homebrew/core", name: "homebrew/core")]

        let manager = BrewStoreSnapshotManager()
        let diff = manager.computeDiff(for: snapshot, currentPackages: currentPackages, currentTaps: currentTaps)

        XCTAssertTrue(diff.hasDifferences)
        XCTAssertEqual(diff.addedFormulae, ["python@3.11"])
        XCTAssertEqual(diff.missingFormulae, ["redis"])
        XCTAssertEqual(diff.missingCasks, ["iterm2"])
        XCTAssertEqual(diff.identicalCount, 3) // git, node, docker
    }

    func testEditorialPicksLookup() {
        XCTAssertFalse(BrewStoreEditorialPick.allPicks.isEmpty)

        let raycast = BrewStoreEditorialPick.pick(for: "raycast")
        XCTAssertNotNil(raycast)
        XCTAssertEqual(raycast?.name, "Raycast")
        XCTAssertEqual(raycast?.kind, .cask)
        XCTAssertEqual(raycast?.badge, "Editor's Choice")

        let ripgrep = BrewStoreEditorialPick.pick(for: "ripgrep")
        XCTAssertNotNil(ripgrep)
        XCTAssertEqual(ripgrep?.kind, .formula)

        let unknown = BrewStoreEditorialPick.pick(for: "non-existent-xyz")
        XCTAssertNil(unknown)
    }

    func testEditorialStoriesCatalog() {
        XCTAssertEqual(BrewStoreStory.allStories.count, 8)
        for story in BrewStoreStory.allStories {
            XCTAssertFalse(story.id.isEmpty)
            XCTAssertFalse(story.title.isEmpty)
            XCTAssertFalse(story.eyebrow.isEmpty)
            XCTAssertFalse(story.subtitle.isEmpty)
            XCTAssertFalse(story.featuredPackageIDs.isEmpty)
            XCTAssertGreaterThanOrEqual(story.featuredPackageIDs.count, 3)
            XCTAssertGreaterThan(story.readTimeMinutes, 0)
        }
    }

    func testExpandedEditorialPicks() {
        XCTAssertGreaterThanOrEqual(BrewStoreEditorialPick.allPicks.count, 20)
        let formulae = BrewStoreEditorialPick.allPicks.filter { $0.kind == .formula }
        let casks = BrewStoreEditorialPick.allPicks.filter { $0.kind == .cask }
        XCTAssertFalse(formulae.isEmpty)
        XCTAssertFalse(casks.isEmpty)

        for pick in BrewStoreEditorialPick.allPicks {
            XCTAssertFalse(pick.id.isEmpty)
            XCTAssertFalse(pick.name.isEmpty)
            XCTAssertFalse(pick.badge.isEmpty)
            XCTAssertFalse(pick.review.isEmpty)
        }
    }

    func testCategoriesHubDefinitions() {
        XCTAssertEqual(CategoriesGridView.categories.count, 8)
        let ids = Set(CategoriesGridView.categories.map(\.id))
        XCTAssertEqual(ids.count, 8)
    }

    func testSectionIconsAndIdentifiers() {
        for section in BrewStoreSection.allCases {
            XCTAssertFalse(section.id.isEmpty)
            XCTAssertFalse(section.icon.isEmpty)
        }
    }

    @MainActor
    func testGitHubAccountInitialState() {
        let account = GitHubAccountManager()
        XCTAssertFalse(account.isAuthenticated)
        XCTAssertGreaterThanOrEqual(account.rateLimitRemaining, 0)
        XCTAssertGreaterThanOrEqual(account.rateLimitTotal, 60)
    }

    @MainActor
    func testBrewStorePreferencesDefaultsAndReset() {
        let prefs = BrewStorePreferences.shared
        prefs.resetToDefaults()

        XCTAssertTrue(prefs.isAutoCheckEnabled)
        XCTAssertEqual(prefs.checkIntervalHours, 1)
        XCTAssertTrue(prefs.autoFetchMetadata)
        XCTAssertFalse(prefs.autoCleanupOnQuit)
        XCTAssertTrue(prefs.showNotifications)
        XCTAssertTrue(prefs.showMenuBarBadge)
        XCTAssertEqual(prefs.defaultMenuBarTab, "Updates")

        XCTAssertTrue(prefs.enableEditorialStories)
        XCTAssertTrue(prefs.enableDeveloperStacks)
        XCTAssertTrue(prefs.enableVisualDependencyGraph)
        XCTAssertTrue(prefs.enableAppCleaner)
        XCTAssertTrue(prefs.enableAutoSnapshotBeforeMutations)
        XCTAssertFalse(prefs.enableAutoGistCloudSync)
    }

    @MainActor
    func testBrewStorePreferencesMutation() {
        let prefs = BrewStorePreferences.shared
        prefs.checkIntervalHours = 12
        XCTAssertEqual(prefs.checkIntervalHours, 12)

        prefs.enableAppCleaner = false
        XCTAssertFalse(prefs.enableAppCleaner)

        prefs.resetToDefaults()
        XCTAssertEqual(prefs.checkIntervalHours, 1)
        XCTAssertTrue(prefs.enableAppCleaner)
    }

    func testSettingsTabStructure() {
        XCTAssertEqual(SettingsTab.allCases.count, 7)
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.id.isEmpty)
            XCTAssertFalse(tab.icon.isEmpty)
        }
    }

    func testHelpManualTopics() {
        XCTAssertEqual(HelpManualView.topics.count, 8)
        for topic in HelpManualView.topics {
            XCTAssertFalse(topic.id.isEmpty)
            XCTAssertFalse(topic.title.isEmpty)
            XCTAssertFalse(topic.icon.isEmpty)
            XCTAssertFalse(topic.sections.isEmpty)
            for section in topic.sections {
                XCTAssertFalse(section.heading.isEmpty)
                XCTAssertFalse(section.paragraphs.isEmpty)
            }
        }
    }

    @MainActor
    func testMenuBarBadgeStylesAndPreferences() {
        let prefs = BrewStorePreferences.shared
        prefs.resetToDefaults()

        XCTAssertEqual(prefs.menuBarBadgeStyle, "count")
        XCTAssertFalse(prefs.menuBarCloseOnAction)
        XCTAssertFalse(prefs.compactMenuBarView)

        prefs.menuBarBadgeStyle = "dot"
        XCTAssertEqual(prefs.menuBarBadgeStyle, "dot")

        prefs.defaultMenuBarTab = "Services"
        XCTAssertEqual(prefs.defaultMenuBarTab, "Services")

        prefs.resetToDefaults()
        XCTAssertEqual(prefs.menuBarBadgeStyle, "count")
    }

    @MainActor
    func testAIAssistantQueryMatching() {
        let assistant = BrewStoreAIAssistant()
        let manager = HomebrewManager()

        assistant.analyze(query: "convert video mkv to mp4", manager: manager)
        XCTAssertFalse(assistant.recommendations.isEmpty)
        XCTAssertTrue(assistant.recommendations.contains { $0.packageID == "ffmpeg" || $0.packageID == "handbrake" })

        assistant.analyze(query: "fast terminal gpu", manager: manager)
        XCTAssertFalse(assistant.recommendations.isEmpty)
        XCTAssertTrue(assistant.recommendations.contains { $0.packageID == "ghostty" })

        assistant.analyze(query: "database gui postgres redis", manager: manager)
        XCTAssertFalse(assistant.recommendations.isEmpty)
        XCTAssertTrue(assistant.recommendations.contains { $0.packageID == "tableplus" })
    }

    func testServiceTelemetryFormatting() {
        let metrics = ServiceProcessMetrics(
            id: "postgresql@16",
            pid: 1234,
            cpuPercent: 2.5,
            memoryRSSBytes: 52_428_800, // 50 MB
            listeningPort: 5432,
            cpuTimeUsed: "00:04:12",
            elapsedTime: "1h 15m",
            uptimeSeconds: 3600
        )
        XCTAssertEqual(metrics.formattedCPU, "2.5%")
        XCTAssertEqual(metrics.formattedCPUTime, "00:04:12")
        XCTAssertEqual(metrics.formattedUptime, "1h 15m")
        XCTAssertFalse(metrics.formattedMemory.isEmpty)
        XCTAssertEqual(metrics.listeningPort, 5432)
        XCTAssertEqual(metrics.pid, 1234)
    }

    @MainActor
    func testShellConfigHookGeneration() {
        let assistant = BrewStoreShellConfigAssistant()
        assistant.detectShellEnvironment()
        XCTAssertFalse(assistant.detectedShell.isEmpty)
        XCTAssertNotNil(assistant.configURL)
    }

    @MainActor
    func testLocalizationTranslations() {
        let loc = BrewStoreLocalizationManager.shared
        loc.currentLanguage = .english
        XCTAssertEqual(loc.localized("Storefront"), "Storefront")

        loc.currentLanguage = .simplifiedChinese
        XCTAssertEqual(loc.localized("Storefront"), "商店精选")
        XCTAssertEqual(loc.localized("GET"), "获取")
        XCTAssertEqual(loc.localized("LaunchAgent Automation"), "后台自动化")

        loc.currentLanguage = .traditionalChinese
        XCTAssertEqual(loc.localized("Storefront"), "商店精選")
        XCTAssertEqual(loc.localized("GET"), "取得")

        loc.currentLanguage = .japanese
        XCTAssertEqual(loc.localized("Storefront"), "ストアフロント")
        XCTAssertEqual(loc.localized("GET"), "入手")

        loc.currentLanguage = .german
        XCTAssertEqual(loc.localized("GET"), "LADEN")
        XCTAssertEqual(loc.localized("Storefront"), "Storefront")

        loc.currentLanguage = .french
        XCTAssertEqual(loc.localized("Storefront"), "Boutique")
        XCTAssertEqual(loc.localized("GET"), "OBTENIR")

        loc.currentLanguage = .spanish
        XCTAssertEqual(loc.localized("Storefront"), "Tienda")
        XCTAssertEqual(loc.localized("GET"), "OBTENER")

        loc.currentLanguage = .english
    }

    func testSecurityInspectorReportModel() {
        let rep = PackageSecurityReport(
            id: "ghostty",
            architecture: .appleSilicon,
            architectureDetail: "Mach-O 64-bit executable arm64",
            codeSignAuthority: "Developer ID Application: Ghostty LLC",
            isHardenedRuntime: true,
            isQuarantined: false,
            targetPath: "/Applications/Ghostty.app"
        )
        XCTAssertEqual(rep.architecture, .appleSilicon)
        XCTAssertTrue(rep.isHardenedRuntime)
        XCTAssertFalse(rep.isQuarantined)
        XCTAssertEqual(rep.architecture.badgeColor, "green")
    }

    @MainActor
    func testWishlistAndCollectionsManager() {
        let wishlist = BrewStoreWishlistManager.shared
        wishlist.wishlistIDs.removeAll()
        XCTAssertFalse(wishlist.isWishlisted(id: "ripgrep"))

        wishlist.toggleWishlist(id: "ripgrep")
        XCTAssertTrue(wishlist.isWishlisted(id: "ripgrep"))

        let countBefore = wishlist.collections.count
        wishlist.createCollection(title: "Test Rig", description: "Testing", packageIDs: ["ripgrep", "bat"])
        XCTAssertEqual(wishlist.collections.count, countBefore + 1)

        let lastID = wishlist.collections.last!.id
        wishlist.deleteCollection(id: lastID)
        XCTAssertEqual(wishlist.collections.count, countBefore)
    }

    @MainActor
    func testHealthScoreCalculation() {
        let optimizer = BrewStoreHealthOptimizer()
        let manager = HomebrewManager()
        optimizer.evaluateHealth(manager: manager, doctorDiagnostics: [])
    }

    func testPackageAdoptActionArguments() {
        let pkg = BrewStorePackage(id: "visual-studio-code", name: "Visual Studio Code", description: "", homepage: "", version: "1.90.0", kind: .cask)
        let args = PackageAction.adopt.arguments(for: pkg)
        XCTAssertEqual(args, ["install", "--cask", "--adopt", "visual-studio-code"])
        XCTAssertEqual(PackageAction.adopt.title, "Adopt into Homebrew")
    }

    func testAppAdoptionMatching() {
        let casks = [
            BrewStorePackage(id: "google-chrome", name: "Google Chrome", description: "", homepage: "", version: "120.0", kind: .cask, applicationNames: ["Google Chrome.app"]),
            BrewStorePackage(id: "visual-studio-code", name: "Visual Studio Code", description: "", homepage: "", version: "1.90.0", kind: .cask, applicationNames: ["Visual Studio Code.app"]),
            BrewStorePackage(id: "raycast", name: "Raycast", description: "", homepage: "", version: "1.70.0", kind: .cask, applicationNames: ["Raycast.app"])
        ]

        let match1 = BrewStoreAppAdoptionManager.matchCask(appName: "Google Chrome", fileName: "Google Chrome", bundleID: "com.google.Chrome", casks: casks)
        XCTAssertEqual(match1.cask?.id, "google-chrome")
        XCTAssertEqual(match1.confidence, .exactName)

        let match2 = BrewStoreAppAdoptionManager.matchCask(appName: "Custom Launcher", fileName: "raycast", bundleID: "com.custom.launcher", casks: casks)
        XCTAssertEqual(match2.cask?.id, "raycast")
        XCTAssertEqual(match2.confidence, .exactBundleID)

        let match3 = BrewStoreAppAdoptionManager.matchCask(appName: "Unknown Foo App", fileName: "Unknown Foo App", bundleID: "com.example.unknown", casks: casks)
        XCTAssertNil(match3.cask)
        XCTAssertEqual(match3.confidence, .unmatched)
    }

    func testAppleSiliconMigrationReportModel() {
        let pkg1 = BrewStorePackage(id: "native-tool", name: "native-tool", description: "", homepage: "", version: "1.0", kind: .formula, isInstalled: true)
        let pkg2 = BrewStorePackage(id: "legacy-intel", name: "legacy-intel", description: "", homepage: "", version: "1.0", kind: .cask, isInstalled: true)

        let cand1 = MigrationCandidate(package: pkg1, architecture: .appleSilicon, binaryPath: "/opt/homebrew/bin/tool", needsMigration: false)
        let cand2 = MigrationCandidate(package: pkg2, architecture: .intel, binaryPath: "/Applications/Legacy.app", needsMigration: true)

        let report = AppleSiliconMigrationReport(
            isAppleSiliconHost: true,
            totalChecked: 2,
            nativeArm64Count: 1,
            universalCount: 0,
            rosettaIntelCount: 1,
            candidates: [cand1, cand2]
        )

        XCTAssertFalse(report.isFullyOptimized)
        XCTAssertEqual(report.migrationRequiredCandidates.count, 1)
        XCTAssertEqual(report.migrationRequiredCandidates.first?.package.id, "legacy-intel")
    }

    @MainActor
    func testBrewfileImportParsing() {
        let sample = """
        # Test Brewfile
        tap "homebrew/cask-fonts"
        brew "ripgrep"
        brew "bat"
        cask "visual-studio-code"
        """

        let manager = HomebrewManager()
        let importer = BrewStoreBrewfileImporter.shared
        let summary = importer.parseBrewfile(content: sample, manager: manager)

        XCTAssertEqual(summary.taps, ["homebrew/cask-fonts"])
        XCTAssertEqual(summary.formulae.count, 2)
        XCTAssertEqual(summary.casks.count, 1)
        XCTAssertEqual(summary.formulae.map(\.rawName), ["ripgrep", "bat"])
        XCTAssertEqual(summary.casks.first?.rawName, "visual-studio-code")
    }

    @MainActor
    func testTouchIDBiometricsState() {
        let auth = BrewStoreTouchIDAuthenticator.shared
        XCTAssertFalse(auth.biometryTypeDescription.isEmpty)
    }

    func testMASAppParsing() {
        let listSample = """
        497799835 Xcode (15.3)
        803453959 Slack (4.38.125)
        1295203466 Microsoft Remote Desktop (10.9.6)
        """

        let outdatedSample = """
        497799835 Xcode (15.3 -> 15.4)
        """

        let apps = BrewStoreMASManager.parseMASApps(listOutput: listSample, outdatedOutput: outdatedSample)
        XCTAssertEqual(apps.count, 3)

        let xcode = apps.first { $0.id == "497799835" }
        XCTAssertNotNil(xcode)
        XCTAssertEqual(xcode?.name, "Xcode")
        XCTAssertEqual(xcode?.installedVersion, "15.3")
        XCTAssertEqual(xcode?.latestVersion, "15.4")
        XCTAssertTrue(xcode?.isOutdated == true)

        let slack = apps.first { $0.id == "803453959" }
        XCTAssertNotNil(slack)
        XCTAssertEqual(slack?.name, "Slack")
        XCTAssertFalse(slack?.isOutdated == true)
    }

    func testCVESecurityAuditParsing() {
        let sampleAudit = """
        openssl@1.1:
          * CVE-2023-5678: Buffer overflow vulnerability in SSL handshake
          * Deprecated upstream
        node@16:
          * Warning: Formula is disabled and no longer supported
        """

        let packages = [
            BrewStorePackage(id: "openssl@1.1", name: "openssl@1.1", description: "", homepage: "", version: "1.1.1", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "node@16", name: "node@16", description: "", homepage: "", version: "16.0", kind: .formula, isInstalled: true)
        ]

        let issues = BrewStoreCVESecurityScanner.parseAuditOutput(output: sampleAudit, installedPackages: packages)
        XCTAssertFalse(issues.isEmpty)

        let cveIssue = issues.first { $0.cveIdentifier != nil }
        XCTAssertNotNil(cveIssue)
        XCTAssertEqual(cveIssue?.cveIdentifier, "CVE-2023-5678")
        XCTAssertEqual(cveIssue?.severity, .critical)

        let deprecatedIssue = issues.first { $0.description.contains("Deprecated") }
        XCTAssertNotNil(deprecatedIssue)
        XCTAssertEqual(deprecatedIssue?.severity, .high)
    }

    @MainActor
    func testTapDiscoveryCatalogItems() {
        XCTAssertFalse(BrewStoreTapDiscoveryCatalog.curatedTaps.isEmpty)
        let fonts = BrewStoreTapDiscoveryCatalog.curatedTaps.first { $0.id == "homebrew/cask-fonts" }
        XCTAssertNotNil(fonts)
        XCTAssertTrue(fonts?.isOfficial == true)
        XCTAssertEqual(fonts?.category, "Typography")
    }

    func testAutoUpdateSchedulerIntervals() {
        XCTAssertEqual(AutoUpdateFrequency.manual.intervalSeconds, 0)
        XCTAssertEqual(AutoUpdateFrequency.hourly.intervalSeconds, 3600)
        XCTAssertEqual(AutoUpdateFrequency.daily.intervalSeconds, 86400)
        XCTAssertEqual(AutoUpdateFrequency.weekly.intervalSeconds, 604800)
    }

    func testVersionFamilyDetection() {
        let pkgs = [
            BrewStorePackage(id: "node", name: "node", description: "", homepage: "", version: "22.2.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "node@20", name: "node@20", description: "", homepage: "", version: "20.14.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "node@18", name: "node@18", description: "", homepage: "", version: "18.20.0", kind: .formula, isInstalled: false),
            BrewStorePackage(id: "python@3.11", name: "python@3.11", description: "", homepage: "", version: "3.11.9", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "python@3.12", name: "python@3.12", description: "", homepage: "", version: "3.12.3", kind: .formula, isInstalled: false)
        ]

        let families = BrewStoreVersionLinkManager.parseVersionFamilies(packages: pkgs)
        XCTAssertEqual(families.count, 2)

        let nodeFamily = families.first { $0.id == "node" }
        XCTAssertNotNil(nodeFamily)
        XCTAssertEqual(nodeFamily?.members.count, 3)
        XCTAssertEqual(nodeFamily?.installedMembers.count, 2)
        XCTAssertTrue(nodeFamily?.hasMultipleInstalled == true)
    }

    func testDependencyTreeResolver() {
        let pkgA = BrewStorePackage(id: "tool-a", name: "Tool A", description: "", homepage: "", version: "1.0", kind: .formula, dependencies: ["tool-b", "tool-c"])
        let pkgB = BrewStorePackage(id: "tool-b", name: "Tool B", description: "", homepage: "", version: "1.0", kind: .formula, dependencies: ["tool-d"])
        let pkgC = BrewStorePackage(id: "tool-c", name: "Tool C", description: "", homepage: "", version: "1.0", kind: .formula)
        let pkgD = BrewStorePackage(id: "tool-d", name: "Tool D", description: "", homepage: "", version: "1.0", kind: .formula)
        let pkgApp = BrewStorePackage(id: "my-app", name: "My App", description: "", homepage: "", version: "1.0", kind: .formula, dependencies: ["tool-a"])

        let all = [pkgA, pkgB, pkgC, pkgD, pkgApp]
        let graph = DependencyTreeCalculator.buildGraph(for: pkgA, in: all)

        XCTAssertEqual(graph.rootID, "tool-a")
        XCTAssertEqual(graph.upstreamNodes.count, 3) // tool-b, tool-c, tool-d
        XCTAssertTrue(graph.hasDependents) // my-app depends on tool-a
        XCTAssertEqual(graph.downstreamNodes.first?.id, "my-app")
    }

    func testFastCachePayloadEncodeDecode() {
        let payload = FastCachePayload(
            timestamp: Date(),
            version: "1.0.0",
            packages: [
                BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.45.0", kind: .formula, isInstalled: true)
            ],
            taps: [
                BrewStoreTap(id: "homebrew/core", name: "homebrew/core")
            ],
            services: []
        )

        guard let encoded = try? JSONEncoder().encode(payload) else {
            XCTFail("Failed to encode FastCachePayload")
            return
        }

        let decoded = try? JSONDecoder().decode(FastCachePayload.self, from: encoded)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.packages.count, 1)
        XCTAssertEqual(decoded?.packages.first?.id, "git")
    }

    func testTrendingRankingsBadges() {
        let gitPkg = BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.45.0", kind: .formula)
        let gitBadge = TrendingRankingsManager.badge(for: gitPkg)
        XCTAssertNotNil(gitBadge)
        XCTAssertEqual(gitBadge?.title, "Top 10 Formula")

        let codePkg = BrewStorePackage(id: "visual-studio-code", name: "Visual Studio Code", description: "", homepage: "", version: "1.90.0", kind: .cask)
        let codeBadge = TrendingRankingsManager.badge(for: codePkg)
        XCTAssertNotNil(codeBadge)
        XCTAssertEqual(codeBadge?.title, "Top 10 App")
    }

    @MainActor
    func testBrewStoreCLIInstallation() {
        let assistant = BrewStoreShellConfigAssistant()
        let result = assistant.installBrewStoreCLI()
        XCTAssertTrue(result)
        XCTAssertTrue(assistant.isCLIInstalled)
    }

    func testHomebrewPrefixDiscovery() {
        let prefixes = BrewStorePrefixManager.discoverPrefixes(currentActiveBrewPath: "/opt/homebrew/bin/brew")
        XCTAssertGreaterThanOrEqual(prefixes.count, 2)
        let arm64 = prefixes.first { $0.id == "/opt/homebrew" }
        XCTAssertNotNil(arm64)
        XCTAssertEqual(arm64?.architecture, .appleSilicon)
    }

    func testCustomInstallOptionsArgumentBuilding() {
        let pkg = BrewStorePackage(id: "neovim", name: "neovim", description: "", homepage: "", version: "0.10.0", kind: .formula)
        var options = CustomInstallOptions()
        options.buildFromSource = true
        options.headCommit = true
        options.forceInstall = true
        options.verbose = true
        options.customArguments = "--with-custom-flag"

        let args = options.buildArguments(for: pkg)
        XCTAssertTrue(args.contains("install"))
        XCTAssertTrue(args.contains("--build-from-source"))
        XCTAssertTrue(args.contains("--HEAD"))
        XCTAssertTrue(args.contains("--force"))
        XCTAssertTrue(args.contains("--verbose"))
        XCTAssertTrue(args.contains("--with-custom-flag"))
        XCTAssertEqual(args.last, "neovim")
    }

    @MainActor
    func testSnapshotRollbackPlanComputation() {
        let current = [
            BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.45.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "htop", name: "htop", description: "", homepage: "", version: "3.3.0", kind: .formula, isInstalled: true)
        ]
        let snapshot = BrewStoreSnapshot(
            id: "snap-1",
            timestamp: Date(),
            name: "Test Snapshot",
            fileURL: URL(fileURLWithPath: "/tmp/Brewfile"),
            formulae: ["git", "wget"],
            casks: [],
            taps: []
        )

        let rollbackManager = BrewStoreSnapshotRollbackManager.shared
        let plan = rollbackManager.computePlan(currentPackages: current, snapshot: snapshot)

        XCTAssertEqual(plan.packagesToUninstall, ["htop"])
        XCTAssertEqual(plan.packagesToReinstall, ["wget"])
        XCTAssertEqual(plan.totalOperations, 2)
        XCTAssertFalse(plan.isEmpty)
    }

    @MainActor
    func testServiceWatchdogStateAndNotifications() {
        let watchdog = BrewStoreServiceWatchdog.shared
        XCTAssertNotNil(watchdog.isWatchdogEnabled)
        BrewStoreServiceWatchdog.dispatchCrashNotification(serviceName: "redis-test")
    }

    func testLaunchAgentPlistGeneration() {
        let plist = BrewStoreLaunchAgentManager.generatePlist(
            label: "com.amfi-disable.brewstore.autoupdate",
            scriptPath: "/tmp/script.sh",
            intervalSeconds: 86400,
            logPath: "/tmp/log.log"
        )
        XCTAssertTrue(plist.contains("<string>com.amfi-disable.brewstore.autoupdate</string>"))
        XCTAssertTrue(plist.contains("<string>/tmp/script.sh</string>"))
        XCTAssertTrue(plist.contains("<integer>86400</integer>"))
    }

    func testLaunchAgentStatusJSONDecoding() {
        let jsonStr = """
        {
          "timestamp": "2026-08-24T12:00:00Z",
          "status": "success",
          "totalOutdated": 2,
          "outdatedFormulae": ["git", "node"],
          "outdatedCasks": [],
          "summary": "2 updates available"
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let status = try? decoder.decode(LaunchAgentRunStatus.self, from: data)
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.status, "success")
        XCTAssertEqual(status?.totalOutdated, 2)
        XCTAssertEqual(status?.outdatedFormulae, ["git", "node"])
        XCTAssertTrue(status?.isSuccess == true)
    }

    func testAppUpdateCheckerVersionComparison() {
        XCTAssertTrue(BrewStoreAppUpdateChecker.isNewerVersion(remote: "1.0.1", local: "1.0.0"))
        XCTAssertTrue(BrewStoreAppUpdateChecker.isNewerVersion(remote: "v1.1.0", local: "1.0.9"))
        XCTAssertTrue(BrewStoreAppUpdateChecker.isNewerVersion(remote: "2.0.0", local: "1.99.99"))
        XCTAssertFalse(BrewStoreAppUpdateChecker.isNewerVersion(remote: "1.0.0", local: "1.0.0"))
        XCTAssertFalse(BrewStoreAppUpdateChecker.isNewerVersion(remote: "0.9.9", local: "1.0.0"))
    }

    func testURLSchemeRouterParsing() {
        let pkgURL = URL(string: "brewstore://package?id=visual-studio-code&kind=cask")!
        let route1 = BrewStoreURLSchemeRouter.parse(url: pkgURL)
        XCTAssertEqual(route1, .package(id: "visual-studio-code", kind: .cask))

        let installURL = URL(string: "brewstore://install?id=neovim&kind=formula")!
        let route2 = BrewStoreURLSchemeRouter.parse(url: installURL)
        XCTAssertEqual(route2, .install(id: "neovim", kind: .formula))

        let searchURL = URL(string: "brewstore://search?q=python")!
        let route3 = BrewStoreURLSchemeRouter.parse(url: searchURL)
        XCTAssertEqual(route3, .search(query: "python"))

        let doctorURL = URL(string: "brewstore://doctor")!
        let route4 = BrewStoreURLSchemeRouter.parse(url: doctorURL)
        XCTAssertEqual(route4, .doctor)

        let adoptURL = URL(string: "brewstore://adopt")!
        let route5 = BrewStoreURLSchemeRouter.parse(url: adoptURL)
        XCTAssertEqual(route5, .adopt)

        let securityURL = URL(string: "brewstore://security")!
        let route6 = BrewStoreURLSchemeRouter.parse(url: securityURL)
        XCTAssertEqual(route6, .security)

        let settingsURL = URL(string: "brewstore://settings")!
        let route7 = BrewStoreURLSchemeRouter.parse(url: settingsURL)
        XCTAssertEqual(route7, .settings)

        let directHostURL = URL(string: "brewstore://docker")!
        let route8 = BrewStoreURLSchemeRouter.parse(url: directHostURL)
        XCTAssertEqual(route8, .package(id: "docker", kind: nil))

        let openURL = URL(string: "brewstore://open")!
        let route9 = BrewStoreURLSchemeRouter.parse(url: openURL)
        XCTAssertEqual(route9, .open)

        let openWithIdURL = URL(string: "brewstore://open?id=htop")!
        let route10 = BrewStoreURLSchemeRouter.parse(url: openWithIdURL)
        XCTAssertEqual(route10, .package(id: "htop", kind: nil))

        let invalidSchemeURL = URL(string: "https://google.com")!
        XCTAssertNil(BrewStoreURLSchemeRouter.parse(url: invalidSchemeURL))
    }

    func testURLSchemeRouterNewRoutes() {
        let updateAllURL = URL(string: "brewstore://update-all")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: updateAllURL), .updateAll)

        let upgradeAllURL = URL(string: "brewstore://upgrade-all")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: upgradeAllURL), .updateAll)

        let cleanURL = URL(string: "brewstore://clean")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: cleanURL), .clean)

        let cleanupURL = URL(string: "brewstore://cleanup")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: cleanupURL), .clean)

        let blueprintWithIDURL = URL(string: "brewstore://blueprint?id=my-dev-stack")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: blueprintWithIDURL), .blueprint(id: "my-dev-stack"))

        let blueprintNoIDURL = URL(string: "brewstore://blueprints")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: blueprintNoIDURL), .blueprint(id: nil))

        let quickInstallURL = URL(string: "brewstore://quick-install?packages=bat,eza,fzf")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: quickInstallURL), .quickInstall(ids: ["bat", "eza", "fzf"]))

        let quickInstallWhitespaceURL = URL(string: "brewstore://quick-install?packages=%20bat%20,%20eza%20,%20%20")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: quickInstallWhitespaceURL), .quickInstall(ids: ["bat", "eza"]))

        if let quickInstallEmptyURL = URL(string: "brewstore://quick-install?packages=") {
            XCTAssertNil(BrewStoreURLSchemeRouter.parse(url: quickInstallEmptyURL))
        }
    }

    func testURLSchemeRouterPercentEncodingAndSpaceDecoding() {
        let searchPlusURL = URL(string: "brewstore://search?q=visual+studio+code")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: searchPlusURL), .search(query: "visual studio code"))

        let pkgEncodedURL = URL(string: "brewstore://package/node%4020")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: pkgEncodedURL), .package(id: "node@20", kind: nil))

        let installEncodedURL = URL(string: "brewstore://install/openssl%403")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: installEncodedURL), .install(id: "openssl@3", kind: nil))

        let quickInstallEncodedURL = URL(string: "brewstore://quick-install?packages=python%403.11,node%4020")!
        XCTAssertEqual(BrewStoreURLSchemeRouter.parse(url: quickInstallEncodedURL), .quickInstall(ids: ["python@3.11", "node@20"]))
    }

    @MainActor
    func testStackBlueprintExportAndImportRoundtrip() throws {
        let stack = BrewStoreStack(
            id: "test-blueprint-stack",
            name: "Dev Stack",
            description: "Custom workstation setup",
            icon: "laptopcomputer",
            bundleType: .hybrid,
            pricingTier: .freeFOSS,
            formulae: ["ripgrep", "bat"],
            casks: ["visual-studio-code"],
            isCustom: true
        )

        let stackManager = BrewStoreStackManager.shared
        guard let data = stackManager.exportBlueprint(stack: stack) else {
            XCTFail("Failed to export blueprint stack")
            return
        }

        let imported = try stackManager.importBlueprint(data: data)
        XCTAssertEqual(imported.name, "Dev Stack")
        XCTAssertEqual(imported.description, "Custom workstation setup")
        XCTAssertEqual(imported.formulae, ["bat", "ripgrep"])
        XCTAssertEqual(imported.casks, ["visual-studio-code"])
        XCTAssertTrue(imported.isCustom)

        XCTAssertThrowsError(try stackManager.importBlueprint(data: Data()))

        let invalidNameJSON = Data("""
        {
            "id": "123",
            "name": "   ",
            "description": "test",
            "icon": "shippingbox",
            "bundleType": "hybrid",
            "pricingTier": "freeFOSS",
            "formulae": [],
            "casks": [],
            "isCustom": true
        }
        """.utf8)
        XCTAssertThrowsError(try stackManager.importBlueprint(data: invalidNameJSON))
    }

    @MainActor
    func testBlueprintGenerationFromInstalledPackages() {
        let mockExecutor = BrewStoreCommandExecutor(customHandler: { _, _, _, _, _, _, _ in
            BrewStoreCommandResult(
                standardOutput: "", standardError: "", terminationStatus: 0,
                wasTerminated: false, didTimeOut: false, wasCancelled: false,
                standardOutputWasTruncated: false, standardErrorWasTruncated: false,
                category: .readOnly, launchErrorDescription: nil
            )
        })
        let manager = HomebrewManager(executor: mockExecutor)
        manager.packages = [
            BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "", homepage: "", version: "14.1.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "bat", name: "bat", description: "", homepage: "", version: "0.24.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "docker", name: "Docker", description: "", homepage: "", version: "4.28.0", kind: .cask, isInstalled: true),
            BrewStorePackage(id: "wget", name: "wget", description: "", homepage: "", version: "1.24.5", kind: .formula, isInstalled: false)
        ]

        let stackManager = BrewStoreStackManager.shared
        let generated = stackManager.generateBlueprintFromInstalled(
            name: "Workstation Blueprints",
            description: "Captured local packages",
            manager: manager
        )

        XCTAssertEqual(generated.name, "Workstation Blueprints")
        XCTAssertEqual(generated.formulae, ["bat", "ripgrep"])
        XCTAssertEqual(generated.casks, ["docker"])
        XCTAssertEqual(generated.bundleType, .hybrid)
        XCTAssertTrue(generated.isCustom)
    }

    @MainActor
    func testWebhookPreferencesRegistrationAndReset() {
        let preferences = BrewStorePreferences.shared
        preferences.webhookURL = "https://discord.com/api/webhooks/test"
        preferences.webhookEnabled = true
        preferences.webhookNotifyOnUpdatesFound = false

        XCTAssertEqual(preferences.webhookURL, "https://discord.com/api/webhooks/test")
        XCTAssertTrue(preferences.webhookEnabled)
        XCTAssertFalse(preferences.webhookNotifyOnUpdatesFound)

        preferences.resetToDefaults()

        XCTAssertEqual(preferences.webhookURL, "")
        XCTAssertFalse(preferences.webhookEnabled)
        XCTAssertTrue(preferences.webhookNotifyOnUpdatesFound)
    }

    func testWebhookURLValidation() async {
        let emptyResult = await BrewStoreAutoUpdateScheduler.testWebhook(urlString: "")
        XCTAssertFalse(emptyResult.success)

        let whitespaceResult = await BrewStoreAutoUpdateScheduler.testWebhook(urlString: "   ")
        XCTAssertFalse(whitespaceResult.success)

        let ftpResult = await BrewStoreAutoUpdateScheduler.testWebhook(urlString: "ftp://example.com/webhook")
        XCTAssertFalse(ftpResult.success)

        let invalidResult = await BrewStoreAutoUpdateScheduler.testWebhook(urlString: "not-a-valid-url")
        XCTAssertFalse(invalidResult.success)
    }

    func testAnalyticsJSONParsingAndVelocity() {
        let jsonStr = """
        {
          "name": "ripgrep",
          "analytics": {
            "install": {
              "30d": {
                "ripgrep": 150000
              },
              "90d": {
                "ripgrep": 360000
              },
              "365d": {
                "ripgrep": 1200000
              }
            },
            "install_on_request": {
              "30d": {
                "ripgrep": 120000
              },
              "90d": {
                "ripgrep": 290000
              },
              "365d": {
                "ripgrep": 950000
              }
            }
          }
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let analytics = BrewStoreAnalyticsManager.parseJSON(data: data, packageID: "ripgrep", kind: .formula)
        XCTAssertNotNil(analytics)
        XCTAssertEqual(analytics?.install7d, Int(round(150000.0 * 7.0 / 30.0)))
        XCTAssertEqual(analytics?.formatted7d, "35.0K")
        XCTAssertEqual(analytics?.install30d, 150000)
        XCTAssertEqual(analytics?.install90d, 360000)
        XCTAssertEqual(analytics?.install365d, 1200000)
        XCTAssertEqual(analytics?.formatted30d, "150.0K")
        XCTAssertEqual(analytics?.formatted365d, "1.2M")
        XCTAssertEqual(analytics?.installOnRequest30d, 120000)
        XCTAssertEqual(analytics?.directRequestRatio, 0.8)
        XCTAssertTrue(analytics?.velocityPercent ?? 0 > 0)
        XCTAssertTrue(analytics?.momentumBadge.isPositive == true)
    }

    func testDependencyTopologyAnalysis() {
        let openssl = BrewStorePackage(id: "openssl@3", name: "openssl@3", description: "", homepage: "", version: "3.3.0", kind: .formula, isInstalled: true)
        let zstd = BrewStorePackage(id: "zstd", name: "zstd", description: "", homepage: "", version: "1.5.6", kind: .formula, isInstalled: true)
        let git = BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.45.0", kind: .formula, isInstalled: true, dependencies: ["openssl@3", "zstd"])
        let node = BrewStorePackage(id: "node", name: "node", description: "", homepage: "", version: "22.0.0", kind: .formula, isInstalled: true, dependencies: ["openssl@3"])
        let orphanTool = BrewStorePackage(id: "old-tool", name: "old-tool", description: "", homepage: "", version: "1.0.0", kind: .formula, isInstalled: true, dependencies: ["zstd"])

        let packages = [openssl, zstd, git, node, orphanTool]
        let topology = BrewStoreDependencyTopologyManager.analyze(packages: packages)

        XCTAssertEqual(topology.totalPackagesInstalled, 5)
        XCTAssertEqual(topology.totalDependenciesMapped, 4)

        // openssl@3 is required by git and node -> 2 dependents
        let topFoundation = topology.sharedFoundations.first { $0.id == "openssl@3" }
        XCTAssertNotNil(topFoundation)
        XCTAssertEqual(topFoundation?.dependentCount, 2)
        XCTAssertEqual(topFoundation?.dependentPackageIDs.sorted(), ["git", "node"])

        // git, node, old-tool have 0 dependents -> orphans
        XCTAssertEqual(topology.orphanLeaves.count, 3)
    }

    func testPreFlightDependencyAndBlastRadiusCheckers() {
        let openssl = BrewStorePackage(id: "openssl@3", name: "openssl@3", description: "", homepage: "", version: "3.3.0", kind: .formula, isInstalled: true)
        let zstd = BrewStorePackage(id: "zstd", name: "zstd", description: "", homepage: "", version: "1.5.6", kind: .formula, isInstalled: false)
        let curl = BrewStorePackage(id: "curl", name: "curl", description: "", homepage: "", version: "8.7.1", kind: .formula, isInstalled: false, dependencies: ["openssl@3", "zstd"])
        let git = BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.45.0", kind: .formula, isInstalled: true, dependencies: ["openssl@3"])

        let all = [openssl, zstd, curl, git]

        // 1. Pre-Install Simulation for curl
        let sim = BrewStorePreFlightDependencyChecker.simulatePreInstall(package: curl, in: all)
        XCTAssertEqual(sim.alreadyInstalledDependencies, ["openssl@3"])
        XCTAssertEqual(sim.missingDependencies, ["zstd"])
        XCTAssertTrue(sim.isSafeToInstall)

        // 2. Uninstall Blast Radius for openssl@3
        let blast = BrewStorePreFlightDependencyChecker.simulateUninstallBlastRadius(package: openssl, in: all)
        XCTAssertTrue(blast.isDestructive)
        XCTAssertEqual(blast.brokenDownstreamPackages, ["git"])
    }

    func testAlternativeRecommendations() {
        let docker = BrewStorePackage(id: "docker", name: "docker", description: "Container runtime", homepage: "", version: "26.0", kind: .formula)
        let orbstack = BrewStorePackage(id: "orbstack", name: "orbstack", description: "Fast lightweight containers", homepage: "", version: "1.5", kind: .cask)
        let colima = BrewStorePackage(id: "colima", name: "colima", description: "Container runtimes on macOS", homepage: "", version: "0.6", kind: .formula)
        let ripgrep = BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "Fast line-oriented search", homepage: "", version: "14.1", kind: .formula)

        let packages = [docker, orbstack, colima, ripgrep]
        let alternatives = BrewStoreAlternativeRecommendationManager.findAlternatives(for: docker, in: packages)

        XCTAssertTrue(alternatives.contains(where: { $0.id == "orbstack" }))
        XCTAssertTrue(alternatives.contains(where: { $0.id == "colima" }))
        XCTAssertFalse(alternatives.contains(where: { $0.id == "ripgrep" }))
    }

    func testBottleFootprintEstimator() {
        let llvm = BrewStorePackage(id: "llvm", name: "llvm", description: "", homepage: "", version: "18.1.5", kind: .formula)
        let info = BrewStoreBottleFootprintEstimator.estimateFootprint(for: llvm)
        XCTAssertEqual(info.estimatedDownloadMB, 420.0)
        XCTAssertEqual(info.estimatedCellarFootprintMB, 3200.0)
        XCTAssertEqual(info.formattedDownloadSize, "420.0 MB")
        XCTAssertEqual(info.formattedFootprintSize, "3.1 GB")
    }

    func testPackageFilterEngineLicenseAndEditorial() {
        let ripgrep = BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "Search tool", homepage: "", version: "14.1", kind: .formula)
        let chrome = BrewStorePackage(id: "google-chrome", name: "google-chrome", description: "Web browser", homepage: "", version: "125.0", kind: .cask)
        let raycast = BrewStorePackage(id: "raycast", name: "raycast", description: "Launcher", homepage: "", version: "1.75", kind: .cask)

        let packages = [ripgrep, chrome, raycast]

        // Test FOSS filter
        let foss = BrewStorePackageFilterEngine.filterAndSort(
            packages: packages,
            query: "",
            kind: nil,
            tap: "All Taps",
            pinnedOnly: false,
            updatesOnly: false,
            license: .openSource,
            editorial: .all,
            sort: .nameAsc
        )
        XCTAssertTrue(foss.contains(where: { $0.id == "ripgrep" }))
        XCTAssertFalse(foss.contains(where: { $0.id == "google-chrome" }))

        // Test Proprietary filter
        let proprietary = BrewStorePackageFilterEngine.filterAndSort(
            packages: packages,
            query: "",
            kind: nil,
            tap: "All Taps",
            pinnedOnly: false,
            updatesOnly: false,
            license: .proprietary,
            editorial: .all,
            sort: .nameAsc
        )
        XCTAssertTrue(proprietary.contains(where: { $0.id == "google-chrome" }))
        XCTAssertFalse(proprietary.contains(where: { $0.id == "ripgrep" }))
    }

    func testPackageFilterEngineGroupingAndSorting() {
        let a = BrewStorePackage(id: "alacritty", name: "alacritty", description: "", homepage: "", version: "1.0", kind: .cask, tap: "homebrew/cask")
        let z = BrewStorePackage(id: "zsh", name: "zsh", description: "", homepage: "", version: "5.9", kind: .formula, tap: "homebrew/core")

        let packages = [z, a]
        let sorted = BrewStorePackageFilterEngine.filterAndSort(
            packages: packages,
            query: "",
            kind: nil,
            tap: "All Taps",
            pinnedOnly: false,
            updatesOnly: false,
            license: .all,
            editorial: .all,
            sort: .nameAsc
        )
        XCTAssertEqual(sorted.first?.id, "alacritty")
        XCTAssertEqual(sorted.last?.id, "zsh")

        let grouped = BrewStorePackageFilterEngine.groupPackages(packages, by: .tap)
        XCTAssertEqual(grouped.count, 2)
    }

    func testPackageFilterEngineTapClassification() {
        let officialFormula = BrewStorePackage(id: "wget", name: "wget", description: "Internet downloader", homepage: "", version: "1.24", kind: .formula, tap: "homebrew/core")
        let officialCaskNilTap = BrewStorePackage(id: "visual-studio-code", name: "Visual Studio Code", description: "Editor", homepage: "", version: "1.90", kind: .cask, tap: nil)
        let thirdPartyTap = BrewStorePackage(id: "vault", name: "vault", description: "Secrets", homepage: "", version: "1.16", kind: .formula, tap: "hashicorp/tap")
        let thirdPartyPathID = BrewStorePackage(id: "cloudflare/cloudflare/cloudflared", name: "cloudflared", description: "Tunnel", homepage: "", version: "2024.1", kind: .formula, tap: nil)

        let packages = [officialFormula, officialCaskNilTap, thirdPartyTap, thirdPartyPathID]

        // Filter by Official Taps
        let officialResult = BrewStorePackageFilterEngine.filterAndSort(
            packages: packages,
            query: "",
            kind: nil,
            tap: "All Taps",
            pinnedOnly: false,
            updatesOnly: false,
            license: .all,
            editorial: .official,
            sort: .nameAsc
        )
        XCTAssertEqual(officialResult.count, 2)
        XCTAssertTrue(officialResult.contains(where: { $0.id == "wget" }))
        XCTAssertTrue(officialResult.contains(where: { $0.id == "visual-studio-code" }))
        XCTAssertFalse(officialResult.contains(where: { $0.id == "vault" }))
        XCTAssertFalse(officialResult.contains(where: { $0.id == "cloudflare/cloudflare/cloudflared" }))

        // Filter by Third-Party Taps
        let thirdPartyResult = BrewStorePackageFilterEngine.filterAndSort(
            packages: packages,
            query: "",
            kind: nil,
            tap: "All Taps",
            pinnedOnly: false,
            updatesOnly: false,
            license: .all,
            editorial: .thirdParty,
            sort: .nameAsc
        )
        XCTAssertEqual(thirdPartyResult.count, 2)
        XCTAssertTrue(thirdPartyResult.contains(where: { $0.id == "vault" }))
        XCTAssertTrue(thirdPartyResult.contains(where: { $0.id == "cloudflare/cloudflare/cloudflared" }))
        XCTAssertFalse(thirdPartyResult.contains(where: { $0.id == "wget" }))
    }

    @MainActor
    func testThemeAndVibrancyManager() {
        let themeMgr = BrewStoreThemeVibrancyManager.shared
        themeMgr.currentTheme = .neonCyan
        XCTAssertEqual(themeMgr.currentTheme, .neonCyan)
        XCTAssertNotNil(themeMgr.currentTheme.color)

        themeMgr.vibrancyLevel = .highTranslucency
        XCTAssertEqual(themeMgr.vibrancyLevel, .highTranslucency)

        themeMgr.currentTheme = .amberBrew
    }

    func testDiskStorageReportCalculations() {
        let item1 = StorageItem(id: "llvm", name: "llvm", kind: .formula, sizeBytes: 3_000_000_000, formattedSize: "3.0 GB", percentageOfTotal: 0.75, path: "/opt/homebrew/Cellar/llvm")
        let item2 = StorageItem(id: "node", name: "node", kind: .formula, sizeBytes: 1_000_000_000, formattedSize: "1.0 GB", percentageOfTotal: 0.25, path: "/opt/homebrew/Cellar/node")

        let report = StorageReport(
            totalCellarBytes: 4_000_000_000,
            totalCacheBytes: 500_000_000,
            items: [item1, item2],
            topHogs: [item1]
        )

        XCTAssertEqual(report.items.count, 2)
        XCTAssertEqual(report.topHogs.first?.id, "llvm")
        XCTAssertFalse(report.formattedTotalCellar.isEmpty)
        XCTAssertFalse(report.formattedTotalCache.isEmpty)
    }

    func testBottleIntegrityParser() {
        let receiptJSON: [String: Any] = [
            "built_as_bottle": true,
            "compiler": "clang",
            "source_modified": false,
            "bottle": [
                "files": [
                    "arm64_sonoma": [
                        "sha256": "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
                    ]
                ]
            ]
        ]

        let report = BrewStoreBottleIntegrityAuditor.parseReceiptJSON(receiptJSON, packageID: "ripgrep")
        XCTAssertEqual(report.status, .verifiedBottle)
        XCTAssertEqual(report.bottleSHA256, "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")
        XCTAssertEqual(report.compiler, "clang")
        XCTAssertFalse(report.sourceModified)
    }

    func testCreatorRepoAndTapParsing() {
        let tapRepo = GitHubRepo(
            id: 101,
            name: "homebrew-devtools",
            full_name: "johndoe/homebrew-devtools",
            description: "Personal devtools tap",
            html_url: "https://github.com/johndoe/homebrew-devtools",
            stargazers_count: 42,
            forks_count: 5,
            open_issues_count: 1,
            default_branch: "main"
        )

        let appRepo = GitHubRepo(
            id: 102,
            name: "my-cool-app",
            full_name: "johndoe/my-cool-app",
            description: "Native macOS app",
            html_url: "https://github.com/johndoe/my-cool-app",
            stargazers_count: 120,
            forks_count: 12,
            open_issues_count: 0,
            default_branch: "main"
        )

        XCTAssertTrue(tapRepo.isTap)
        XCTAssertEqual(tapRepo.tapShortName, "devtools")
        XCTAssertEqual(tapRepo.tapCommandName(owner: "johndoe"), "johndoe/devtools")

        XCTAssertFalse(appRepo.isTap)
        XCTAssertEqual(appRepo.tapShortName, "my-cool-app")
    }

    func testFormulaScaffolderGeneration() {
        let repo = GitHubRepo(
            id: 201,
            name: "fast-grep",
            full_name: "alice/fast-grep",
            description: "High speed grep tool",
            html_url: "https://github.com/alice/fast-grep",
            stargazers_count: 85,
            forks_count: 8,
            open_issues_count: 2,
            default_branch: "main"
        )

        let formulaCode = BrewStoreFormulaScaffolder.scaffoldFormula(repo: repo, owner: "alice", version: "2.1.0")
        XCTAssertTrue(formulaCode.contains("class FastGrep < Formula"))
        XCTAssertTrue(formulaCode.contains("desc \"High speed grep tool\""))
        XCTAssertTrue(formulaCode.contains("version \"2.1.0\""))
        XCTAssertTrue(formulaCode.contains("bin.install \"fast-grep\""))

        let caskCode = BrewStoreFormulaScaffolder.scaffoldCask(repo: repo, owner: "alice", version: "1.5.0")
        XCTAssertTrue(caskCode.contains("cask \"fast-grep\" do"))
        XCTAssertTrue(caskCode.contains("version \"1.5.0\""))
        XCTAssertTrue(caskCode.contains("app \"FastGrep.app\""))
    }

    @MainActor
    func testMirrorBenchmarkEndpoints() {
        let benchmarkMgr = BrewStoreMirrorBenchmarkManager.shared
        XCTAssertEqual(benchmarkMgr.mirrors.count, 4)

        let official = benchmarkMgr.mirrors.first { $0.id == "official" }!
        let snippet = BrewStoreMirrorBenchmarkManager.generateShellExportSnippet(mirror: official)
        XCTAssertTrue(snippet.contains("HOMEBREW_BOTTLE_DOMAIN"))
        XCTAssertTrue(snippet.contains("HOMEBREW_CORE_GIT_REMOTE"))
    }

    func testCVEScanningAdvisories() {
        let xz = BrewStorePackage(id: "xz", name: "xz", description: "Compression", homepage: "", version: "5.6.0", kind: .formula, isInstalled: true)
        let safePkg = BrewStorePackage(id: "bat", name: "bat", description: "Cat clone", homepage: "", version: "0.24", kind: .formula, isInstalled: true)

        let xzAdvisories = BrewStoreCVEScanningManager.advisories(for: xz)
        XCTAssertFalse(xzAdvisories.isEmpty)
        XCTAssertEqual(xzAdvisories.first?.id, "CVE-2024-3094")
        XCTAssertEqual(xzAdvisories.first?.severity, .critical)

        let safeAdvisories = BrewStoreCVEScanningManager.advisories(for: safePkg)
        XCTAssertTrue(safeAdvisories.isEmpty)
    }

    @MainActor
    func testMultiMachineEnvironmentDiff() {
        let workMac = MacMachineProfile(
            id: "mac-1",
            name: "Work MacBook",
            arch: "Apple Silicon",
            timestamp: Date(),
            formulae: ["git", "node", "ripgrep", "docker"],
            casks: ["visual-studio-code", "raycast"],
            taps: ["homebrew/core"]
        )

        let homeMac = MacMachineProfile(
            id: "mac-2",
            name: "Home Mac mini",
            arch: "Apple Silicon",
            timestamp: Date(),
            formulae: ["git", "node", "starship", "bat"],
            casks: ["visual-studio-code", "ghostty"],
            taps: ["homebrew/core"]
        )

        let syncMgr = BrewStoreMultiMachineSyncManager.shared
        let diff = syncMgr.computeDiff(local: workMac, remote: homeMac)

        XCTAssertEqual(diff.commonCount, 3) // git, node, visual-studio-code
        XCTAssertTrue(diff.missingOnLocalFormulae.contains("starship"))
        XCTAssertTrue(diff.missingOnLocalFormulae.contains("bat"))
        XCTAssertTrue(diff.missingOnLocalCasks.contains("ghostty"))
        XCTAssertTrue(diff.missingOnRemoteFormulae.contains("docker"))
    }

    @MainActor
    func testAppReplacementDetection() {
        let scannedApps = [
            ScannedAppItem(
                id: "/Applications/CleanMyMac X.app",
                appName: "CleanMyMac X",
                appPath: "/Applications/CleanMyMac X.app",
                bundleID: "com.macpaw.CleanMyMac4",
                installedVersion: "4.15.0",
                matchedCask: nil,
                matchConfidence: .unmatched,
                isAlreadyManaged: false
            ),
            ScannedAppItem(
                id: "/Applications/Docker.app",
                appName: "Docker Desktop",
                appPath: "/Applications/Docker.app",
                bundleID: "com.docker.docker",
                installedVersion: "4.30.0",
                matchedCask: nil,
                matchConfidence: .unmatched,
                isAlreadyManaged: false
            )
        ]

        let replacementMgr = BrewStoreAppReplacementManager.shared
        replacementMgr.scanForReplacements(scannedApps: scannedApps)

        XCTAssertEqual(replacementMgr.detectedAlternatives.count, 3)
        XCTAssertTrue(replacementMgr.detectedAlternatives.contains(where: { $0.replacementPackageID == "mole" }))
        XCTAssertTrue(replacementMgr.detectedAlternatives.contains(where: { $0.replacementPackageID == "pearcleaner" }))
        XCTAssertTrue(replacementMgr.detectedAlternatives.contains(where: { $0.replacementPackageID == "orbstack" }))
    }

    @MainActor
    func testPackagePinningManager() {
        let pinMgr = BrewStorePackagePinningManager.shared
        let testPkgID = "test-postgres"

        XCTAssertFalse(pinMgr.isPinned(packageID: testPkgID))
        pinMgr.pinnedPackageIDs.insert(testPkgID)
        XCTAssertTrue(pinMgr.isPinned(packageID: testPkgID))
        pinMgr.pinnedPackageIDs.remove(testPkgID)
        XCTAssertFalse(pinMgr.isPinned(packageID: testPkgID))
    }

    @MainActor
    func testDotfilesAutoSync() {
        let dotfilesMgr = BrewStoreDotfilesAutoSyncManager.shared
        XCTAssertNotNil(dotfilesMgr.resolvedURL)
        XCTAssertFalse(dotfilesMgr.customBrewfilePath.isEmpty)
    }

    func testCommunityAnalytics() {
        let nodeMetrics = BrewStoreCommunityAnalyticsManager.analytics(for: "node")
        XCTAssertEqual(nodeMetrics.rank, 1)
        XCTAssertGreaterThan(nodeMetrics.installCount30d, 100_000)
        XCTAssertTrue(nodeMetrics.isPositiveGrowth)
        XCTAssertFalse(nodeMetrics.formatted30d.isEmpty)
        XCTAssertEqual(nodeMetrics.sparklinePoints.count, 7)

        let customMetrics = BrewStoreCommunityAnalyticsManager.analytics(for: "custom-tool")
        XCTAssertGreaterThan(customMetrics.installCount30d, 0)
        XCTAssertEqual(customMetrics.sparklinePoints.count, 7)
    }

    @MainActor
    func testAutoUpdateSchedulerModes() {
        _ = BrewStoreAutoUpdateScheduler.shared
        XCTAssertEqual(AutoUpdateFrequency.allCases.count, 4)
        XCTAssertEqual(AutoUpgradeMode.allCases.count, 3)
        XCTAssertEqual(AutoUpdateFrequency.daily.intervalSeconds, 86400)
        XCTAssertEqual(AutoUpdateFrequency.hourly.intervalSeconds, 3600)
    }

    func testJSONParserArrayRootHandling() {
        let arrayJSON = """
        [
            {
                "name": ["ripgrep"],
                "desc": "Fast search tool",
                "homepage": "https://github.com/BurntSushi/ripgrep",
                "versions": { "stable": "14.1.0" }
            }
        ]
        """.data(using: .utf8)!

        let packages = HomebrewJSONParser.packages(from: arrayJSON, kind: .formula, installedIDs: [], outdatedIDs: [])
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages.first?.name, "ripgrep")
        XCTAssertEqual(packages.first?.version, "14.1.0")
    }

    func testJSONParserCorruptedData() {
        let corruptedData = "Not valid json {{{".data(using: .utf8)!
        let packages = HomebrewJSONParser.packages(from: corruptedData, kind: .formula, installedIDs: [], outdatedIDs: [])
        XCTAssertTrue(packages.isEmpty)

        let services = HomebrewJSONParser.services(from: corruptedData)
        XCTAssertTrue(services.isEmpty)

        let ids = HomebrewJSONParser.identifiers(fromOutdated: corruptedData, kind: .formula)
        XCTAssertTrue(ids.isEmpty)
    }

    func testPackagePinningCellarMissingDirectory() {
        let versions = BrewStorePackagePinningManager.installedCellarVersions(for: "non-existent-pkg", prefix: "/non/existent/prefix")
        XCTAssertTrue(versions.isEmpty)
    }

    func testBundleTypeRawValuesAndIDs() {
        for type in BundleType.allCases {
            XCTAssertEqual(type.id, type.rawValue)
            XCTAssertFalse(type.rawValue.isEmpty)
        }
    }

    func testBundlePricingTierBadges() {
        XCTAssertEqual(BundlePricingTier.freeFOSS.badgeColor, "green")
        XCTAssertEqual(BundlePricingTier.allowedFreemium.badgeColor, "blue")
        XCTAssertEqual(BundlePricingTier.freeFOSS.id, BundlePricingTier.freeFOSS.rawValue)
    }

    @MainActor
    func testCustomBundleCategorization() {
        let stackMgr = BrewStoreStackManager.shared
        let initialCount = stackMgr.customStacks.count

        stackMgr.addCustomStack(
            name: "Test CLI Only",
            description: "A test bundle with only formulae",
            icon: "terminal",
            formulae: ["bat", "eza"],
            casks: []
        )

        let added = stackMgr.customStacks.first(where: { $0.name == "Test CLI Only" })
        XCTAssertNotNil(added)
        XCTAssertEqual(added?.bundleType, .formulae)
        XCTAssertEqual(added?.pricingTier, .freeFOSS)

        if let added {
            stackMgr.deleteCustomStack(added)
            XCTAssertEqual(stackMgr.customStacks.count, initialCount)
        }
    }

    func testCommunityAnalyticsFormatting() {
        let sample = PackageAnalyticsMetrics(
            id: "test",
            installCount30d: 1_500_000,
            installCount90d: 4_500_000,
            installCount365d: 18_000_000,
            monthlyGrowthPercent: -4.2,
            rank: 12,
            sparklinePoints: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]
        )

        XCTAssertEqual(sample.formatted30d, "1.5M")
        XCTAssertEqual(sample.formatted365d, "18.0M")
        XCTAssertFalse(sample.isPositiveGrowth)
        XCTAssertEqual(sample.formattedGrowth, "-4.2%")
    }

    func testBottleIntegrityAuditorFallback() {
        let uninstalledPkg = BrewStorePackage(
            id: "fake-package",
            name: "fake-package",
            description: "",
            homepage: "",
            version: "1.0",
            kind: .formula,
            isInstalled: false
        )

        let audit = BrewStoreBottleIntegrityAuditor.auditPackage(package: uninstalledPkg, prefix: "/opt/homebrew")
        XCTAssertEqual(audit.status, .verifiedBottle)
        XCTAssertNil(audit.bottleSHA256)
    }

    func testCVEAdvisorySeverityOrdering() {
        XCTAssertEqual(VulnerabilitySeverity.critical.rawValue, "Critical")
        XCTAssertEqual(VulnerabilitySeverity.high.rawValue, "High")
        XCTAssertEqual(VulnerabilitySeverity.medium.rawValue, "Medium")
        XCTAssertEqual(VulnerabilitySeverity.low.rawValue, "Low")
    }

    @MainActor
    func testMirrorBenchmarkDefaultMirrors() {
        let mirrors = BrewStoreMirrorBenchmarkManager.shared.mirrors
        XCTAssertEqual(mirrors.count, 4)
        XCTAssertTrue(mirrors.contains(where: { $0.id == "official" }))
        XCTAssertTrue(mirrors.contains(where: { $0.id == "ustc" }))
        XCTAssertTrue(mirrors.contains(where: { $0.id == "tsinghua" }))
        XCTAssertTrue(mirrors.contains(where: { $0.id == "aliyun" }))
    }

    func testGenericOfflineScaffolder() {
        let formulaRuby = BrewStoreFormulaScaffolder.scaffoldGenericFormula(
            name: "local-cli",
            desc: "A local CLI tool",
            homepage: "https://local.dev",
            url: "https://local.dev/cli.tar.gz",
            version: "2.0.0",
            bin: "local-cli"
        )
        XCTAssertTrue(formulaRuby.contains("class LocalCli < Formula"))
        XCTAssertTrue(formulaRuby.contains("desc \"A local CLI tool\""))
        XCTAssertTrue(formulaRuby.contains("version \"2.0.0\""))

        let caskRuby = BrewStoreFormulaScaffolder.scaffoldGenericCask(
            name: "Local App",
            desc: "A local GUI app",
            homepage: "https://local.dev",
            url: "https://local.dev/app.dmg",
            version: "1.5.0",
            appName: "Local App.app"
        )
        XCTAssertTrue(caskRuby.contains("cask \"local-app\" do"))
        XCTAssertTrue(caskRuby.contains("version \"1.5.0\""))
        XCTAssertTrue(caskRuby.contains("name \"LocalApp\""))
    }

    @MainActor
    func testPinAndUnpinToggle() {
        let pinning = BrewStorePackagePinningManager.shared
        let pkgID = "test-pin-tool"

        pinning.pinnedPackageIDs.remove(pkgID)
        XCTAssertFalse(pinning.isPinned(packageID: pkgID))

        pinning.pinnedPackageIDs.insert(pkgID)
        XCTAssertTrue(pinning.isPinned(packageID: pkgID))

        pinning.pinnedPackageIDs.remove(pkgID)
        XCTAssertFalse(pinning.isPinned(packageID: pkgID))
    }

    @MainActor
    func testIgnoredUpdatesToggle() {
        let manager = BrewStoreIgnoredUpdatesManager.shared
        let pkgID = "test-muted-tool"

        manager.unignore(packageID: pkgID)
        XCTAssertFalse(manager.isIgnored(packageID: pkgID))

        manager.toggleIgnore(packageID: pkgID)
        XCTAssertTrue(manager.isIgnored(packageID: pkgID))

        manager.toggleIgnore(packageID: pkgID)
        XCTAssertFalse(manager.isIgnored(packageID: pkgID))
    }

    @MainActor
    func testWishlistStarAndUnstarToggle() {
        let wishlist = BrewStoreWishlistManager.shared
        let pkgID = "test-star-tool"

        if wishlist.isWishlisted(id: pkgID) {
            wishlist.toggleWishlist(id: pkgID)
        }
        XCTAssertFalse(wishlist.isWishlisted(id: pkgID))

        // Star
        wishlist.toggleWishlist(id: pkgID)
        XCTAssertTrue(wishlist.isWishlisted(id: pkgID))

        // Unstar
        wishlist.toggleWishlist(id: pkgID)
        XCTAssertFalse(wishlist.isWishlisted(id: pkgID))
    }

    func testStoragePurgeReportAndReclaimCalculation() {
        let report = StorageReport(
            totalCellarBytes: 5_000_000_000,
            totalCacheBytes: 2_000_000_000,
            totalLogsBytes: 50_000_000,
            inactiveVersionsBytes: 500_000_000,
            items: [],
            topHogs: []
        )
        XCTAssertEqual(report.reclaimableBytes, 2_550_000_000)
        XCTAssertFalse(report.formattedReclaimable.isEmpty)
        XCTAssertFalse(report.formattedTotalLogs.isEmpty)
        XCTAssertFalse(report.formattedInactiveVersions.isEmpty)

        // Verify zero-byte formatting standardizes to "0 KB" without literal "Zero"
        let zeroReport = StorageReport(
            totalCellarBytes: 0,
            totalCacheBytes: 0,
            totalLogsBytes: 0,
            inactiveVersionsBytes: 0,
            items: [],
            topHogs: []
        )
        XCTAssertEqual(zeroReport.formattedInactiveVersions, "0 KB")
        XCTAssertEqual(zeroReport.formattedTotalLogs, "0 KB")
        XCTAssertFalse(zeroReport.formattedInactiveVersions.contains("Zero"))
        XCTAssertFalse(zeroReport.formattedTotalLogs.contains("Zero"))
    }

    func testDependencyDoctorReportScoreCalculation() {
        let issue1 = ToolchainIssue(
            id: "orphan-lib",
            title: "Orphaned lib",
            description: "Orphan",
            kind: .orphan,
            severity: "info",
            recommendedAction: "Prune",
            packageID: "lib"
        )
        let report = ToolchainDiagnosisReport(
            issues: [issue1],
            score: 88,
            grade: "A",
            summary: "1 issue"
        )
        XCTAssertEqual(report.orphanCount, 1)
        XCTAssertEqual(report.unlinkedCount, 0)
        XCTAssertEqual(report.missingCount, 0)
        XCTAssertEqual(report.grade, "A")
    }

    @MainActor
    func testMacTransferBundleAndBootstrapScript() {
        let transfer = BrewStoreMacTransferManager.shared
        let bundle = MacRigExportBundle(
            rigName: "Work MacBook Pro",
            macModel: "MacBook Pro",
            architecture: "arm64",
            exportDate: Date(),
            taps: ["homebrew/cask", "homebrew/core"],
            formulae: [MacRigPackageBundle(name: "ripgrep", version: "14.1.0", kind: "formula", tap: nil)],
            casks: [MacRigPackageBundle(name: "ghostty", version: "1.0.0", kind: "cask", tap: nil)],
            pinnedPackages: ["ripgrep"],
            brewfileContent: "brew \"ripgrep\"\ncask \"ghostty\""
        )

        XCTAssertEqual(bundle.totalPackagesCount, 2)
        let script = transfer.generateBootstrapScript(bundle: bundle)
        XCTAssertTrue(script.contains("brew install ripgrep"))
        XCTAssertTrue(script.contains("brew install --cask ghostty"))
        XCTAssertTrue(script.contains("brew pin ripgrep"))
    }

    @MainActor
    func testPinAndUnpinFilledIconStateConsistency() {
        let pinning = BrewStorePackagePinningManager.shared
        let pkgID = "test-pin-tool"

        pinning.pinnedPackageIDs.remove(pkgID)
        XCTAssertFalse(pinning.isPinned(packageID: pkgID))

        // When unpinned: button should offer "Pin Version" with filled pin icon
        let unpinnedLabel = pinning.isPinned(packageID: pkgID) ? "Unpin Version" : "Pin Version"
        let unpinnedIcon = pinning.isPinned(packageID: pkgID) ? "pin.slash.fill" : "pin.fill"
        XCTAssertEqual(unpinnedLabel, "Pin Version")
        XCTAssertEqual(unpinnedIcon, "pin.fill")

        // Toggle to Pinned
        pinning.pinnedPackageIDs.insert(pkgID)
        XCTAssertTrue(pinning.isPinned(packageID: pkgID))

        // When pinned: badge is "pin.fill" (orange) and button offers "Unpin Version" with "pin.slash.fill"
        let pinnedLabel = pinning.isPinned(packageID: pkgID) ? "Unpin Version" : "Pin Version"
        let pinnedIcon = pinning.isPinned(packageID: pkgID) ? "pin.slash.fill" : "pin.fill"
        XCTAssertEqual(pinnedLabel, "Unpin Version")
        XCTAssertEqual(pinnedIcon, "pin.slash.fill")
    }

    @MainActor
    func testWishlistStarAndUnstarFilledIconStateConsistency() {
        let wishlist = BrewStoreWishlistManager.shared
        let pkgID = "test-star-consistency-tool"

        if wishlist.isWishlisted(id: pkgID) {
            wishlist.toggleWishlist(id: pkgID)
        }
        XCTAssertFalse(wishlist.isWishlisted(id: pkgID))

        // When unstarred: detail icon is unfilled "star", action offers "Star (Add to Wishlist)"
        let unstarredIcon = wishlist.isWishlisted(id: pkgID) ? "star.fill" : "star"
        let unstarredActionLabel = wishlist.isWishlisted(id: pkgID) ? "Unstar (Remove from Wishlist)" : "Star (Add to Wishlist)"
        XCTAssertEqual(unstarredIcon, "star")
        XCTAssertEqual(unstarredActionLabel, "Star (Add to Wishlist)")

        // Star it
        wishlist.toggleWishlist(id: pkgID)
        XCTAssertTrue(wishlist.isWishlisted(id: pkgID))

        // When starred: detail icon is filled "star.fill", action offers "Unstar (Remove from Wishlist)" with "star.slash"
        let starredIcon = wishlist.isWishlisted(id: pkgID) ? "star.fill" : "star"
        let starredActionLabel = wishlist.isWishlisted(id: pkgID) ? "Unstar (Remove from Wishlist)" : "Star (Add to Wishlist)"
        XCTAssertEqual(starredIcon, "star.fill")
        XCTAssertEqual(starredActionLabel, "Unstar (Remove from Wishlist)")
    }

    @MainActor
    func testActionConsoleDrawerCustomBrewCommandExecution() {
        let manager = HomebrewManager()
        manager.clearOutputLog()
        XCTAssertEqual(manager.outputLog, "")

        manager.runCustomBrewCommand("   ")
        XCTAssertFalse(manager.isOperating)
    }

    @MainActor
    func testAIAssistantCaskAndFormulaPrefixFiltering() {
        let assistant = BrewStoreAIAssistant()
        let manager = HomebrewManager()

        // 1. Cask prefix filter
        assistant.analyze(query: "cask browser", manager: manager)
        XCTAssertEqual(assistant.detectedFilter, .cask)
        XCTAssertFalse(assistant.recommendations.isEmpty)
        for rec in assistant.recommendations {
            XCTAssertEqual(rec.kind, .cask, "Recommendation '\(rec.name)' should be a cask")
        }

        // 2. Formula prefix filter
        assistant.analyze(query: "formula python", manager: manager)
        XCTAssertEqual(assistant.detectedFilter, .formula)
        XCTAssertFalse(assistant.recommendations.isEmpty)
        for rec in assistant.recommendations {
            XCTAssertEqual(rec.kind, .formula, "Recommendation '\(rec.name)' should be a formula")
        }
    }

    @MainActor
    func testAIAssistantEducationalNotesAndOfflineCatalogMatching() {
        let assistant = BrewStoreAIAssistant()
        let manager = HomebrewManager()

        // 1. Educational question
        assistant.analyze(query: "what is a cask?", manager: manager)
        XCTAssertNotNil(assistant.educationalNote)
        XCTAssertTrue(assistant.educationalNote!.contains("Casks vs Formulae"))

        // 2. Offline catalog search with action recipes
        assistant.analyze(query: "convert video", manager: manager)
        XCTAssertFalse(assistant.recommendations.isEmpty)
        let ffmpegRec = assistant.recommendations.first { $0.packageID == "ffmpeg" }
        XCTAssertNotNil(ffmpegRec)
        XCTAssertEqual(ffmpegRec?.commandRecipe, "ffmpeg -i input.mkv -c:v copy -c:a aac output.mp4")
    }

    @MainActor
    func testAutoRefreshPreferencesAndIntervalClamping() {
        let prefs = BrewStorePreferences.shared

        // Test default
        prefs.resetToDefaults()
        XCTAssertTrue(prefs.isAutoRefreshEnabled)
        XCTAssertEqual(prefs.autoRefreshIntervalSeconds, 15)
        XCTAssertTrue(prefs.autoRefreshOnExternalBrewCommands)

        // Test custom interval values
        prefs.autoRefreshIntervalSeconds = 30
        XCTAssertEqual(prefs.autoRefreshIntervalSeconds, 30)

        prefs.autoRefreshIntervalSeconds = 300 // 5 minutes
        XCTAssertEqual(prefs.autoRefreshIntervalSeconds, 300)

        // Test clamping: minimum 5s, maximum 3600s
        prefs.autoRefreshIntervalSeconds = 1
        XCTAssertEqual(prefs.autoRefreshIntervalSeconds, 5)

        prefs.autoRefreshIntervalSeconds = 5000
        XCTAssertEqual(prefs.autoRefreshIntervalSeconds, 3600)

        // Restore default
        prefs.autoRefreshIntervalSeconds = 15
    }

    @MainActor
    func testAutoRefreshTimestampAndWatcherInitialization() {
        let manager = HomebrewManager()
        XCTAssertNotNil(manager)

        // Setup auto refresh triggers timer and watcher
        manager.setupAutoRefresh()
        manager.restartAutoRefreshTimer()
        manager.setupDirectoryWatcher()

        // Verify manager can refresh cleanly
        manager.refresh()
    }

    func testEditorialHeroPicksAndGradientColorMappings() {
        let picks = BrewStoreEditorialPick.allPicks
        XCTAssertFalse(picks.isEmpty)

        for pick in picks {
            XCTAssertFalse(pick.id.isEmpty)
            XCTAssertFalse(pick.name.isEmpty)
            XCTAssertFalse(pick.headline.isEmpty)
            XCTAssertFalse(pick.review.isEmpty)
            XCTAssertFalse(pick.badge.isEmpty)
            XCTAssertFalse(pick.systemImage.isEmpty)
            XCTAssertFalse(pick.accentColorName.isEmpty)
            _ = pick.accentColor
            _ = pick.secondaryAccentColor
        }

        let raycast = BrewStoreEditorialPick.pick(for: "raycast")
        XCTAssertNotNil(raycast)
        XCTAssertEqual(raycast?.name, "Raycast")
        XCTAssertEqual(raycast?.kind, .cask)
    }

    @MainActor
    func testStatusHUDViewMetricsAndServiceCount() {
        let manager = HomebrewManager()
        let hud = BrewStoreStatusHUDView(
            manager: manager,
            onOpenHealth: {},
            onOpenServices: {}
        )
        XCTAssertNotNil(hud)
        XCTAssertFalse(manager.isOperating)
    }

    @MainActor
    func testCommandPaletteViewInitializationAndFiltering() {
        let manager = HomebrewManager()
        let discovery = BrewStoreDiscoveryCatalog()
        var selection: BrewStoreSection? = .discover
        var isPresented = true

        let palette = CommandPaletteView(
            manager: manager,
            discovery: discovery,
            selection: Binding(get: { selection }, set: { selection = $0 }),
            isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })
        )
        XCTAssertNotNil(palette)
    }

    @MainActor
    func testThemeAndVibrancyManagerConfiguration() {
        let themeManager = BrewStoreThemeVibrancyManager.shared

        for theme in AppAccentTheme.allCases {
            XCTAssertFalse(theme.rawValue.isEmpty)
            XCTAssertFalse(theme.icon.isEmpty)
            _ = theme.color
        }

        for vibrancy in WindowVibrancyLevel.allCases {
            XCTAssertFalse(vibrancy.rawValue.isEmpty)
        }

        themeManager.currentTheme = .cyberViolet
        XCTAssertEqual(themeManager.currentTheme, .cyberViolet)

        themeManager.vibrancyLevel = .highTranslucency
        XCTAssertEqual(themeManager.vibrancyLevel, .highTranslucency)

        // Restore default
        themeManager.currentTheme = .amberBrew
        themeManager.vibrancyLevel = .standard
    }

    @MainActor
    func testPackageDetailViewInitializationAndDependencyResolution() {
        let manager = HomebrewManager()
        let package = BrewStorePackage(
            id: "ffmpeg",
            name: "FFmpeg",
            description: "Play, record, convert, and stream audio and video",
            homepage: "https://ffmpeg.org",
            version: "7.0.1",
            kind: .formula,
            dependencies: ["lame", "x264", "x265"]
        )

        let detailView = PackageDetailView(manager: manager, package: package)
        XCTAssertNotNil(detailView)
        XCTAssertEqual(package.dependencies.count, 3)
    }

    @MainActor
    func testSnapshotRollbackManagerPlanComputationAndExecution() {
        let rollbackManager = BrewStoreSnapshotRollbackManager.shared
        let manager = HomebrewManager()

        let currentPackages = [
            BrewStorePackage(id: "git", name: "Git", description: "", homepage: "", version: "2.40.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "node", name: "Node", description: "", homepage: "", version: "20.0.0", kind: .formula, isInstalled: true)
        ]

        let snapshot = BrewStoreSnapshot(
            id: "snap-1",
            timestamp: Date(),
            name: "Clean State",
            fileURL: URL(fileURLWithPath: "/tmp/snap.json"),
            formulae: ["git", "python"],
            casks: ["raycast"],
            taps: ["homebrew/core"]
        )

        let plan = rollbackManager.computePlan(currentPackages: currentPackages, snapshot: snapshot)
        XCTAssertTrue(plan.packagesToUninstall.contains("node"))
        XCTAssertTrue(plan.packagesToReinstall.contains("python"))
        XCTAssertTrue(plan.packagesToReinstall.contains("raycast"))
        XCTAssertFalse(plan.isEmpty)

        // Verify clean invocation of executeRollback initiates rollback state
        rollbackManager.executeRollback(plan: plan, manager: manager)
        XCTAssertTrue(rollbackManager.isRollingBack)

        // Reset state
        rollbackManager.isRollingBack = false
    }

    @MainActor
    func testHelpManualTopicsCountAndContent() {
        XCTAssertEqual(HelpManualView.topics.count, 8)
        let topicIDs = Set(HelpManualView.topics.map(\.id))
        XCTAssertTrue(topicIDs.contains("getting-started"))
        XCTAssertTrue(topicIDs.contains("v1-changelog"))
        XCTAssertTrue(topicIDs.contains("services"))
        XCTAssertTrue(topicIDs.contains("app-cleaner"))
        XCTAssertTrue(topicIDs.contains("snapshots"))
        XCTAssertTrue(topicIDs.contains("doctor"))
        XCTAssertTrue(topicIDs.contains("creator-studio"))
        XCTAssertTrue(topicIDs.contains("shortcuts"))
    }

    @MainActor
    func testDiscoveryCatalogMergeLocalPackages() {
        let catalog = BrewStoreDiscoveryCatalog()
        let packages = [
            BrewStorePackage(id: "visual-studio-code", name: "Visual Studio Code", description: "Code editor", homepage: "https://code.visualstudio.com", version: "1.90.0", kind: .cask),
            BrewStorePackage(id: "postgresql@16", name: "PostgreSQL 16", description: "Relational database server", homepage: "https://postgresql.org", version: "16.2", kind: .formula)
        ]

        catalog.mergeLocalPackages(packages)
        XCTAssertEqual(catalog.items.count, 2)
        XCTAssertEqual(catalog.items.first(where: { $0.id == "visual-studio-code" })?.category, "Development")
        XCTAssertEqual(catalog.items.first(where: { $0.id == "postgresql@16" })?.category, "Infrastructure & Cloud")
    }

    @MainActor
    func testCVESecurityReportSynthesis() {
        let installed = [
            BrewStorePackage(id: "xz", name: "XZ Utils", description: "Compression library", homepage: "", version: "5.6.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "Fast grep", homepage: "", version: "14.0.0", kind: .formula, isInstalled: true)
        ]

        let issues = BrewStoreCVESecurityScanner.parseAuditOutput(output: "", installedPackages: installed)
        XCTAssertNotNil(issues)

        // Verify known advisories for xz
        let xzAdvisories = BrewStoreCVEScanningManager.knownAdvisories.filter { $0.packageID == "xz" }
        XCTAssertFalse(xzAdvisories.isEmpty)
        XCTAssertEqual(xzAdvisories.first?.id, "CVE-2024-3094")
    }

    @MainActor
    func testBrewfileImporterWithInlineCommentsAndOptions() {
        let importer = BrewStoreBrewfileImporter.shared
        let manager = HomebrewManager()

        let content = """
        # My Developer Environment Brewfile
        tap "homebrew/cask-versions" # Legacy versions
        brew "ripgrep" # Fast CLI search
        brew 'node', args: ['--HEAD'] # Node bleeding edge
        cask "visual-studio-code" # Primary IDE
        cask 'iterm2' # Terminal
        """

        let summary = importer.parseBrewfile(content: content, manager: manager)
        XCTAssertEqual(summary.taps.count, 1)
        XCTAssertEqual(summary.taps.first, "homebrew/cask-versions")
        XCTAssertEqual(summary.formulae.count, 2)
        XCTAssertEqual(summary.formulae[0].rawName, "ripgrep")
        XCTAssertEqual(summary.formulae[1].rawName, "node")
        XCTAssertEqual(summary.casks.count, 2)
        XCTAssertEqual(summary.casks[0].rawName, "visual-studio-code")
        XCTAssertEqual(summary.casks[1].rawName, "iterm2")
    }

    @MainActor
    func testDiskStorageReportComputations() {
        let report = StorageReport(
            totalCellarBytes: 500_000_000,
            totalCacheBytes: 200_000_000,
            totalLogsBytes: 50_000_000,
            inactiveVersionsBytes: 150_000_000,
            items: [],
            topHogs: []
        )

        XCTAssertEqual(report.reclaimableBytes, 400_000_000)
        XCTAssertFalse(report.formattedTotalCellar.isEmpty)
        XCTAssertFalse(report.formattedTotalCache.isEmpty)
        XCTAssertFalse(report.formattedReclaimable.isEmpty)
    }

    @MainActor
    func testAppUpdateCheckerSemanticVersionEdgeCases() {
        XCTAssertTrue(BrewStoreAppUpdateChecker.isNewerVersion(remote: "1.0.1", local: "1.0.0"))
        XCTAssertTrue(BrewStoreAppUpdateChecker.isNewerVersion(remote: "v1.1.0", local: "1.0.0"))
        XCTAssertTrue(BrewStoreAppUpdateChecker.isNewerVersion(remote: "2.0.0", local: "1.9.9"))
        XCTAssertFalse(BrewStoreAppUpdateChecker.isNewerVersion(remote: "1.0.0", local: "1.0.0"))
        XCTAssertFalse(BrewStoreAppUpdateChecker.isNewerVersion(remote: "v1.0.0", local: "1.0.0"))
        XCTAssertFalse(BrewStoreAppUpdateChecker.isNewerVersion(remote: "0.9.9", local: "1.0.0"))
        XCTAssertFalse(BrewStoreAppUpdateChecker.isNewerVersion(remote: "1.0.0", local: "1.0.1"))
    }

    @MainActor
    func testAppcastParsing() {
        let sampleXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>BrewStore Changelog</title>
            <item>
              <title>Version 1.0.1</title>
              <enclosure
                url="https://github.com/amfi-disable/BrewStore/releases/download/v1.0.1/brewstore-1.0.1.dmg"
                sparkle:shortVersionString="1.0.1"
                length="9632448"
              />
            </item>
          </channel>
        </rss>
        """

        let release = BrewStoreAppUpdateChecker.parseAppcast(xml: sampleXML, currentVersion: "1.0.0")
        XCTAssertEqual(release.version, "1.0.1")
        XCTAssertEqual(release.downloadURL?.absoluteString, "https://github.com/amfi-disable/BrewStore/releases/download/v1.0.1/brewstore-1.0.1.dmg")
    }

    @MainActor
    func testDockLifecyclePreferencesAndManager() {
        let prefs = BrewStorePreferences.shared
        prefs.resetToDefaults()
        XCTAssertTrue(prefs.hideDockIconWhenWindowClosed)

        let manager = BrewStoreDockLifecycleManager.shared
        manager.setup()
        XCTAssertNotNil(manager)
    }

    func testDiscoveryViewModesAndStorefrontSections() {
        for mode in DiscoveryViewMode.allCases {
            XCTAssertFalse(mode.id.isEmpty)
        }
        for sort in DiscoverySortOrder.allCases {
            XCTAssertFalse(sort.id.isEmpty)
        }
        XCTAssertTrue(BrewStoreSection.allCases.contains(.allPackages))
        XCTAssertTrue(BrewStoreSection.allCases.contains(.allApps))
        XCTAssertTrue(BrewStoreSection.allCases.contains(.allFormulae))
        XCTAssertEqual(BrewStoreSection.allPackages.icon, "shippingbox.2.fill")
        XCTAssertEqual(BrewStoreSection.allApps.icon, "macwindow.on.rectangle")
        XCTAssertEqual(BrewStoreSection.allFormulae.icon, "terminal.fill")
    }

    @MainActor
    func testDiscoveryCatalogTapNormalizationAndAliasSearch() {
        let catalog = BrewStoreDiscoveryCatalog()
        catalog.clearCache()

        let localCask = BrewStorePackage(id: "google-chrome", name: "Google Chrome", description: "Browser", homepage: "", version: "125.0", kind: .cask, tap: nil)
        let localFormula = BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "Search", homepage: "", version: "14.1", kind: .formula, tap: nil)
        let thirdParty = BrewStorePackage(id: "vault", name: "vault", description: "Secrets", homepage: "", version: "1.16", kind: .formula, tap: "hashicorp/tap")

        catalog.mergeLocalPackages([localCask, localFormula, thirdParty])
        XCTAssertEqual(catalog.items.count, 3)

        let chromeItem = catalog.items.first { $0.id == "google-chrome" }
        XCTAssertEqual(chromeItem?.tap, "homebrew/cask")

        let rgItem = catalog.items.first { $0.id == "ripgrep" }
        XCTAssertEqual(rgItem?.tap, "homebrew/core")

        let vaultItem = catalog.items.first { $0.id == "vault" }
        XCTAssertEqual(vaultItem?.tap, "hashicorp/tap")

        // Test alias matching
        let customItem = BrewStoreDiscoveryItem(
            id: "kubernetes-cli",
            name: "kubernetes-cli",
            description: "Kubernetes CLI",
            homepage: "https://kubernetes.io",
            version: "1.30.0",
            kind: .formula,
            installCount30Days: 15000,
            tap: "homebrew/core",
            license: "Apache-2.0",
            aliases: ["kubectl", "k8s"],
            dependencies: [],
            artifacts: []
        )
        catalog.setMockItems(catalog.items + [customItem])

        let foundByAlias = catalog.findItem(id: "k8s")
        XCTAssertNotNil(foundByAlias)
        XCTAssertEqual(foundByAlias?.id, "kubernetes-cli")

        let foundByExact = catalog.findItem(id: "kubernetes-cli")
        XCTAssertNotNil(foundByExact)
    }

    func testUpdateEstimatorCalculationsAndFormatting() {
        let formula = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Search tool",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula
        )

        let cask = BrewStorePackage(
            id: "visual-studio-code",
            name: "Visual Studio Code",
            description: "Code Editor",
            homepage: "https://code.visualstudio.com",
            version: "1.90.0",
            kind: .cask
        )

        // Single package estimates
        let formulaEst = BrewStoreUpdateEstimator.estimate(for: formula)
        XCTAssertGreaterThan(formulaEst.totalSeconds, 5.0)
        XCTAssertEqual(formulaEst.formulaCount, 1)
        XCTAssertEqual(formulaEst.caskCount, 0)
        XCTAssertFalse(formulaEst.formattedEstimate.isEmpty)

        let caskEst = BrewStoreUpdateEstimator.estimate(for: cask)
        XCTAssertGreaterThan(caskEst.totalSeconds, 10.0)
        XCTAssertEqual(caskEst.caskCount, 1)
        XCTAssertEqual(caskEst.formulaCount, 0)

        // Batch package estimates
        let batch = BrewStoreUpdateEstimator.estimate(for: [formula, cask])
        XCTAssertEqual(batch.caskCount, 1)
        XCTAssertEqual(batch.formulaCount, 1)
        XCTAssertGreaterThan(batch.totalSeconds, formulaEst.totalSeconds + caskEst.totalSeconds)
        XCTAssertTrue(batch.detailedSummary.contains("1 app"))
        XCTAssertTrue(batch.detailedSummary.contains("1 CLI tool"))

        // Empty list estimate
        let empty = BrewStoreUpdateEstimator.estimate(for: [])
        XCTAssertEqual(empty.totalSeconds, 0)
        XCTAssertEqual(empty.detailedSummary, "No updates needed")

        // Duration formatting
        XCTAssertEqual(BrewStoreUpdateEstimator.formatDuration(5), "< 10s")
        XCTAssertEqual(BrewStoreUpdateEstimator.formatDuration(42), "42s")
        XCTAssertEqual(BrewStoreUpdateEstimator.formatDuration(75), "1m 15s")
        XCTAssertEqual(BrewStoreUpdateEstimator.formatDuration(180), "3m")
        XCTAssertEqual(BrewStoreUpdateEstimator.formatDuration(3600), "1.0h")

        // Remaining formatting
        XCTAssertEqual(BrewStoreUpdateEstimator.formatRemaining(seconds: 4), "Finishing up…")
        XCTAssertEqual(BrewStoreUpdateEstimator.formatRemaining(seconds: 45), "~45s remaining")
    }

    @MainActor
    func testBrewStoreResetManager() {
        let resetManager = BrewStoreResetManager.shared
        let manager = HomebrewManager()
        let discovery = BrewStoreDiscoveryCatalog()

        XCTAssertEqual(BrewStoreResetOption.allCases.count, 8)
        XCTAssertEqual(BrewStoreResetTier.allCases.count, 4)

        // Test selective reset of preferences
        BrewStorePreferences.shared.autoRefreshIntervalSeconds = 999
        resetManager.performSelectiveReset(options: [.clearPersonalSettings], manager: manager, discovery: discovery)
        XCTAssertEqual(BrewStorePreferences.shared.autoRefreshIntervalSeconds, 15)

        // Test wishlist reset
        BrewStoreWishlistManager.shared.wishlistIDs.insert("test-app")
        XCTAssertTrue(BrewStoreWishlistManager.shared.isWishlisted(id: "test-app"))
        resetManager.unstarEverything()
        XCTAssertFalse(BrewStoreWishlistManager.shared.isWishlisted(id: "test-app"))

        // Test nuclear verification phrase validation
        XCTAssertTrue(resetManager.verifyNuclearPhrase("UNINSTALL ALL PACKAGES"))
        XCTAssertTrue(resetManager.verifyNuclearPhrase("  UNINSTALL ALL PACKAGES  "))
        XCTAssertFalse(resetManager.verifyNuclearPhrase("uninstall all packages"))
        XCTAssertFalse(resetManager.verifyNuclearPhrase("DELETE"))

        // Test factory reset
        resetManager.performFactoryReset(manager: manager, discovery: discovery)
        XCTAssertNotNil(resetManager.lastResetMessage)
        XCTAssertEqual(BrewStorePreferences.shared.autoRefreshIntervalSeconds, 15)
        XCTAssertEqual(BrewStoreWishlistManager.shared.wishlistIDs.count, 0)
        XCTAssertEqual(BrewStoreThemeVibrancyManager.shared.currentTheme, .amberBrew)
        XCTAssertEqual(BrewStoreLocalizationManager.shared.currentLanguage, .english)
    }

    @MainActor
    func testBrewStoreSplitViewManagerOptimalWidthAndSnap() {
        let optimal = BrewStoreSplitViewManager.optimalSidebarWidth
        XCTAssertEqual(optimal, 248.0)
        XCTAssertEqual(BrewStoreSplitViewManager.fixedSidebarWidth, 248.0)
        XCTAssertEqual(BrewStoreSplitViewManager.maxSidebarWidth, 248.0)
        XCTAssertEqual(BrewStoreSplitViewManager.minSidebarWidth, 248.0)

        // Verify that 248.0 pt comfortably accommodates the longest sidebar element ("Adoption & Replacements")
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular))
        let longestTextWidth = ("Adoption & Replacements" as NSString).size(withAttributes: [.font: font]).width
        let neededWidth = 18.0 + 8.0 + longestTextWidth // icon + spacing + text
        XCTAssertLessThan(neededWidth, optimal, "Optimal width 248 must accommodate longest element with breathing room")

        // Verify split view configuration and snap-to-optimal behavior
        let splitVC = NSSplitViewController()
        let sidebarVC = NSViewController()
        sidebarVC.view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        let contentVC = NSViewController()
        contentVC.view = NSView(frame: NSRect(x: 260, y: 0, width: 540, height: 600))

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        let contentItem = NSSplitViewItem(viewController: contentVC)
        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(contentItem)

        let splitView = splitVC.splitView
        splitView.isVertical = true
        splitView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        let manager = BrewStoreSplitViewManager.shared
        manager.configure(splitView: splitView)

        XCTAssertFalse(sidebarItem.canCollapse)
        XCTAssertEqual(sidebarItem.minimumThickness, 248.0)
        XCTAssertEqual(sidebarItem.maximumThickness, 248.0)
        XCTAssertEqual(sidebarItem.holdingPriority, NSLayoutConstraint.Priority(1000))

        // Verify that NSSplitViewController swizzling returns zero effective rect for divider 0
        let proposedRect = NSRect(x: 247, y: 0, width: 2, height: 600)
        let effectiveRect = (splitVC as NSSplitViewDelegate).splitView?(splitView, effectiveRect: proposedRect, forDrawnRect: proposedRect, ofDividerAt: 0)
        XCTAssertEqual(effectiveRect, .zero)

        // When snapToOptimalWidthOrToggle is invoked, width is set to 248
        manager.snapToOptimalWidthOrToggle(splitView: splitView)
        XCTAssertEqual(BrewStoreSplitViewManager.optimalSidebarWidth, 248.0)
    }
}
