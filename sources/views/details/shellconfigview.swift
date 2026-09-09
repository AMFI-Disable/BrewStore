import AppKit
import SwiftUI

struct ShellConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @StateObject private var assistant = BrewStoreShellConfigAssistant()

    @State private var showingApplyConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .padding(8)
                    .background(Color.green.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Shell Environment Assistant").font(.title2.bold())
                        Text(assistant.detectedShell)
                            .font(.caption2.monospaced().bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    if let url = assistant.configURL {
                        Text(url.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let url = assistant.configURL {
                    Button("Reveal Config") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()
            .background(Color.secondary.opacity(0.04))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let msg = assistant.statusMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(msg).font(.caption.bold()).foregroundStyle(.green)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // BrewStore CLI Companion Tool
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BrewStore Terminal CLI Companion").font(.headline)
                        Text("Access BrewStore adoption, multi-version switching, and audits directly from your terminal with the 'brewstore' command.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Image(systemName: assistant.isCLIInstalled ? "checkmark.circle.fill" : "terminal")
                                .foregroundStyle(assistant.isCLIInstalled ? .green : .blue)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(assistant.isCLIInstalled ? "brewstore CLI is installed in PATH (~/.local/bin/brewstore)" : "Install 'brewstore' CLI helper to ~/.local/bin")
                                    .font(.subheadline.bold())
                                Text("Usage: brewstore adopt, brewstore switch, brewstore audit, brewstore mas")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !assistant.isCLIInstalled {
                                Button("Install CLI") {
                                    _ = assistant.installBrewStoreCLI()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Shell Integrations Table
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Detected Shell Integrations").font(.headline)
                        Text("BrewStore checks if your installed CLI packages are properly linked in your shell startup file.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(assistant.hooks) { hook in
                            HStack(spacing: 12) {
                                Image(systemName: hook.isConfiguredInShell ? "checkmark.circle.fill" : (hook.isInstalledLocally ? "exclamationmark.triangle.fill" : "circle.dashed"))
                                    .foregroundStyle(hook.isConfiguredInShell ? .green : (hook.isInstalledLocally ? .orange : .secondary))
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(hook.packageName).font(.headline)
                                        if hook.isConfiguredInShell {
                                            Text("Active in Shell")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.12), in: Capsule())
                                                .foregroundStyle(.green)
                                        } else if hook.isInstalledLocally {
                                            Text("Missing Configuration")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.12), in: Capsule())
                                                .foregroundStyle(.orange)
                                        } else {
                                            Text("Not Installed")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Text(hook.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                let snippet = (assistant.detectedShell == "fish") ? hook.fishSnippet : ((assistant.detectedShell == "bash") ? hook.bashSnippet : hook.zshSnippet)
                                Text(snippet)
                                    .font(.caption2.monospaced())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Proposed Snippet Block
                    if !assistant.generatedSnippet.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Pending Shell Additions").font(.headline)
                            Text("The following block will be appended to your shell configuration file. A backup is created automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(assistant.generatedSnippet)
                                .font(.caption.monospaced())
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                )

                            HStack {
                                Spacer()
                                Button {
                                    showingApplyConfirmation = true
                                } label: {
                                    Label("Apply to \(assistant.configURL?.lastPathComponent ?? "Shell Config")", systemImage: "sparkles")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Shell Configuration Is Up To Date")
                                    .font(.headline)
                                Text("All installed Homebrew shell integrations are active.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(20)
            }
            .onAppear {
                assistant.scanInstalledHooks(manager: manager)
            }
            .confirmationDialog("Apply Shell Environment Config?", isPresented: $showingApplyConfirmation, titleVisibility: .visible) {
                Button("Apply with Automatic Backup", role: .none) {
                    _ = assistant.applySnippetToShell(manager: manager)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("BrewStore will create a timestamped backup of your shell configuration before appending the new environment hooks.")
            }
        }
        .frame(minWidth: 760, minHeight: 540)
    }
}
