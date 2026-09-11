import AppKit
import SwiftUI

struct WishlistView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject private var wishlistManager = BrewStoreWishlistManager.shared
    @ObservedObject private var pinningManager = BrewStorePackagePinningManager.shared

    @State private var selectedTab = 0 // 0: Wishlist, 1: Collections
    @State private var selectedPackageForDetail: BrewStorePackage?
    @State private var showingCreateCollectionSheet = false
    @State private var newCollectionTitle = ""
    @State private var newCollectionDescription = ""
    @State private var copiedBrewfile = false
    @State private var searchQuery = ""

    private var allWishlistedPackages: [BrewStorePackage] {
        wishlistManager.wishlistIDs.compactMap { id in
            if let installed = manager.packages.first(where: { $0.id == id }) {
                return installed
            }
            return BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: .formula)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var wishlistedPackages: [BrewStorePackage] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allWishlistedPackages }
        return allWishlistedPackages.filter {
            $0.name.lowercased().contains(q) ||
                $0.id.lowercased().contains(q) ||
                $0.description.lowercased().contains(q)
        }
    }

    var showHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                headerBar
            }
            tabPicker
            Divider()

            ScrollView {
                if selectedTab == 0 {
                    wishlistContent
                } else {
                    collectionsContent
                }
            }
            .id(selectedTab)
            .animation(nil, value: selectedTab)
        }
        .detailModalOverlay(item: $selectedPackageForDetail) { pkg in
            PackageDetailView(manager: manager, package: pkg, onDismiss: {
                selectedPackageForDetail = nil
            })
        }
        .sheet(isPresented: $showingCreateCollectionSheet) {
            createCollectionSheet
        }
    }

    private var copyBrewfileButton: some View {
        Button {
            let text = wishlistManager.exportToBrewfile(packageIDs: Array(wishlistManager.wishlistIDs), manager: manager)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedBrewfile = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                copiedBrewfile = false
            }
        } label: {
            Label(copiedBrewfile ? "Copied Brewfile!" : "Copy as Brewfile", systemImage: copiedBrewfile ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private var newCollectionButton: some View {
        if selectedTab == 1 {
            Button {
                showingCreateCollectionSheet = true
            } label: {
                Label("New Collection", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Wishlist & Collections").font(.largeTitle.bold())
                Text("Save tools for later and organize packages into exportable bundles.")
                    .foregroundStyle(.secondary)
            }
            Spacer()

            copyBrewfileButton
            newCollectionButton
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private var tabPicker: some View {
        HStack(spacing: Spacing.sm) {
            Picker("View Mode", selection: $selectedTab) {
                Text("Starred Wishlist (\(wishlistManager.wishlistIDs.count))").tag(0)
                Text("Custom Collections (\(wishlistManager.collections.count))").tag(1)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)

            Spacer()

            BrewStoreSectionSearchBar(text: $searchQuery, placeholder: "Search saved packages…", count: wishlistedPackages.count)
                .frame(minWidth: 160, maxWidth: 240)

            if !showHeader {
                copyBrewfileButton
                newCollectionButton
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, showHeader ? 0 : Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }

    @ViewBuilder
    private var wishlistContent: some View {
        if allWishlistedPackages.isEmpty {
            ContentUnavailableView(
                "Your Wishlist is Empty",
                systemImage: "star.slash",
                description: Text("Click the star icon on any package to save it to your wishlist.")
            )
            .padding(.top, Spacing.xl)
        } else if wishlistedPackages.isEmpty {
            ContentUnavailableView(
                "No Matching Packages",
                systemImage: "magnifyingglass",
                description: Text("No wishlisted packages match \"\(searchQuery)\".")
            )
            .padding(.top, Spacing.xl)
        } else {
            LazyVStack(spacing: Spacing.xs) {
                ForEach(wishlistedPackages) { pkg in
                    wishlistRow(package: pkg)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
    }

    @ViewBuilder
    private func wishlistRow(package: BrewStorePackage) -> some View {
        let isPinned = pinningManager.isPinned(packageID: package.id)

        HStack(spacing: 12) {
            Image(systemName: package.kind == .cask ? "app.fill" : "terminal.fill")
                .font(.title2)
                .foregroundStyle(package.kind == .cask ? Color.blue : Color.green)
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name).font(.headline)

                    if package.isInstalled {
                        Text("Installed")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Text(package.description.isEmpty ? (package.kind == .cask ? "macOS Application" : "Command-line tool") : package.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if package.isInstalled {
                Button {
                    pinningManager.togglePin(package: package, manager: manager)
                } label: {
                    Image(systemName: isPinned ? "pin.slash" : "pin")
                }
                .controlSize(.small)
                .help(isPinned ? "Unpin this package" : "Pin this package to prevent updates")
            }

            Button {
                wishlistManager.toggleWishlist(id: package.id)
            } label: {
                Image(systemName: "star.slash")
            }
            .controlSize(.small)
            .help("Remove from wishlist")

            Button {
                selectedPackageForDetail = package
            } label: {
                Text("Details")
            }
            .controlSize(.small)

            if !package.isInstalled {
                Button("Install") {
                    manager.perform(package: package, action: .install)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manager.isOperating)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var collectionsContent: some View {
        if wishlistManager.collections.isEmpty {
            ContentUnavailableView(
                "No Custom Collections",
                systemImage: "folder.badge.plus",
                description: Text("Group packages into organized stacks like 'Design Rig' or 'DevOps Tools'.")
            )
            .padding(.top, Spacing.xl)
        } else {
            let filtered = wishlistManager.collections.filter { col in
                let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !q.isEmpty else { return true }
                return col.title.lowercased().contains(q) ||
                    col.description.lowercased().contains(q) ||
                    col.packageIDs.contains { $0.lowercased().contains(q) }
            }

            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Matching Collections",
                    systemImage: "magnifyingglass",
                    description: Text("No collections match \"\(searchQuery)\".")
                )
                .padding(.top, Spacing.xl)
            } else {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(filtered) { col in
                        collectionCard(collection: col)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    private func collectionCard(collection: BrewStoreCollection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.title).font(.headline.bold())
                    if !collection.description.isEmpty {
                        Text(collection.description).font(.caption).foregroundStyle(.secondary)
                    }
                }

                let missingIDs = collection.packageIDs.filter { id in
                    manager.packages.first(where: { $0.id.lowercased() == id.lowercased() })?.isInstalled != true
                }
                if !missingIDs.isEmpty {
                    Button {
                        let pkgs = missingIDs.compactMap { id in
                            manager.packages.first(where: { $0.id.lowercased() == id.lowercased() }) ?? BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: .formula)
                        }
                        if !pkgs.isEmpty {
                            BrewStoreActionReviewCoordinator.shared.requestInstall(packages: pkgs, manager: manager) {
                                manager.batchPerform(packages: pkgs, action: .install)
                            }
                        }
                    } label: {
                        Label("Install Missing (\(missingIDs.count))", systemImage: "arrow.down.circle")
                    }
                    .controlSize(.small)
                }

                Button {
                    let text = wishlistManager.exportToBrewfile(packageIDs: collection.packageIDs, manager: manager)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Export", systemImage: "doc.on.doc")
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    BrewStoreActionReviewCoordinator.shared.requestWishlistCollectionDelete(collection: collection) {
                        wishlistManager.deleteCollection(id: collection.id)
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete Collection")
            }

            Divider()

            if collection.packageIDs.isEmpty {
                Text("No packages in this collection yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 8) {
                    ForEach(collection.packageIDs, id: \.self) { id in
                        let pkg = manager.packages.first(where: { $0.id == id }) ?? BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: .formula)
                        HStack {
                            Image(systemName: pkg.kind == .cask ? "app.fill" : "terminal.fill")
                                .font(.caption)
                                .foregroundStyle(pkg.kind == .cask ? .blue : .green)
                            Text(pkg.name).font(.caption.bold()).lineLimit(1)
                            Spacer()
                            Button {
                                selectedPackageForDetail = pkg
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
    }

    private var createCollectionSheet: some View {
        VStack(spacing: 16) {
            Text("New Custom Collection").font(.headline)

            TextField("Collection Name (e.g. Video Suite)", text: $newCollectionTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $newCollectionDescription)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { showingCreateCollectionSheet = false }
                Spacer()
                Button {
                    let title = newCollectionTitle.trimmingCharacters(in: .whitespaces)
                    guard !title.isEmpty else { return }
                    wishlistManager.createCollection(title: title, description: newCollectionDescription, packageIDs: [], colorName: "blue")
                    newCollectionTitle = ""
                    newCollectionDescription = ""
                    showingCreateCollectionSheet = false
                } label: {
                    Text("Create Collection")
                }
                .buttonStyle(.borderedProminent)
                .disabled(newCollectionTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
