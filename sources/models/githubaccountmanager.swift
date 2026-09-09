import AppKit
import Foundation

struct GitHubProfile: Codable, Hashable {
    let login: String
    let name: String?
    let avatar_url: String?
    let public_repos: Int?
    let public_gists: Int?
}

@MainActor
final class GitHubAccountManager: ObservableObject {
    @Published var profile: GitHubProfile?
    @Published var isAuthenticated = false
    @Published var rateLimitRemaining = 60
    @Published var rateLimitTotal = 60
    @Published var isSyncingGist = false
    @Published var lastGistURL: URL?
    @Published var statusMessage: String?

    private let tokenKey = "BrewStore.github.token"

    init() {
        loadStoredToken()
    }

    func loadStoredToken() {
        if let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty {
            verifyToken(token)
        } else {
            checkCLIAuth()
        }
    }

    func checkCLIAuth() {
        // Try reading gh auth token asynchronously if user has GitHub CLI installed
        Task { [weak self] in
            let output: String? = await Task.detached(priority: .utility) {
                let whichResult = BrewStoreCommandExecutor.shared.run(
                    executablePath: "/usr/bin/which",
                    arguments: ["gh"],
                    timeout: 5,
                    category: .readOnly
                )
                guard whichResult.succeeded else { return nil }
                let ghPath = whichResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !ghPath.isEmpty, FileManager.default.isExecutableFile(atPath: ghPath) else { return nil }

                let authResult = BrewStoreCommandExecutor.shared.run(
                    executablePath: ghPath,
                    arguments: ["auth", "token"],
                    timeout: 10,
                    category: .readOnly
                )
                let token = authResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard authResult.succeeded, !token.isEmpty, !token.contains("no token found") else { return nil }
                return token
            }.value

            guard let self, let output else { return }
            self.verifyToken(output)
        }
    }

    func verifyToken(_ token: String) {
        guard let url = URL(string: "https://api.github.com/user") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { return }

                if let remaining = httpResponse.value(forHTTPHeaderField: "x-ratelimit-remaining"), let remInt = Int(remaining) {
                    self.rateLimitRemaining = remInt
                }
                if let limit = httpResponse.value(forHTTPHeaderField: "x-ratelimit-limit"), let limInt = Int(limit) {
                    self.rateLimitTotal = limInt
                }

                if httpResponse.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(GitHubProfile.self, from: data)
                    self.profile = decoded
                    self.isAuthenticated = true
                    UserDefaults.standard.set(token, forKey: tokenKey)
                    self.statusMessage = "Connected as @\(decoded.login)"

                    // Trigger Creator Studio Repo discovery
                    await BrewStoreCreatorRepoManager.shared.fetchRepos(token: token)

                    // Keep GitServiceManager in sync
                    _ = await GitServiceManager.shared.connectAccount(provider: .github, host: nil, token: token)
                } else {
                    self.isAuthenticated = false
                    self.profile = nil
                }
            } catch {
                self.statusMessage = "Could not verify GitHub account: \(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        self.profile = nil
        self.isAuthenticated = false
        self.rateLimitRemaining = 60
        self.rateLimitTotal = 60
        self.statusMessage = nil
        BrewStoreCreatorRepoManager.shared.repos = []
        if let ghAcc = GitServiceManager.shared.accounts.first(where: { $0.provider == .github }) {
            GitServiceManager.shared.removeAccount(id: ghAcc.id)
        }
    }

    func syncGist(packages: [BrewStorePackage], taps: [BrewStoreTap]) async -> Bool {
        guard let token = UserDefaults.standard.string(forKey: tokenKey), isAuthenticated else {
            statusMessage = "Connect your GitHub account to sync Brewfile to Gist."
            return false
        }

        isSyncingGist = true
        statusMessage = "Syncing Brewfile to private GitHub Gist…"

        let brewfileContent = BrewStoreBrewfileParser.generate(packages: packages.filter(\.isInstalled), taps: taps)
        let payload: [String: Any] = [
            "description": "BrewStore Automatic macOS Package Backup",
            "public": false,
            "files": [
                "Brewfile": [
                    "content": brewfileContent
                ]
            ]
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: payload) else {
            isSyncingGist = false
            return false
        }

        guard let url = URL(string: "https://api.github.com/gists") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = requestData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200 ... 201).contains(httpResponse.statusCode) else {
                isSyncingGist = false
                statusMessage = "Gist sync failed."
                return false
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let htmlURL = json["html_url"] as? String,
               let gistURL = URL(string: htmlURL) {
                self.lastGistURL = gistURL
                self.statusMessage = "Successfully synced to private Gist!"
                self.isSyncingGist = false
                return true
            }
        } catch {
            statusMessage = "Sync error: \(error.localizedDescription)"
        }

        isSyncingGist = false
        return false
    }
}
