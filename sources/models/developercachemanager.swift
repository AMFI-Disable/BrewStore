import AppKit
import Foundation

enum DeveloperCacheCategory: String, CaseIterable, Identifiable, Codable {
    case xcode = "Xcode"
    case docker = "Containers & Docker"
    case node = "Node.js & Web"
    case rust = "Rust & Cargo"
    case packageManagers = "Build & Package Caches"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .xcode:
            "hammer.fill"
        case .docker:
            "shippingbox.fill"
        case .node:
            "globe"
        case .rust:
            "gearshape.2.fill"
        case .packageManagers:
            "archivebox.fill"
        }
    }
}

struct DeveloperCacheTarget: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let category: DeveloperCacheCategory
    let description: String
    let url: URL
    let sizeBytes: Int64
    var isSelected: Bool

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

@MainActor
final class BrewStoreDeveloperCacheManager: ObservableObject {
    static let shared = BrewStoreDeveloperCacheManager()

    @Published var targets: [DeveloperCacheTarget] = []
    @Published var isScanning = false
    @Published var isPurging = false
    @Published var statusMessage: String?
    @Published var lastReclaimedBytes: Int64 = 0

    var totalReclaimableBytes: Int64 {
        targets.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedReclaimableBytes: Int64 {
        targets.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    var formattedTotalReclaimable: String {
        ByteCountFormatter.string(fromByteCount: totalReclaimableBytes, countStyle: .file)
    }

    var formattedSelectedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: selectedReclaimableBytes, countStyle: .file)
    }

    func scanCaches() {
        isScanning = true
        statusMessage = nil

        Task.detached(priority: .userInitiated) {
            let scanned = Self.computeDeveloperCacheTargets()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.targets = scanned
                self.isScanning = false
            }
        }
    }

    func toggleTarget(id: String) {
        if let index = targets.firstIndex(where: { $0.id == id }) {
            targets[index].isSelected.toggle()
        }
    }

    func selectAll() {
        for index in targets.indices {
            targets[index].isSelected = true
        }
    }

    func deselectAll() {
        for index in targets.indices {
            targets[index].isSelected = false
        }
    }

    func purgeSelected() {
        let selected = targets.filter(\.isSelected)
        guard !selected.isEmpty else { return }

        isPurging = true
        statusMessage = nil

        Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let allowedRoots = [
                home.appendingPathComponent("Library/Developer"),
                home.appendingPathComponent("Library/Caches"),
                home.appendingPathComponent("Library/Containers/com.docker.docker/Data"),
                home.appendingPathComponent(".npm"),
                home.appendingPathComponent(".yarn"),
                home.appendingPathComponent(".pnpm-store"),
                home.appendingPathComponent("Library/pnpm"),
                home.appendingPathComponent(".cargo"),
                home.appendingPathComponent(".gradle"),
                home.appendingPathComponent(".orbstack")
            ]

            let validator = BrewStorePathSafetyValidator(allowedRoots: allowedRoots)
            let executor = BrewStoreTrashExecutor(validator: validator)

            let identity = BrewStoreAppIdentity(
                name: "Developer Caches",
                bundleIdentifier: "dev.brewstore.caches",
                applicationURL: URL(fileURLWithPath: "/tmp")
            )

            let removalCandidates = selected.map { target in
                BrewStoreRemovalCandidate(
                    url: target.url,
                    kind: .cache,
                    size: target.sizeBytes,
                    confidence: .relatedPath,
                    isSelected: true
                )
            }

            let plan = BrewStoreRemovalPlan(application: identity, candidates: removalCandidates)
            let result = executor.execute(plan: plan)

            var reclaimed: Int64 = 0
            var failureReason: String?
            switch result {
            case let .completed(manifest), let .partiallyCompleted(manifest):
                for url in manifest.movedURLs {
                    if let matched = selected.first(where: { $0.url == url }) {
                        reclaimed += matched.sizeBytes
                    }
                }
            case let .failed(reason, _):
                failureReason = reason
            default:
                break
            }

            let finalReclaimed = reclaimed
            let finalFailure = failureReason
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.lastReclaimedBytes = finalReclaimed
                self.isPurging = false
                if let finalFailure {
                    self.statusMessage = "Purge failed: \(finalFailure)"
                } else if finalReclaimed > 0 {
                    let formatted = ByteCountFormatter.string(fromByteCount: finalReclaimed, countStyle: .file)
                    self.statusMessage = "Safely moved \(formatted) of developer caches to Trash."
                } else {
                    self.statusMessage = "No files were moved."
                }
                self.scanCaches()
            }
        }
    }

    nonisolated static func computeDeveloperCacheTargets() -> [DeveloperCacheTarget] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        struct TargetSpec {
            let id: String
            let name: String
            let category: DeveloperCacheCategory
            let description: String
            let relativePath: String
        }

        let specs: [TargetSpec] = [
            TargetSpec(
                id: "xcode-deriveddata",
                name: "Xcode DerivedData",
                category: .xcode,
                description: "Intermediate build output, module caches, and indexing artifacts",
                relativePath: "Library/Developer/Xcode/DerivedData"
            ),
            TargetSpec(
                id: "xcode-archives",
                name: "Xcode Archives",
                category: .xcode,
                description: "Historical application release builds and organizer archives",
                relativePath: "Library/Developer/Xcode/Archives"
            ),
            TargetSpec(
                id: "xcode-devicesupport",
                name: "iOS DeviceSupport",
                category: .xcode,
                description: "Symbol files for connected real iOS/iPadOS test devices",
                relativePath: "Library/Developer/Xcode/iOS DeviceSupport"
            ),
            TargetSpec(
                id: "simulator-caches",
                name: "CoreSimulator Caches",
                category: .xcode,
                description: "Simulator runtime caches and temporary test file data",
                relativePath: "Library/Developer/CoreSimulator/Caches"
            ),
            TargetSpec(
                id: "docker-desktop-data",
                name: "Docker Containers Cache",
                category: .docker,
                description: "Unused container layer caches and virtual disk scratch spaces",
                relativePath: "Library/Containers/com.docker.docker/Data"
            ),
            TargetSpec(
                id: "orbstack-cache",
                name: "OrbStack Virtual Cache",
                category: .docker,
                description: "OrbStack virtual machine image caches and rootfs bundles",
                relativePath: ".orbstack/cache"
            ),
            TargetSpec(
                id: "npm-cache",
                name: "npm Global Cache",
                category: .node,
                description: "Content-addressable download store (_cacache) for npm modules",
                relativePath: ".npm/_cacache"
            ),
            TargetSpec(
                id: "yarn-cache",
                name: "Yarn Package Cache",
                category: .node,
                description: "Cached tarballs and unzipped dependencies across yarn installs",
                relativePath: "Library/Caches/Yarn"
            ),
            TargetSpec(
                id: "pnpm-store",
                name: "pnpm Content Store",
                category: .node,
                description: "Hard-linked deduplicated package store for pnpm workspaces",
                relativePath: "Library/pnpm/store"
            ),
            TargetSpec(
                id: "cargo-registry-cache",
                name: "Cargo Registry Crates",
                category: .rust,
                description: "Downloaded .crate archive files from crates.io index",
                relativePath: ".cargo/registry/cache"
            ),
            TargetSpec(
                id: "cargo-git-db",
                name: "Cargo Git Dependency DB",
                category: .rust,
                description: "Cloned git repositories for cargo git-based dependencies",
                relativePath: ".cargo/git/db"
            ),
            TargetSpec(
                id: "cocoapods-cache",
                name: "CocoaPods Cache",
                category: .packageManagers,
                description: "Downloaded pod archives and specs repository cache",
                relativePath: "Library/Caches/CocoaPods"
            ),
            TargetSpec(
                id: "gradle-caches",
                name: "Gradle Build Cache",
                category: .packageManagers,
                description: "Artifacts, transforms, and downloaded dependencies for Java/Kotlin",
                relativePath: ".gradle/caches"
            ),
            TargetSpec(
                id: "go-build-cache",
                name: "Go Build & Test Cache",
                category: .packageManagers,
                description: "Compiled packages and test results for Go toolchains",
                relativePath: "Library/Caches/go-build"
            ),
            TargetSpec(
                id: "homebrew-bottles",
                name: "Homebrew Bottle Downloads",
                category: .packageManagers,
                description: "Downloaded pre-compiled .bottle.tar.gz archives",
                relativePath: "Library/Caches/Homebrew"
            )
        ]

        var results: [DeveloperCacheTarget] = []
        for spec in specs {
            let targetURL = home.appendingPathComponent(spec.relativePath)
            if fm.fileExists(atPath: targetURL.path) {
                let size = computeDirectorySize(url: targetURL)
                if size > 0 {
                    results.append(
                        DeveloperCacheTarget(
                            id: spec.id,
                            name: spec.name,
                            category: spec.category,
                            description: spec.description,
                            url: targetURL,
                            sizeBytes: size,
                            isSelected: true
                        )
                    )
                }
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    nonisolated static func computeDirectorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
