@testable import BrewStore
import XCTest

final class AuditRemediationTests: XCTestCase {
    func testCustomInstallOptionsGeneratesInstallForUninstalledPackage() {
        let package = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Fast line-oriented search tool",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula,
            isInstalled: false
        )

        var options = CustomInstallOptions()
        options.buildFromSource = true
        options.verbose = true

        let args = options.buildArguments(for: package)
        XCTAssertEqual(args.first, "install")
        XCTAssertTrue(args.contains("--build-from-source"))
        XCTAssertTrue(args.contains("--verbose"))
        XCTAssertEqual(args.last, "ripgrep")
    }

    func testCustomInstallOptionsGeneratesReinstallForInstalledPackage() {
        let package = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Fast line-oriented search tool",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula,
            isInstalled: true
        )

        var options = CustomInstallOptions()
        options.forceInstall = true
        options.customArguments = "--with-features"

        let args = options.buildArguments(for: package)
        XCTAssertEqual(args.first, "reinstall", "Installed package must generate 'reinstall' rather than 'install'")
        XCTAssertTrue(args.contains("--force"))
        XCTAssertTrue(args.contains("--with-features"))
        XCTAssertEqual(args.last, "ripgrep")
    }

    func testCustomInstallOptionsForCaskPackage() {
        let cask = BrewStorePackage(
            id: "visual-studio-code",
            name: "Visual Studio Code",
            description: "Code editor",
            homepage: "https://code.visualstudio.com",
            version: "1.90.0",
            kind: .cask,
            isInstalled: false
        )

        let options = CustomInstallOptions()
        let args = options.buildArguments(for: cask)
        XCTAssertEqual(args, ["install", "--cask", "visual-studio-code"])
    }

    @MainActor
    func testLeaderboardDeduplication() {
        let items: [BrewStoreDiscoveryItem] = [
            BrewStoreDiscoveryItem(
                id: "dotnet@8",
                name: ".NET 8 SDK",
                description: "SDK",
                homepage: "https://dotnet.microsoft.com",
                version: "8.0",
                kind: .formula,
                installCount30Days: 50000,
                tap: nil, license: "MIT", aliases: [], dependencies: [], artifacts: []
            ),
            BrewStoreDiscoveryItem(
                id: "dotnet@7",
                name: ".NET 7 SDK",
                description: "SDK",
                homepage: "https://dotnet.microsoft.com",
                version: "7.0",
                kind: .formula,
                installCount30Days: 40000,
                tap: nil, license: "MIT", aliases: [], dependencies: [], artifacts: []
            ),
            BrewStoreDiscoveryItem(
                id: "ripgrep",
                name: "ripgrep",
                description: "Search tool",
                homepage: "https://github.com/BurntSushi/ripgrep",
                version: "14.1.0",
                kind: .formula,
                installCount30Days: 45000,
                tap: nil, license: "MIT", aliases: [], dependencies: [], artifacts: []
            ),
            BrewStoreDiscoveryItem(
                id: "bat",
                name: "bat",
                description: "Cat clone with syntax highlighting",
                homepage: "https://github.com/sharkdp/bat",
                version: "0.24.0",
                kind: .formula,
                installCount30Days: 30000,
                tap: nil, license: "MIT", aliases: [], dependencies: [], artifacts: []
            )
        ]

        let sorted = items.sorted {
            if $0.installCount30Days != $1.installCount30Days {
                return $0.installCount30Days > $1.installCount30Days
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        var seenFamilies = Set<String>()
        var deduplicated: [BrewStoreDiscoveryItem] = []
        for item in sorted {
            let baseFamily = item.id.components(separatedBy: "@").first?
                .replacingOccurrences(of: "-preview", with: "")
                .replacingOccurrences(of: "-beta", with: "")
                .replacingOccurrences(of: "-nightly", with: "") ?? item.id
            if !seenFamilies.contains(baseFamily) {
                seenFamilies.insert(baseFamily)
                deduplicated.append(item)
            }
        }

        XCTAssertEqual(deduplicated.count, 3, "dotnet@8 and dotnet@7 should be deduplicated under dotnet family")
        XCTAssertEqual(deduplicated[0].id, "dotnet@8")
        XCTAssertEqual(deduplicated[1].id, "ripgrep")
        XCTAssertEqual(deduplicated[2].id, "bat")
    }

    @MainActor
    func testToolkitBatchInstallTriggersReviewCoordinator() {
        let coordinator = BrewStoreActionReviewCoordinator.shared
        coordinator.cancel()

        let dummyPkg1 = BrewStorePackage(
            id: "fzf",
            name: "fzf",
            description: "Command-line fuzzy finder",
            homepage: "https://github.com/junegunn/fzf",
            version: "0.50.0",
            kind: .formula,
            isInstalled: false
        )
        let dummyPkg2 = BrewStorePackage(
            id: "ghostty",
            name: "Ghostty",
            description: "Fast terminal emulator",
            homepage: "https://ghostty.org",
            version: "1.0.0",
            kind: .cask,
            isInstalled: false
        )

        var confirmed = false
        coordinator.requestInstall(
            packages: [dummyPkg1, dummyPkg2],
            manager: HomebrewManager(),
            onConfirm: {
                confirmed = true
            }
        )

        guard let review = coordinator.pendingReview else {
            XCTFail("pendingReview should be non-nil")
            return
        }

        XCTAssertEqual(review.kind, .install(packages: [dummyPkg1, dummyPkg2]))
        XCTAssertEqual(review.items.count, 2)
        XCTAssertTrue(review.commandPreview?.contains("brew install") == true)
        XCTAssertTrue(review.commandPreview?.contains("fzf") == true)
        XCTAssertTrue(review.commandPreview?.contains("ghostty") == true)

        coordinator.confirm()
        XCTAssertTrue(confirmed, "Confirming review request must invoke the onConfirm callback")
        XCTAssertNil(coordinator.pendingReview)
    }

    func testEveryPackageIsCategorizedInCanonicalCategory() {
        let canonicalCategoryIDs = Set(CategoriesGridView.categories.map(\.id))
        XCTAssertEqual(canonicalCategoryIDs.count, 8)

        let samplePackages: [(id: String, name: String, desc: String, kind: BrewPackageKind)] = [
            ("google-chrome", "Google Chrome", "Web browser by Google", .cask),
            ("firefox", "Firefox", "Open-source web browser", .cask),
            ("vlc", "VLC media player", "Multimedia player and framework", .cask),
            ("font-fira-code", "Fira Code", "Monospaced font with programming ligatures", .cask),
            ("rust", "Rust", "Safe, concurrent, practical language", .formula),
            ("ripgrep", "ripgrep", "Line-oriented search tool", .formula),
            ("docker", "Docker", "Pack, ship and run any application as a lightweight container", .formula),
            ("postgresql@16", "PostgreSQL", "Object-relational SQL database", .formula),
            ("obsidian", "Obsidian", "Markdown-based knowledge base and note taking app", .cask),
            ("1password", "1Password", "Password manager and digital vault", .cask),
            ("dosbox", "DOSBox", "DOS emulator for gaming", .cask),
            ("random-obscure-lib", "random-obscure-lib", "A completely obscure library without keywords", .formula)
        ]

        for sample in samplePackages {
            let item = BrewStoreDiscoveryItem(
                id: sample.id,
                name: sample.name,
                description: sample.desc,
                homepage: "https://example.com",
                version: "1.0",
                kind: sample.kind,
                installCount30Days: 100,
                tap: nil,
                license: nil,
                aliases: [],
                dependencies: [],
                artifacts: []
            )

            let category = item.category
            XCTAssertFalse(category.isEmpty, "Category for \(sample.id) must not be empty")
            XCTAssertTrue(
                canonicalCategoryIDs.contains(category),
                "Category '\(category)' for package \(sample.id) must be one of the canonical categories: \(canonicalCategoryIDs)"
            )
        }

        // Test fallback rule on empty string / unknown descriptions
        let emptyItem = BrewStoreDiscoveryItem(
            id: "xyz123",
            name: "xyz123",
            description: "",
            homepage: "",
            version: "1.0",
            kind: .formula,
            installCount30Days: 0,
            tap: nil, license: nil, aliases: [], dependencies: [], artifacts: []
        )
        XCTAssertEqual(emptyItem.category, "Utilities", "Unrecognized or empty package must deterministically fallback to Utilities")
    }

    func testVersionFormattingNormalizesMalformedBuildNumbers() {
        XCTAssertEqual(BrewStorePackage.formatDisplayVersion("4.2.19,317"), "v4.2.19")
        XCTAssertEqual(BrewStorePackage.formatDisplayVersion("v2.11.0,6376446768316416"), "v2.11.0")
        XCTAssertEqual(BrewStorePackage.formatDisplayVersion("0.1,47"), "v0.1")
        XCTAssertEqual(BrewStorePackage.formatDisplayVersion("1.0.0"), "v1.0.0")
        XCTAssertEqual(BrewStorePackage.formatDisplayVersion("v3.2.1"), "v3.2.1")
        XCTAssertEqual(BrewStorePackage.formatDisplayVersion(""), "")
    }

    @MainActor
    func testAppAdoptionActionReviewCoordination() {
        let coordinator = BrewStoreActionReviewCoordinator.shared
        coordinator.cancel()

        let matchedCask = BrewStorePackage(
            id: "visual-studio-code",
            name: "Visual Studio Code",
            description: "Code editor",
            homepage: "https://code.visualstudio.com",
            version: "1.92.0",
            kind: .cask
        )

        let item = ScannedAppItem(
            id: "vscode",
            appName: "Visual Studio Code",
            appPath: "/Applications/Visual Studio Code.app",
            bundleID: "com.microsoft.VSCode",
            installedVersion: "1.91.0",
            matchedCask: matchedCask,
            matchConfidence: .exactVerified,
            isAlreadyManaged: false,
            reviewReasons: []
        )

        var confirmed = false
        coordinator.requestAdopt(item: item, manager: HomebrewManager()) {
            confirmed = true
        }

        guard let review = coordinator.pendingReview else {
            XCTFail("pendingReview must not be nil")
            return
        }

        XCTAssertEqual(review.kind, .adopt(items: [item]))
        XCTAssertEqual(review.items.count, 1)
        XCTAssertTrue(review.commandPreview?.contains("brew install --cask --adopt visual-studio-code") == true)
        XCTAssertFalse(review.isDestructive)

        coordinator.confirm()
        XCTAssertTrue(confirmed)
        XCTAssertNil(coordinator.pendingReview)
    }
}
