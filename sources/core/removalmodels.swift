import Foundation

enum BrewStoreRemovalCandidateKind: String, Codable, CaseIterable, Sendable {
    case applicationBundle, applicationSupport, cache, container, groupContainer, preference, helperTool, log, unknown
}

enum BrewStoreRemovalConfidence: String, Codable, CaseIterable, Sendable {
    case exactBundleIdentifier, exactApplicationName, relatedPath, unknown
}

struct BrewStoreAppIdentity: Codable, Hashable, Sendable {
    let name: String
    let bundleIdentifier: String
    let applicationURL: URL
}

struct BrewStoreRemovalCandidate: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let kind: BrewStoreRemovalCandidateKind
    let size: Int64
    let confidence: BrewStoreRemovalConfidence
    var isSelected: Bool

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    init(id: UUID = UUID(), url: URL, kind: BrewStoreRemovalCandidateKind, size: Int64, confidence: BrewStoreRemovalConfidence, isSelected: Bool = true) {
        self.id = id
        self.url = url
        self.kind = kind
        self.size = max(0, size)
        self.confidence = confidence
        self.isSelected = isSelected
    }
}

struct BrewStoreRemovalPlan: Codable, Identifiable, Sendable {
    let id: UUID
    let application: BrewStoreAppIdentity
    let createdAt: Date
    var candidates: [BrewStoreRemovalCandidate]

    init(id: UUID = UUID(), application: BrewStoreAppIdentity, createdAt: Date = Date(), candidates: [BrewStoreRemovalCandidate]) {
        self.id = id
        self.application = application
        self.createdAt = createdAt
        self.candidates = candidates
    }

    var selectedCandidates: [BrewStoreRemovalCandidate] {
        candidates.filter(\.isSelected)
    }

    var selectedCount: Int {
        selectedCandidates.count
    }

    var selectedBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.size }
    }

    var formattedSelectedBytes: String {
        ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)
    }
}

struct BrewStoreRemovalFailure: Codable, Hashable, Sendable {
    let url: URL
    let reason: String
}

struct BrewStoreRemovalManifest: Codable, Identifiable, Sendable {
    let id: UUID
    let planID: UUID
    let application: BrewStoreAppIdentity
    let movedURLs: [URL]
    let failures: [BrewStoreRemovalFailure]
    let createdAt: Date
}

enum BrewStoreRemovalResult: Sendable {
    case completed(manifest: BrewStoreRemovalManifest)
    case partiallyCompleted(manifest: BrewStoreRemovalManifest)
    case cancelled(manifest: BrewStoreRemovalManifest)
    case failed(reason: String, manifest: BrewStoreRemovalManifest?)
}
