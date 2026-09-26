import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DeveloperPackagingView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var packagingManager = BrewStorePackagingStudioManager.shared

    @State private var isCask = false
    @State private var packageName = ""
    @State private var packageVersion = "1.0.0"
    @State private var packageURL = ""
    @State private var packageSHA256 = ""
    @State private var packageDescription = ""
    @State private var packageHomepage = ""
    @State private var packageLicense = "MIT"
    @State private var binaryOrAppName = ""
    @State private var buildSystem = "Precompiled Binary"
    @State private var dependencyInput = ""
    @State private var dependencies: [String] = []

    @State private var copiedRuby = false
    @State private var publishStatusMessage: String?
    @State private var showingAuditSheet = false

    private let buildSystems = ["Precompiled Binary", "CMake", "Rust / Cargo", "Go", "Makefile"]

    private var generatedRecipe: String {
        if isCask {
            return packagingManager.generateCaskRecipe(
                name: packageName,
                version: packageVersion,
                url: packageURL,
                sha256: packageSHA256,
                desc: packageDescription,
                homepage: packageHomepage,
                appName: binaryOrAppName,
                bundleID: "com.example.\(packageName.lowercased())"
            )
        } else {
            return packagingManager.generateFormulaRecipe(
                name: packageName,
                version: packageVersion,
                url: packageURL,
                sha256: packageSHA256,
                desc: packageDescription,
                homepage: packageHomepage,
                license: packageLicense,
                dependencies: dependencies,
                buildSystem: buildSystem,
                binaryName: binaryOrAppName
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Formula & Cask Packaging Suite").font(.title2.bold())
                        Text("Create, audit, and publish custom Homebrew formulae and casks with automatic SHA256 hashing and sandboxed validation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Picker("Type", selection: $isCask) {
                        Text("Formula (CLI)").tag(false)
                        Text("Cask (macOS App)").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                Divider()

                // Form & Preview in side-by-side or stacked layout
                HStack(alignment: .top, spacing: 18) {
                    // Left Form Panel
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Package Configuration").font(.headline)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Name").font(.caption.bold())
                                TextField(isCask ? "e.g. MyMacApp" : "e.g. my-cli-tool", text: $packageName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Version").font(.caption.bold())
                                TextField("1.0.0", text: $packageVersion)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Source Archive URL or File Path").font(.caption.bold())
                            HStack(spacing: 8) {
                                TextField("https://github.com/user/repo/archive/v1.0.0.tar.gz", text: $packageURL)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = false
                                    panel.allowedContentTypes = [.init(filenameExtension: "tar.gz") ?? .gzip, .zip, .init(filenameExtension: "dmg") ?? .data, .data]
                                    if panel.runModal() == .OK, let url = panel.url {
                                        packageURL = url.path
                                        Task {
                                            if let hash = await packagingManager.computeSHA256(for: url) {
                                                packageSHA256 = hash
                                            }
                                        }
                                    }
                                } label: {
                                    Label("File…", systemImage: "folder")
                                }
                                .controlSize(.small)

                                if !packageURL.isEmpty, packageURL.hasPrefix("http") {
                                    Button {
                                        guard let u = URL(string: packageURL) else { return }
                                        Task {
                                            if let hash = await packagingManager.downloadAndComputeSHA256(from: u) {
                                                packageSHA256 = hash
                                            }
                                        }
                                    } label: {
                                        if packagingManager.isCalculatingSHA256 {
                                            ProgressView().controlSize(.mini)
                                        } else {
                                            Label("Hash URL", systemImage: "bolt.fill")
                                        }
                                    }
                                    .controlSize(.small)
                                    .disabled(packagingManager.isCalculatingSHA256)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("SHA-256 Checksum").font(.caption.bold())
                                Spacer()
                                if packageSHA256.count == 64 {
                                    Label("Valid Hex", systemImage: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.green)
                                }
                            }
                            TextField("Auto-calculated or enter 64-character hex", text: $packageSHA256)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description").font(.caption.bold())
                            TextField("Brief one-line summary of what this package does", text: $packageDescription)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Homepage").font(.caption.bold())
                                TextField("https://example.com", text: $packageHomepage)
                                    .textFieldStyle(.roundedBorder)
                            }

                            if !isCask {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("License").font(.caption.bold())
                                    TextField("MIT", text: $packageLicense)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 90)
                                }
                            }
                        }

                        if !isCask {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Build System").font(.caption.bold())
                                Picker("", selection: $buildSystem) {
                                    ForEach(buildSystems, id: \.self) { bs in
                                        Text(bs).tag(bs)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Dependencies").font(.caption.bold())
                                HStack(spacing: 6) {
                                    TextField("e.g. openssl@3", text: $dependencyInput)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Add") {
                                        let trimmed = dependencyInput.trimmingCharacters(in: .whitespaces)
                                        if !trimmed.isEmpty && !dependencies.contains(trimmed) {
                                            dependencies.append(trimmed)
                                            dependencyInput = ""
                                        }
                                    }
                                    .controlSize(.small)
                                }
                                if !dependencies.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(dependencies, id: \.self) { dep in
                                            HStack(spacing: 2) {
                                                Text(dep).font(.caption2.monospaced())
                                                Button {
                                                    dependencies.removeAll { $0 == dep }
                                                } label: {
                                                    Image(systemName: "xmark").font(.system(size: 8))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12), in: Capsule())
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(isCask ? "App Bundle Name" : "Binary Executable Name").font(.caption.bold())
                            TextField(isCask ? "e.g. MyApp.app" : "e.g. my-cli", text: $binaryOrAppName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                    .frame(width: 340)

                    // Right Ruby DSL Preview & Actions Panel
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Generated Ruby Recipe (\(packageName.isEmpty ? "recipe" : packageName.lowercased()).rb)")
                                .font(.headline)
                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(generatedRecipe, forType: .string)
                                copiedRuby = true
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    copiedRuby = false
                                }
                            } label: {
                                Label(copiedRuby ? "Copied!" : "Copy Ruby", systemImage: copiedRuby ? "checkmark" : "doc.on.doc")
                            }
                            .controlSize(.small)

                            Button {
                                exportRecipeFile()
                            } label: {
                                Label("Export…", systemImage: "square.and.arrow.down")
                            }
                            .controlSize(.small)
                        }

                        // Monospaced Code View
                        ScrollView {
                            Text(generatedRecipe)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                        .frame(minHeight: 280, maxHeight: 360)

                        // Sandboxed Validation & Publishing Actions
                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    _ = await packagingManager.runSandboxedAudit(recipeCode: generatedRecipe, isCask: isCask, manager: manager)
                                    showingAuditSheet = true
                                }
                            } label: {
                                if packagingManager.isRunningAudit {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Label("Run Sandboxed brew audit", systemImage: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.purple)
                            .controlSize(.small)
                            .disabled(packagingManager.isRunningAudit || manager.isOperating)

                            if !manager.taps.isEmpty {
                                Menu {
                                    ForEach(manager.taps) { tap in
                                        Button("Publish to \(tap.name)") {
                                            let res = packagingManager.publishToLocalTap(
                                                recipeCode: generatedRecipe,
                                                name: packageName.isEmpty ? "custom-package" : packageName,
                                                isCask: isCask,
                                                tap: tap,
                                                manager: manager
                                            )
                                            publishStatusMessage = res.message
                                        }
                                    }
                                } label: {
                                    Label("Publish to Local Tap", systemImage: "spigot.fill")
                                }
                                .menuStyle(.borderedButton)
                                .controlSize(.small)
                            }
                        }

                        if let status = publishStatusMessage {
                            Text(status)
                                .font(.caption.bold())
                                .foregroundStyle(Color.green)
                        }
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                }
            }
            .padding(Spacing.lg)
        }
        .sheet(isPresented: $showingAuditSheet) {
            if let res = packagingManager.auditResult {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(res.isSuccess ? "Audit Passed Cleanly" : "Audit Diagnostics Found", systemImage: res.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(res.isSuccess ? Color.green : Color.orange)
                        Spacer()
                        Button("Done") { showingAuditSheet = false }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    if res.isSuccess {
                        Text("The recipe adheres to Homebrew's strict formula guidelines and DSL syntax.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Issues Flagged by brew audit:").font(.caption.bold())
                            ForEach(res.issues, id: \.self) { issue in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(Color.orange)
                                        .font(.caption2)
                                        .padding(.top, 2)
                                    Text(issue).font(.caption.monospaced())
                                }
                            }
                        }
                    }

                    Divider()

                    Text("Raw Terminal Output:").font(.caption.bold())
                    ScrollView {
                        Text(res.rawOutput.isEmpty ? "No output." : res.rawOutput)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .frame(height: 140)
                }
                .padding(20)
                .frame(width: 520, height: 360)
            }
        }
    }

    private func exportRecipeFile() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        let name = packageName.isEmpty ? "package" : packageName.lowercased()
        savePanel.nameFieldStringValue = "\(name).rb"
        savePanel.allowedContentTypes = [.init(filenameExtension: "rb") ?? .plainText]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? generatedRecipe.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
