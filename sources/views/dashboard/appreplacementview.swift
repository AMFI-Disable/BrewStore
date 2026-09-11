import AppKit
import SwiftUI

struct AppReplacementView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var replacementManager = BrewStoreAppReplacementManager.shared
    @StateObject private var adoptionManager = BrewStoreAppAdoptionManager.shared
    @ObservedObject private var wishlistManager = BrewStoreWishlistManager.shared
    @ObservedObject private var pinningManager = BrewStorePackagePinningManager.shared
    @State private var selectedTab = 0 // 0: Detected Replacements, 1: Full Catalog
    @State private var searchText = ""
    @State private var sheetMapping: OpenSourceAlternativeMapping?
    @State private var sheetAppURL: URL?

    private var displayedCatalog: [OpenSourceAlternativeMapping] {
        let base = selectedTab == 0 ? (replacementManager.detectedAlternatives.isEmpty ? BrewStoreAppReplacementManager.curatedAlternativeCatalog : replacementManager.detectedAlternatives) : BrewStoreAppReplacementManager.curatedAlternativeCatalog
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return base
        }
        let q = searchText.lowercased()
        return base.filter {
            $0.targetProprietaryApp.lowercased().contains(q) ||
                $0.replacementName.lowercased().contains(q) ||
                $0.category.lowercased().contains(q) ||
                $0.replacementPackageID.lowercased().contains(q)
        }
    }

    var showHeader: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if showHeader {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Open-Source Alternatives").font(.headline)
                    Text("Discover open-source alternatives to everyday commercial software, ready to install with Homebrew.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
            }

            // Controls Bar
            HStack(spacing: Spacing.sm) {
                Picker("", selection: $selectedTab) {
                    Text("Suggested Replacements (\(replacementManager.detectedAlternatives.count))").tag(0)
                    Text("Full Directory (\(BrewStoreAppReplacementManager.curatedAlternativeCatalog.count))").tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search replacements by app or category…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .frame(minWidth: 180, maxWidth: 280)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, showHeader ? 0 : Spacing.sm)

            // Replacements List
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(displayedCatalog) { mapping in
                        replacementCard(for: mapping)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
            .id(selectedTab)
            .animation(nil, value: selectedTab)
        }
        .sheet(item: $sheetMapping) { mapping in
            AppReplacementSheet(
                mapping: mapping,
                detectedAppURL: sheetAppURL,
                manager: manager
            )
        }
        .onAppear {
            if adoptionManager.scannedApps.isEmpty {
                adoptionManager.scanApplications(manager: manager)
            }
            replacementManager.scanForReplacements(scannedApps: adoptionManager.scannedApps)
        }
    }

    @ViewBuilder
    private func replacementCard(for mapping: OpenSourceAlternativeMapping) -> some View {
        let isInstalled = manager.packages.contains { $0.id == mapping.replacementPackageID && $0.isInstalled }
        let detectedApp = replacementManager.findMatchingScannedApp(for: mapping, in: adoptionManager.scannedApps)
        let detectedURL = replacementManager.findAppBundleURL(for: mapping, scannedApps: adoptionManager.scannedApps)
        let isTargetAppInstalled = detectedURL != nil || detectedApp != nil

        VStack(alignment: .leading, spacing: 10) {
            // Top Row
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text(mapping.targetProprietaryApp)
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "arrow.right")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                    Text(mapping.replacementName)
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(mapping.category)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)

                if isTargetAppInstalled, !isInstalled {
                    HStack(spacing: 3) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 8))
                        Text("Detected on Mac")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    let isWishlisted = wishlistManager.isWishlisted(id: mapping.replacementPackageID)
                    Button {
                        wishlistManager.toggleWishlist(id: mapping.replacementPackageID)
                    } label: {
                        Image(systemName: isWishlisted ? "star.fill" : "star")
                            .foregroundStyle(isWishlisted ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isWishlisted ? "Remove from Wishlist" : "Add to Wishlist")

                    if isInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Installed via Brew")
                                .font(.caption2.bold())
                                .foregroundStyle(.green)
                        }
                    } else if isTargetAppInstalled {
                        Button {
                            sheetAppURL = detectedURL
                            sheetMapping = mapping
                        } label: {
                            Label("Replace & Migrate", systemImage: "sparkles.rectangle.stack.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(manager.isOperating)
                    } else {
                        Button {
                            replacementManager.installReplacement(mapping: mapping, manager: manager)
                        } label: {
                            Label("Install (\(mapping.replacementPackageID))", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(manager.isOperating)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            // Reasoning Text
            Text(mapping.whyReplace)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Advantages Bullet Tags
            HStack(spacing: 8) {
                ForEach(Array(mapping.advantages.prefix(3)), id: \.self) { adv in
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.green)
                        Text(adv).font(.caption2).lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isInstalled ? Color.green.opacity(0.2) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - App Replacement Sheet Component

struct AppReplacementSheet: View {
    let mapping: OpenSourceAlternativeMapping
    let detectedAppURL: URL?
    @ObservedObject var manager: HomebrewManager
    @ObservedObject private var moleManager = BrewStoreMoleManager.shared
    @ObservedObject private var preferences = BrewStorePreferences.shared

    @State private var selectedMode: BrewStoreAppUninstallMode = .preserveData
    @State private var isExecuting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Switch Application")
                        .font(.title3.bold())
                    Text("Switch from \(mapping.targetProprietaryApp) to \(mapping.replacementName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Source App & Detection status
            HStack(spacing: 8) {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.secondary)
                Text("Detected Application:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(detectedAppURL?.path ?? "\(mapping.targetProprietaryApp).app (Detected)")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            // Strategy Picker Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Old App Options")
                    .font(.headline)

                VStack(spacing: 8) {
                    ForEach(BrewStoreAppUninstallMode.allCases) { mode in
                        modeOptionRow(mode)
                    }
                }
            }

            if selectedMode == .purgeAllData {
                HStack(spacing: 10) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Native macOS Safe Cleanup")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text("The app bundle and leftover settings, caches, and support files will be moved to macOS Trash.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if moleManager.isAvailable {
                        Text("Mole Active")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
            }

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Divider()

            // Footer Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    executeReplacement()
                } label: {
                    if isExecuting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Label("Execute Replacement", systemImage: "arrow.right.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExecuting)
            }
        }
        .padding(20)
        .frame(width: 540, height: 480)
        .onAppear {
            self.selectedMode = preferences.defaultUninstallMode
        }
    }

    @ViewBuilder
    private func modeOptionRow(_ mode: BrewStoreAppUninstallMode) -> some View {
        let isSelected = selectedMode == mode
        Button {
            selectedMode = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.system(size: 14))
                    .padding(.top, 2)

                Image(systemName: mode.icon)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.system(size: 16))
                    .frame(width: 20)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func executeReplacement() {
        isExecuting = true
        errorMessage = nil

        Task {
            let (success, message) = await BrewStoreAppReplacementManager.shared.executeReplacement(
                mapping: mapping,
                mode: selectedMode,
                appURL: detectedAppURL,
                manager: manager
            )
            isExecuting = false
            if success {
                dismiss()
            } else {
                errorMessage = message
            }
        }
    }
}
