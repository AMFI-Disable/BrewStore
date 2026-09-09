import AppKit
import SwiftUI

struct StoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    let story: BrewStoreStory
    var onSelectPackage: ((BrewStorePackage) -> Void)?
    var onDismiss: (() -> Void)?

    private func handleDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero Header
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [Color(hex: story.gradientColors.first ?? "#1e293b"), Color(hex: story.gradientColors.last ?? "#0f172a")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 240)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(story.eyebrow)
                                .font(.caption.monospaced().bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(.white)

                            Spacer()

                            Text("\(story.readTimeMinutes) min read")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        Text(story.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)

                        Text(story.subtitle)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(24)
                }

                // Article Content
                VStack(alignment: .leading, spacing: 20) {
                    MarkdownTextView(
                        markdown: story.bodyMarkdown,
                        baseFont: .body,
                        lineSpacing: 6,
                        accentColor: Color(hex: story.gradientColors.first ?? "#f59e0b")
                    )

                    Divider()

                    // Featured Packages in this Story
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Featured in this Story").font(.title3.bold())

                        ForEach(story.featuredPackageIDs, id: \.self) { pkgID in
                            let installed = manager.packages.first { $0.id == pkgID }
                            let pkg = installed ?? BrewStorePackage(
                                id: pkgID,
                                name: pkgID,
                                description: "",
                                homepage: "",
                                version: "",
                                kind: pkgID.contains("@") || !pkgID.contains("-") ? .formula : .cask
                            )

                            HStack(spacing: 14) {
                                Image(systemName: pkg.kind == .cask ? "app.fill" : "terminal.fill")
                                    .font(.title2)
                                    .foregroundStyle(pkg.kind == .cask ? Color.blue : Color.green)
                                    .frame(width: 40, height: 40)
                                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pkg.name).font(.headline)
                                    Text(pkg.description.isEmpty ? (pkg.kind == .cask ? "macOS Application" : "Command-line tool") : pkg.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                AppStoreActionButton(manager: manager, package: pkg, size: .small)
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        }

                        // Batch Install All Tools in Story
                        let uninstalledPackages = story.featuredPackageIDs.compactMap { id -> BrewStorePackage? in
                            let p = manager.packages.first { $0.id == id } ?? BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: .formula)
                            return p.isInstalled ? nil : p
                        }

                        if !uninstalledPackages.isEmpty {
                            Button {
                                BrewStoreActionReviewCoordinator.shared.requestInstall(
                                    packages: uninstalledPackages,
                                    manager: manager,
                                    onConfirm: {
                                        for p in uninstalledPackages {
                                            manager.perform(package: p, action: .install)
                                        }
                                    }
                                )
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text(uninstalledPackages.count == 1 ? "Install \(uninstalledPackages[0].name)" : "Install \(uninstalledPackages.count) Featured Packages")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(manager.isOperating)
                        }
                    }

                    // Interactive blank space at the bottom to dismiss/go back
                    Color.clear
                        .frame(height: 36)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleDismiss()
                        }
                }
                .padding(28)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .overlay(alignment: .topLeading) {
            Button { handleDismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)
            .keyboardShortcut(.escape, modifiers: [])
            .padding(16)
        }
        .overlay(alignment: .topTrailing) {
            Button { handleDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8), .black.opacity(0.4))
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0
        if scanner.scanHexInt64(&hexNumber) {
            let r = Double((hexNumber & 0xff0000) >> 16) / 255
            let g = Double((hexNumber & 0x00ff00) >> 8) / 255
            let b = Double(hexNumber & 0x0000ff) / 255
            self.init(red: r, green: g, blue: b)
            return
        }
        self = .accentColor
    }
}
