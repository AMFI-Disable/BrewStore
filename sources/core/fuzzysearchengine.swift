import Foundation

/// Fast in-memory fuzzy matching engine designed for instant, Raycast-like package search.
enum BrewStoreFuzzySearchEngine {
    /// Evaluates the match score between a user query and a target string.
    /// Higher scores represent closer, more relevant matches. Returns 0 if there is no match.
    static func score(query: String, target: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !q.isEmpty, !t.isEmpty else { return 0 }

        // 1. Exact match
        if q == t {
            return 1000
        }

        // 2. Exact prefix match
        if t.hasPrefix(q) {
            return 800 + max(0, 100 - t.count)
        }

        // 3. Exact substring match
        if let range = t.range(of: q) {
            let distance = t.distance(from: t.startIndex, to: range.lowerBound)
            return 500 + max(0, 100 - distance)
        }

        // 4. Acronym / Word boundary match (e.g., "vsc" -> "visual-studio-code", "rg" -> "ripgrep")
        let boundaries = extractBoundaryCharacters(t)
        if boundaries.contains(q) || boundaries.hasPrefix(q) {
            return 450 + max(0, 50 - t.count)
        }

        // 5. Subsequence fuzzy match with consecutive run bonuses
        return calculateSubsequenceScore(query: q, target: t)
    }

    /// Evaluates the best match score across multiple candidate fields (e.g. name, id, description).
    static func bestScore(query: String, targets: [String]) -> Int {
        var highest = 0
        for target in targets {
            let s = score(query: query, target: target)
            if s > highest {
                highest = s
            }
        }
        return highest
    }

    /// Filters and ranks an array of items based on fuzzy search relevance.
    static func filterAndRank<T>(
        items: [T],
        query: String,
        minimumScore: Int = 1,
        targetExtractor: (T) -> [String]
    ) -> [T] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }

        var scoredItems: [(item: T, score: Int)] = []
        scoredItems.reserveCapacity(items.count)

        for item in items {
            let targets = targetExtractor(item)
            let s = bestScore(query: q, targets: targets)
            if s >= minimumScore {
                scoredItems.append((item, s))
            }
        }

        scoredItems.sort { $0.score > $1.score }
        return scoredItems.map(\.item)
    }

    // MARK: - Private Helpers

    private static func extractBoundaryCharacters(_ string: String) -> String {
        let delimiters = CharacterSet(charactersIn: "-_/. @")
        let components = string.components(separatedBy: delimiters).filter { !$0.isEmpty }
        var result = ""
        for comp in components {
            if let first = comp.first {
                result.append(first)
            }
        }
        return result
    }

    private static func calculateSubsequenceScore(query: String, target: String) -> Int {
        let qChars = Array(query)
        let tChars = Array(target)

        var qIndex = 0
        var tIndex = 0
        var score = 0
        var consecutiveCount = 0
        var prevMatchedIndex = -1

        while qIndex < qChars.count, tIndex < tChars.count {
            if qChars[qIndex] == tChars[tIndex] {
                score += 20 // Base character match

                // Consecutive match bonus
                if prevMatchedIndex == tIndex - 1 {
                    consecutiveCount += 1
                    score += consecutiveCount * 15
                } else {
                    consecutiveCount = 0
                }

                // Word start bonus (at index 0 or right after delimiter)
                if tIndex == 0 || isDelimiter(tChars[tIndex - 1]) {
                    score += 35
                }

                prevMatchedIndex = tIndex
                qIndex += 1
            }
            tIndex += 1
        }

        // Must match all characters in the query
        if qIndex == qChars.count {
            // Penalize for long targets when query is short
            let lengthPenalty = max(0, tChars.count - qChars.count)
            return max(1, score - lengthPenalty)
        }

        return 0
    }

    private static func isDelimiter(_ char: Character) -> Bool {
        char == "-" || char == "_" || char == "/" || char == "." || char == " " || char == "@"
    }
}
