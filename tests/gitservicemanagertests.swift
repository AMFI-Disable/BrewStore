@testable import BrewStore
import XCTest

final class GitServiceManagerTests: XCTestCase {
    func testGitServiceProviderMetadata() {
        XCTAssertEqual(GitServiceProvider.github.displayName, "GitHub")
        XCTAssertEqual(GitServiceProvider.gitlab.displayName, "GitLab")
        XCTAssertEqual(GitServiceProvider.codeberg.displayName, "Codeberg")
        XCTAssertEqual(GitServiceProvider.custom.displayName, "Forgejo / Gitea (Self-Hosted)")

        XCTAssertTrue(GitServiceProvider.github.defaultHost.contains("github.com"))
        XCTAssertTrue(GitServiceProvider.gitlab.defaultHost.contains("gitlab.com"))
        XCTAssertTrue(GitServiceProvider.codeberg.defaultHost.contains("codeberg.org"))

        XCTAssertNotNil(GitServiceProvider.github.tokenCreationURL())
        XCTAssertNotNil(GitServiceProvider.gitlab.tokenCreationURL())
        XCTAssertNotNil(GitServiceProvider.codeberg.tokenCreationURL())
        XCTAssertNotNil(GitServiceProvider.custom.tokenCreationURL(host: "https://git.internal.org"))
        XCTAssertNil(GitServiceProvider.custom.tokenCreationURL(host: nil))
    }

    func testNormalizeHost() {
        XCTAssertEqual(GitServiceManager.normalizeHost("gitlab.com"), "https://gitlab.com")
        XCTAssertEqual(GitServiceManager.normalizeHost("https://gitlab.com/"), "https://gitlab.com")
        XCTAssertEqual(GitServiceManager.normalizeHost("http://selfhosted.git:8080/"), "http://selfhosted.git:8080")
        XCTAssertEqual(GitServiceManager.normalizeHost("  codeberg.org  "), "https://codeberg.org")
    }

    func testGitAccountProfileProperties() {
        let profile = GitAccountProfile(
            provider: .gitlab,
            login: "developer",
            name: "Jane Doe",
            avatarURL: "https://gitlab.com/avatar.png",
            host: "https://gitlab.com",
            webURL: "https://gitlab.com/developer",
            token: "glpat-secret123",
            createdAt: Date()
        )

        XCTAssertEqual(profile.displayName, "Jane Doe")
        XCTAssertEqual(profile.hostKey, "gitlab.com")
        XCTAssertTrue(profile.id.contains("gitlab:developer@gitlab.com"))
    }

    func testGitAccountProfileFallbackDisplayName() {
        let profile = GitAccountProfile(
            provider: .codeberg,
            login: "coder42",
            name: nil,
            avatarURL: nil,
            host: "https://codeberg.org",
            webURL: nil,
            token: "cb-secret",
            createdAt: Date()
        )

        XCTAssertEqual(profile.displayName, "@coder42")
    }

    @MainActor
    func testAccountManagementAndActiveSelection() {
        let manager = GitServiceManager()
        // Clear existing for clean test
        for acc in manager.accounts {
            manager.removeAccount(id: acc.id)
        }
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.activeAccount)

        let gh = GitAccountProfile(
            provider: .github,
            login: "gh-user",
            name: "GitHub User",
            avatarURL: nil,
            host: "https://api.github.com",
            webURL: nil,
            token: "ghp-123",
            createdAt: Date()
        )
        let gl = GitAccountProfile(
            provider: .gitlab,
            login: "gl-user",
            name: "GitLab User",
            avatarURL: nil,
            host: "https://gitlab.com",
            webURL: nil,
            token: "glpat-456",
            createdAt: Date()
        )

        manager.accounts = [gh, gl]
        manager.setActiveAccount(id: gh.id)
        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.activeAccount?.id, gh.id)

        // Switch active
        manager.setActiveAccount(id: gl.id)
        XCTAssertEqual(manager.activeAccount?.id, gl.id)

        // Remove active
        manager.removeAccount(id: gl.id)
        XCTAssertEqual(manager.accounts.count, 1)
        XCTAssertEqual(manager.activeAccount?.id, gh.id)

        // Clean up
        manager.removeAccount(id: gh.id)
        XCTAssertFalse(manager.isAuthenticated)
    }

    @MainActor
    func testConnectAccountEmptyTokenFails() async {
        let manager = GitServiceManager()
        let result = await manager.connectAccount(provider: .github, host: nil, token: "   ")
        XCTAssertFalse(result)
        XCTAssertEqual(manager.statusMessage, "Please enter a valid personal access token.")
    }

    @MainActor
    func testGistAndSnippetIDPersistence() {
        let manager = GitServiceManager()
        let accountID = "github:testuser@github.com"

        manager.setSavedGistID("gist_123456", for: accountID)
        XCTAssertEqual(manager.getSavedGistID(for: accountID), "gist_123456")

        manager.setSavedSnippetID("snippet_78910", for: accountID)
        XCTAssertEqual(manager.getSavedSnippetID(for: accountID), "snippet_78910")

        // Clearing removes from UserDefaults
        manager.setSavedGistID(nil, for: accountID)
        XCTAssertNil(manager.getSavedGistID(for: accountID))

        manager.setSavedSnippetID(nil, for: accountID)
        XCTAssertNil(manager.getSavedSnippetID(for: accountID))
    }
}
