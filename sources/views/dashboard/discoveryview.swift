import AppKit
import SwiftUI

enum DiscoveryStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Status"
    case installed = "Installed"
    case outdated = "Updates"
    case notInstalled = "Not Installed"

    var id: String {
        rawValue
    }
}

enum DiscoveryViewMode: String, CaseIterable, Identifiable, Sendable {
    case spotlight = "Spotlight"
    case allApps = "All Apps"
    case allFormulae = "All CLI Tools"
    case allCatalog = "All Packages"

    var id: String {
        rawValue
    }
}

enum DiscoverySortOrder: String, CaseIterable, Identifiable, Sendable {
    case popular = "Most Popular"
    case nameAsc = "Name (A → Z)"
    case nameDesc = "Name (Z → A)"

    var id: String {
        rawValue
    }
}

struct DiscoveryView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var catalog: BrewStoreDiscoveryCatalog
    @State private var viewMode: DiscoveryViewMode
    @State private var search = ""
    @State private var selectedKind: BrewPackageKind?
    @State private var selectedCategory = "All"
    @State private var selectedStatus: DiscoveryStatusFilter = .all
    @State private var selectedSort: DiscoverySortOrder = .popular
    @State private var selectedTap = "All Taps"
    @State private var selectedItem: BrewStoreDiscoveryItem?
    @State private var selectedStory: BrewStoreStory?
    @State private var displayLimit = 150
    @AppStorage("brewstore_compact_discovery_view") private var isCompactView = false

    @State private var isTrendingLeaderboard = false
    @State private var onlineResults: [BrewStorePackage] = []
    @State private var isSearchingOnline = false
    @State private var selectedOnlinePackage: BrewStorePackage?

    var onModeChange: ((DiscoveryViewMode) -> Void)?

    private var hasActiveFilters: Bool {
        selectedCategory != "All" || selectedTap != "All Taps" || selectedStatus != .all || !search.isEmpty
    }

    private func resetFilters() {
        search = ""
        selectedCategory = "All"
        selectedTap = "All Taps"
        selectedStatus = .all
        selectedSort = .popular
    }

    init(manager: HomebrewManager, catalog: BrewStoreDiscoveryCatalog, initialMode: DiscoveryViewMode = .spotlight, onModeChange: ((DiscoveryViewMode) -> Void)? = nil) {
        self.manager = manager
        self.catalog = catalog
        self.onModeChange = onModeChange
        self._viewMode = State(initialValue: initialMode)
        switch initialMode {
        case .allApps:
            self._selectedKind = State(initialValue: .cask)
        case .allFormulae:
            self._selectedKind = State(initialValue: .formula)
        case .spotlight, .allCatalog:
            self._selectedKind = State(initialValue: nil)
        }
    }

    @State private var filteredItems: [BrewStoreDiscoveryItem] = []
    @State private var popularItemsList: [BrewStoreDiscoveryItem] = []
    @State private var newlyDiscoveredItemsList: [BrewStoreDiscoveryItem] = []
    @State private var leaderboardItemsList: [BrewStoreDiscoveryItem] = []
    @State private var categoriesList: [String] = ["All", "Editor's Picks"]
    @State private var availableTapsList: [String] = ["All Taps"]
    @State private var totalAppsCount: Int = 0
    @State private var totalFormulaeCount: Int = 0
    @State private var filterTask: Task<Void, Never>?

    private var availableTaps: [String] {
        availableTapsList
    }

    private var categories: [String] {
        categoriesList
    }

    private var visibleItems: [BrewStoreDiscoveryItem] {
        filteredItems
    }

    private var popularItems: [BrewStoreDiscoveryItem] {
        popularItemsList
    }

    private var newlyDiscoveredItems: [BrewStoreDiscoveryItem] {
        newlyDiscoveredItemsList
    }

    private var leaderboardItems: [BrewStoreDiscoveryItem] {
        leaderboardItemsList
    }

    private var effectiveKind: BrewPackageKind? {
        switch viewMode {
        case .spotlight: selectedKind
        case .allApps: .cask
        case .allFormulae: .formula
        case .allCatalog: selectedKind
        }
    }

    private var headerTitle: String {
        switch viewMode {
        case .spotlight: "Discover"
        case .allApps: "All Applications"
        case .allFormulae: "All Command-Line Tools"
        case .allCatalog: "Homebrew Catalog"
        }
    }

    private var freshnessSuffix: String {
        if let last = catalog.lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return " · Synced \(formatter.localizedString(for: last, relativeTo: Date()))"
        } else if let last = manager.lastRefreshedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return " · Synced \(formatter.localizedString(for: last, relativeTo: Date()))"
        }
        return ""
    }

    private var headerSubtitle: String {
        let base: String
        switch viewMode {
        case .spotlight:
            base = "\(catalog.items.count) packages available (\(totalAppsCount) apps, \(totalFormulaeCount) CLI tools)"
        case .allApps:
            let installedCasks = manager.packages.filter { $0.kind == .cask && $0.isInstalled }.count
            base = "\(totalAppsCount) macOS applications · \(installedCasks) installed"
        case .allFormulae:
            let installedFormulae = manager.packages.filter { $0.kind == .formula && $0.isInstalled }.count
            base = "\(totalFormulaeCount) developer tools & libraries · \(installedFormulae) installed"
        case .allCatalog:
            base = "\(catalog.items.count) packages total · \(manager.packages.filter(\.isInstalled).count) installed locally"
        }
        return "\(base)\(freshnessSuffix)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sleek, well-spaced top bar: Row 1 has Title & Actions; Row 2 has Mode Picker
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(headerTitle).font(.title2.bold())
                        Text(headerSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    actionsGroup
                }

                HStack {
                    modePicker
                    Spacer()
                }

                filterBar
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)
            .animation(.easeInOut(duration: 0.2), value: viewMode)

            List {
                // Editor's Pick Hero Spotlight (Featured in Spotlight mode)
                if viewMode == .spotlight, !isTrendingLeaderboard, search.isEmpty, selectedCategory == "All" {
                    Section {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            EditorialHeroView(manager: manager) { pick in
                                if let story = BrewStoreStory.story(containingPackageID: pick.id) {
                                    selectedStory = story
                                } else if let found = catalog.items.first(where: { $0.id == pick.id }) {
                                    selectedItem = found
                                } else {
                                    selectedOnlinePackage = BrewStorePackage(
                                        id: pick.id,
                                        name: pick.name,
                                        description: pick.headline,
                                        homepage: "",
                                        version: "",
                                        kind: pick.kind
                                    )
                                }
                            }
                            .padding(.top, Spacing.xs)

                            // Trending This Week Shelf
                            trendingShelfView

                            // Quick Navigation Cards
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 400), spacing: Spacing.md)], spacing: Spacing.md) {
                                browseAppsCard
                                browseFormulaeCard
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.bottom, Spacing.xs)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                // Top 3 Podium Showcase when Leaderboard is active
                if viewMode == .spotlight, isTrendingLeaderboard, search.isEmpty {
                    Section {
                        trendingPodiumView
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if let error = catalog.errorMessage {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.lg)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if viewMode == .spotlight, isTrendingLeaderboard {
                    Section("Trending Community Installs") {
                        ForEach(Array(leaderboardItems.dropFirst(3).enumerated()), id: \.element.id) { entry in
                            leaderboardRow(index: entry.offset, item: entry.element)
                        }
                    }
                } else if !search.isEmpty {
                    Section("Search Results (\(visibleItems.count) matching)") {
                        ForEach(visibleItems.prefix(displayLimit)) { item in
                            packageRow(for: item)
                        }
                        if visibleItems.count > displayLimit {
                            HStack {
                                Spacer()
                                Button("Load All \(visibleItems.count) Results…") {
                                    displayLimit = visibleItems.count
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else if viewMode == .spotlight {
                    if !newlyDiscoveredItems.isEmpty {
                        Section("New since last refresh") {
                            ForEach(newlyDiscoveredItems) { item in
                                packageRow(for: item)
                            }
                        }
                    }

                    if !popularItems.isEmpty {
                        Section("Popular this month") {
                            ForEach(popularItems) { item in
                                packageRow(for: item)
                            }
                        }
                    }

                    Section("Directory Spotlight (\(visibleItems.count))") {
                        ForEach(visibleItems.prefix(displayLimit)) { item in
                            packageRow(for: item)
                        }
                        if visibleItems.count > displayLimit {
                            HStack {
                                Spacer()
                                Button("Load All \(visibleItems.count) Spotlight Packages…") {
                                    displayLimit = visibleItems.count
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    // Full Directory / All Apps / All Formulae / All Catalog
                    let sectionHeader: String = switch viewMode {
                    case .allApps: "All macOS Applications (\(visibleItems.count))"
                    case .allFormulae: "All Command-Line Tools & Libraries (\(visibleItems.count))"
                    case .allCatalog, .spotlight: "All Packages (\(visibleItems.count))"
                    }

                    Section(sectionHeader) {
                        ForEach(visibleItems.prefix(displayLimit)) { item in
                            packageRow(for: item)
                        }
                        if visibleItems.count > displayLimit {
                            HStack {
                                Spacer()
                                Button("Load All \(visibleItems.count) Packages…") {
                                    displayLimit = visibleItems.count
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search \(headerTitle.lowercased())…")
            .overlay {
                if catalog.isLoading, catalog.items.isEmpty {
                    ProgressView("Loading Homebrew catalog…")
                } else if visibleItems.isEmpty, onlineResults.isEmpty {
                    VStack(spacing: 12) {
                        ContentUnavailableView("No matching packages", systemImage: "sparkles", description: Text("Try a different search, filter, or category."))
                        if hasActiveFilters {
                            Button {
                                resetFilters()
                            } label: {
                                Label("Reset All Filters", systemImage: "xmark.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                        if !search.isEmpty, manager.isAvailable {
                            Button {
                                performOnlineSearch()
                            } label: {
                                if isSearchingOnline {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Search Online with Homebrew (brew search)", systemImage: "magnifyingglass")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSearchingOnline)
                        }
                    }
                }
            }
        }
        .task {
            catalog.mergeLocalPackages(manager.packages)
            catalog.load()
        }
        .detailModalOverlay(item: $selectedItem) { item in
            DiscoveryDetailView(item: item, manager: manager, onSelectDependency: { depID in
                if let found = catalog.items.first(where: { $0.id == depID || $0.aliases.contains(depID) }) {
                    selectedItem = found
                }
            }, onDismiss: {
                selectedItem = nil
            })
        }
        .detailModalOverlay(item: $selectedStory) { story in
            StoryDetailView(manager: manager, story: story, onDismiss: {
                selectedStory = nil
            })
        }
        .detailModalOverlay(item: $selectedOnlinePackage) { pkg in
            PackageDetailView(manager: manager, package: pkg, onDismiss: {
                selectedOnlinePackage = nil
            })
        }
        .onAppear {
            recomputeItems(debounce: false)
        }
        .onDisappear {
            filterTask?.cancel()
        }
        .onChange(of: search) { _, _ in
            recomputeItems(debounce: true)
        }
        .onChange(of: selectedKind) { _, _ in
            recomputeItems(debounce: false)
        }
        .onChange(of: viewMode) { _, _ in
            recomputeItems(debounce: false)
        }
        .onChange(of: selectedCategory) { _, _ in
            recomputeItems(debounce: false)
        }
        .onChange(of: selectedStatus) { _, _ in
            recomputeItems(debounce: false)
        }
        .onChange(of: selectedSort) { _, _ in
            recomputeItems(debounce: false)
        }
        .onChange(of: selectedTap) { _, _ in
            recomputeItems(debounce: false)
        }
        .onChange(of: catalog.items) { _, _ in
            recomputeItems(debounce: false)
        }
        .onChange(of: manager.packages.count) { _, _ in
            recomputeItems(debounce: false)
        }
        .onChange(of: manager.lastRefreshedAt) { _, _ in
            recomputeItems(debounce: false)
        }
        .background {
            Group {
                Button("") { viewMode = .spotlight }.keyboardShortcut("1", modifiers: .command)
                Button("") { viewMode = .allCatalog }.keyboardShortcut("2", modifiers: .command)
                Button("") { viewMode = .allApps }.keyboardShortcut("3", modifiers: .command)
                Button("") { viewMode = .allFormulae }.keyboardShortcut("4", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    private struct ComputedDiscoveryState: Sendable {
        let filtered: [BrewStoreDiscoveryItem]
        let popular: [BrewStoreDiscoveryItem]
        let newlyDiscovered: [BrewStoreDiscoveryItem]
        let leaderboard: [BrewStoreDiscoveryItem]
        let categories: [String]
        let taps: [String]
        let totalApps: Int
        let totalFormulae: Int
    }

    private nonisolated static func calculateDiscoveryState(
        catalogItems: [BrewStoreDiscoveryItem],
        newlyDiscoveredIDs: Set<String>,
        packages: [BrewStorePackage],
        search: String,
        effectiveKind: BrewPackageKind?,
        selectedCategory: String,
        selectedTap: String,
        selectedStatus: DiscoveryStatusFilter,
        selectedSort: DiscoverySortOrder,
        selectedKind: BrewPackageKind?
    ) -> ComputedDiscoveryState {
        let editorialIDs = Set(BrewStoreEditorialPick.allPicks.map(\.id))
        let installedMap = Dictionary(packages.map { ("\($0.kind.rawValue):\($0.id)", $0) }, uniquingKeysWith: { first, _ in first })

        let totalApps = catalogItems.filter { $0.kind == .cask }.count
        let totalFormulae = catalogItems.filter { $0.kind == .formula }.count

        let baseCategories = catalogItems.filter { item in
            if let effectiveKind {
                return item.kind == effectiveKind
            }
            return true
        }
        let categories = ["All", "Editor's Picks"] + Array(Set(baseCategories.map(\.category))).sorted()

        let baseTaps = catalogItems.filter { item in
            if let effectiveKind {
                return item.kind == effectiveKind
            }
            return true
        }
        let availableTaps = ["All Taps"] + Array(Set(baseTaps.compactMap(\.tap))).sorted()

        let cleanSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = catalogItems.filter { item in
            if let effectiveKind, item.kind != effectiveKind {
                return false
            }

            if selectedCategory == "Editor's Picks" {
                if !editorialIDs.contains(item.id) {
                    return false
                }
            } else if selectedCategory != "All" {
                if categories.contains(selectedCategory) {
                    if item.category != selectedCategory {
                        return false
                    }
                }
            }

            if selectedTap != "All Taps" {
                if availableTaps.contains(selectedTap) {
                    if item.tap != selectedTap {
                        return false
                    }
                }
            }

            if selectedStatus != .all {
                let installedPkg = installedMap["\(item.kind.rawValue):\(item.id)"]
                switch selectedStatus {
                case .all: break
                case .installed:
                    if installedPkg?.isInstalled != true {
                        return false
                    }
                case .outdated:
                    if installedPkg?.isOutdated != true {
                        return false
                    }
                case .notInstalled:
                    if installedPkg?.isInstalled == true {
                        return false
                    }
                }
            }

            if !cleanSearch.isEmpty {
                let matches = item.name.localizedCaseInsensitiveContains(cleanSearch) ||
                    item.id.localizedCaseInsensitiveContains(cleanSearch) ||
                    item.description.localizedCaseInsensitiveContains(cleanSearch) ||
                    item.aliases.contains(where: { $0.localizedCaseInsensitiveContains(cleanSearch) }) ||
                    item.artifacts.contains(where: { $0.localizedCaseInsensitiveContains(cleanSearch) })
                if !matches {
                    return false
                }
            }

            return true
        }

        let sortedFiltered: [BrewStoreDiscoveryItem] = switch selectedSort {
        case .popular:
            filtered.sorted {
                if $0.installCount30Days != $1.installCount30Days {
                    return $0.installCount30Days > $1.installCount30Days
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .nameAsc:
            filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        }

        let popular = sortedFiltered.sorted { $0.installCount30Days > $1.installCount30Days }.prefix(12).map { $0 }
        let newlyDiscovered = sortedFiltered.filter { newlyDiscoveredIDs.contains($0.id) }

        let itemsWithTelemetry = catalogItems.filter { $0.installCount30Days > 0 }
        let candidateItems = itemsWithTelemetry.isEmpty ? catalogItems : itemsWithTelemetry
        let sortedLeaderboard = candidateItems.sorted {
            if $0.installCount30Days != $1.installCount30Days {
                return $0.installCount30Days > $1.installCount30Days
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        var seenFamilies = Set<String>()
        var deduplicated: [BrewStoreDiscoveryItem] = []
        for item in sortedLeaderboard {
            let baseFamily = item.id.components(separatedBy: "@").first?
                .replacingOccurrences(of: "-preview", with: "")
                .replacingOccurrences(of: "-beta", with: "")
                .replacingOccurrences(of: "-nightly", with: "") ?? item.id
            if !seenFamilies.contains(baseFamily) {
                seenFamilies.insert(baseFamily)
                deduplicated.append(item)
            }
            if deduplicated.count >= 50 {
                break
            }
        }

        return ComputedDiscoveryState(
            filtered: sortedFiltered,
            popular: popular,
            newlyDiscovered: newlyDiscovered,
            leaderboard: deduplicated,
            categories: categories,
            taps: availableTaps,
            totalApps: totalApps,
            totalFormulae: totalFormulae
        )
    }

    private func recomputeItems(debounce: Bool = false) {
        filterTask?.cancel()
        let items = catalog.items
        let newlyDiscovered = catalog.newlyDiscoveredIDs
        let packages = manager.packages
        let query = search
        let kind = effectiveKind
        let category = selectedCategory
        let tap = selectedTap
        let status = selectedStatus
        let sort = selectedSort
        let selKind = selectedKind

        filterTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled else { return }
            }

            let result = await Task.detached(priority: .userInitiated) { () -> ComputedDiscoveryState in
                Self.calculateDiscoveryState(
                    catalogItems: items,
                    newlyDiscoveredIDs: newlyDiscovered,
                    packages: packages,
                    search: query,
                    effectiveKind: kind,
                    selectedCategory: category,
                    selectedTap: tap,
                    selectedStatus: status,
                    selectedSort: sort,
                    selectedKind: selKind
                )
            }.value

            guard !Task.isCancelled else { return }
            self.filteredItems = result.filtered
            self.popularItemsList = result.popular
            self.newlyDiscoveredItemsList = result.newlyDiscovered
            self.leaderboardItemsList = result.leaderboard
            self.categoriesList = result.categories
            self.availableTapsList = result.taps
            self.totalAppsCount = result.totalApps
            self.totalFormulaeCount = result.totalFormulae
            if self.selectedCategory != "All" && !result.categories.contains(self.selectedCategory) {
                self.selectedCategory = "All"
            }
            if self.selectedTap != "All Taps" && !result.taps.contains(self.selectedTap) {
                self.selectedTap = "All Taps"
            }
        }
    }

    private func performOnlineSearch() {
        guard !search.isEmpty else { return }
        isSearchingOnline = true
        Task {
            let results = await manager.liveSearch(query: search)
            await MainActor.run {
                onlineResults = results
                isSearchingOnline = false
            }
        }
    }

    private var modePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            Text("Spotlight").tag(DiscoveryViewMode.spotlight)
            Text("All Packages").tag(DiscoveryViewMode.allCatalog)
            Text("Applications").tag(DiscoveryViewMode.allApps)
            Text("CLI Tools").tag(DiscoveryViewMode.allFormulae)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: viewMode) { _, newMode in
            displayLimit = 150
            switch newMode {
            case .allApps:
                selectedKind = .cask
            case .allFormulae:
                selectedKind = .formula
            case .spotlight, .allCatalog:
                selectedKind = nil
            }
            onModeChange?(newMode)
        }
    }

    private var actionsGroup: some View {
        HStack(spacing: 8) {
            if viewMode == .spotlight {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTrendingLeaderboard.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(isTrendingLeaderboard ? .white : .orange)
                        Text("Trending")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(isTrendingLeaderboard ? Color.orange : Color.orange.opacity(0.14), in: Capsule())
                    .foregroundStyle(isTrendingLeaderboard ? Color.white : Color.orange)
                }
                .buttonStyle(.plain)
                .help("Toggle Top 50 Trending Leaderboard")
            }

            // Compact vs Rich layout toggle
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCompactView.toggle()
                }
            } label: {
                Image(systemName: isCompactView ? "list.bullet" : "square.grid.2x2")
            }
            .controlSize(.small)
            .help(isCompactView ? "Switch to Standard View" : "Switch to Compact List View")

            Button(action: {
                catalog.load(force: true)
                manager.retryRefresh()
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("Refresh Catalog")
            .disabled(catalog.isLoading || manager.isLoading || manager.isOperating)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                if viewMode == .allCatalog {
                    Picker("Type", selection: $selectedKind) {
                        Text("All Types").tag(BrewPackageKind?.none)
                        Text("Apps").tag(Optional(BrewPackageKind.cask))
                        Text("CLI").tag(Optional(BrewPackageKind.formula))
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                }

                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .controlSize(.small)

                Picker("Status", selection: $selectedStatus) {
                    ForEach(DiscoveryStatusFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .controlSize(.small)

                Picker("Sort", selection: $selectedSort) {
                    ForEach(DiscoverySortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .controlSize(.small)

                if availableTaps.count > 1 {
                    Picker("Tap", selection: $selectedTap) {
                        ForEach(availableTaps, id: \.self) { Text($0).tag($0) }
                    }
                    .controlSize(.small)
                }

                if hasActiveFilters {
                    Button {
                        resetFilters()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Reset")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reset all filters & search")
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func packageRow(for item: BrewStoreDiscoveryItem) -> some View {
        Group {
            if isCompactView {
                CompactDiscoveryRow(item: item, manager: manager) {
                    selectedItem = item
                }
            } else {
                DiscoveryRow(item: item, manager: manager) {
                    selectedItem = item
                }
            }
        }
        .onAppear {
            if item.id == visibleItems.prefix(displayLimit).last?.id {
                if visibleItems.count > displayLimit {
                    displayLimit = min(displayLimit + 100, visibleItems.count)
                }
            }
        }
    }

    private func leaderboardRow(index: Int, item: BrewStoreDiscoveryItem) -> some View {
        HStack(spacing: 12) {
            Text("#\(index + 4)")
                .font(.headline.monospaced())
                .foregroundStyle(Color.secondary)
                .frame(width: 38, alignment: .leading)

            DiscoveryRow(item: item, manager: manager) {
                selectedItem = item
            }
        }
    }

    private var browseAppsCard: some View {
        Button {
            viewMode = .allApps
        } label: {
            HStack {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse All \(totalAppsCount) Applications").font(.subheadline.bold())
                    Text("GUI apps for design, dev, utilities, and media").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var browseFormulaeCard: some View {
        Button {
            viewMode = .allFormulae
        } label: {
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse All \(totalFormulaeCount) CLI Tools").font(.subheadline.bold())
                    Text("Compilers, servers, runtimes, and libraries").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trendingShelfView: some View {
        let topTrending = Array(leaderboardItems.prefix(6))
        if !topTrending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("Trending This Week")
                            .font(.headline)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTrendingLeaderboard = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Top 50 Leaderboard")
                            Image(systemName: "chevron.right")
                                .font(.caption2.bold())
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(topTrending.enumerated()), id: \.element.id) { index, item in
                            trendingMiniCard(item: item, rank: index + 1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func trendingMiniCard(item: BrewStoreDiscoveryItem, rank: Int) -> some View {
        let targetPackage = manager.packages.first { $0.id == item.id && $0.kind == item.kind } ?? BrewStorePackage(
            id: item.id,
            name: item.name,
            description: item.description,
            homepage: item.homepage,
            version: item.version,
            kind: item.kind
        )

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Text("#\(rank)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(rank <= 3 ? Color.orange : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(rank <= 3 ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                Spacer()

                if item.installCount30Days > 0 {
                    Text("\(item.installCount30Days.formatted())")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                PackageIconView(item: item, installedPackage: targetPackage.isInstalled ? targetPackage : nil, size: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Text(item.category)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(item.description.isEmpty ? "Popular package" : item.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(height: 28, alignment: .topLeading)

            HStack {
                Button("Details") {
                    selectedItem = item
                }
                .buttonStyle(.plain)
                .font(.caption2.bold())
                .foregroundStyle(Color.accentColor)

                Spacer()

                AppStoreActionButton(manager: manager, package: targetPackage, size: .small, onShowDetail: {
                    selectedItem = item
                })
            }
        }
        .padding(10)
        .frame(width: 235)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(rank <= 3 ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var trendingPodiumView: some View {
        let top3 = Array(leaderboardItems.prefix(3))
        if top3.count == 3 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("Top 3 Trending Packages")
                            .font(.headline)
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTrendingLeaderboard = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                            Text("Back to Spotlight")
                        }
                        .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 450), spacing: 12)], spacing: 12) {
                    podiumCard(item: top3[0], rank: 1, color: .orange)
                    podiumCard(item: top3[1], rank: 2, color: .gray)
                    podiumCard(item: top3[2], rank: 3, color: .brown)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private func podiumCard(item: BrewStoreDiscoveryItem, rank: Int, color: Color) -> some View {
        let targetPackage = manager.packages.first { $0.id == item.id && $0.kind == item.kind } ?? BrewStorePackage(
            id: item.id,
            name: item.name,
            description: item.description,
            homepage: item.homepage,
            version: item.version,
            kind: item.kind
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Image(systemName: rank == 1 ? "trophy.fill" : (rank == 2 ? "medal.fill" : "award.fill"))
                        .font(.caption2)
                    Text("#\(rank)")
                        .font(.caption.bold())
                }
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15), in: Capsule())

                Spacer()

                if item.installCount30Days > 0 {
                    let count7d = max(1, Int(round(Double(item.installCount30Days) * 7.0 / 30.0)))
                    let count365d = item.installCount30Days * 12
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                        Text("\(BrewStoreAnalyticsManager.formatCount(item.installCount30Days))/mo")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .help("Install Statistics for \(item.id):\n• Last 7 days: ~\(BrewStoreAnalyticsManager.formatCount(count7d)) (\(count7d.formatted()) installs)\n• Last 30 days (1 mo): \(BrewStoreAnalyticsManager.formatCount(item.installCount30Days)) (\(item.installCount30Days.formatted()) installs)\n• Last 365 days (1 yr): ~\(BrewStoreAnalyticsManager.formatCount(count365d)) (\(count365d.formatted()) installs)")
                }
            }

            HStack(spacing: 10) {
                PackageIconView(item: item, installedPackage: targetPackage.isInstalled ? targetPackage : nil, size: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)

                    Text(item.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(item.description.isEmpty ? "Popular \(item.kind == .cask ? "application" : "utility")" : item.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(height: 28, alignment: .topLeading)

            HStack {
                Button("Details") {
                    selectedItem = item
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()

                AppStoreActionButton(manager: manager, package: targetPackage, size: .small, onShowDetail: {
                    selectedItem = item
                })
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.35), lineWidth: rank == 1 ? 1.5 : 1)
        )
    }
}
