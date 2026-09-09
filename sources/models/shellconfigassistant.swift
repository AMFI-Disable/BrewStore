import Foundation

struct ShellIntegrationHook: Identifiable, Hashable {
    let id: String
    let packageName: String
    let description: String
    let zshSnippet: String
    let bashSnippet: String
    let fishSnippet: String
    var isInstalledLocally: Bool
    var isConfiguredInShell: Bool
}

@MainActor
final class BrewStoreShellConfigAssistant: ObservableObject {
    @Published var detectedShell: String = "zsh"
    @Published var configURL: URL?
    @Published var hooks: [ShellIntegrationHook] = []
    @Published var existingContent: String = ""
    @Published var generatedSnippet: String = ""
    @Published var statusMessage: String?
    @Published var lastBackupURL: URL?

    private let fileManager = FileManager.default

    private static let knownHooks: [ShellIntegrationHook] = [
        ShellIntegrationHook(
            id: "starship",
            packageName: "starship",
            description: "Initializes the fast Starship shell prompt.",
            zshSnippet: "eval \"$(starship init zsh)\"",
            bashSnippet: "eval \"$(starship init bash)\"",
            fishSnippet: "starship init fish | source",
            isInstalledLocally: false,
            isConfiguredInShell: false
        ),
        ShellIntegrationHook(
            id: "zoxide",
            packageName: "zoxide",
            description: "Enables smart directory jumping (`z <folder>`).",
            zshSnippet: "eval \"$(zoxide init zsh)\"",
            bashSnippet: "eval \"$(zoxide init bash)\"",
            fishSnippet: "zoxide init fish | source",
            isInstalledLocally: false,
            isConfiguredInShell: false
        ),
        ShellIntegrationHook(
            id: "fzf",
            packageName: "fzf",
            description: "Adds fuzzy search keybindings (CTRL+R, CTRL+T).",
            zshSnippet: "source <(fzf --zsh)",
            bashSnippet: "eval \"$(fzf --bash)\"",
            fishSnippet: "fzf --fish | source",
            isInstalledLocally: false,
            isConfiguredInShell: false
        ),
        ShellIntegrationHook(
            id: "bat-manpager",
            packageName: "bat",
            description: "Formats manual pages (`man`) with colored syntax highlighting.",
            zshSnippet: "export MANPAGER=\"sh -c 'col -bx | bat -l man -p'\"",
            bashSnippet: "export MANPAGER=\"sh -c 'col -bx | bat -l man -p'\"",
            fishSnippet: "set -gx MANPAGER \"sh -c 'col -bx | bat -l man -p'\"",
            isInstalledLocally: false,
            isConfiguredInShell: false
        ),
        ShellIntegrationHook(
            id: "node@20",
            packageName: "node@20",
            description: "Exports Node.js 20 LTS binary directory to your PATH.",
            zshSnippet: "export PATH=\"/opt/homebrew/opt/node@20/bin:$PATH\"",
            bashSnippet: "export PATH=\"/opt/homebrew/opt/node@20/bin:$PATH\"",
            fishSnippet: "fish_add_path /opt/homebrew/opt/node@20/bin",
            isInstalledLocally: false,
            isConfiguredInShell: false
        ),
        ShellIntegrationHook(
            id: "python@3.12",
            packageName: "python@3.12",
            description: "Exports Python 3.12 binary directory to your PATH.",
            zshSnippet: "export PATH=\"/opt/homebrew/opt/python@3.12/libexec/bin:$PATH\"",
            bashSnippet: "export PATH=\"/opt/homebrew/opt/python@3.12/libexec/bin:$PATH\"",
            fishSnippet: "fish_add_path /opt/homebrew/opt/python@3.12/libexec/bin",
            isInstalledLocally: false,
            isConfiguredInShell: false
        )
    ]

    init() {
        detectShellEnvironment()
    }

    func detectShellEnvironment() {
        let shellEnv = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shellEnv as NSString).lastPathComponent.lowercased()
        self.detectedShell = shellName

        let home = fileManager.homeDirectoryForCurrentUser
        if shellName == "fish" {
            let fishDir = home.appendingPathComponent(".config/fish", isDirectory: true)
            try? fileManager.createDirectory(at: fishDir, withIntermediateDirectories: true)
            self.configURL = fishDir.appendingPathComponent("config.fish")
        } else if shellName == "bash" {
            let bashrc = home.appendingPathComponent(".bash_profile")
            self.configURL = fileManager.fileExists(atPath: bashrc.path) ? bashrc : home.appendingPathComponent(".bashrc")
        } else {
            self.configURL = home.appendingPathComponent(".zshrc")
        }
    }

    func scanInstalledHooks(manager: HomebrewManager) {
        detectShellEnvironment()

        guard let configURL else { return }
        let content = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        self.existingContent = content

        var evaluatedHooks: [ShellIntegrationHook] = []
        var missingSnippets: [String] = []

        for item in Self.knownHooks {
            var hook = item
            let isInstalled = manager.packages.contains { $0.id == hook.packageName && $0.isInstalled }
            hook.isInstalledLocally = isInstalled

            let snippet = (detectedShell == "fish") ? hook.fishSnippet : ((detectedShell == "bash") ? hook.bashSnippet : hook.zshSnippet)
            let isConfigured = content.contains(snippet) || content.contains(hook.packageName)
            hook.isConfiguredInShell = isConfigured

            evaluatedHooks.append(hook)

            if isInstalled, !isConfigured {
                missingSnippets.append(snippet)
            }
        }

        self.hooks = evaluatedHooks
        if !missingSnippets.isEmpty {
            self.generatedSnippet = """

            # >>> BrewStore Environment Setup >>>
            \(missingSnippets.joined(separator: "\n"))
            # <<< BrewStore Environment Setup <<<
            """
        } else {
            self.generatedSnippet = ""
        }
    }

    func applySnippetToShell(manager: HomebrewManager) -> Bool {
        guard let configURL, !generatedSnippet.isEmpty else { return false }

        // 1. Create Timestamped Backup
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupFilename = "\(configURL.lastPathComponent).brewstore-bak-\(formatter.string(from: timestamp))"
        let backupURL = configURL.deletingLastPathComponent().appendingPathComponent(backupFilename)

        do {
            if fileManager.fileExists(atPath: configURL.path) {
                try fileManager.copyItem(at: configURL, to: backupURL)
                self.lastBackupURL = backupURL
            }

            // 2. Append new snippet
            let updatedContent = existingContent + generatedSnippet
            try updatedContent.write(to: configURL, atomically: true, encoding: .utf8)

            self.statusMessage = "Successfully updated \(configURL.lastPathComponent). Backup saved to \(backupFilename)."
            scanInstalledHooks(manager: manager)
            return true
        } catch {
            self.statusMessage = "Failed to update shell config: \(error.localizedDescription)"
            return false
        }
    }

    var isCLIInstalled: Bool {
        let home = fileManager.homeDirectoryForCurrentUser
        let localBin = home.appendingPathComponent(".local/bin/brewstore")
        let usrLocalBin = URL(fileURLWithPath: "/usr/local/bin/brewstore")
        return fileManager.isExecutableFile(atPath: localBin.path) || fileManager.isExecutableFile(atPath: usrLocalBin.path)
    }

    func installBrewStoreCLI() -> Bool {
        let home = fileManager.homeDirectoryForCurrentUser
        let localBinDir = home.appendingPathComponent(".local/bin", isDirectory: true)
        let targetURL = localBinDir.appendingPathComponent("brewstore")

        do {
            try fileManager.createDirectory(at: localBinDir, withIntermediateDirectories: true)
            let scriptContent = """
            #!/usr/bin/env bash
            open -a BrewStore 2>/dev/null || open "/Applications/BrewStore.app"
            """
            try scriptContent.write(to: targetURL, atomically: true, encoding: .utf8)
            var attributes = (try? fileManager.attributesOfItem(atPath: targetURL.path)) ?? [:]
            attributes[.posixPermissions] = 0o755
            try fileManager.setAttributes(attributes, ofItemAtPath: targetURL.path)
            self.statusMessage = "Installed brewstore CLI to ~/.local/bin/brewstore"
            return true
        } catch {
            self.statusMessage = "Failed to install CLI: \(error.localizedDescription)"
            return false
        }
    }
}
