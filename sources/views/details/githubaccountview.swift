import AppKit
import SwiftUI

struct GitHubAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accountManager: GitHubAccountManager
    @ObservedObject var manager: HomebrewManager
    @ObservedObject private var gitService = GitServiceManager.shared

    @State private var selectedProvider: GitServiceProvider = .github
    @State private var hostInput = ""
    @State private var tokenInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Top Bar
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        Text("Git Accounts & Cloud Sync").font(.title2.bold())
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }

                Text("Connect GitHub, GitLab, Codeberg, or custom self-hosted Forgejo/Gitea instances for cloud Brewfile backups, tap discovery, and developer tools.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                // Connected Accounts List
                if !gitService.accounts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connected Accounts (\(gitService.accounts.count))")
                            .font(.headline)

                        ForEach(gitService.accounts) { account in
                            HStack(spacing: 12) {
                                Image(systemName: account.provider.iconName)
                                    .font(.title2)
                                    .foregroundStyle(providerColor(account.provider))
                                    .frame(width: 36, height: 36)
                                    .background(providerColor(account.provider).opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(account.displayName).font(.subheadline.bold())
                                        Text(account.provider.displayName)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(providerColor(account.provider).opacity(0.15), in: Capsule())
                                            .foregroundStyle(providerColor(account.provider))
                                    }
                                    Text("\(account.hostKey) · @\(account.login)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if gitService.activeAccount?.id == account.id {
                                    Label("Active Sync", systemImage: "checkmark.circle.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Set Active") {
                                        gitService.setActiveAccount(id: account.id)
                                    }
                                    .controlSize(.small)
                                }

                                Button("Disconnect", role: .destructive) {
                                    gitService.removeAccount(id: account.id)
                                    if account.provider == .github {
                                        accountManager.disconnect()
                                    }
                                }
                                .controlSize(.small)
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }

                        // Cloud Brewfile Sync Card
                        if let active = gitService.activeAccount {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Cloud Brewfile Sync (\(active.provider.displayName))")
                                            .font(.headline)
                                        Text("Back up installed formulae, casks, and taps to a private \(active.provider == .github ? "Gist" : (active.provider == .gitlab ? "Snippet" : "repository")).")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()

                                    Button {
                                        Task {
                                            _ = await gitService.syncBrewfile(packages: manager.packages, taps: manager.taps)
                                        }
                                    } label: {
                                        if gitService.isSyncing {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath.icloud.fill")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(gitService.isSyncing || manager.isOperating)
                                }

                                if let lastURL = gitService.lastSyncURL {
                                    HStack {
                                        Text("Backup: \(lastURL.absoluteString)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        Button("Open in Browser") {
                                            NSWorkspace.shared.open(lastURL)
                                        }
                                        .controlSize(.small)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(14)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    Divider()
                }

                // Add / Connect New Account Section
                VStack(alignment: .leading, spacing: 14) {
                    Text("Connect a Git Account")
                        .font(.headline)

                    Picker("Service Provider", selection: $selectedProvider) {
                        ForEach(GitServiceProvider.allCases) { provider in
                            Label(provider.displayName, systemImage: provider.iconName)
                                .tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedProvider == .gitlab || selectedProvider == .custom {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Instance Host URL").font(.caption.bold())
                            TextField(selectedProvider == .gitlab ? "https://gitlab.com" : "https://git.example.com", text: $hostInput)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedProvider.tokenScopeHelp).font(.caption).foregroundStyle(.secondary)
                        SecureField("Personal Access Token", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        if let tokenURL = selectedProvider.tokenCreationURL(host: hostInput.isEmpty ? nil : hostInput) {
                            Button("Generate Token on \(selectedProvider.displayName)") {
                                NSWorkspace.shared.open(tokenURL)
                            }
                            .controlSize(.small)
                        }

                        Spacer()

                        Button {
                            Task {
                                let effectiveHost = (selectedProvider == .gitlab || selectedProvider == .custom) && !hostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? hostInput
                                    : nil
                                let success = await gitService.connectAccount(provider: selectedProvider, host: effectiveHost, token: tokenInput)
                                if success {
                                    tokenInput = ""
                                    if selectedProvider == .github {
                                        accountManager.loadStoredToken()
                                    }
                                }
                            }
                        } label: {
                            if gitService.isVerifying {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Connect Account")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || gitService.isVerifying)
                    }

                    if let status = gitService.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.contains("failed") || status.contains("error") ? .red : .green)
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
        .frame(minWidth: 580, minHeight: 480)
    }

    private func providerColor(_ provider: GitServiceProvider) -> Color {
        switch provider {
        case .github: .purple
        case .gitlab: .orange
        case .codeberg: .blue
        case .custom: .teal
        }
    }
}
