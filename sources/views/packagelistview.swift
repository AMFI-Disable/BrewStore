import SwiftUI

struct PackageListView: View {
    @ObservedObject var manager: HomebrewManager
    let kind: BrewPackageKind?
    let title: String
    var updatesOnly = false
    @State private var search = ""

    private var packages: [BrewStorePackage] {
        manager.packages.filter { package in
            (kind == nil || package.kind == kind) && (!updatesOnly || package.isOutdated) &&
            (search.isEmpty || package.name.localizedCaseInsensitiveContains(search) || package.id.localizedCaseInsensitiveContains(search) || package.description.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.largeTitle.bold())
                    Text("\(packages.count) packages").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: manager.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(manager.isLoading || manager.isOperating)
            }
            .padding()

            if !manager.statusMessage.isEmpty || manager.errorMessage != nil {
                HStack {
                    Text(manager.errorMessage ?? manager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(manager.errorMessage == nil ? Color.secondary : Color.red)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            List(packages) { package in
                NavigationLink(value: package) {
                    HStack(spacing: 12) {
                        Image(systemName: package.kind == .cask ? "app.fill" : "terminal.fill")
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(package.name).font(.headline)
                            Text(package.description.isEmpty ? package.id : package.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if package.isOutdated { Text("Update").font(.caption.bold()).foregroundStyle(.orange) }
                        Text(package.isInstalled ? "Installed" : package.version)
                            .font(.caption)
                            .foregroundStyle(package.isInstalled ? .green : .secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .searchable(text: $search, prompt: "Search \(title.lowercased())")
            .navigationDestination(for: BrewStorePackage.self) { package in
                PackageDetailView(manager: manager, package: package)
            }
            .overlay {
                if manager.isLoading { ProgressView("Refreshing Homebrew…") }
                else if packages.isEmpty && manager.errorMessage == nil { ContentUnavailableView("No packages", systemImage: "shippingbox", description: Text("Try a different search or refresh Homebrew.")) }
            }
        }
    }
}
