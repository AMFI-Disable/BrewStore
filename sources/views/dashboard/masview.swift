import AppKit
import SwiftUI

struct MASView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @StateObject private var masManager = BrewStoreMASManager.shared
    @State private var searchText = ""

    private var filteredApps: [MASApp] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return masManager.installedApps
        }
        let q = searchText.lowercased()
        return masManager.installedApps.filter {
            $0.name.lowercased().contains(q) || $0.id.contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if !masManager.isMASInstalled && masManager.installedApps.isEmpty {
                installMASPromptView
            } else if masManager.isRefreshing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(masManager.isMASInstalled ? "Reading Mac App Store installations via mas-cli…" : "Scanning installed Mac App Store receipts…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                ContentUnavailableView(
                    "No Mac App Store Apps Found",
                    systemImage: "apple.logo",
                    description: Text("Ensure you have downloaded applications from the Mac App Store.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                appsListView
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            if masManager.installedApps.isEmpty {
                masManager.refresh()
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "apple.logo")
                .font(.title2)
                .foregroundStyle(.primary)
                .padding(8)
                .background(Color.secondary.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Mac App Store Bridge").font(.title2.bold())
                Text("Manage Mac App Store installations and updates directly alongside Homebrew.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if masManager.isMASInstalled {
                Button {
                    masManager.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(masManager.isRefreshing || masManager.isOperating)

                if !masManager.outdatedApps.isEmpty {
                    Button {
                        masManager.upgradeAll()
                    } label: {
                        Label("Update All MAS Apps (\(masManager.outdatedApps.count))", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(masManager.isOperating)
                }
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("MASView.DoneButton")
        }
        .padding()
        .background(Color.secondary.opacity(0.04))
    }

    private var installMASPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            VStack(spacing: 6) {
                Text("mas-cli is Required")
                    .font(.title2.bold())
                Text("To manage Mac App Store applications within BrewStore, install the official 'mas' Homebrew formula.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            Button {
                masManager.installMAS(manager: manager)
            } label: {
                Label("Install mas with Homebrew", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(manager.isOperating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var appsListView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(masManager.installedApps.count) Apps Installed")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                if !masManager.outdatedApps.isEmpty {
                    Text("• \(masManager.outdatedApps.count) Update\(masManager.outdatedApps.count == 1 ? "" : "s") Available")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search App Store apps…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .frame(width: 220)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            if !masManager.isMASInstalled {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Discovered via Native App Receipts")
                            .font(.subheadline.bold())
                        Text("Install the 'mas' CLI via Homebrew to enable 1-click updates and command-line management.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        masManager.installMAS(manager: manager)
                    } label: {
                        Label("Install mas CLI", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                }
                .padding(12)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredApps) { app in
                        HStack(spacing: 14) {
                            Image(systemName: "app.gift.fill")
                                .foregroundStyle(.blue)
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(app.name).font(.headline)
                                    Text("ID: \(app.id)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 6) {
                                    Text("v\(app.installedVersion)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let latest = app.latestVersion {
                                        Text("➔ v\(latest)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }

                            Spacer()

                            if !masManager.isMASInstalled {
                                Button("Open in App Store") {
                                    if let trackID = Int(app.id), let url = URL(string: "macappstore://apps.apple.com/app/id\(trackID)") {
                                        NSWorkspace.shared.open(url)
                                    } else if let encodedName = app.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                              let url = URL(string: "macappstore://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?q=\(encodedName)") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else if app.isOutdated {
                                Button("Update") {
                                    masManager.upgradeApp(app)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(masManager.isOperating)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title3)
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
                .padding(20)
            }
        }
    }
}
