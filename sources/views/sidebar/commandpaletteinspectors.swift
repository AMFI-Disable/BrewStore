import AppKit
import SwiftUI

struct CommandPaletteRightInspectorColumn: View {
    let item: PaletteItem?
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var wishlistManager: BrewStoreWishlistManager
    @ObservedObject var pinningManager: BrewStorePackagePinningManager
    @Binding var selection: BrewStoreSection?
    @Binding var isPresented: Bool
    @Binding var selectedPackage: BrewStorePackage?
    let copyToClipboard: (String, String) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                if let item {
                    if let pkg = item.package {
                        CommandPalettePackageInspector(
                            pkg: pkg,
                            item: item,
                            manager: manager,
                            wishlistManager: wishlistManager,
                            pinningManager: pinningManager,
                            isPresented: $isPresented,
                            selectedPackage: $selectedPackage,
                            copyToClipboard: copyToClipboard
                        )
                    } else if let svc = item.service {
                        CommandPaletteServiceInspector(
                            svc: svc,
                            item: item,
                            manager: manager,
                            selection: $selection,
                            isPresented: $isPresented,
                            copyToClipboard: copyToClipboard
                        )
                    } else if item.category == .actions {
                        CommandPaletteActionInspector(
                            item: item,
                            copyToClipboard: copyToClipboard
                        )
                    } else if item.category == .navigation {
                        CommandPaletteNavigationInspector(item: item)
                    }
                } else {
                    CommandPaletteEmptyInspector()
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
}

struct CommandPalettePackageInspector: View {
    let pkg: BrewStorePackage
    let item: PaletteItem
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var wishlistManager: BrewStoreWishlistManager
    @ObservedObject var pinningManager: BrewStorePackagePinningManager
    @Binding var isPresented: Bool
    @Binding var selectedPackage: BrewStorePackage?
    let copyToClipboard: (String, String) -> Void

    var body: some View {
        let isWishlisted = wishlistManager.isWishlisted(id: pkg.id)
        let isPinned = pinningManager.isPinned(packageID: pkg.id)

        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(pkg.kind == .cask ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: pkg.kind == .cask ? "app.fill" : "terminal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(pkg.kind == .cask ? Color.blue : Color.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(pkg.name)
                        .font(.headline.bold())
                        .lineLimit(1)
                    Text(pkg.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Badges
            HStack(spacing: 6) {
                Text(pkg.kind == .cask ? "Cask App" : "Formula")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                if pkg.isInstalled {
                    Text(pkg.isOutdated ? "Outdated" : "Installed")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(pkg.isOutdated ? Color.orange.opacity(0.16) : Color.green.opacity(0.16), in: Capsule())
                        .foregroundStyle(pkg.isOutdated ? .orange : .green)
                } else {
                    Text("Available")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                if isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }

            Divider()

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("About")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(pkg.description.isEmpty ? "No description provided." : pkg.description)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Specifications
            VStack(alignment: .leading, spacing: 6) {
                Text("Specifications")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                CommandPaletteSpecRow(label: "Version", value: pkg.version.isEmpty ? "Unknown" : pkg.version)
                CommandPaletteSpecRow(label: "Tap", value: pkg.tap ?? "homebrew/core")
                if !pkg.dependencies.isEmpty {
                    CommandPaletteSpecRow(label: "Dependencies", value: "\(pkg.dependencies.count) linked")
                }
                if !pkg.homepage.isEmpty {
                    CommandPaletteSpecRow(label: "Homepage", value: pkg.homepage, isLink: true)
                }
            }

            Divider()

            // Terminal Command Snippet Box
            if let snippet = item.commandSnippet {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Terminal Command")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyToClipboard(snippet, "'\(snippet)'")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help("Copy CLI command to clipboard")
                    }

                    Text(snippet)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Quick Actions
            VStack(spacing: 6) {
                Button {
                    selectedPackage = pkg
                } label: {
                    Label("Open Package Details", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                HStack(spacing: 8) {
                    if pkg.isInstalled {
                        if pkg.isOutdated {
                            Button {
                                manager.perform(package: pkg, action: .upgrade)
                                isPresented = false
                            } label: {
                                Label("Upgrade", systemImage: "arrow.up.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.orange)
                        }

                        Button(role: .destructive) {
                            BrewStoreUninstallCoordinator.shared.requestUninstall(package: pkg, manager: manager)
                            isPresented = false
                        } label: {
                            Label("Uninstall", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button {
                            manager.perform(package: pkg, action: .install)
                            isPresented = false
                        } label: {
                            Label("Install", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.green)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        pinningManager.togglePin(package: pkg, manager: manager)
                    } label: {
                        Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        wishlistManager.toggleWishlist(id: pkg.id)
                    } label: {
                        Label(isWishlisted ? "Starred" : "Star", systemImage: isWishlisted ? "star.fill" : "star")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(isWishlisted ? Color.yellow : Color.primary)
                }
            }
        }
    }
}

struct CommandPaletteServiceInspector: View {
    let svc: BrewStoreService
    let item: PaletteItem
    @ObservedObject var manager: HomebrewManager
    @Binding var selection: BrewStoreSection?
    @Binding var isPresented: Bool
    let copyToClipboard: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "server.rack")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(svc.name)
                        .font(.headline.bold())
                        .lineLimit(1)
                    Text("Background Daemon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Status Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(svc.isRunning ? Color.green : (svc.isError ? Color.red : Color.secondary))
                    .frame(width: 8, height: 8)

                Text(svc.isRunning ? "Active Daemon" : (svc.isError ? "Error" : "Stopped"))
                    .font(.caption.bold())
                    .foregroundStyle(svc.isRunning ? .green : (svc.isError ? .red : .secondary))

                Spacer()

                if let user = svc.user, !user.isEmpty {
                    Text("User: \(user)")
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            Divider()

            // Details
            VStack(alignment: .leading, spacing: 6) {
                Text("Daemon Information")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                CommandPaletteSpecRow(label: "Status", value: svc.status.capitalized)
                if let file = svc.file {
                    CommandPaletteSpecRow(label: "Plist Path", value: file)
                }
            }

            Divider()

            // Command Snippet
            if let snippet = item.commandSnippet {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Terminal Command")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyToClipboard(snippet, "'\(snippet)'")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help("Copy CLI command to clipboard")
                    }

                    Text(snippet)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Quick Actions
            VStack(spacing: 8) {
                Button {
                    item.execute()
                } label: {
                    Label(svc.isRunning ? "Stop Service" : "Start Service", systemImage: svc.isRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(svc.isRunning ? .red : .green)

                Button {
                    manager.perform(service: svc, action: .restart)
                    isPresented = false
                } label: {
                    Label("Restart Service", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    selection = .services
                    isPresented = false
                } label: {
                    Label("View In Services Manager", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

struct CommandPaletteActionInspector: View {
    let item: PaletteItem
    let copyToClipboard: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: item.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline.bold())
                        .lineLimit(2)
                    if let badge = item.impactBadge {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }

            Divider()

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Action Description")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Command Snippet
            if let snippet = item.commandSnippet {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Equivalent CLI Command")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyToClipboard(snippet, "'\(snippet)'")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help("Copy CLI command to clipboard")
                    }

                    Text(snippet)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Divider()

            // Run Button
            Button {
                item.execute()
            } label: {
                Label("Execute Action", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
        }
    }
}

struct CommandPaletteNavigationInspector: View {
    let item: PaletteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: item.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline.bold())
                        .lineLimit(1)
                    Text("Sidebar Navigation Hub")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Destination")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let shortcut = item.shortcut {
                HStack {
                    Text("Keyboard Shortcut")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(shortcut)
                        .font(.caption.bold().monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            Divider()

            // Go Button
            Button {
                item.execute()
            } label: {
                Label("Switch to Section", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

struct CommandPaletteSpecRow: View {
    let label: String
    let value: String
    var isLink: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            if isLink, let url = URL(string: value) {
                Link(destination: url) {
                    Text(value)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text(value)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

struct CommandPaletteEmptyInspector: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "command")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Select an item to view inspector")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
