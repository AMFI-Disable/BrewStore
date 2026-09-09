import AppKit
import SwiftUI

struct AppStoreActionButton: View {
    @ObservedObject var manager: HomebrewManager
    let package: BrewStorePackage
    var size: ButtonSize = .regular
    var onShowDetail: (() -> Void)?

    enum ButtonSize {
        case small
        case regular

        var controlSize: ControlSize {
            switch self {
            case .small: .small
            case .regular: .regular
            }
        }
    }

    @State private var isSpinning = false
    @ObservedObject private var pinningManager = BrewStorePackagePinningManager.shared
    @ObservedObject private var wishlistManager = BrewStoreWishlistManager.shared

    private var currentPackage: BrewStorePackage {
        manager.packages.first { $0.id == package.id && $0.kind == package.kind } ?? package
    }

    private var isOperatingThisPackage: Bool {
        guard manager.isOperating else { return false }
        if let title = manager.activeOperationTitle {
            return title.localizedCaseInsensitiveContains(currentPackage.name) ||
                title.localizedCaseInsensitiveContains(currentPackage.id)
        }
        return false
    }

    private var installedAppURL: URL? {
        guard currentPackage.kind == .cask else { return nil }
        let names = currentPackage.applicationNames.isEmpty ? [currentPackage.name] : currentPackage.applicationNames
        return BrewStoreAppIconResolver.localAppURL(for: names)
    }

    var body: some View {
        Group {
            if isOperatingThisPackage {
                // Spinning Progress Ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(isSpinning ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                }
                .frame(width: size == .small ? 24 : 30, height: size == .small ? 24 : 30)
                .onAppear { isSpinning = true }
                .onDisappear { isSpinning = false }
                .onTapGesture { manager.cancelCurrentOperation() }
                .help("Cancel operation")
            } else if currentPackage.isOutdated {
                // UPDATE button
                Button("UPDATE") {
                    BrewStoreActionReviewCoordinator.shared.requestUpgrade(package: currentPackage, manager: manager) {
                        manager.perform(package: currentPackage, action: .upgrade)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(size.controlSize)
                .font(.system(size: size == .small ? 11 : 12, weight: .bold, design: .rounded))
                .clipShape(Capsule())
                .disabled(manager.isOperating)
            } else if currentPackage.isInstalled {
                // OPEN / INSTALLED button with action menu
                Menu {
                    Button {
                        wishlistManager.toggleWishlist(id: currentPackage.id)
                    } label: {
                        Label(
                            wishlistManager.isWishlisted(id: currentPackage.id) ? "Unstar (Remove from Wishlist)" : "Star (Add to Wishlist)",
                            systemImage: wishlistManager.isWishlisted(id: currentPackage.id) ? "star.slash" : "star.fill"
                        )
                    }

                    if currentPackage.kind == .cask {
                        if let appURL = installedAppURL {
                            Button("Open Application") {
                                NSWorkspace.shared.open(appURL)
                            }
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([appURL])
                            }
                        }
                    } else {
                        if let cellar = currentPackage.cellarURL(prefix: manager.brewPrefix) {
                            Button("Show in Cellar") {
                                NSWorkspace.shared.activateFileViewerSelecting([cellar])
                            }
                        }
                        let isPinning = pinningManager.isPinningInProgress(packageID: currentPackage.id)
                        let isPinned = pinningManager.isPinned(packageID: currentPackage.id)
                        Button {
                            pinningManager.togglePin(package: currentPackage, manager: manager)
                        } label: {
                            if isPinning {
                                Label(isPinned ? "Unpinning…" : "Pinning…", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label(
                                    isPinned ? "Unpin Version" : "Pin Version",
                                    systemImage: isPinned ? "pin.slash" : "pin.fill"
                                )
                            }
                        }
                        .disabled(manager.isOperating || isPinning)
                        Button("Unlink Formula") {
                            manager.unlink(package: currentPackage)
                        }
                    }

                    if let onShowDetail {
                        Button("View Details", action: onShowDetail)
                    }

                    Divider()

                    Button("Uninstall…", role: .destructive) {
                        BrewStoreUninstallCoordinator.shared.requestUninstall(package: currentPackage, manager: manager)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if currentPackage.kind == .cask {
                            Text("OPEN")
                                .font(.system(size: size == .small ? 11 : 12, weight: .bold, design: .rounded))
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("INSTALLED")
                                .font(.system(size: size == .small ? 10 : 11, weight: .bold, design: .rounded))
                        }
                    }
                    .padding(.horizontal, size == .small ? 11 : 14)
                    .padding(.vertical, size == .small ? 5 : 6)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                    .foregroundStyle(.primary)
                }
                .menuStyle(.borderlessButton)
            } else {
                // GET button
                Button("GET") {
                    BrewStoreActionReviewCoordinator.shared.requestInstall(package: currentPackage, manager: manager) {
                        manager.perform(package: currentPackage, action: .install)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .controlSize(size.controlSize)
                .font(.system(size: size == .small ? 11 : 12, weight: .bold, design: .rounded))
                .clipShape(Capsule())
                .shadow(color: Color.accentColor.opacity(0.25), radius: 4, y: 2)
                .disabled(manager.isOperating)
            }
        }
        .frame(minWidth: size == .small ? 74 : 84, alignment: .trailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPackage.isInstalled)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPackage.isOutdated)
    }
}
