import AppKit
import SwiftUI

struct TapDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @StateObject private var catalog = BrewStoreTapDiscoveryCatalog.shared

    @State private var selectedCategory: String = "All"
    @State private var searchText = ""
    @State private var tapToReview: CuratedTap?

    private var categories: [String] {
        ["All"] + catalog.allCategories
    }

    private var filteredTaps: [CuratedTap] {
        var list = BrewStoreTapDiscoveryCatalog.curatedTaps
        if selectedCategory != "All" {
            list = list.filter { $0.category == selectedCategory }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                    $0.id.lowercased().contains(q) ||
                    $0.description.lowercased().contains(q) ||
                    $0.featuredPackages.contains { $0.lowercased().contains(q) }
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            filterBar
            Divider()

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(filteredTaps) { tap in
                        tapCard(tap: tap)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .confirmationDialog(
            "Tap Third-Party Repository?",
            isPresented: Binding(get: { tapToReview != nil }, set: {
                if !$0 {
                    tapToReview = nil
                }
            }),
            titleVisibility: .visible
        ) {
            if let tap = tapToReview {
                Button("Tap \(tap.id)") {
                    manager.tap(name: tap.id)
                    tapToReview = nil
                }
            }
            Button("Cancel", role: .cancel) {
                tapToReview = nil
            }
        } message: {
            if let tap = tapToReview {
                Text("Tapping '\(tap.id)' adds third-party package definitions to your Homebrew environment. Packages from this repository will become available for installation via 'brew install'.")
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "square.3.layers.3d.down.forward")
                .font(.title2)
                .foregroundStyle(.purple)
                .padding(8)
                .background(Color.purple.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Third-Party Tap Explorer").font(.title2.bold())
                Text("Discover and tap curated community repositories for specialized fonts, dev tools, and packages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding()
        .background(Color.secondary.opacity(0.04))
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            selectedCategory = cat
                        } label: {
                            Text(cat)
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedCategory == cat ? Color.purple : Color.secondary.opacity(0.1), in: Capsule())
                                .foregroundStyle(selectedCategory == cat ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search taps or packages…", text: $searchText)
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
    }

    @ViewBuilder
    private func tapCard(tap: CuratedTap) -> some View {
        let isTapped = manager.taps.contains { $0.name.lowercased() == tap.id.lowercased() }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(tap.name).font(.headline)
                        Text(tap.category)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        if tap.isOfficial {
                            Text("Official")
                                .font(.caption2.bold())
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(tap.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isTapped {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Tapped")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())

                    Button("Untap") {
                        manager.untap(name: tap.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                } else {
                    Button {
                        tapToReview = tap
                    } label: {
                        Label("Tap Repository", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                }
            }

            Text(tap.description)
                .font(.callout)
                .foregroundStyle(.secondary)

            // Featured Packages Chips
            HStack(spacing: 6) {
                Text("Featured:").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(tap.featuredPackages, id: \.self) { pkg in
                    Text(pkg)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
