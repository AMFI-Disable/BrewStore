import SwiftUI

struct SecurityApprovalSheet: View {
    let package: BrewStorePackage
    let permissions: [TCCPermissionKind]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "hand.raised.square.on.square.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("System Permissions Required")
                        .font(.headline)
                    Text(package.name)
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

            Text("macOS requires user authorization before \(package.name) can run its system integrations. Review the requested permissions below:")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: Spacing.xs) {
                ForEach(permissions) { perm in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: perm.systemImage)
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(perm.rawValue)
                                .font(.subheadline.bold())
                            Text(perm.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            TCCPermissionManager.shared.openSystemSettings(for: perm)
                        } label: {
                            Label("Open Settings", systemImage: "arrow.up.forward.app")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(Spacing.sm)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.sm))
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(Spacing.lg)
        .frame(minWidth: 500, minHeight: 340)
    }
}
