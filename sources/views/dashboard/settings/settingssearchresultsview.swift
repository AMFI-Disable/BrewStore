import AppKit
import SwiftUI

struct SettingsSearchResultsView: View {
    let query: String
    var onSelectTab: (SettingsTab) -> Void
    var onClearSearch: () -> Void

    @State private var selectedFilterTab: SettingsTab?

    private var allMatches: [SettingsSearchItem] {
        SettingsSearchEngine.search(query: query)
    }

    private var matchingTabs: [SettingsTab] {
        Array(Set(allMatches.map(\.tab))).sorted { $0.rawValue < $1.rawValue }
    }

    private var filteredResults: [SettingsSearchItem] {
        if let filter = selectedFilterTab {
            return allMatches.filter { $0.tab == filter }
        }
        return allMatches
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if allMatches.isEmpty {
                    emptyStateView
                } else {
                    summaryAndFiltersHeader
                    resultsList
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var summaryAndFiltersHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Found \(allMatches.count) \(allMatches.count == 1 ? "setting" : "settings") for “\(query)”")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button("Clear Search") {
                    onClearSearch()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if matchingTabs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip(
                            title: "All (\(allMatches.count))",
                            icon: "square.grid.2x2",
                            isSelected: selectedFilterTab == nil
                        ) {
                            selectedFilterTab = nil
                        }

                        ForEach(matchingTabs) { tab in
                            let count = allMatches.filter { $0.tab == tab }.count
                            filterChip(
                                title: "\(tab.rawValue) (\(count))",
                                icon: tab.icon,
                                isSelected: selectedFilterTab == tab
                            ) {
                                selectedFilterTab = tab
                            }
                        }
                    }
                }
            }
        }
    }

    private func filterChip(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var resultsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredResults) { item in
                Button {
                    onSelectTab(item.tab)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Spacer()

                                HStack(spacing: 4) {
                                    Image(systemName: item.tab.icon)
                                        .font(.system(size: 10))
                                    Text(item.tab.rawValue)
                                        .font(.caption2.bold())
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(.secondary)
                            }

                            Text(item.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: 6) {
                                ForEach(item.keywords.prefix(4), id: \.self) { keyword in
                                    Text("#\(keyword)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                }

                                Spacer()

                                HStack(spacing: 4) {
                                    Text("Open in \(item.tab.rawValue)")
                                        .font(.caption.bold())
                                    Image(systemName: "arrow.right")
                                        .font(.caption2.bold())
                                }
                                .foregroundStyle(Color.accentColor)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.top, 40)

            Text("No Settings Found")
                .font(.title3.bold())

            Text("No configuration options match “\(query)”. Try searching for keywords like “theme”, “mirror”, “auto-refresh”, “sync”, “doctor”, or “cache”.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button("Clear Search") {
                onClearSearch()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }
}
