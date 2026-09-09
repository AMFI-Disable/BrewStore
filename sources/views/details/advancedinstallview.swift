import AppKit
import SwiftUI

struct CustomInstallOptions: Hashable, Codable {
    var buildFromSource: Bool = false
    var headCommit: Bool = false
    var forceInstall: Bool = false
    var ignoreDependencies: Bool = false
    var verbose: Bool = false
    var customArguments: String = ""

    func buildArguments(for package: BrewStorePackage) -> [String] {
        var args = [package.isInstalled ? "reinstall" : "install"]
        if package.kind == .cask {
            args.append("--cask")
        }
        if buildFromSource {
            args.append("--build-from-source")
        }
        if headCommit {
            args.append("--HEAD")
        }
        if forceInstall {
            args.append("--force")
        }
        if ignoreDependencies {
            args.append("--ignore-dependencies")
        }
        if verbose {
            args.append("--verbose")
        }

        let extra = customArguments.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        args.append(contentsOf: extra)
        args.append(package.id)
        return args
    }
}

struct AdvancedInstallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    let package: BrewStorePackage

    @State private var options = CustomInstallOptions()

    private var previewCommand: String {
        let args = options.buildArguments(for: package)
        return "brew \(args.joined(separator: " "))"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Command Preview Hero
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GENERATED HOMEBREW COMMAND").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(previewCommand)
                            .font(.system(.subheadline, design: .monospaced))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                    }

                    // Compilation Toggles
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Compilation & Source Options").font(.headline)

                        Toggle(isOn: $options.buildFromSource) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Build From Source (--build-from-source)").font(.subheadline.bold())
                                Text("Compile directly on your Mac instead of downloading pre-built binaries.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        Toggle(isOn: $options.headCommit) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Install from HEAD (--HEAD)").font(.subheadline.bold())
                                Text("Clone and build the latest unreleased commit directly from the master/main branch.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        Toggle(isOn: $options.forceInstall) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Force Overwrite (--force)").font(.subheadline.bold())
                                Text("Delete any existing conflicts and force a clean reinstall.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        Toggle(isOn: $options.ignoreDependencies) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ignore Dependencies (--ignore-dependencies)").font(.subheadline.bold())
                                Text("Skip installing prerequisite formulae (Advanced).")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        Toggle(isOn: $options.verbose) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Verbose Output (--verbose)").font(.subheadline.bold())
                                Text("Show detailed build output and compiler messages in the console.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                    // Custom Argument Input
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom Configure Arguments").font(.headline)
                        Text("Pass additional flags to the formula configure or make step.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("e.g. --with-custom-flag --cc=clang", text: $options.customArguments)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer Actions
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button {
                    let actionTitle = package.isInstalled ? "Custom Reinstall" : "Custom Install"
                    let customAction = PackageAction.custom(title: actionTitle, arguments: options.buildArguments(for: package))
                    dismiss()
                    manager.perform(package: package, action: customAction)
                } label: {
                    Label(package.isInstalled ? "Reinstall with Options" : "Run Advanced Install", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isOperating)
            }
            .padding()
            .background(Color.secondary.opacity(0.04))
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(.orange)
                .padding(8)
                .background(Color.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(package.isInstalled ? "Reinstallation Options" : "Advanced Installation Customizer").font(.title2.bold())
                Text(package.isInstalled ? "Configure compilation sources, HEAD commits, and flags to reinstall \(package.name)." : "Configure compilation sources, HEAD commits, and flags for \(package.name).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.04))
    }
}
