import AppKit
import SwiftUI

public struct CommunityShowdownView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var accountManager: GitHubAccountManager
    @ObservedObject private var showdown = CommunityShowdownManager.shared
    @ObservedObject private var gitService = GitServiceManager.shared

    @State private var selectedTab: ShowdownViewTab = .qualifying
    @State private var isShowingNominateSheet = false
    @State private var isShowingHallOfFameSheet = false
    @State private var isShowingGitAuthSheet = false
    @State private var nomineeSearch = ""
    @State private var celebrationNomineeID: String?

    enum ShowdownViewTab: String, CaseIterable, Identifiable {
        case qualifying = "Community Nominees"
        case brackets = "Community Showcases"

        var id: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .qualifying: "flag.checkered"
            case .brackets: "flame.fill"
            }
        }
    }

    init(manager: HomebrewManager, accountManager: GitHubAccountManager) {
        self.manager = manager
        self.accountManager = accountManager
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Header Banner
                headerBanner

                // Status message
                if let message = showdown.statusMessage {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(message)
                            .font(.callout)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm))
                }

                // Phase Switcher Tab
                Picker("Showdown View", selection: $selectedTab) {
                    ForEach(ShowdownViewTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Group {
                    if selectedTab == .qualifying {
                        qualifyingNomineesSection
                    } else {
                        tournamentBracketsSection
                    }
                }
                .id(selectedTab)
                .animation(nil, value: selectedTab)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .sheet(isPresented: $isShowingNominateSheet) {
            NominatePackageSheet(manager: manager, showdown: showdown)
        }
        .sheet(isPresented: $isShowingHallOfFameSheet) {
            HallOfFameSheet(showdown: showdown)
        }
        .sheet(isPresented: $isShowingGitAuthSheet) {
            GitHubAccountView(accountManager: accountManager, manager: manager)
        }
    }

    // MARK: - Header Banner

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.title2)
                            .foregroundColor(.orange)

                        Text(showdown.currentSeason?.title ?? "Community Picks")
                            .font(.title.bold())
                    }

                    Text("Vote for outstanding community tools and discover rising open-source software.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let season = showdown.currentSeason {
                        HStack(spacing: 8) {
                            phaseBadge(for: season.phase)

                            Text("•")
                                .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text(season.timeRemainingString)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        isShowingHallOfFameSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trophy")
                            Text("Hall of Fame")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)

                    if let account = gitService.activeAccount {
                        HStack(spacing: 6) {
                            Image(systemName: account.provider.iconName)
                            Text("@\(account.login)")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(8)
                    } else {
                        Button {
                            isShowingGitAuthSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                Text("Connect Git Account")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            if let description = showdown.currentSeason?.themeDescription {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }

    private func phaseBadge(for phase: ShowdownPhase) -> some View {
        HStack(spacing: 5) {
            Image(systemName: phase.badgeIcon)
            Text(phase.displayName)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            phase == .qualifying ? Color.yellow.opacity(0.2) :
                phase == .showdown ? Color.green.opacity(0.2) : Color.purple.opacity(0.2)
        )
        .foregroundColor(
            phase == .qualifying ? .orange :
                phase == .showdown ? .green : .purple
        )
        .cornerRadius(6)
    }

    // MARK: - Qualifying Nominees Section

    private var filteredNominees: [(offset: Int, element: ShowdownNominee)] {
        guard let nominees = showdown.currentSeason?.nominees else { return [] }
        let enumerated = Array(nominees.enumerated())
        let q = nomineeSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return enumerated }
        return enumerated.filter {
            $0.element.name.lowercased().contains(q) ||
                $0.element.id.lowercased().contains(q) ||
                $0.element.summary.lowercased().contains(q)
        }
    }

    private var qualifyingNomineesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Community Nominees (\(filteredNominees.count))")
                        .font(.title2.bold())
                    Text("Vote for your favorite tool or nominate one from Homebrew. Each person gets 1 vote per season.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                BrewStoreSectionSearchBar(
                    text: $nomineeSearch,
                    placeholder: "Search nominees…",
                    count: filteredNominees.count
                )
                .frame(minWidth: 180, maxWidth: 260)

                Button {
                    isShowingNominateSheet = true
                } label: {
                    Label("Nominate Package", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }

            if !filteredNominees.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 16)], spacing: 16) {
                    ForEach(filteredNominees, id: \.element.id) { index, nominee in
                        nomineeCard(nominee: nominee, rank: index + 1)
                    }
                }
            } else if !nomineeSearch.isEmpty {
                ContentUnavailableView(
                    "No Matching Nominees",
                    systemImage: "magnifyingglass",
                    description: Text("No nominated packages match \"\(nomineeSearch)\".")
                )
                .padding(30)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No candidates nominated yet.")
                        .font(.headline)
                    Text("Be the first to nominate a package for this season!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Nominate Package") {
                        isShowingNominateSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
        }
    }

    private func nomineeCard(nominee: ShowdownNominee, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                // Rank Badge
                Text("#\(rank)")
                    .font(.headline)
                    .foregroundColor(rank <= 3 ? .orange : .secondary)
                    .frame(width: 32, alignment: .leading)

                // Package Icon & Details
                Image(systemName: nominee.packageKind == "cask" ? "macwindow.on.rectangle" : "terminal.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(nominee.name)
                            .font(.headline)

                        Text(nominee.packageKind.capitalized)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)

                        if nominee.isInstalled {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Installed")
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.green)
                        }
                    }

                    if let author = nominee.authorLogin {
                        Text("Nominated by @\(author)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Upvote Button (1 vote per user)
                Button {
                    Task {
                        let token = gitService.activeAccount?.token
                        let success = await showdown.toggleVote(nominee: nominee, token: token)
                        if success {
                            celebrationNomineeID = nominee.id
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: nominee.hasVoted ? "heart.fill" : "heart")
                            .foregroundColor(nominee.hasVoted ? .red : .primary)
                        Text("\(nominee.voteCount)")
                            .font(.subheadline.bold())
                        if nominee.hasVoted {
                            Text("Your Vote")
                                .font(.caption2.bold())
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(nominee.hasVoted ? Color.red.opacity(0.12) : Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help(nominee.hasVoted ? "Click to remove your vote" : "Click to cast your single vote for \(nominee.name)")
            }

            Text(nominee.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(nominee.hasVoted ? Color.red.opacity(0.3) : Color(nsColor: .separatorColor), lineWidth: 1)
                )
        )
    }

    // MARK: - Tournament Brackets Section

    private var tournamentBracketsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Head-to-Head")
                    .font(.title2.bold())
                Text("Vote between top community picks to decide this season's favorite.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let matchups = showdown.currentSeason?.matchups, !matchups.isEmpty {
                VStack(spacing: 16) {
                    ForEach(matchups) { matchup in
                        matchupCard(matchup: matchup)
                    }
                }
            } else {
                Text("Brackets will open once the qualifying round completes.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    private func matchupCard(matchup: ShowdownMatchup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(matchup.title)
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                // Candidate A
                matchupCandidateButton(
                    candidate: matchup.candidateA,
                    votes: matchup.votesA,
                    percentage: matchup.percentageA,
                    isSelected: matchup.userChoice == matchup.candidateA.id
                ) {
                    Task {
                        let token = gitService.activeAccount?.token
                        _ = await showdown.voteMatchup(
                            matchupID: matchup.id,
                            candidateChoice: matchup.candidateA.id,
                            token: token
                        )
                    }
                }

                Text("VS")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                // Candidate B
                matchupCandidateButton(
                    candidate: matchup.candidateB,
                    votes: matchup.votesB,
                    percentage: matchup.percentageB,
                    isSelected: matchup.userChoice == matchup.candidateB.id
                ) {
                    Task {
                        let token = gitService.activeAccount?.token
                        _ = await showdown.voteMatchup(
                            matchupID: matchup.id,
                            candidateChoice: matchup.candidateB.id,
                            token: token
                        )
                    }
                }
            }

            // Percentage Split Bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: geo.size.width * CGFloat(matchup.percentageA / 100.0))

                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(matchup.percentageB / 100.0))
                }
            }
            .frame(height: 6)
            .cornerRadius(3)

            HStack {
                Text("\(Int(matchup.percentageA))%")
                    .font(.caption.bold())
                    .foregroundColor(.orange)

                Spacer()

                Text("\(matchup.totalVotes) total votes")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(matchup.percentageB))%")
                    .font(.caption.bold())
                    .foregroundColor(.blue)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        )
    }

    private func matchupCandidateButton(
        candidate: ShowdownNominee,
        votes: Int,
        percentage _: Double,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: candidate.packageKind == "cask" ? "macwindow.on.rectangle" : "terminal.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.headline)

                    Text("\(votes) votes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Nominate Package Sheet

struct NominatePackageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var showdown: CommunityShowdownManager
    @ObservedObject private var gitService = GitServiceManager.shared

    @State private var searchText = ""
    @State private var selectedPackage: BrewStorePackage?
    @State private var nominationError: String?

    var filteredPackages: [BrewStorePackage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pool = manager.packages.filter { pkg in
            // Filter out custom third-party taps
            if let tap = pkg.tap, !tap.isEmpty, tap != "homebrew/core", tap != "homebrew/cask" {
                return false
            }
            return true
        }
        guard !query.isEmpty else {
            return Array(pool.prefix(20))
        }
        return pool.filter {
            $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sheet Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nominate a Candidate")
                        .font(.title2.bold())
                    Text("Select an official Formula or Cask to enter into the current season.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            Divider()

            // Search Bar
            BrewStoreSectionSearchBar(
                text: $searchText,
                placeholder: "Search official formulas and casks…",
                count: filteredPackages.count
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if let error = nominationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Results List
            List(filteredPackages, selection: $selectedPackage) { pkg in
                HStack(spacing: 12) {
                    Image(systemName: pkg.kind == .cask ? "macwindow.on.rectangle" : "terminal.fill")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(pkg.name)
                                .font(.headline)
                            Text(pkg.kind.rawValue.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }

                        if !pkg.description.isEmpty {
                            Text(pkg.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    let eligibility = showdown.isEligibleForNomination(pkg)
                    if !eligibility.eligible {
                        Text(eligibility.reason ?? "Ineligible")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else if pkg.isInstalled {
                        Text("Installed")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                .tag(pkg)
            }
            .listStyle(.inset)

            Divider()

            // Bottom Action Bar
            HStack {
                if let selected = selectedPackage {
                    Text("Selected: \(selected.name)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Submit Nomination") {
                    guard let selected = selectedPackage else { return }
                    let (eligible, reason) = showdown.isEligibleForNomination(selected)
                    guard eligible else {
                        nominationError = reason
                        return
                    }

                    Task {
                        let token = gitService.activeAccount?.token
                        let success = await showdown.nominatePackage(selected, manager: manager, token: token)
                        if success {
                            dismiss()
                        } else {
                            nominationError = showdown.statusMessage
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPackage == nil || showdown.isSubmitting)
            }
            .padding(16)
        }
        .frame(width: 560, height: 500)
    }
}

// MARK: - Hall of Fame Sheet

struct HallOfFameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var showdown: CommunityShowdownManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.title)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hall of Fame")
                            .font(.title2.bold())
                        Text("Honoring past champions and ensuring fair competition for new tools.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Previous winners take a 6-month break so other useful tools have a chance to be featured.")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(12)
                .background(Color.yellow.opacity(0.12))
                .cornerRadius(8)

            List(showdown.hallOfFame) { entry in
                HStack(spacing: 14) {
                    Image(systemName: "trophy.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(entry.name)
                                .font(.headline)
                            Text(entry.packageKind.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }

                        Text("Featured: \(entry.seasonTitle)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("On break")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        Text("Eligible again on \(entry.retirementUntilDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
        .padding(20)
        .frame(width: 520, height: 440)
    }
}
