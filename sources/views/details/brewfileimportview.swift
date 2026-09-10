import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BrewfileImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @StateObject private var importer = BrewStoreBrewfileImporter.shared

    @State private var entries: [ImportedBrewfileEntry] = []
    @State private var taps: [String] = []
    @State private var isTargeted = false
    @State private var selectedFilter = 0 // 0: Missing Only, 1: All Entries, 2: Installed

    private var filteredEntries: [ImportedBrewfileEntry] {
        switch selectedFilter {
        case 0:
            entries.filter { !$0.isInstalled }
        case 1:
            entries
        case 2:
            entries.filter(\.isInstalled)
        default:
            entries
        }
    }

    private var selectedMissingCount: Int {
        entries.filter { $0.isSelected && !$0.isInstalled }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if entries.isEmpty {
                dropZoneView
            } else {
                importDetailsView
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "doc.badge.plus")
                .font(.title2)
                .foregroundStyle(.blue)
                .padding(8)
                .background(Color.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Visual Brewfile Bundle Importer").font(.title2.bold())
                Text("Import software configurations, stacks, and restore bundles from any Brewfile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !entries.isEmpty {
                Button("Choose Another") {
                    entries = []
                    taps = []
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding()
        .background(Color.secondary.opacity(0.04))
    }

    private var dropZoneView: some View {
        VStack(spacing: 16) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.text.fill")
                .font(.system(size: 56))
                .foregroundStyle(isTargeted ? .blue : .secondary)

            VStack(spacing: 6) {
                Text("Drag & Drop your Brewfile here")
                    .font(.title3.bold())
                Text("Supports standard Brewfile, Brewfile.lock.json, or plain text brew/cask bundles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                selectFile()
            } label: {
                Label("Browse for Brewfile…", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(isTargeted ? Color.blue.opacity(0.08) : Color.clear)
        .onDrop(of: [UTType.fileURL.identifier, UTType.plainText.identifier], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private var importDetailsView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Picker("Filter", selection: $selectedFilter) {
                        Text("Missing (\(entries.filter { !$0.isInstalled }.count))").tag(0)
                        Text("All (\(entries.count))").tag(1)
                        Text("Installed (\(entries.filter(\.isInstalled).count))").tag(2)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()

                    Button {
                        BrewStoreActionReviewCoordinator.shared.requestBrewfileImport(
                            entries: entries,
                            taps: importer.importSummary?.taps ?? []
                        ) {
                            importer.installSelectedMissing(manager: manager, entries: entries, taps: importer.importSummary?.taps ?? [])
                            dismiss()
                        }
                    } label: {
                        Label("Install Selected (\(selectedMissingCount))", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedMissingCount == 0 || manager.isOperating)
                }

                HStack(spacing: 8) {
                    Button("Select All") {
                        for i in entries.indices where !entries[i].isInstalled {
                            entries[i].isSelected = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Deselect All") {
                        for i in entries.indices {
                            entries[i].isSelected = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    if !taps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Included Taps").font(.caption.bold()).foregroundStyle(.secondary)
                            HStack {
                                ForEach(taps, id: \.self) { tap in
                                    Text(tap)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 6)
                    }

                    ForEach($entries) { $entry in
                        if shouldShow(entry) {
                            HStack(spacing: 12) {
                                if !entry.isInstalled {
                                    Toggle("", isOn: $entry.isSelected)
                                        .labelsHidden()
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.title3)
                                }

                                Image(systemName: entry.kind == .cask ? "app.fill" : "terminal.fill")
                                    .foregroundStyle(entry.kind == .cask ? .blue : .green)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(entry.rawName).font(.headline)
                                        Text(entry.kind.rawValue)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.12), in: Capsule())
                                    }
                                    if let pkg = entry.matchedPackage, !pkg.description.isEmpty {
                                        Text(pkg.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if entry.isInstalled {
                                    Text("Installed")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.green)
                                } else if entry.matchedPackage != nil {
                                    Text("Ready to Install")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.blue)
                                } else {
                                    Text("Not in Catalog")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func shouldShow(_ entry: ImportedBrewfileEntry) -> Bool {
        switch selectedFilter {
        case 0: !entry.isInstalled
        case 1: true
        case 2: entry.isInstalled
        default: true
        }
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .data, UTType(filenameExtension: "Brewfile") ?? .plainText]

        if panel.runModal() == .OK, let url = panel.url {
            loadFile(url: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSURL.self) { object, _ in
            if let url = object as? NSURL {
                Task { @MainActor in
                    self.loadFile(url: url as URL)
                }
            }
        }
        return true
    }

    private func loadFile(url: URL) {
        if let summary = importer.parseBrewfile(from: url, manager: manager) {
            self.entries = summary.entries
            self.taps = summary.taps
        }
    }
}
