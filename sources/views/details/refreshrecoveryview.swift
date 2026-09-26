import SwiftUI

struct BrewStoreRefreshRecoveryBanner: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var discovery: BrewStoreDiscoveryCatalog
    let onRetry: () -> Void
    let onClearCacheAndRetry: () -> Void

    var body: some View {
        if manager.catalogRefreshError != nil || discovery.errorMessage != nil {
            let raw = manager.errorMessage ?? discovery.errorMessage ?? "Catalog refresh failed."
            let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: info.iconName)
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.subheadline.bold())
                    Text(info.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !info.suggestion.isEmpty {
                        Text(info.suggestion)
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
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
