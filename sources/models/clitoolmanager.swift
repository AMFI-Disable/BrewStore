import AppKit
import Foundation

@MainActor
final class BrewStoreCLIToolManager: ObservableObject {
    static let shared = BrewStoreCLIToolManager()

    @Published var isInstalled = false
    @Published var installedPath: String?
    @Published var statusMessage: String?
    @Published var isOperating = false
    @Published var completionsInstalled = false

    private let fileManager = FileManager.default

    init() {
        checkInstallationStatus()
    }

    // MARK: - Path Resolution

    var bundledScriptPath: String? {
        // First check inside main app bundle Resources
        if let bundlePath = Bundle.main.path(forResource: "brewstore", ofType: nil, inDirectory: "scripts") {
            return bundlePath
        }
        if let resourceURL = Bundle.main.resourceURL {
            let direct = resourceURL.appendingPathComponent("scripts/brewstore").path
            if fileManager.fileExists(atPath: direct) {
                return direct
            }
        }
        // Fallback for local development / testing
        let localWorkspace = "/Users/even/Desktop/Projects/Apps/BrewStore/scripts/brewstore"
        if fileManager.fileExists(atPath: localWorkspace) {
            return localWorkspace
        }
        let appBundlePath = "/Applications/BrewStore.app/Contents/Resources/scripts/brewstore"
        if fileManager.fileExists(atPath: appBundlePath) {
            return appBundlePath
        }
        return nil
    }

    var primaryInstallPath: String {
        let home = fileManager.homeDirectoryForCurrentUser.path
        return "\(home)/.local/bin/brewstore"
    }

    var fallbackInstallPath: String {
        "/usr/local/bin/brewstore"
    }

    // MARK: - Status Checking

    func checkInstallationStatus() {
        let primary = primaryInstallPath
        let fallback = fallbackInstallPath

        if fileManager.isExecutableFile(atPath: primary) {
            isInstalled = true
            installedPath = primary
        } else if fileManager.isExecutableFile(atPath: fallback) {
            isInstalled = true
            installedPath = fallback
        } else {
            isInstalled = false
            installedPath = nil
        }

        checkCompletionsStatus()
    }

    private func checkCompletionsStatus() {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let zshCompletion = "\(home)/.zsh/completions/_brewstore"
        let fishCompletion = "\(home)/.config/fish/completions/brewstore.fish"
        let bashCompletion = "\(home)/.bash_completion.d/brewstore.bash"

        completionsInstalled = fileManager.fileExists(atPath: zshCompletion) ||
            fileManager.fileExists(atPath: fishCompletion) ||
            fileManager.fileExists(atPath: bashCompletion)
    }

    // MARK: - Symlink Installation

    func installCLISymlink() {
        guard let sourceScript = bundledScriptPath else {
            statusMessage = "Could not locate the bundled BrewStore CLI helper tool in the application bundle."
            return
        }

        isOperating = true
        defer { isOperating = false }

        let targetPath = primaryInstallPath
        let targetDirectory = (targetPath as NSString).deletingLastPathComponent

        do {
            try fileManager.createDirectory(atPath: targetDirectory, withIntermediateDirectories: true)

            // Remove existing symlink or file if present
            if fileManager.fileExists(atPath: targetPath) {
                try fileManager.removeItem(atPath: targetPath)
            }

            try fileManager.createSymbolicLink(atPath: targetPath, withDestinationPath: sourceScript)

            // Ensure executable permissions on target
            let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
            try fileManager.setAttributes(attributes, ofItemAtPath: targetPath)

            isInstalled = true
            installedPath = targetPath
            statusMessage = "Successfully installed brewstore to \(targetPath)"
        } catch {
            statusMessage = "Installation failed: \(error.localizedDescription)"
        }
    }

    func uninstallCLISymlink() {
        isOperating = true
        defer { isOperating = false }

        var removedAny = false
        for path in [primaryInstallPath, fallbackInstallPath] {
            if fileManager.fileExists(atPath: path) {
                do {
                    try fileManager.removeItem(atPath: path)
                    removedAny = true
                } catch {
                    statusMessage = "Uninstall failed: \(error.localizedDescription)"
                    return
                }
            }
        }

        isInstalled = false
        installedPath = nil
        statusMessage = removedAny ? "Successfully uninstalled brewstore CLI tool." : "No CLI symlink found to remove."
    }

    // MARK: - Shell Completions Installation

    func installShellCompletions() {
        isOperating = true
        defer { isOperating = false }

        let home = fileManager.homeDirectoryForCurrentUser.path
        var installedCount = 0

        // 1. Zsh
        let zshDir = "\(home)/.zsh/completions"
        let zshFile = "\(zshDir)/_brewstore"
        if writeString(Self.generateZshCompletion(), toDirectory: zshDir, filePath: zshFile) {
            installedCount += 1
        }

        // 2. Fish
        let fishDir = "\(home)/.config/fish/completions"
        let fishFile = "\(fishDir)/brewstore.fish"
        if writeString(Self.generateFishCompletion(), toDirectory: fishDir, filePath: fishFile) {
            installedCount += 1
        }

        // 3. Bash
        let bashDir = "\(home)/.bash_completion.d"
        let bashFile = "\(bashDir)/brewstore.bash"
        if writeString(Self.generateBashCompletion(), toDirectory: bashDir, filePath: bashFile) {
            installedCount += 1
        }

        completionsInstalled = installedCount > 0
        statusMessage = installedCount > 0
            ? "Installed completions for \(installedCount) shells (zsh, fish, bash)."
            : "Failed to install shell completions."
    }

    private func writeString(_ content: String, toDirectory dir: String, filePath: String) -> Bool {
        do {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: filePath) {
                try fileManager.removeItem(atPath: filePath)
            }
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Completion Generators

    static func generateZshCompletion() -> String {
        """
        #compdef brewstore

        _brewstore() {
            local -a commands
            commands=(
                'adopt:Scan /Applications for unmanaged apps and adopt them into Homebrew'
                'switch:Switch active symlinked version (e.g. node 20)'
                'audit:Run CVE and security vulnerability audit on packages'
                'mas:Manage Mac App Store applications via mas-cli'
                'health:Evaluate local Homebrew health score and disk storage'
                'clean:Reclaim disk space via cache cleanup and orphan autoremove'
                'devclean:Purge developer caches (Xcode, Docker, Cargo, npm)'
                'blueprint:Export or restore complete Mac setup blueprint'
                'completions:Print shell completion scripts (zsh, bash, fish)'
                'install-cli:Install brewstore symlink and completions'
                'launch:Launch the BrewStore native GUI app'
                'version:Display BrewStore version'
                'help:Show command line help'
            )

            if (( CURRENT == 2 )); then
                _describe -t commands 'brewstore command' commands
                return
            fi

            case $words[2] in
                adopt)
                    _values 'options' '--all[Adopt all detected applications]'
                    ;;
                mas)
                    _values 'subcommands' 'list[List installed apps]' 'upgrade[Upgrade outdated apps]' 'outdated[Show outdated apps]'
                    ;;
                blueprint)
                    _values 'subcommands' 'export[Export Mac Blueprint JSON]' 'restore[Restore Mac Blueprint from file]'
                    ;;
                completions)
                    _values 'shells' 'zsh[Zsh completions]' 'bash[Bash completions]' 'fish[Fish completions]'
                    ;;
            esac
        }

        _brewstore "$@"
        """
    }

    static func generateBashCompletion() -> String {
        """
        #!/usr/bin/env bash

        _brewstore_completions() {
            local cur prev commands
            COMPREPLY=()
            cur="${COMP_WORDS[COMP_CWORD]}"
            prev="${COMP_WORDS[COMP_CWORD-1]}"
            commands="adopt switch audit mas health clean devclean blueprint completions install-cli launch version help"

            if [[ ${COMP_CWORD} -eq 1 ]]; then
                COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
                return 0
            fi

            case "${prev}" in
                adopt)
                    COMPREPLY=( $(compgen -W "--all" -- ${cur}) )
                    ;;
                mas)
                    COMPREPLY=( $(compgen -W "list upgrade outdated" -- ${cur}) )
                    ;;
                blueprint)
                    COMPREPLY=( $(compgen -W "export restore" -- ${cur}) )
                    ;;
                completions)
                    COMPREPLY=( $(compgen -W "zsh bash fish" -- ${cur}) )
                    ;;
            esac
        }

        complete -F _brewstore_completions brewstore
        """
    }

    static func generateFishCompletion() -> String {
        """
        # fish completion for brewstore

        set -l commands adopt switch audit mas health clean devclean blueprint completions install-cli launch version help

        complete -c brewstore -f
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a adopt -d "Scan and adopt unmanaged macOS apps"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a switch -d "Switch active version symlinks"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a audit -d "Run CVE security vulnerability scan"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a mas -d "Manage Mac App Store apps"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a health -d "Evaluate Homebrew health score"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a clean -d "Clean package download caches"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a devclean -d "Purge developer tooling caches"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a blueprint -d "Export or restore Mac blueprint"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a completions -d "Print shell completion script"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a install-cli -d "Install brewstore CLI symlink"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a launch -d "Launch the BrewStore GUI app"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a version -d "Show version"
        complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a help -d "Show usage help"
        """
    }
}
