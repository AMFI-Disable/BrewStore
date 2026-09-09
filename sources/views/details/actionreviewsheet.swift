import SwiftUI

struct BrewStoreActionReviewSheet: View {
    let request: BrewStoreActionReviewRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: request.kind.icon)
                    .font(.title)
                    .foregroundStyle(request.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(request.title)
                            .font(.title2.bold())

                        if request.isDestructive {
                            Text("Destructive")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                    }

                    Text(request.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Main Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Impacted Items Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Items (\(request.items.count))")
                            .font(.headline)

                        VStack(spacing: 8) {
                            ForEach(request.items) { item in
                                HStack(alignment: .center, spacing: 12) {
                                    Image(systemName: item.icon)
                                        .font(.title3)
                                        .foregroundStyle(item.badgeColor)
                                        .frame(width: 28, height: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.title)
                                                .font(.headline)

                                            if let badge = item.badgeText {
                                                Text(badge)
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 1.5)
                                                    .background(item.badgeColor.opacity(0.12), in: Capsule())
                                                    .foregroundStyle(item.badgeColor)
                                            }
                                        }

                                        Text(item.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    if let cmd = item.command {
                                        Text(cmd)
                                            .font(.caption2.monospaced())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                            }
                        }
                    }

                    // Command Preview Section
                    if let cmdPreview = request.commandPreview, !cmdPreview.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Planned Homebrew Execution")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Text(cmdPreview)
                                .font(.system(.caption, design: .monospaced))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                                .textSelection(.enabled)
                        }
                    }

                    // Advisory Notes
                    if !request.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(request.notes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: request.isDestructive ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(request.accentColor)
                                        .padding(.top, 2)

                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(request.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            // Footer Buttons
            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(request.confirmationTitle, role: request.isDestructive ? .destructive : nil, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(request.accentColor)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
    }
}
