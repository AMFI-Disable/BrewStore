import AppKit
import Foundation

public enum ShowdownPhase: String, Codable, Sendable {
    case qualifying
    case showdown
    case completed

    public var displayName: String {
        switch self {
        case .qualifying: "Voting Round"
        case .showdown: "Head-to-Head"
        case .completed: "Season Champion"
        }
    }

    public var badgeIcon: String {
        switch self {
        case .qualifying: "flag.checkered"
        case .showdown: "flame.fill"
        case .completed: "crown.fill"
        }
    }
}

public struct ShowdownNominee: Identifiable, Codable, Hashable, Sendable {
    public var id: String {
        "\(packageKind):\(packageID.lowercased())"
    }

    public let packageID: String
    public let packageKind: String
    public let name: String
    public let summary: String
    public var commentID: String?
    public var voteCount: Int
    public var hasVoted: Bool
    public let authorLogin: String?
    public var isInstalled: Bool
    public let nominatedAt: Date

    public init(
        packageID: String,
        packageKind: String,
        name: String,
        summary: String,
        commentID: String? = nil,
        voteCount: Int = 1,
        hasVoted: Bool = false,
        authorLogin: String? = nil,
        isInstalled: Bool = false,
        nominatedAt: Date = Date()
    ) {
        self.packageID = packageID
        self.packageKind = packageKind
        self.name = name
        self.summary = summary
        self.commentID = commentID
        self.voteCount = voteCount
        self.hasVoted = hasVoted
        self.authorLogin = authorLogin
        self.isInstalled = isInstalled
        self.nominatedAt = nominatedAt
    }
}

public struct ShowdownMatchup: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let candidateA: ShowdownNominee
    public let candidateB: ShowdownNominee
    public var votesA: Int
    public var votesB: Int
    public var userChoice: String?

    public var totalVotes: Int {
        votesA + votesB
    }

    public var percentageA: Double {
        guard totalVotes > 0 else { return 50.0 }
        return (Double(votesA) / Double(totalVotes)) * 100.0
    }

    public var percentageB: Double {
        guard totalVotes > 0 else { return 50.0 }
        return (Double(votesB) / Double(totalVotes)) * 100.0
    }

    public init(
        id: String,
        title: String,
        candidateA: ShowdownNominee,
        candidateB: ShowdownNominee,
        votesA: Int = 0,
        votesB: Int = 0,
        userChoice: String? = nil
    ) {
        self.id = id
        self.title = title
        self.candidateA = candidateA
        self.candidateB = candidateB
        self.votesA = votesA
        self.votesB = votesB
        self.userChoice = userChoice
    }
}

public struct HallOfFameEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String {
        "\(packageKind):\(packageID.lowercased())"
    }

    public let packageID: String
    public let packageKind: String
    public let name: String
    public let seasonTitle: String
    public let crownedDate: Date
    public let retirementUntilDate: Date

    public init(
        packageID: String,
        packageKind: String,
        name: String,
        seasonTitle: String,
        crownedDate: Date,
        retirementUntilDate: Date
    ) {
        self.packageID = packageID
        self.packageKind = packageKind
        self.name = name
        self.seasonTitle = seasonTitle
        self.crownedDate = crownedDate
        self.retirementUntilDate = retirementUntilDate
    }
}

public struct ShowdownSeason: Identifiable, Codable, Sendable {
    public let id: String
    public let title: String
    public let themeDescription: String
    public var phase: ShowdownPhase
    public let phaseEndTime: Date
    public let discussionID: String?
    public let discussionNumber: Int?
    public var retiredPackageIDs: Set<String>
    public var nominees: [ShowdownNominee]
    public var matchups: [ShowdownMatchup]

    public var timeRemainingString: String {
        let diff = phaseEndTime.timeIntervalSince(Date())
        if diff <= 0 {
            return "Voting Closed"
        }
        let hours = Int(diff) / 3600
        let days = hours / 24
        let remainingHours = hours % 24
        if days > 0 {
            return "\(days)d \(remainingHours)h left"
        }
        let mins = (Int(diff) % 3600) / 60
        return "\(hours)h \(mins)m left"
    }

    public init(
        id: String,
        title: String,
        themeDescription: String,
        phase: ShowdownPhase,
        phaseEndTime: Date,
        discussionID: String? = nil,
        discussionNumber: Int? = nil,
        retiredPackageIDs: Set<String> = [],
        nominees: [ShowdownNominee] = [],
        matchups: [ShowdownMatchup] = []
    ) {
        self.id = id
        self.title = title
        self.themeDescription = themeDescription
        self.phase = phase
        self.phaseEndTime = phaseEndTime
        self.discussionID = discussionID
        self.discussionNumber = discussionNumber
        self.retiredPackageIDs = retiredPackageIDs
        self.nominees = nominees
        self.matchups = matchups
    }
}

@MainActor
public final class CommunityShowdownManager: ObservableObject {
    public static let shared = CommunityShowdownManager()

    @Published public var currentSeason: ShowdownSeason?
    @Published public var hallOfFame: [HallOfFameEntry] = []
    @Published public var isLoading: Bool = false
    @Published public var isSubmitting: Bool = false
    @Published public var statusMessage: String?

    private let cacheKey = "BrewStore.showdown.currentSeason.v1"
    private let hallOfFameKey = "BrewStore.showdown.hallOfFame.v1"

    public init() {
        loadHallOfFame()
        loadCachedSeason()
    }

    public func resetShowdown() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: hallOfFameKey)
        loadHallOfFame()
        self.currentSeason = Self.makeDefaultSeason(hallOfFame: hallOfFame)
    }

    public func resetForTesting() {
        resetShowdown()
    }

    public func loadHallOfFame() {
        if let data = UserDefaults.standard.data(forKey: hallOfFameKey),
           let decoded = try? JSONDecoder().decode([HallOfFameEntry].self, from: data) {
            self.hallOfFame = decoded
        } else {
            // Seed initial Hall of Fame with legendary giants so they don't dominate early seasons
            let calendar = Calendar.current
            let sixMonthsAhead = calendar.date(byAdding: .month, value: 6, to: Date()) ?? Date()
            self.hallOfFame = [
                HallOfFameEntry(
                    packageID: "git",
                    packageKind: "formula",
                    name: "Git",
                    seasonTitle: "Community Favorites",
                    crownedDate: Date(),
                    retirementUntilDate: sixMonthsAhead
                ),
                HallOfFameEntry(
                    packageID: "docker",
                    packageKind: "cask",
                    name: "Docker",
                    seasonTitle: "Community Favorites",
                    crownedDate: Date(),
                    retirementUntilDate: sixMonthsAhead
                ),
                HallOfFameEntry(
                    packageID: "visual-studio-code",
                    packageKind: "cask",
                    name: "Visual Studio Code",
                    seasonTitle: "Community Favorites",
                    crownedDate: Date(),
                    retirementUntilDate: sixMonthsAhead
                )
            ]
            saveHallOfFame()
        }
    }

    private func saveHallOfFame() {
        if let data = try? JSONEncoder().encode(hallOfFame) {
            UserDefaults.standard.set(data, forKey: hallOfFameKey)
        }
    }

    public func loadCachedSeason() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode(ShowdownSeason.self, from: data) {
            self.currentSeason = decoded
        } else {
            self.currentSeason = Self.makeDefaultSeason(hallOfFame: hallOfFame)
        }
    }

    public func saveSeason() {
        guard let season = currentSeason else { return }
        if let data = try? JSONEncoder().encode(season) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    public static func makeDefaultSeason(hallOfFame: [HallOfFameEntry]) -> ShowdownSeason {
        let calendar = Calendar.current
        let threeDaysLater = calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        let retired = Set(hallOfFame.map { $0.packageID.lowercased() })

        let initialNominees = [
            ShowdownNominee(
                packageID: "ripgrep",
                packageKind: "formula",
                name: "ripgrep",
                summary: "Fast code search tool written in Rust that respects your .gitignore.",
                voteCount: 42,
                hasVoted: false,
                authorLogin: "burntsushi"
            ),
            ShowdownNominee(
                packageID: "fd",
                packageKind: "formula",
                name: "fd",
                summary: "Simple, fast and user-friendly alternative to find.",
                voteCount: 38,
                hasVoted: false,
                authorLogin: "sharkdp"
            ),
            ShowdownNominee(
                packageID: "bat",
                packageKind: "formula",
                name: "bat",
                summary: "Cat clone with syntax highlighting and Git integration.",
                voteCount: 35,
                hasVoted: false,
                authorLogin: "sharkdp"
            ),
            ShowdownNominee(
                packageID: "eza",
                packageKind: "formula",
                name: "eza",
                summary: "Modern, maintained replacement for ls with colors and icons.",
                voteCount: 29,
                hasVoted: false,
                authorLogin: "eza-community"
            ),
            ShowdownNominee(
                packageID: "ghostty",
                packageKind: "cask",
                name: "Ghostty",
                summary: "Fast, native, GPU-accelerated terminal emulator for macOS.",
                voteCount: 24,
                hasVoted: false,
                authorLogin: "mitchellh"
            ),
            ShowdownNominee(
                packageID: "dust",
                packageKind: "formula",
                name: "dust",
                summary: "A more intuitive version of du in Rust.",
                voteCount: 19,
                hasVoted: false,
                authorLogin: "bootandy"
            )
        ]

        let matchups = [
            ShowdownMatchup(
                id: "matchup_semi_1",
                title: "Speed Grep vs Modern Find",
                candidateA: initialNominees[0],
                candidateB: initialNominees[1],
                votesA: 64,
                votesB: 51
            ),
            ShowdownMatchup(
                id: "matchup_semi_2",
                title: "Smarter Cat vs Modern Ls",
                candidateA: initialNominees[2],
                candidateB: initialNominees[3],
                votesA: 48,
                votesB: 55
            )
        ]

        return ShowdownSeason(
            id: "season_2026_w35",
            title: "Season 1: Modern Rust CLI Rewrites",
            themeDescription: "Vote for the ultimate modern CLI tools that speed up your daily terminal workflow! Qualifying is open: nominate your top picks or upvote existing contenders.",
            phase: .qualifying,
            phaseEndTime: threeDaysLater,
            retiredPackageIDs: retired,
            nominees: initialNominees,
            matchups: matchups
        )
    }

    func isEligibleForNomination(_ package: BrewStorePackage) -> (eligible: Bool, reason: String?) {
        let lowerID = package.id.lowercased()

        // 1. Must not be in Hall of Fame (retired)
        if let season = currentSeason, season.retiredPackageIDs.contains(lowerID) {
            return (false, "\(package.name) is currently retired in the Hall of Fame.")
        }

        // 2. Must not be already nominated
        if let season = currentSeason, season.nominees.contains(where: { $0.packageID.lowercased() == lowerID }) {
            return (false, "\(package.name) has already been nominated for this season.")
        }

        // 3. Must be an official Homebrew Formula or Cask (exclude custom unverified third-party taps)
        if let tap = package.tap, !tap.isEmpty, tap != "homebrew/core", tap != "homebrew/cask" {
            return (false, "Only official formulas, casks, and new Homebrew packages are eligible.")
        }

        return (true, nil)
    }

    func nominatePackage(
        _ package: BrewStorePackage,
        manager _: HomebrewManager,
        token: String?
    ) async -> Bool {
        let (eligible, reason) = isEligibleForNomination(package)
        guard eligible else {
            statusMessage = reason ?? "Package not eligible."
            return false
        }

        isSubmitting = true
        statusMessage = "Submitting nomination for \(package.name)…"

        // Build nominee item
        let nominee = ShowdownNominee(
            packageID: package.id,
            packageKind: package.kind.rawValue,
            name: package.name,
            summary: package.description.isEmpty ? "Popular Homebrew \(package.kind.rawValue)" : package.description,
            commentID: "nominee_\(UUID().uuidString.prefix(8))",
            voteCount: 1,
            hasVoted: true,
            authorLogin: GitServiceManager.shared.activeAccount?.login ?? "community",
            isInstalled: package.isInstalled,
            nominatedAt: Date()
        )

        // Enforce single vote rule: clear any previous vote across all nominees
        if var nominees = currentSeason?.nominees {
            for i in nominees.indices {
                if nominees[i].hasVoted {
                    nominees[i].voteCount = max(0, nominees[i].voteCount - 1)
                    nominees[i].hasVoted = false
                }
            }
            currentSeason?.nominees = nominees
        }

        // Optimistically insert locally with the user's single vote
        currentSeason?.nominees.insert(nominee, at: 0)
        saveSeason()

        // If GitHub token is present, asynchronously post discussion comment via GraphQL
        if let token, !token.isEmpty {
            _ = await postNominationCommentToGitHub(nominee: nominee, token: token)
        }

        isSubmitting = false
        statusMessage = "Nominated \(package.name)! You gave your single vote."
        return true
    }

    public func toggleVote(nominee: ShowdownNominee, token: String?) async -> Bool {
        guard var season = currentSeason else { return false }
        guard let index = season.nominees.firstIndex(where: { $0.id == nominee.id }) else { return false }

        let currentlyVoted = season.nominees[index].hasVoted
        if currentlyVoted {
            season.nominees[index].voteCount = max(0, season.nominees[index].voteCount - 1)
            season.nominees[index].hasVoted = false
            statusMessage = "Removed your vote for \(nominee.name)"
        } else {
            // Enforce single vote: remove any existing vote on other nominees
            for i in season.nominees.indices {
                if season.nominees[i].hasVoted {
                    season.nominees[i].voteCount = max(0, season.nominees[i].voteCount - 1)
                    season.nominees[i].hasVoted = false
                }
            }
            season.nominees[index].voteCount += 1
            season.nominees[index].hasVoted = true
            statusMessage = "Cast your single vote for \(nominee.name)!"
        }

        self.currentSeason = season
        saveSeason()

        // Sync with GitHub Reactions API if token provided
        if let token, !token.isEmpty, let commentID = nominee.commentID {
            _ = await toggleGitHubCommentReaction(commentID: commentID, remove: currentlyVoted, token: token)
        }

        return true
    }

    public func voteMatchup(matchupID: String, candidateChoice: String, token _: String?) async -> Bool {
        guard var season = currentSeason else { return false }
        guard let idx = season.matchups.firstIndex(where: { $0.id == matchupID }) else { return false }

        var matchup = season.matchups[idx]
        if matchup.userChoice == candidateChoice {
            return true
        }

        // Revert previous vote if switching
        if let previous = matchup.userChoice {
            if previous == matchup.candidateA.id {
                matchup.votesA = max(0, matchup.votesA - 1)
            } else if previous == matchup.candidateB.id {
                matchup.votesB = max(0, matchup.votesB - 1)
            }
        }

        if candidateChoice == matchup.candidateA.id {
            matchup.votesA += 1
            matchup.userChoice = candidateChoice
            statusMessage = "Voted for \(matchup.candidateA.name)!"
        } else {
            matchup.votesB += 1
            matchup.userChoice = candidateChoice
            statusMessage = "Voted for \(matchup.candidateB.name)!"
        }

        season.matchups[idx] = matchup
        self.currentSeason = season
        saveSeason()
        return true
    }

    private func postNominationCommentToGitHub(nominee: ShowdownNominee, token: String) async -> Bool {
        // GitHub GraphQL addDiscussionComment stub / network sync
        guard let season = currentSeason, let discussionID = season.discussionID else { return false }
        let query = """
        mutation AddComment($discussionId: ID!, $body: String!) {
            addDiscussionComment(input: { discussionId: $discussionId, body: $body }) {
                comment { id }
            }
        }
        """
        let body = "<!-- brewstore-nominee: {\"id\": \"\(nominee.packageID)\", \"kind\": \"\(nominee.packageKind)\"} -->\nNomination: **\(nominee.name)**"
        let payload: [String: Any] = [
            "query": query,
            "variables": ["discussionId": discussionID, "body": body]
        ]
        guard let reqData = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "https://api.github.com/graphql") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = reqData

        let resp = try? await URLSession.shared.data(for: request)
        return (resp?.1 as? HTTPURLResponse)?.statusCode == 200
    }

    private func toggleGitHubCommentReaction(commentID: String, remove: Bool, token: String) async -> Bool {
        guard let url = URL(string: "https://api.github.com/graphql") else { return false }
        let mutationName = remove ? "removeReaction" : "addReaction"
        let query = """
        mutation ToggleReaction($subjectId: ID!) {
            \(mutationName)(input: { subjectId: $subjectId, content: THUMBS_UP }) {
                reaction { content }
            }
        }
        """
        let payload: [String: Any] = [
            "query": query,
            "variables": ["subjectId": commentID]
        ]
        guard let reqData = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = reqData

        let resp = try? await URLSession.shared.data(for: request)
        return (resp?.1 as? HTTPURLResponse)?.statusCode == 200
    }
}
