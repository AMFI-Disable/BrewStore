import SwiftUI

struct BrewStoreRefreshRecoveryBanner: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var discovery: BrewStoreDiscoveryCatalog
    let onRetry: () -> Void
    let onClearCacheAndRetry: () -> Void

    var body: some View {
        if manager.catalogRefreshError != nil || discovery.errorMessage != nil {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Homebrew refresh failed")
                        .font(.subheadline.bold())
                    Text(manager.errorMessage ?? discovery.errorMessage ?? "Catalog refresh failed. Tap Retry to try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 8)

                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(manager.isLoading || manager.isOperating)

                Button("Clear Cache & Retry", action: onClearCacheAndRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Purges cached Homebrew JSON manifests and forces a clean live query.")
                    .disabled(manager.isLoading || manager.isOperating)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.orange.opacity(0.12))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.orange.opacity(0.35))
                    .frame(height: 1)
            }
        }
    }
}
