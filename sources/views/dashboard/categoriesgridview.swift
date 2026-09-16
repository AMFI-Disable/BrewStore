import AppKit
import SwiftUI

struct AppCategoryDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let systemImage: String
    let gradient: [Color]
}

struct CategoriesGridView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var catalog: BrewStoreDiscoveryCatalog
    var onSelectCategory: ((String) -> Void)?

    @State private var selectedCategoryID: String = "Development"
    @State private var filterType: PackageFilterType = .all
    @State private var sortOption: PackageSortOption = .popular
    @State private var searchQuery: String = ""
    @State private var selectedPackageForDetail: BrewStorePackage?

    enum PackageFilterType: String, CaseIterable, Identifiable {
        case all = "All Items"
        case casks = "GUI Casks"
        case formulae = "CLI Formulae"
        case installed = "Installed Only"

        var id: String {
            rawValue
        }
    }

    enum PackageSortOption: String, CaseIterable, Identifiable {
        case popular = "Popular"
        case name = "Name (A–Z)"
        case status = "Status"

        var id: String {
            rawValue
        }
    }

    static let categories: [AppCategoryDefinition] = [
        AppCategoryDefinition(id: "Development", name: "Developer Tools", description: "IDEs, code editors, compilers, language runtimes, and debuggers.", systemImage: "chevron.left.forwardslash.chevron.right", gradient: [.indigo, .purple]),
        AppCategoryDefinition(id: "Productivity", name: "Productivity & Office", description: "Launchers, note-taking, task managers, and window management.", systemImage: "doc.text.fill", gradient: [.blue, .cyan]),
        AppCategoryDefinition(id: "Media & Design", name: "Graphics & Media", description: "3D modeling, vector design, video players, and audio encoders.", systemImage: "paintpalette.fill", gradient: [.purple, .pink]),
        AppCategoryDefinition(id: "Utilities", name: "System Utilities", description: "File monitors, shell prompts, terminal multiplexers, and disk tools.", systemImage: "wrench.and.screwdriver.fill", gradient: [.orange, .yellow]),
        AppCategoryDefinition(id: "Security & Privacy", name: "Security & Privacy", description: "Password managers, encryption utilities, VPNs, and GPG tools.", systemImage: "lock.shield.fill", gradient: [.green, .teal]),
        AppCategoryDefinition(id: "Infrastructure & Cloud", name: "Cloud & DevOps", description: "Docker, Kubernetes, AWS/GCP CLIs, and container runtimes.", systemImage: "cloud.fill", gradient: [.cyan, .blue]),
        AppCategoryDefinition(id: "Browsers", name: "Web & Browsers", description: "Modern web browsers, HTTP clients, and network analyzers.", systemImage: "globe", gradient: [.teal, .mint]),
        AppCategoryDefinition(id: "Games", name: "Games & Emulation", description: "Retro gaming emulators, game engines, and native titles.", systemImage: "gamecontroller.fill", gradient: [.red, .orange])
    ]

    private var activeCategory: AppCategoryDefinition {
        Self.categories.first { $0.id == selectedCategoryID } ?? Self.categories.first ?? AppCategoryDefinition(id: "Development", name: "Developer Tools", description: "", systemImage: "wrench.fill", gradient: [.blue, .cyan])
    }

    private var allPackagesForActiveCategory: [BrewStorePackage] {
        let catalogMatches = catalog.items.filter { $0.category == selectedCategoryID }
        let installedMap = Dictionary(manager.packages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var resultPackages: [BrewStorePackage] = []
        for item in catalogMatches {
            if let installed = installedMap[item.id] {
                resultPackages.append(installed)
            } else {
                resultPackages.append(
                    BrewStorePackage(
                        id: item.id,
                        name: item.name,
                        description: item.description,
                        homepage: "",
                        version: "",
                        kind: item.kind
                    )
                )
            }
        }

        return resultPackages
    }

    private var filteredPackages: [BrewStorePackage] {
        var list = allPackagesForActiveCategory

        // Filter Type
        switch filterType {
        case .all:
            break
        case .casks:
            list = list.filter { $0.kind == .cask }
        case .formulae:
            list = list.filter { $0.kind == .formula }
        case .installed:
            list = list.filter(\.isInstalled)
        }

        // Search Query
        if !searchQuery.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(searchQuery) ||
                    $0.id.localizedCaseInsensitiveContains(searchQuery) ||
                    $0.description.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        // Sort
        switch sortOption {
        case .popular:
            break // Catalog order is popularity weighted
        case .name:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .status:
            list.sort { ($0.isOutdated ? 0 : ($0.isInstalled ? 1 : 2)) < ($1.isOutdated ? 0 : ($1.isInstalled ? 1 : 2)) }
        }

        return list
    }

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 380), spacing: Spacing.md)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Top Category Selector Pills (Full-Width Horizontal Rail)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(Self.categories) { cat in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategoryID = cat.id
                                }
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: cat.systemImage)
                                        .font(.subheadline)
                                    Text(cat.name)
                                        .font(.subheadline.bold())
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs)
                                .background(
                                    selectedCategoryID == cat.id
                                        ? AnyShapeStyle(LinearGradient(colors: cat.gradient, startPoint: .leading, endPoint: .trailing))
                                        : AnyShapeStyle(Color.secondary.opacity(0.08))
                                    // End background
                                )
                                .foregroundStyle(selectedCategoryID == cat.id ? Color.white : Color.primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(selectedCategoryID == cat.id ? Color.clear : Color.secondary.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
                }

                // Selected Category Hero Banner (Full-Width)
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: activeCategory.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 125)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: activeCategory.systemImage)
                                .font(.title)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.2), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(activeCategory.name)
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)

                                Text("\(allPackagesForActiveCategory.count) Packages Available")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }

                        Text(activeCategory.description)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                    .padding(Spacing.lg)
                }
                .padding(.horizontal, Spacing.lg)

                // Controls & Search Bar: Row 1 Filter Picker, Row 2 Search & Sort
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Picker("Filter", selection: $filterType) {
                        ForEach(PackageFilterType.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)

                    HStack(spacing: Spacing.sm) {
                        BrewStoreSectionSearchBar(text: $searchQuery, placeholder: "Search \(activeCategory.name) packages…", count: filteredPackages.count)
                            .frame(minWidth: 180, maxWidth: 280)

                        Picker("Sort", selection: $sortOption) {
                            ForEach(PackageSortOption.allCases) { sort in
                                Text(sort.rawValue).tag(sort)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                }
                .padding(.horizontal, Spacing.lg)

                // Responsive Full-Width Package Wall Grid
                if filteredPackages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No packages found in \(activeCategory.name)")
                            .font(.headline)
                        Text("Try selecting a different filter or clearing your search term.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(Spacing.lg)
                } else {
                    LazyVGrid(columns: columns, spacing: Spacing.md) {
                        ForEach(filteredPackages) { pkg in
                            CategoryPackageCard(manager: manager, package: pkg) {
                                selectedPackageForDetail = pkg
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.xl)
                }
            }
        }
        .detailModalOverlay(item: $selectedPackageForDetail) { pkg in
            PackageDetailView(manager: manager, package: pkg, onDismiss: {
                selectedPackageForDetail = nil
            })
        }
    }
}

private struct CategoryPackageCard: View {
    @ObservedObject var manager: HomebrewManager
    let package: BrewStorePackage
    let onSelect: () -> Void

    private var resolvedPackage: BrewStorePackage {
        manager.packages.first { $0.id == package.id } ?? package
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    // App Icon / Symbol
                    if resolvedPackage.kind == .cask,
                       let icon = BrewStoreAppIconResolver.localAppIcon(for: resolvedPackage.applicationNames.isEmpty ? [resolvedPackage.name] : resolvedPackage.applicationNames) {
                        Image(nsImage: icon)
                            .resizable().scaledToFit()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: resolvedPackage.kind == .cask ? "app.fill" : "terminal.fill")
                            .font(.title2)
                            .foregroundStyle(resolvedPackage.kind == .cask ? Color.blue : Color.green)
                            .frame(width: 44, height: 44)
                            .background(
                                (resolvedPackage.kind == .cask ? Color.blue : Color.green).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(resolvedPackage.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            PackageInstallCountBadge(package: resolvedPackage)
                        }

                        HStack(spacing: 6) {
                            Text(resolvedPackage.kind == .cask ? "Cask" : "Formula")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (resolvedPackage.kind == .cask ? Color.blue : Color.green).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                                .foregroundStyle(resolvedPackage.kind == .cask ? Color.blue : Color.green)

                            if !resolvedPackage.displayVersion.isEmpty {
                                Text(resolvedPackage.displayVersion)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    // App Store Action Pill
                    AppStoreActionButton(manager: manager, package: resolvedPackage)
                }

                Text(resolvedPackage.description.isEmpty ? "High-performance Homebrew package." : resolvedPackage.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .brewStorePackageContextMenu(package: resolvedPackage, manager: manager, onShowDetails: onSelect)
    }
}
