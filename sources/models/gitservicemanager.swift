import AppKit
import Foundation

public enum GitServiceProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case github = "github"
    case gitlab = "gitlab"
    case codeberg = "codeberg"
    case custom = "custom"

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .codeberg: "Codeberg"
        case .custom: "Custom Git"
        }
    }

    public var iconName: String {
        switch self {
        case .github: "arrow.triangle.branch"
        case .gitlab: "flame.fill"
        case .codeberg: "mountain.2.fill"
        case .custom: "server.rack"
        }
    }

    public var defaultHost: String {
        switch self {
        case .github: "https://api.github.com"
        case .gitlab: "https://gitlab.com"
        case .codeberg: "https://codeberg.org"
        case .custom: "https://"
        }
    }

    public var tokenScopeHelp: String {
        switch self {
        case .github:
            "Personal Access Token with 'gist' and 'read:user' scopes."
        case .gitlab:
            "Personal Access Token with 'read_user' and 'api' (for Snippets) scopes."
        case .codeberg:
            "Access Token with 'read:user' and 'write:repository' scopes."
        case .custom:
            "Personal Access Token from your self-hosted instance."
        }
    }

    public func tokenCreationURL(host: String? = nil) -> URL? {
        switch self {
        case .github:
            return URL(string: "https://github.com/settings/tokens/new?description=BrewStore%20macOS&scopes=gist,read:user")
        case .gitlab:
            let base = GitServiceManager.normalizeHost(host ?? defaultHost)
            return URL(string: "\(base)/-/user_settings/personal_access_tokens?name=BrewStore%20macOS&scopes=read_user,api")
        case .codeberg:
            return URL(string: "https://codeberg.org/user/settings/applications")
        case .custom:
            guard let host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let base = GitServiceManager.normalizeHost(host)
            return URL(string: "\(base)/user/settings/applications")
        }
    }
}

public struct GitAccountProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: String {
        "\(provider.rawValue):\(login)@\(hostKey)"
    }

    public let provider: GitServiceProvider
    public let login: String
    public let name: String?
    public let avatarURL: String?
    public let host: String
    public let webURL: String?
    public let token: String
    public let createdAt: Date

    public var hostKey: String {
        URL(string: host)?.host ?? host
    }

    public var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return "@\(login)"
    }
}

@MainActor
public final class GitServiceManager: ObservableObject {
    public static let shared = GitServiceManager()

    @Published public var accounts: [GitAccountProfile] = []
    @Published public var activeAccountID: String?
    @Published public var isVerifying: Bool = false
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncURL: URL?
    @Published public var statusMessage: String?

    private let storageKey = "BrewStore.git.accounts.v1"
    private let activeIDKey = "BrewStore.git.activeAccountID.v1"
    private let legacyGitHubTokenKey = "BrewStore.github.token"

    public var activeAccount: GitAccountProfile? {
        guard let activeAccountID else { return accounts.first }
        return accounts.first(where: { $0.id == activeAccountID }) ?? accounts.first
    }

    public var isAuthenticated: Bool {
        activeAccount != nil
    }

    public init() {
        loadAccounts()
    }

    public nonisolated static func normalizeHost(_ host: String) -> String {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "https://"
        }
        if !trimmed.lowercased().hasPrefix("http://"), !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://\(trimmed)"
        }
        if trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        return trimmed
    }

    public func loadAccounts() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([GitAccountProfile].self, from: data) {
            self.accounts = decoded
            self.activeAccountID = UserDefaults.standard.string(forKey: activeIDKey)
        }

        // Migrate legacy single-token GitHub if no accounts exist
        if accounts.isEmpty, let legacyToken = UserDefaults.standard.string(forKey: legacyGitHubTokenKey), !legacyToken.isEmpty {
            Task {
                _ = await connectAccount(provider: .github, host: nil, token: legacyToken)
            }
        }
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(activeAccountID, forKey: activeIDKey)
    }

    public func setActiveAccount(id: String) {
        if accounts.contains(where: { $0.id == id }) {
            self.activeAccountID = id
            saveAccounts()
        }
    }

    public func removeAccount(id: String) {
        accounts.removeAll(where: { $0.id == id })
        if activeAccountID == id {
            activeAccountID = accounts.first?.id
        }
        saveAccounts()
        if accounts.isEmpty {
            UserDefaults.standard.removeObject(forKey: legacyGitHubTokenKey)
        }
    }

    public func disconnectAllAccounts() {
        accounts.removeAll()
        activeAccountID = nil
        saveAccounts()
        UserDefaults.standard.removeObject(forKey: legacyGitHubTokenKey)
    }

    public func connectAccount(provider: GitServiceProvider, host: String?, token: String) async -> Bool {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            statusMessage = "Please enter a valid personal access token."
            return false
        }

        isVerifying = true
        statusMessage = "Verifying \(provider.displayName) credentials…"

        let targetHost = Self.normalizeHost(host ?? provider.defaultHost)

        do {
            let profile = try await verifyCredentials(provider: provider, host: targetHost, token: cleanToken)
            // Replace if account with same ID exists, else append
            if let existingIndex = accounts.firstIndex(where: { $0.id == profile.id }) {
                accounts[existingIndex] = profile
            } else {
                accounts.append(profile)
            }
            self.activeAccountID = profile.id
            self.saveAccounts()

            // Keep legacy key in sync if GitHub
            if provider == .github {
                UserDefaults.standard.set(cleanToken, forKey: legacyGitHubTokenKey)
            }

            self.statusMessage = "Connected to \(provider.displayName) as @\(profile.login)"
            self.isVerifying = false
            return true
        } catch {
            self.statusMessage = "Verification failed: \(error.localizedDescription)"
            self.isVerifying = false
            return false
        }
    }

    public func verifyCredentials(provider: GitServiceProvider, host: String, token: String) async throws -> GitAccountProfile {
        switch provider {
        case .github:
            guard let url = URL(string: "https://api.github.com/user") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NSError(domain: "BrewStoreGit", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid GitHub token or unauthorized (status \((response as? HTTPURLResponse)?.statusCode ?? 0))."])
            }

            struct GitHubUserResp: Codable {
                let login: String
                let name: String?
                let avatar_url: String?
                let html_url: String?
                let public_repos: Int?
            }

            let user = try JSONDecoder().decode(GitHubUserResp.self, from: data)
            return GitAccountProfile(
                provider: .github,
                login: user.login,
                name: user.name,
                avatarURL: user.avatar_url,
                host: "https://api.github.com",
                webURL: user.html_url ?? "https://github.com/\(user.login)",
                token: token,
                createdAt: Date()
            )

        case .gitlab:
            let base = host.isEmpty ? "https://gitlab.com" : host
            guard let url = URL(string: "\(base)/api/v4/user") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
            request.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NSError(domain: "BrewStoreGit", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid GitLab token or unauthorized (status \((response as? HTTPURLResponse)?.statusCode ?? 0))."])
            }

            struct GitLabUserResp: Codable {
                let username: String
                let name: String?
                let avatar_url: String?
                let web_url: String?
            }

            let user = try JSONDecoder().decode(GitLabUserResp.self, from: data)
            return GitAccountProfile(
                provider: .gitlab,
                login: user.username,
                name: user.name,
                avatarURL: user.avatar_url,
                host: base,
                webURL: user.web_url,
                token: token,
                createdAt: Date()
            )

        case .codeberg, .custom:
            let base = host.isEmpty ? (provider == .codeberg ? "https://codeberg.org" : "https://") : host
            guard let url = URL(string: "\(base)/api/v1/user") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NSError(domain: "BrewStoreGit", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid token or unauthorized for \(base) (status \((response as? HTTPURLResponse)?.statusCode ?? 0))."])
            }

            struct ForgejoUserResp: Codable {
                let login: String
                let full_name: String?
                let avatar_url: String?
                let html_url: String?
            }

            let user = try JSONDecoder().decode(ForgejoUserResp.self, from: data)
            return GitAccountProfile(
                provider: provider,
                login: user.login,
                name: user.full_name,
                avatarURL: user.avatar_url,
                host: base,
                webURL: user.html_url ?? "\(base)/\(user.login)",
                token: token,
                createdAt: Date()
            )
        }
    }

    func syncBrewfile(packages: [BrewStorePackage], taps: [BrewStoreTap]) async -> Bool {
        guard let account = activeAccount else {
            statusMessage = "Please connect a Git account first."
            return false
        }

        isSyncing = true
        statusMessage = "Syncing Brewfile to \(account.provider.displayName)…"

        let brewfileContent = BrewStoreBrewfileParser.generate(
            packages: packages.filter(\.isInstalled),
            taps: taps
        )

        do {
            let syncURL: URL = switch account.provider {
            case .github:
                try await syncToGitHubGist(token: account.token, content: brewfileContent)
            case .gitlab:
                try await syncToGitLabSnippet(host: account.host, token: account.token, content: brewfileContent)
            case .codeberg, .custom:
                try await syncToForgejoRepo(host: account.host, user: account.login, token: account.token, content: brewfileContent)
            }

            self.lastSyncURL = syncURL
            self.statusMessage = "Successfully backed up to \(account.provider.displayName)!"
            self.isSyncing = false
            return true
        } catch {
            self.statusMessage = "Backup failed: \(error.localizedDescription)"
            self.isSyncing = false
            return false
        }
    }

    public func syncToGitHubGist(token: String, content: String) async throws -> URL {
        guard let url = URL(string: "https://api.github.com/gists") else {
            throw URLError(.badURL)
        }
        let payload: [String: Any] = [
            "description": "BrewStore Automatic macOS Package Backup",
            "public": false,
            "files": [
                "Brewfile": ["content": content]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = data

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 201).contains(http.statusCode) else {
            throw NSError(domain: "BrewStoreGit", code: 500, userInfo: [NSLocalizedDescriptionKey: "GitHub Gist API error."])
        }

        if let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
           let htmlURL = json["html_url"] as? String,
           let gistURL = URL(string: htmlURL) {
            return gistURL
        }
        throw URLError(.cannotParseResponse)
    }

    public func syncToGitLabSnippet(host: String, token: String, content: String) async throws -> URL {
        let base = host.isEmpty ? "https://gitlab.com" : host
        guard let url = URL(string: "\(base)/api/v4/snippets") else {
            throw URLError(.badURL)
        }
        let payload: [String: Any] = [
            "title": "BrewStore Automatic macOS Package Backup",
            "file_name": "Brewfile",
            "content": content,
            "visibility": "private"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = data

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 201).contains(http.statusCode) else {
            throw NSError(domain: "BrewStoreGit", code: 500, userInfo: [NSLocalizedDescriptionKey: "GitLab Snippets API error."])
        }

        if let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
           let webURL = json["web_url"] as? String,
           let snippetURL = URL(string: webURL) {
            return snippetURL
        }
        throw URLError(.cannotParseResponse)
    }

    public func syncToForgejoRepo(host: String, user: String, token: String, content: String) async throws -> URL {
        let base = host.isEmpty ? "https://codeberg.org" : host
        let repoName = "brewstore-backup"
        guard let createRepoURL = URL(string: "\(base)/api/v1/user/repos") else {
            throw URLError(.badURL)
        }
        var createReq = URLRequest(url: createRepoURL)
        createReq.httpMethod = "POST"
        createReq.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createReq.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")
        let repoPayload: [String: Any] = [
            "name": repoName,
            "description": "BrewStore Automatic macOS Package Backup",
            "private": true,
            "auto_init": true
        ]
        createReq.httpBody = try? JSONSerialization.data(withJSONObject: repoPayload)
        _ = try? await URLSession.shared.data(for: createReq)

        // Upload Brewfile
        guard let fileURL = URL(string: "\(base)/api/v1/repos/\(user)/\(repoName)/contents/Brewfile") else {
            throw URLError(.badURL)
        }
        var fileReq = URLRequest(url: fileURL)
        fileReq.httpMethod = "POST"
        fileReq.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        fileReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        fileReq.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")

        let base64Content = Data(content.utf8).base64EncodedString()
        let filePayload: [String: Any] = [
            "message": "Update Brewfile backup",
            "content": base64Content
        ]
        fileReq.httpBody = try JSONSerialization.data(withJSONObject: filePayload)

        let (fileData, fileResp) = try await URLSession.shared.data(for: fileReq)
        if let http = fileResp as? HTTPURLResponse, (200 ... 201).contains(http.statusCode),
           let json = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any],
           let contentObj = json["content"] as? [String: Any],
           let htmlURL = contentObj["html_url"] as? String,
           let finalURL = URL(string: htmlURL) {
            return finalURL
        }

        // Fallback to the repo URL
        if let fallbackURL = URL(string: "\(base)/\(user)/\(repoName)") {
            return fallbackURL
        }
        throw URLError(.cannotParseResponse)
    }
}
