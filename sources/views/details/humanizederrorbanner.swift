import AppKit
import SwiftUI

struct HumanizedErrorBanner: View {
    let rawError: String
    var titleOverride: String?
    var manager: HomebrewManager?
    var package: BrewStorePackage?
    var onDismiss: (() -> Void)?
    var customActionTitle: String?
    var customAction: (() -> Void)?

    @State private var copiedCommand: String?

    init(
        rawError: String,
        titleOverride: String? = nil,
        manager: HomebrewManager? = nil,
        package: BrewStorePackage? = nil,
        onDismiss: (() -> Void)? = nil,
        customActionTitle: String? = nil,
        customAction: (() -> Void)? = nil
    ) {
        self.rawError = rawError
        self.titleOverride = titleOverride
        self.manager = manager
        self.package = package
        self.onDismiss = onDismiss
        self.customActionTitle = customActionTitle
        self.customAction = customAction
    }

    public var body: some View {
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: rawError)
        let displayTitle = titleOverride ?? info.title

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: info.iconName)
                    .font(.headline)
                    .foregroundStyle(.red)

                Text(displayTitle)
                    .font(.headline)
                    .foregroundStyle(.red)

                Spacer()

                Text(info.category.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .foregroundStyle(.red)

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                    .help("Dismiss error message")
                }
            }

            Text(info.summary)
                .font(.callout)
                .foregroundStyle(.primary)

            Text(info.suggestion)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Quick Action Buttons
            HStack(spacing: 8) {
                if let mgr = manager, let pkg = package, mgr.lastOperationRequiresElevation || info.category == .permissions {
                    Button {
                        let action: PackageAction = pkg.isInstalled ? .upgrade : .install
                        mgr.performElevated(package: pkg, action: action)
                    } label: {
                        Label("Rerun with Administrator Privileges", systemImage: "lock.shield.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if let mgr = manager, info.category == .lock {
                    Button {
                        mgr.clearLocks()
                    } label: {
                        Label("Clear Homebrew Locks", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if info.category == .developerTools {
                    let cmd = "xcode-select --install"
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                        copiedCommand = cmd
                    } label: {
                        Label(copiedCommand == cmd ? "Copied!" : "Copy Install Command", systemImage: "terminal.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let actionTitle = customActionTitle, let action = customAction {
                    Button(actionTitle) {
                        action()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color.red.opacity(0.25), lineWidth: 1))
        .textSelection(.enabled)
    }
}
