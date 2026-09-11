import AppKit
import SwiftUI

struct StoriesFeedView: View {
    @ObservedObject var manager: HomebrewManager
    @State private var selectedStory: BrewStoreStory?
    @State private var searchQuery = ""

    private let stories = BrewStoreStory.allStories

    private var filteredStories: [BrewStoreStory] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return stories }
        return stories.filter {
            $0.title.lowercased().contains(q) ||
                $0.eyebrow.lowercased().contains(q) ||
                $0.subtitle.lowercased().contains(q) ||
                $0.featuredPackageIDs.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Stories").font(.title2.bold())
                        Text("Deep-dive guides, setup walkthroughs, and curated Mac software collections.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    BrewStoreSectionSearchBar(
                        text: $searchQuery,
                        placeholder: "Search stories and featured tools…",
                        count: filteredStories.count
                    )
                    .frame(minWidth: 200, maxWidth: 300)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)

                if filteredStories.isEmpty {
                    ContentUnavailableView(
                        "No Stories Found",
                        systemImage: "book.closed",
                        description: Text("No stories or featured packages match \"\(searchQuery)\".")
                    )
                    .padding(.top, Spacing.xl)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 580), spacing: Spacing.md)], spacing: Spacing.md) {
                        ForEach(filteredStories) { story in
                            Button {
                                selectedStory = story
                            } label: {
                                StoryCard(story: story)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.md)
                }
            }
        }
        .sheet(item: $selectedStory) { story in
            StoryDetailView(manager: manager, story: story)
        }
    }
}

private struct StoryCard: View {
    let story: BrewStoreStory

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(hex: story.gradientColors.first ?? "#1e293b"), Color(hex: story.gradientColors.last ?? "#0f172a")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 150)

                VStack(alignment: .leading, spacing: 4) {
                    Text(story.eyebrow)
                        .font(.caption2.monospaced().bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.white)

                    Text(story.title)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)

                    Text(story.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
                .padding(Spacing.md)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            HStack {
                Text("\(story.readTimeMinutes) min read")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Read Story →")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 4)
        }
        .padding(Spacing.sm)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}
