import AppKit
import SwiftUI

struct TapDetailView: View {
    @ObservedObject var manager: HomebrewManager
    let tap: BrewStoreTap
    @State private var search = ""
    @State private var showingTapGraph = false
    @State private var selectedPackageForDetail: BrewStorePackage?
    @StateObject private var healthManager = BrewStoreTapHealthManager.shared

    private var tapLocalURL: URL? {
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

    private var packagesInTap: [BrewStorePackage] {
        let matching = manager.packages.filter { $0.tap == tap.name }
        if search.isEmpty {
            return matching
        }
        return matching.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
                $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "square.3.layers.3d.down.forward")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tap.name).font(.title.bold())
                        if tap.isOfficial {
                            Text("Official")
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                        if let report = healthManager.report(for: tap.name) {
                            Text(report.hostProvider)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let localURL = tapLocalURL {
                        Text(localURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    showingTapGraph = true
                } label: {
                    Label("Tap Graph", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.bordered)

                if let localURL = tapLocalURL {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([localURL])
                    }
                    .buttonStyle(.bordered)
                }

                if let report = healthManager.report(for: tap.name),
                   let remoteStr = report.remoteURL,
                   let url = URL(string: remoteStr) {
                    Link(report.hostProvider, destination: url)
                        .buttonStyle(.bordered)
                } else if let url = URL(string: "https://github.com/\(tap.name)") {
                    Link("Repository", destination: url)
                        .buttonStyle(.bordered)
                }

                Button("Untap", role: .destructive) {
                    manager.removeTap(tap)
                }
                .buttonStyle(.bordered)
                .disabled(manager.isOperating)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Installed Packages from this Tap (\(packagesInTap.count))")
                        .font(.headline)
                    Spacer()
                    BrewStoreSectionSearchBar(text: $search, placeholder: "Search packages in \(tap.name)…", count: packagesInTap.count)
                        .frame(minWidth: 180, maxWidth: 260)
                }
                .padding(.horizontal)
                .padding(.top, 12)

                List(packagesInTap) { package in
                    Button {
                        selectedPackageForDetail = package
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: package.kind == .cask ? "app.fill" : "terminal.fill")
                                .foregroundStyle(package.kind == .cask ? Color.blue : Color.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(package.name).font(.headline)
                                Text(package.version).font(.caption).foregroundStyle(.secondary)
                            }

                            Spacer()

                            if package.isOutdated {
                                Text("Update")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .brewStorePackageContextMenu(package: package, manager: manager, onShowDetails: {
                        selectedPackageForDetail = package
                    })
                }
                .searchable(text: $search, prompt: "Search packages in \(tap.name)")
                .overlay {
                    if packagesInTap.isEmpty {
                        ContentUnavailableView("No packages found", systemImage: "shippingbox", description: Text("No packages from '\(tap.name)' are currently installed."))
                    }
                }
            }
        }
        .navigationTitle(tap.name)
        .onAppear {
            healthManager.auditTap(tap: tap, prefix: manager.brewPrefix)
        }
        .sheet(isPresented: $showingTapGraph) {
            TapGraphView(manager: manager, tap: tap, packagesInTap: packagesInTap)
        }
        .detailModalOverlay(item: $selectedPackageForDetail) { package in
            PackageDetailView(manager: manager, package: package, onDismiss: {
                selectedPackageForDetail = nil
            })
        }
    }
}

struct TapGraphView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    let tap: BrewStoreTap
    let packagesInTap: [BrewStorePackage]

    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var selectedNodeID: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(tap.name) Ecosystem Graph").font(.title2.bold())
                    Text("\(packagesInTap.count) installed packages linked to this repository.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reset") {
                    withAnimation(.spring) {
                        zoomScale = 1.0
                        panOffset = .zero
                        selectedNodeID = nil
                    }
                }
                .controlSize(.small)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()
            .background(Color.secondary.opacity(0.04))

            Divider()

            // Canvas
            GeometryReader { geometry in
                let size = geometry.size
                let centerX = size.width / 2
                let centerY = size.height / 2
                let rootPoint = CGPoint(x: centerX - 200, y: centerY)

                ZStack {
                    Color(nsColor: .windowBackgroundColor)

                    ZStack {
                        // Edges from Root to Packages
                        ForEach(Array(packagesInTap.enumerated()), id: \.element.id) { index, pkg in
                            let targetPoint = computePackagePoint(index: index, total: packagesInTap.count, center: CGPoint(x: centerX + 120, y: centerY))
                            let isSelected = selectedNodeID == pkg.id || selectedNodeID == tap.id

                            Path { path in
                                path.move(to: rootPoint)
                                let midX = (rootPoint.x + targetPoint.x) / 2
                                path.addCurve(to: targetPoint, control1: CGPoint(x: midX, y: rootPoint.y), control2: CGPoint(x: midX, y: targetPoint.y))
                            }
                            .stroke(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.35),
                                style: StrokeStyle(lineWidth: isSelected ? 3 : 1.5, lineCap: .round)
                            )
                        }

                        // Root Tap Node
                        HStack(spacing: 8) {
                            Image(systemName: "square.3.layers.3d.down.forward")
                                .foregroundStyle(.blue)
                            Text(tap.name)
                                .font(.headline.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.8), lineWidth: selectedNodeID == tap.id ? 2.5 : 1.5)
                        )
                        .shadow(radius: 4)
                        .position(rootPoint)
                        .onTapGesture {
                            selectedNodeID = (selectedNodeID == tap.id) ? nil : tap.id
                        }

                        // Child Package Nodes
                        ForEach(Array(packagesInTap.enumerated()), id: \.element.id) { index, pkg in
                            let point = computePackagePoint(index: index, total: packagesInTap.count, center: CGPoint(x: centerX + 120, y: centerY))
                            let isSelected = selectedNodeID == pkg.id

                            HStack(spacing: 6) {
                                Image(systemName: pkg.kind == .cask ? "app.fill" : "terminal.fill")
                                    .font(.caption2)
                                    .foregroundStyle(pkg.kind == .cask ? Color.blue : Color.green)
                                Text(pkg.name)
                                    .font(.caption.monospaced().bold())
                                if !pkg.version.isEmpty {
                                    Text("v\(pkg.version)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(pkg.kind == .cask ? Color.blue.opacity(0.6) : Color.green.opacity(0.6), lineWidth: isSelected ? 2 : 1)
                            )
                            .shadow(radius: isSelected ? 6 : 2)
                            .position(point)
                            .onTapGesture {
                                selectedNodeID = (selectedNodeID == pkg.id) ? nil : pkg.id
                            }
                        }
                    }
                    .scaleEffect(zoomScale)
                    .offset(x: panOffset.width + dragOffset.width, y: panOffset.height + dragOffset.height)
                }
                .clipped()
                .gesture(
                    DragGesture()
                        .onChanged { value in dragOffset = value.translation }
                        .onEnded { value in
                            panOffset.width += value.translation.width
                            panOffset.height += value.translation.height
                            dragOffset = .zero
                        }
                )
            }

            Divider()

            // Footer
            HStack {
                Text("\(packagesInTap.count) Packages in Tap").font(.caption.bold())
                Spacer()
                Text("Tap any package or repository node to highlight connections").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.04))
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private func computePackagePoint(index: Int, total: Int, center: CGPoint) -> CGPoint {
        if total == 0 {
            return center
        }
        let spacingY: CGFloat = 64
        let totalHeight = CGFloat(total - 1) * spacingY
        let startY = center.y - totalHeight / 2
        return CGPoint(x: center.x, y: startY + CGFloat(index) * spacingY)
    }
}
