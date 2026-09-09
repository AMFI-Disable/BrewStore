import AppKit
import SwiftUI

struct BrewStorePackageContextMenu: ViewModifier {
    @ObservedObject var manager: HomebrewManager
    let package: BrewStorePackage
    let onShowDetails: (() -> Void)?

    @ObservedObject private var pinningManager = BrewStorePackagePinningManager.shared
    @ObservedObject private var wishlistManager = BrewStoreWishlistManager.shared

    private var installedAppURL: URL? {
        guard package.kind == .cask, package.isInstalled else { return nil }
        let names = package.applicationNames.isEmpty ? [package.name] : package.applicationNames
        return BrewStoreAppIconResolver.localAppURL(for: names)
    }

    private var caskroomURL: URL? {
        guard package.kind == .cask, package.isInstalled else { return nil }
        let prefix = manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let candidate = URL(fileURLWithPath: prefix)
            .appendingPathComponent("Caskroom", isDirectory: true)
            .appendingPathComponent(package.id, isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private var cellarURL: URL? {
        package.cellarURL(prefix: manager.brewPrefix)
    }

    private var homepageURL: URL? {
        guard !package.homepage.isEmpty else { return nil }
        return URL(string: package.homepage)
    }

    private var homebrewURL: URL? {
        guard package.tap == nil || package.tap == "homebrew/core" || package.tap == "homebrew/cask" else { return nil }
        let kindPath = package.kind == .cask ? "cask" : "formula"
        let encodedID = package.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? package.id
        return URL(string: "https://formulae.brew.sh/\(kindPath)/\(encodedID)")
    }

    private var installCommand: String {
        "brew install \(package.kind.brewFlag) \(package.id)"
    }

    private var upgradeCommand: String {
        "brew upgrade \(package.kind.brewFlag) \(package.id)"
    }

    private var uninstallCommand: String {
        "brew uninstall \(package.kind.brewFlag) \(package.id)"
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let onShowDetails {
                    Button("View Details", action: onShowDetails)
                    Divider()
                }

                if let installedAppURL {
                    Button("Open Application") {
                        NSWorkspace.shared.open(installedAppURL)
                    }
                    Button("Show Application in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([installedAppURL])
                    }
                }

                if let caskroomURL {
                    Button("Show Cask Files in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([caskroomURL])
                    }
                }

                if let cellarURL {
                    Button("Show Formula in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([cellarURL])
                    }
                }

                if installedAppURL != nil || caskroomURL != nil || cellarURL != nil {
                    Divider()
                }

                if let homepageURL {
                    Button("Open Homepage") {
                        NSWorkspace.shared.open(homepageURL)
                    }
                }

                if let homebrewURL {
                    Button("Open Homebrew Page") {
                        NSWorkspace.shared.open(homebrewURL)
                    }
                }

                Button("Copy Package ID") {
                    copyToPasteboard(package.id)
                }
                Button("Copy Install Command") {
                    copyToPasteboard(installCommand)
                }

                if package.isInstalled {
                    Button("Copy Upgrade Command") {
                        copyToPasteboard(upgradeCommand)
                    }
                    Button("Copy Uninstall Command") {
                        copyToPasteboard(uninstallCommand)
                    }
                }

                Divider()

                let isWishlisted = wishlistManager.isWishlisted(id: package.id)
                Button {
                    wishlistManager.toggleWishlist(id: package.id)
                } label: {
                    Label(
                        isWishlisted ? "Unstar (Remove from Wishlist)" : "Star (Add to Wishlist)",
                        systemImage: isWishlisted ? "star.slash" : "star.fill"
                    )
                }

                if package.isInstalled, package.kind == .formula {
                    let isPinned = pinningManager.isPinned(packageID: package.id)
                    let isPinning = pinningManager.isPinningInProgress(packageID: package.id)
                    Button {
                        pinningManager.togglePin(package: package, manager: manager)
                    } label: {
                        if isPinning {
                            Label(isPinned ? "Unpinning…" : "Pinning…", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label(isPinned ? "Unpin Version" : "Pin Version", systemImage: isPinned ? "pin.slash" : "pin.fill")
                        }
                    }
                    .disabled(manager.isOperating || !manager.isAvailable || isPinning)

                    Button("Link Formula") {
                        manager.link(package: package)
                    }
                    .disabled(manager.isOperating || !manager.isAvailable)

                    Button("Unlink Formula") {
                        manager.unlink(package: package)
                    }
                    .disabled(manager.isOperating || !manager.isAvailable)
                }

                Divider()

                if package.isInstalled {
                    if package.isOutdated {
                        Button("Upgrade") {
                            manager.perform(package: package, action: .upgrade)
                        }
                        .disabled(manager.isOperating || !manager.isAvailable)
                    }

                    Button("Reinstall") {
                        manager.perform(package: package, action: .reinstall)
                    }
                    .disabled(manager.isOperating || !manager.isAvailable)

                    Button("Uninstall…", role: .destructive) {
                        BrewStoreUninstallCoordinator.shared.requestUninstall(package: package, manager: manager)
                    }
                    .disabled(manager.isOperating || !manager.isAvailable)
                } else {
                    Button("Install") {
                        manager.perform(package: package, action: .install)
                    }
                    .disabled(manager.isOperating || !manager.isAvailable)
                }
            }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

extension View {
    func brewStorePackageContextMenu(
        package: BrewStorePackage,
        manager: HomebrewManager,
        onShowDetails: (() -> Void)? = nil
    ) -> some View {
        modifier(BrewStorePackageContextMenu(manager: manager, package: package, onShowDetails: onShowDetails))
    }
}
