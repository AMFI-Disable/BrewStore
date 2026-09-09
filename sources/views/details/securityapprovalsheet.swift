import SwiftUI

struct SecurityApprovalSheet: View {
    let package: BrewStorePackage
    let permissions: [TCCPermissionKind]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.square.on.square.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
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

            VStack(spacing: 12) {
                ForEach(permissions) { perm in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: perm.systemImage)
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
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
                    .padding(12)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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
        .padding(24)
        .frame(minWidth: 520, minHeight: 380)
    }
}
