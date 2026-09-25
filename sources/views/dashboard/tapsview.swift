import AppKit
import SwiftUI

struct TapsView: View {
    @ObservedObject var manager: HomebrewManager
    @State private var newTap = ""
    @State private var search = ""
    @State private var tapToRemove: BrewStoreTap?
    @State private var tapToAdd: String?
    @State private var showingRemoveConfirmation = false
    @State private var showingTapDiscoverySheet = false
    @State private var showingTapHealthBenchmark = false
    @State private var tapInputError: String?
    @ObservedObject private var healthManager = BrewStoreTapHealthManager.shared

    private var filteredTaps: [BrewStoreTap] {
        if search.isEmpty {
            return manager.taps
        }
        return manager.taps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func packageCount(for tap: BrewStoreTap) -> Int {
        manager.packages.filter { $0.tap == tap.name }.count
    }

    var showHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Taps").font(.largeTitle.bold())
                        Text("Manage additional Homebrew repositories.").foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        showingTapHealthBenchmark = true
                    } label: {
                        Label("Health & Latency", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showingTapDiscoverySheet = true
                    } label: {
                        Label("Explore Taps", systemImage: "square.3.layers.3d.down.forward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: manager.refresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(manager.isLoading || manager.isOperating)
                }
                .padding()
            }

            HStack(spacing: Spacing.sm) {
                TextField("user/repository (e.g. homebrew/cask-fonts)", text: $newTap)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitNewTap()
                    }
                Button("Add Tap") {
                    submitNewTap()
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isOperating || newTap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !showHeader {
                    Button {
                        showingTapHealthBenchmark = true
                    } label: {
                        Label("Health & Latency", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showingTapDiscoverySheet = true
                    } label: {
                        Label("Explore Taps", systemImage: "square.3.layers.3d.down.forward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, showHeader ? 0 : Spacing.sm)
            .padding(.bottom, tapInputError == nil ? Spacing.sm : Spacing.xxs)

            if let tapInputError {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(tapInputError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xs)
            }

            HStack {
                BrewStoreSectionSearchBar(text: $search, placeholder: "Search taps & repositories…", count: filteredTaps.count)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            if let error = manager.errorMessage {
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else if manager.isOperating, let op = manager.activeOperationTitle {
                HStack {
                    Text(op)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            List(filteredTaps) { tap in
                NavigationLink {
                    TapDetailView(manager: manager, tap: tap)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.3.layers.3d.down.forward")
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tap.name).font(.headline)
                                if tap.isOfficial {
                                    Text("Official")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                            }

                            let count = packageCount(for: tap)
                            if count > 0 {
                                Text("\(count) package\(count == 1 ? "" : "s") installed")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let rep = healthManager.report(for: tap.name) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(rep.latencyColor)
                                    .frame(width: 6, height: 6)
                                Text(rep.formattedLatency)
                            }
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(rep.latencyColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(rep.latencyColor)

                            HStack(spacing: 3) {
                                Image(systemName: rep.status.iconName)
                                Text(rep.status.rawValue)
                            }
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(rep.status.color.opacity(0.12), in: Capsule())
                            .foregroundStyle(rep.status.color)
                        }

                        Button("Untap", role: .destructive) {
                            tapToRemove = tap
                            showingRemoveConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.isOperating)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Copy Tap Name") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(tap.name, forType: .string)
                        }

                        if let localURL = localTapURL(for: tap) {
                            Button("Show Tap in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([localURL])
                            }
                        }

                        if let url = URL(string: "https://github.com/\(tap.name)") {
                            Button("Open Tap on GitHub") {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        Divider()

                        Button("Untap…", role: .destructive) {
                            tapToRemove = tap
                            showingRemoveConfirmation = true
                        }
                        .disabled(manager.isOperating || !manager.isAvailable)
                    }
                }
            }
            .overlay {
                if let error = manager.errorMessage, manager.taps.isEmpty, !manager.isLoading {
                    let info = BrewStoreHumanizedErrorResolver.resolve(rawError: error)
                    ContentUnavailableView {
                        Label(info.title, systemImage: info.iconName)
                    } description: {
                        VStack(spacing: 6) {
                            Text(info.summary)
                            Text(info.suggestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } actions: {
                        HStack(spacing: 8) {
                            Button("Retry Refresh", action: manager.refresh)
                                .buttonStyle(.borderedProminent)

                            if info.category == .lock {
                                Button("Clear Locks") {
                                    manager.clearLocks()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } else if manager.taps.isEmpty, !manager.isLoading {
                    ContentUnavailableView("No custom taps", systemImage: "square.3.layers.3d.down.forward", description: Text("Add a third-party tap above."))
                } else if filteredTaps.isEmpty, !search.isEmpty {
                    ContentUnavailableView("No matching taps", systemImage: "magnifyingglass", description: Text("No taps match \"\(search)\"."))
                }
            }
        }
        .confirmationDialog("Untap Tap?", isPresented: $showingRemoveConfirmation, titleVisibility: .visible) {
            if let tap = tapToRemove {
                Button("Untap \(tap.name)", role: .destructive) {
                    manager.removeTap(tap)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let tap = tapToRemove {
                Text("Are you sure you want to untap '\(tap.name)'? Packages installed from this tap won't receive updates until tapped again.")
            }
        }
        .confirmationDialog(
            "Add Third-Party Tap?",
            isPresented: Binding(get: { tapToAdd != nil }, set: {
                if !$0 {
                    tapToAdd = nil
                }
            }),
            titleVisibility: .visible
        ) {
            if let tapName = tapToAdd {
                Button("Add Tap \(tapName)") {
                    manager.addTap(tapName)
                    newTap = ""
                    tapToAdd = nil
                }
            }
            Button("Cancel", role: .cancel) {
                tapToAdd = nil
            }
        } message: {
            if let tapName = tapToAdd {
                Text("Adding tap '\(tapName)' configures an external third-party Homebrew package repository on your Mac. Recipes from this tap will become available for installation via 'brew install'.")
            }
        }
        .sheet(isPresented: $showingTapDiscoverySheet) {
            TapDiscoveryView(manager: manager)
        }
        .sheet(isPresented: $showingTapHealthBenchmark) {
            TapHealthBenchmarkView(manager: manager)
        }
        .onAppear {
            if healthManager.reports.isEmpty {
                healthManager.auditAllTaps(taps: manager.taps, prefix: manager.brewPrefix)
            }
        }
        .onChange(of: newTap) { _, _ in
            if tapInputError != nil {
                tapInputError = nil
            }
        }
    }

    private func submitNewTap() {
        let value = newTap.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let isUserRepo = value.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
        let isURL = value.hasPrefix("https://") || value.hasPrefix("http://") || value.hasPrefix("git@")
        let isUserRepoWithURL = value.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\s+\S+$"#, options: .regularExpression) != nil

        guard isUserRepo || isURL || isUserRepoWithURL else {
            tapInputError = "Tap must be in 'user/repo' format or a repository URL (e.g. homebrew/cask-fonts or https://github.com/...)"
            return
        }
        tapInputError = nil
        tapToAdd = value
    }

    private func localTapURL(for tap: BrewStoreTap) -> URL? {
        guard let prefix = manager.brewPrefix else { return nil }
        let parts = tap.name.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let user = String(parts[0])
        let repo = String(parts[1])
        let candidate = URL(fileURLWithPath: prefix)
            .appendingPathComponent("Library/Taps", isDirectory: true)
            .appendingPathComponent(user, isDirectory: true)
            .appendingPathComponent(repo.hasPrefix("homebrew-") ? repo : "homebrew-\(repo)", isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
