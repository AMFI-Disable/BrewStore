import AppKit
import SwiftUI

struct EditorialHeroView: View {
    @ObservedObject var manager: HomebrewManager
    let onSelectPick: (BrewStoreEditorialPick) -> Void
    @ObservedObject private var wishlistManager = BrewStoreWishlistManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var coordinator = SpotlightCarouselCoordinator()
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var activityMonitor: Any?

    private var picks: [BrewStoreEditorialPick] {
        coordinator.picks
    }

    var body: some View {
        if let currentPick = coordinator.currentPick ?? picks.first {
            let installedPkg = manager.packages.first { $0.id == currentPick.id && $0.kind == currentPick.kind }
            let pkg = installedPkg ?? BrewStorePackage(
                id: currentPick.id,
                name: currentPick.name,
                description: currentPick.headline,
                homepage: "",
                version: "",
                kind: currentPick.kind
            )

            VStack(spacing: 0) {
                primaryHeroCard(pick: currentPick, package: pkg)
                    .frame(maxWidth: .infinity)
                    .onHover { coordinator.setHovering($0) }

                // Sleek Scrubber Carousel Navigation Bar
                scrubberBar(currentPick: currentPick)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            .onAppear {
                coordinator.recordUserActivity()
                if activityMonitor == nil {
                    activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { event in
                        Task { @MainActor in
                            coordinator.recordUserActivity()
                        }
                        return event
                    }
                }
                startAutoAdvance()
            }
            .onDisappear {
                if let monitor = activityMonitor {
                    NSEvent.removeMonitor(monitor)
                    activityMonitor = nil
                }
                stopAutoAdvance()
            }
        }
    }

    // MARK: - Primary Hero Card

    private func primaryHeroCard(pick: BrewStoreEditorialPick, package: BrewStorePackage) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Mesh Gradient & Ambient Glass Background
            ZStack {
                // Base Background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))

                // Multi-stop Gradient Mesh
                LinearGradient(
                    colors: [
                        pick.accentColor.opacity(0.22),
                        pick.secondaryAccentColor.opacity(0.12),
                        Color(nsColor: .controlBackgroundColor).opacity(0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Ambient Glow Sphere Behind Icon
                RadialGradient(
                    colors: [
                        pick.accentColor.opacity(0.25),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 180
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            // Content Layout
            HStack(alignment: .top, spacing: 18) {
                // Left: Large Glass Hero Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(pick.accentColor.opacity(0.18))
                        .frame(width: 52, height: 52)
                        .shadow(color: pick.accentColor.opacity(0.25), radius: 6, y: 2)

                    Image(systemName: pick.systemImage)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(pick.accentColor)
                }

                // Center/Left details
                VStack(alignment: .leading, spacing: 7) {
                    // Badges
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .bold))
                            Text(pick.badge.uppercased())
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(pick.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(pick.accentColor.opacity(0.14), in: Capsule())

                        Text(pick.kind == .cask ? "macOS App" : "CLI Tool")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.08), in: Capsule())
                            .foregroundStyle(.secondary)
                    }

                    // Title & Subtitle
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pick.name)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(pick.headline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Review Quote with accent bar
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(pick.accentColor)
                            .frame(width: 3)

                        Text(pick.review)
                            .font(.callout)
                            .foregroundStyle(.primary.opacity(0.88))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)

                    // Tags
                    HStack(spacing: 6) {
                        ForEach(Array(pick.tags.prefix(3)), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right: Action Hub
                VStack(alignment: .trailing, spacing: 8) {
                    if let feedback = coordinator.feedback(for: pick.id) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption2)
                            Text(feedback.message)
                                .font(.caption2.bold())
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.95), in: Capsule())
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel(feedback.message)
                        .accessibilityIdentifier("spotlight_feedback_\(pick.id)")
                    }

                    // Secondary Buttons: Star & Story
                    HStack(spacing: 8) {
                        let pickID = pick.id
                        let pickName = pick.name
                        let isWishlisted = wishlistManager.isWishlisted(id: pickID)
                        Button {
                            coordinator.toggleWishlist(for: pick, wishlistManager: wishlistManager)
                        } label: {
                            Image(systemName: isWishlisted ? "star.fill" : "star")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isWishlisted ? Color.yellow : Color.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            coordinator.setInteractingWithHeroAction(hovering)
                        }
                        .accessibilityLabel(isWishlisted ? "Remove \(pickName) from Wishlist" : "Add \(pickName) to Wishlist")
                        .accessibilityIdentifier("spotlight_favorite_\(pickID)")
                        .help(isWishlisted ? "Remove \(pickName) from Wishlist" : "Add \(pickName) to Wishlist")

                        if let story = BrewStoreStory.story(containingPackageID: pick.id) {
                            Button {
                                coordinator.setInteractingWithHeroAction(true)
                                onSelectPick(pick)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "book.pages")
                                        .font(.caption2)
                                    Text("Story")
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                coordinator.setInteractingWithHeroAction(hovering)
                            }
                            .accessibilityLabel("Read story for \(pickName)")
                            .help("Read Editorial Story: \(story.title)")
                        }
                    }

                    // Primary Action: GET / OPEN / UPDATE
                    AppStoreActionButton(manager: manager, package: package, size: .regular)
                        .onHover { hovering in
                            coordinator.setInteractingWithHeroAction(hovering)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            coordinator.setInteractingWithHeroAction(true)
                        })
                }
                .onHover { hovering in
                    coordinator.setInteractingWithHeroAction(hovering)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(pick.accentColor.opacity(0.28), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
        .onHover { hovering in
            coordinator.setHovering(hovering)
        }
        // Replace the action subtree when the carousel target changes so an
        // accessibility action cannot be reused for a different pick.
        .id(pick.id)
    }

    // MARK: - Scrubber Navigation Bar

    private func scrubberBar(currentPick: BrewStoreEditorialPick) -> some View {
        HStack(spacing: 12) {
            Button {
                coordinator.recordUserActivity()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    coordinator.previousPick()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.bold())
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("spotlight_prev_button")
            .accessibilityLabel("Previous spotlight pick")
            .help("Previous spotlight pick")

            // Play / Pause Auto-Advance Toggle
            Button {
                coordinator.isPaused.toggle()
                if coordinator.isPaused {
                    stopAutoAdvance()
                } else {
                    coordinator.recordUserActivity()
                    startAutoAdvance()
                }
            } label: {
                Image(systemName: coordinator.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(coordinator.isPaused ? Color.orange : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("spotlight_pause_button")
            .accessibilityLabel(coordinator.isPaused ? "Resume spotlight auto-advance" : "Pause spotlight auto-advance")
            .help(coordinator.isPaused ? "Resume spotlight auto-advance" : "Pause spotlight auto-advance")

            // Track & Scrubber Indicator
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)

                    let progressWidth = max(16, geo.size.width / CGFloat(picks.count))
                    Capsule()
                        .fill(currentPick.accentColor)
                        .frame(width: progressWidth, height: 4)
                        .offset(x: CGFloat(coordinator.currentIndex) * (geo.size.width - progressWidth) / CGFloat(max(1, picks.count - 1)))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: coordinator.currentIndex)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 140, height: 16)

            Button {
                coordinator.recordUserActivity()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    coordinator.nextPick()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("spotlight_next_button")
            .accessibilityLabel("Next spotlight pick")
            .help("Next spotlight pick")

            Spacer()

            HStack(spacing: 4) {
                Text("\(coordinator.currentIndex + 1)")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.primary)
                Text("of \(picks.count) Picks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startAutoAdvance() {
        guard !coordinator.isPaused, !reduceMotion else { return }
        stopAutoAdvance()
        autoAdvanceTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000) // 120 seconds (2 minutes)
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    if coordinator.canAutoAdvance(reduceMotion: reduceMotion) {
                        _ = withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            coordinator.advanceIfAllowed(reduceMotion: reduceMotion)
                        }
                    }
                }
            }
        }
    }

    private func stopAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }
}

extension BrewStoreEditorialPick {
    var accentColor: Color {
        switch accentColorName.lowercased() {
        case "purple": Color.purple
        case "blue": Color.blue
        case "orange": Color.orange
        case "indigo": Color.indigo
        case "cyan": Color.cyan
        case "teal": Color.teal
        case "green": Color.green
        case "mint": Color.mint
        case "pink": Color.pink
        case "red": Color.red
        case "yellow": Color.yellow
        default: Color.accentColor
        }
    }

    var secondaryAccentColor: Color {
        switch accentColorName.lowercased() {
        case "purple": Color.pink
        case "blue": Color.cyan
        case "orange": Color.yellow
        case "indigo": Color.purple
        case "cyan": Color.blue
        case "teal": Color.mint
        case "green": Color.teal
        case "mint": Color.cyan
        case "pink": Color.purple
        case "red": Color.orange
        case "yellow": Color.orange
        default: Color.purple
        }
    }
}
