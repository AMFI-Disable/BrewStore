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
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stories").font(.largeTitle.bold())
                        Text("Deep-dive guides, setup walkthroughs, and curated Mac software collections.")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    BrewStoreSectionSearchBar(
                        text: $searchQuery,
                        placeholder: "Search stories and featured tools…",
                        count: filteredStories.count
                    )
                    .frame(minWidth: 220, maxWidth: 320)
                }
                .padding(.horizontal)
                .padding(.top)

                if filteredStories.isEmpty {
                    ContentUnavailableView(
                        "No Stories Found",
                        systemImage: "book.closed",
                        description: Text("No stories or featured packages match \"\(searchQuery)\".")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 580), spacing: 20)], spacing: 20) {
                        ForEach(filteredStories) { story in
                            Button {
                                selectedStory = story
                            } label: {
                                StoryCard(story: story)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
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
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(hex: story.gradientColors.first ?? "#1e293b"), Color(hex: story.gradientColors.last ?? "#0f172a")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 180)

                VStack(alignment: .leading, spacing: 6) {
                    Text(story.eyebrow)
                        .font(.caption.monospaced().bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.white)

                    Text(story.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)

                    Text(story.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Text("\(story.readTimeMinutes) min read")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Read Story →")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}
