import AppKit
import SwiftUI

struct BrewStoreGlobalSearchBar: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var discovery: BrewStoreDiscoveryCatalog
    @Binding var selection: BrewStoreSection?
    var onOpenPackage: ((BrewStorePackage) -> Void)?
    var onOpenAISearch: ((String) -> Void)?

    @State private var query = ""
    @State private var selectedScope: GlobalSearchScope = .all
    @State private var isShowingResults = false
    @FocusState private var isFocused: Bool

    enum GlobalSearchScope: String, CaseIterable, Identifiable {
        case all = "All"
        case apps = "Apps"
        case cli = "CLI Tools"
        case installed = "Installed"

        var id: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .all: "sparkles"
            case .apps: "app.fill"
            case .cli: "terminal.fill"
            case .installed: "checkmark.circle.fill"
            }
        }
    }

    struct ScoredSearchResult: Identifiable {
        let id: String
        let package: BrewStorePackage
        let discoveryItem: BrewStoreDiscoveryItem?
        let score: Int
    }

    init(
        manager: HomebrewManager,
        discovery: BrewStoreDiscoveryCatalog,
        selection: Binding<BrewStoreSection?>,
        onOpenPackage: ((BrewStorePackage) -> Void)? = nil,
        onOpenAISearch: ((String) -> Void)? = nil
    ) {
        self.manager = manager
        self.discovery = discovery
        self._selection = selection
        self.onOpenPackage = onOpenPackage
        self.onOpenAISearch = onOpenAISearch
    }

    private var searchResults: [ScoredSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        let installedMap = Dictionary(manager.packages.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var results: [ScoredSearchResult] = []
        var seenIDs = Set<String>()

        // 1. Search through Discovery Catalog
        for item in discovery.items {
            let idLower = item.id.lowercased()
            let nameLower = item.name.lowercased()
            let descLower = item.description.lowercased()

            // Scope filter
            switch selectedScope {
            case .all: break
            case .apps: if item.kind != .cask {
                    continue
                }
            case .cli: if item.kind != .formula {
                    continue
                }
            case .installed: if installedMap[idLower]?.isInstalled != true {
                    continue
                }
            }

            var score = 0
            if idLower == trimmed || nameLower == trimmed {
                score = 100
            } else if idLower.hasPrefix(trimmed) || nameLower.hasPrefix(trimmed) {
                score = 80
            } else if idLower.contains(trimmed) || nameLower.contains(trimmed) {
                score = 60
            } else if descLower.contains(trimmed) || item.category.lowercased().contains(trimmed) {
                score = 40
            }

            if score > 0 {
                let pkg = installedMap[idLower] ?? BrewStorePackage(
                    id: item.id,
                    name: item.name,
                    description: item.description,
                    homepage: item.homepage,
                    version: item.version,
                    kind: item.kind
                )
                results.append(ScoredSearchResult(id: item.id, package: pkg, discoveryItem: item, score: score + min(20, item.installCount30Days / 5000)))
                seenIDs.insert(idLower)
            }
        }

        // 2. Search through locally installed packages not yet in discovery
        for pkg in manager.packages where !seenIDs.contains(pkg.id.lowercased()) {
            let idLower = pkg.id.lowercased()
            let nameLower = pkg.name.lowercased()
            let descLower = pkg.description.lowercased()

            switch selectedScope {
            case .all: break
            case .apps: if pkg.kind != .cask {
                    continue
                }
            case .cli: if pkg.kind != .formula {
                    continue
                }
            case .installed: if !pkg.isInstalled {
                    continue
                }
            }

            var score = 0
            if idLower == trimmed || nameLower == trimmed {
                score = 100
            } else if idLower.hasPrefix(trimmed) || nameLower.hasPrefix(trimmed) {
                score = 80
            } else if idLower.contains(trimmed) || nameLower.contains(trimmed) {
                score = 60
            } else if descLower.contains(trimmed) {
                score = 40
            }

            if score > 0 {
                results.append(ScoredSearchResult(id: pkg.id, package: pkg, discoveryItem: nil, score: score))
                seenIDs.insert(idLower)
            }
        }

        return results.sorted { $0.score > $1.score }.prefix(15).map { $0 }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFocused ? Color.accentColor : Color.secondary)

            TextField("BrewStore Search… (⌘F)", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular))
                .focused($isFocused)
                .onSubmit {
                    if let first = searchResults.first {
                        openPackage(first.package)
                    }
                }
                .onChange(of: query) { _, newQuery in
                    isShowingResults = !newQuery.trimmingCharacters(in: .whitespaces).isEmpty
                }
                .onChange(of: isFocused) { _, focused in
                    if focused, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        isShowingResults = true
                    }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    isShowingResults = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘F")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: isFocused || !query.isEmpty ? 260 : 210)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFocused)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: query.isEmpty)
        .popover(isPresented: $isShowingResults, arrowEdge: .bottom) {
            resultsPopoverContent
                .frame(width: 420, height: 420)
        }
        .keyboardShortcut("f", modifiers: .command)
    }

    // MARK: - Popover Content

    private var resultsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scope Filter Rail
            HStack(spacing: 6) {
                ForEach(GlobalSearchScope.allCases) { scope in
                    Button {
                        selectedScope = scope
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: scope.icon)
                                .font(.system(size: 10))
                            Text(scope.rawValue)
                                .font(.system(size: 11, weight: selectedScope == scope ? .bold : .regular))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedScope == scope ? Color.accentColor : Color.secondary.opacity(0.08), in: Capsule())
                        .foregroundStyle(selectedScope == scope ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(searchResults.count) results")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Results List
            if searchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No packages found for \"\(query)\"")
                        .font(.headline)
                    Text("Try switching scopes or ask the AI Assistant.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        isShowingResults = false
                        onOpenAISearch?(query)
                    } label: {
                        Label("Ask AI Assistant about \"\(query)\"", systemImage: "wand.and.stars")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(searchResults) { res in
                            resultRow(result: res)
                        }

                        // AI Assistant Recommendation Card
                        Button {
                            isShowingResults = false
                            onOpenAISearch?(query)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "wand.and.stars")
                                    .font(.caption.bold())
                                    .foregroundStyle(.purple)
                                Text("Ask AI Assistant for smart recommendations for \"\(query)\"")
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Footer Bar
            HStack {
                Text("Press ↵ to view top match")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("View all in Catalog →") {
                    isShowingResults = false
                    selection = .discover
                }
                .buttonStyle(.plain)
                .font(.caption2.bold())
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - Result Row

    @ViewBuilder
    private func resultRow(result: ScoredSearchResult) -> some View {
        let pkg = result.package
        let resolvedPkg = manager.packages.first { $0.id == pkg.id } ?? pkg

        Button {
            openPackage(resolvedPkg)
        } label: {
            HStack(spacing: 10) {
                // App Icon or Symbol
                if resolvedPkg.kind == .cask,
                   let icon = BrewStoreAppIconResolver.localAppIcon(for: resolvedPkg.applicationNames.isEmpty ? [resolvedPkg.name] : resolvedPkg.applicationNames) {
                    Image(nsImage: icon)
                        .resizable().scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(resolvedPkg.kind == .cask ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: resolvedPkg.kind == .cask ? "app.fill" : "terminal.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(resolvedPkg.kind == .cask ? Color.blue : Color.green)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(resolvedPkg.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        Text(resolvedPkg.kind == .cask ? "Cask" : "Formula")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)

                        if resolvedPkg.isInstalled {
                            Text("Installed")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.14), in: Capsule())
                                .foregroundStyle(.green)
                        }

                        if !resolvedPkg.version.isEmpty {
                            Text("v\(resolvedPkg.version)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        if let item = result.discoveryItem, item.installCount30Days > 0 {
                            PackageInstallCountBadge(packageID: item.id, kind: item.kind)
                        } else {
                            PackageInstallCountBadge(package: resolvedPkg)
                        }
                    }

                    Text(resolvedPkg.description.isEmpty ? "Homebrew package" : resolvedPkg.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                AppStoreActionButton(manager: manager, package: resolvedPkg, size: .small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func openPackage(_ pkg: BrewStorePackage) {
        isShowingResults = false
        onOpenPackage?(pkg)
    }
}
