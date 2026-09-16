import AppKit
import Foundation

enum AppMatchConfidence: String, Codable, CaseIterable {
    case exactVerified = "Verified Exact Match"
    case exactBundleID = "Verified Bundle ID"
    case exactName = "Verified App Name"
    case uncertainReviewRequired = "Review Required"
    case versionMismatch = "Version Discrepancy"
    case channelMismatch = "Locale / Channel Mismatch"
    case architectureMismatch = "Architecture Mismatch"
    case unmatched = "No Cask Match"

    var badgeColor: String {
        switch self {
        case .exactVerified, .exactBundleID: "green"
        case .exactName: "blue"
        case .uncertainReviewRequired, .versionMismatch, .channelMismatch, .architectureMismatch: "orange"
        case .unmatched: "secondary"
        }
    }

    var isVerifiedSafe: Bool {
        switch self {
        case .exactVerified, .exactBundleID, .exactName:
            true
        case .uncertainReviewRequired, .versionMismatch, .channelMismatch, .architectureMismatch, .unmatched:
            false
        }
    }
}

struct ScannedAppItem: Identifiable, Hashable {
    let id: String
    let appName: String
    let appPath: String
    let bundleID: String?
    let installedVersion: String?
    let matchedCask: BrewStorePackage?
    let matchConfidence: AppMatchConfidence
    let isAlreadyManaged: Bool
    let requiresManualReview: Bool
    let reviewReasons: [String]
    let isFromMacAppStore: Bool
    let masAppID: String?

    var isAdoptable: Bool {
        matchedCask != nil && !isAlreadyManaged && !requiresManualReview && matchConfidence.isVerifiedSafe
    }

    var isDualAvailable: Bool {
        isFromMacAppStore && matchedCask != nil
    }

    init(
        id: String,
        appName: String,
        appPath: String,
        bundleID: String?,
        installedVersion: String?,
        matchedCask: BrewStorePackage?,
        matchConfidence: AppMatchConfidence,
        isAlreadyManaged: Bool,
        requiresManualReview: Bool = false,
        reviewReasons: [String] = [],
        isFromMacAppStore: Bool = false,
        masAppID: String? = nil
    ) {
        self.id = id
        self.appName = appName
        self.appPath = appPath
        self.bundleID = bundleID
        self.installedVersion = installedVersion
        self.matchedCask = matchedCask
        self.matchConfidence = matchConfidence
        self.isAlreadyManaged = isAlreadyManaged
        self.requiresManualReview = requiresManualReview
        self.reviewReasons = reviewReasons
        self.isFromMacAppStore = isFromMacAppStore
        self.masAppID = masAppID
    }
}

@MainActor
final class BrewStoreAppAdoptionManager: ObservableObject {
    static let shared = BrewStoreAppAdoptionManager()

    @Published var scannedApps: [ScannedAppItem] = []
    @Published var isScanning = false
    @Published var lastScanDate: Date?

    var adoptableApps: [ScannedAppItem] {
        scannedApps.filter(\.isAdoptable)
    }

    var reviewRequiredApps: [ScannedAppItem] {
        scannedApps.filter { $0.matchedCask != nil && !$0.isAlreadyManaged && $0.requiresManualReview }
    }

    var managedApps: [ScannedAppItem] {
        scannedApps.filter(\.isAlreadyManaged)
    }

    var unmatchedApps: [ScannedAppItem] {
        scannedApps.filter { $0.matchedCask == nil }
    }

    func scanApplications(manager: HomebrewManager) {
        isScanning = true

        let caskPackages = manager.packages.filter { $0.kind == .cask }
        let installedCaskIDs = Set(caskPackages.filter(\.isInstalled).map(\.id))

        Task.detached(priority: .userInitiated) {
            let searchPaths = [
                "/Applications",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
            ]

            var items: [ScannedAppItem] = []
            var seenPaths = Set<String>()

            for searchPath in searchPaths {
                guard let contents = try? FileManager.default.contentsOfDirectory(atPath: searchPath) else { continue }

                for item in contents where item.hasSuffix(".app") {
                    let fullPath = (searchPath as NSString).appendingPathComponent(item)
                    guard !fullPath.hasPrefix("/System"), !seenPaths.contains(fullPath) else { continue }
                    let itemURL = URL(fileURLWithPath: fullPath)
                    if (try? itemURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                        continue
                    }
                    seenPaths.insert(fullPath)

                    let infoPlistPath = (fullPath as NSString).appendingPathComponent("Contents/Info.plist")
                    var bundleID: String?
                    var appName = (item as NSString).deletingPathExtension
                    var version: String?

                    if let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
                       let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] {
                        bundleID = plist["CFBundleIdentifier"] as? String
                        if let displayName = plist["CFBundleDisplayName"] as? String, !displayName.isEmpty {
                            appName = displayName
                        } else if let bundleName = plist["CFBundleName"] as? String, !bundleName.isEmpty {
                            appName = bundleName
                        }
                        version = plist["CFBundleShortVersionString"] as? String ?? (plist["CFBundleVersion"] as? String)
                    }

                    // Match against Cask catalog with precision verification
                    let matchResult = Self.matchCask(
                        appName: appName,
                        fileName: (item as NSString).deletingPathExtension,
                        bundleID: bundleID,
                        installedVersion: version,
                        appPath: fullPath,
                        casks: caskPackages
                    )

                    let isAlreadyManaged: Bool = if let matched = matchResult.cask {
                        installedCaskIDs.contains(matched.id) ||
                            installedCaskIDs.contains(where: { $0.hasSuffix("/\(matched.id)") })
                    } else {
                        false
                    }

                    let masReceiptPath = (fullPath as NSString).appendingPathComponent("Contents/_MASReceipt/receipt")
                    let isFromMAS = FileManager.default.fileExists(atPath: masReceiptPath)

                    let scanned = ScannedAppItem(
                        id: fullPath,
                        appName: appName,
                        appPath: fullPath,
                        bundleID: bundleID,
                        installedVersion: version,
                        matchedCask: matchResult.cask,
                        matchConfidence: matchResult.confidence,
                        isAlreadyManaged: isAlreadyManaged,
                        requiresManualReview: matchResult.requiresReview,
                        reviewReasons: matchResult.reviewReasons,
                        isFromMacAppStore: isFromMAS,
                        masAppID: nil
                    )
                    items.append(scanned)
                }
            }

            // Sort: Verified adoptable first, then review required, then unmatched, then managed
            let sorted = items.sorted { a, b in
                if a.isAdoptable != b.isAdoptable {
                    return a.isAdoptable && !b.isAdoptable
                }
                if a.requiresManualReview != b.requiresManualReview {
                    return !a.requiresManualReview && b.requiresManualReview
                }
                if a.matchConfidence != b.matchConfidence {
                    return a.matchConfidence.rawValue < b.matchConfidence.rawValue
                }
                return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
            }

            await MainActor.run { [weak self] in
                self?.scannedApps = sorted
                self?.isScanning = false
                self?.lastScanDate = Date()
            }
        }
    }

    typealias MatchResult = (
        cask: BrewStorePackage?,
        confidence: AppMatchConfidence,
        requiresReview: Bool,
        reviewReasons: [String]
    )

    nonisolated static func matchCask(
        appName: String,
        fileName: String,
        bundleID: String?,
        installedVersion: String? = nil,
        appPath: String? = nil,
        casks: [BrewStorePackage]
    ) -> MatchResult {
        let cleanAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAppName = cleanAppName.replacingOccurrences(of: " ", with: "-")
        let normalizedFileName = cleanFileName.replacingOccurrences(of: " ", with: "-")

        // 1. Identify Candidate Casks
        var candidateCasks: [(cask: BrewStorePackage, initialConfidence: AppMatchConfidence, penaltyScore: Int)] = []

        // Exact name match against cask name or cask applicationNames
        for cask in casks {
            let caskName = cask.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let caskID = cask.id.lowercased()
            if caskName == cleanAppName {
                let penalty = channelPenalty(caskID: caskID, appName: cleanAppName, bundleID: bundleID)
                candidateCasks.append((cask, .exactName, penalty))
            } else if cask.applicationNames.contains(where: {
                ($0 as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == cleanAppName
            }) {
                let penalty = channelPenalty(caskID: caskID, appName: cleanAppName, bundleID: bundleID)
                candidateCasks.append((cask, .exactName, penalty))
            }
        }

        // Exact cask ID matches filename or app name
        if candidateCasks.isEmpty {
            for cask in casks {
                let caskID = cask.id.lowercased()
                if caskID == normalizedFileName || caskID == normalizedAppName {
                    let penalty = channelPenalty(caskID: caskID, appName: cleanAppName, bundleID: bundleID)
                    candidateCasks.append((cask, .exactBundleID, penalty))
                }
            }
        }

        // Bundle ID heuristic matching
        if candidateCasks.isEmpty, let bundleID = bundleID?.lowercased() {
            let lastSegment = bundleID.split(separator: ".").last.map(String.init) ?? ""
            if !lastSegment.isEmpty, lastSegment.count >= 3 {
                for cask in casks {
                    let caskID = cask.id.lowercased()
                    if caskID == lastSegment || caskID.hasSuffix("-\(lastSegment)") {
                        let penalty = channelPenalty(caskID: caskID, appName: cleanAppName, bundleID: bundleID) + 5
                        candidateCasks.append((cask, .uncertainReviewRequired, penalty))
                    }
                }
            }
        }

        // Fuzzy alias matching
        if candidateCasks.isEmpty && cleanAppName.count >= 5 {
            for cask in casks {
                let caskID = cask.id.lowercased()
                if caskID == cleanAppName || caskID.hasPrefix("\(cleanAppName)-") || caskID.hasSuffix("-\(cleanAppName)") {
                    let penalty = channelPenalty(caskID: caskID, appName: cleanAppName, bundleID: bundleID) + 10
                    candidateCasks.append((cask, .uncertainReviewRequired, penalty))
                }
            }
        }

        guard let best = candidateCasks.sorted(by: { a, b in
            if a.penaltyScore != b.penaltyScore {
                return a.penaltyScore < b.penaltyScore
            }
            return a.cask.id.count < b.cask.id.count
        }).first else {
            return (nil, .unmatched, false, [])
        }

        // 2. Perform Strict Compatibility & Safety Verifications
        var reviewReasons: [String] = []
        var finalConfidence = best.initialConfidence

        // Channel / Locale validation (e.g. firefox vs firefox@cn)
        let caskChannel = extractChannelOrLocale(caskID: best.cask.id)
        let appChannel = extractAppChannelOrLocale(appName: cleanAppName, bundleID: bundleID)

        if let cChannel = caskChannel {
            if let aChannel = appChannel {
                if cChannel != aChannel {
                    reviewReasons.append("Locale/Channel mismatch: app has '\(aChannel)' while cask specifies '@\(cChannel)'.")
                    finalConfidence = .channelMismatch
                }
            } else {
                reviewReasons.append("Localized/channel cask '@\(cChannel)' matched with standard distribution app.")
                finalConfidence = .channelMismatch
            }
        }

        // Version compatibility validation (e.g. installed 154.0 vs cask 116.0)
        if let instVer = installedVersion, !instVer.isEmpty, !best.cask.version.isEmpty, best.cask.version.lowercased() != "latest" {
            let versionAnalysis = evaluateVersionCompatibility(installed: instVer, caskVersion: best.cask.version)
            if !versionAnalysis.isCompatible {
                reviewReasons.append(versionAnalysis.reason ?? "Major version discrepancy (installed v\(instVer) vs cask v\(best.cask.version)).")
                if finalConfidence == .exactBundleID || finalConfidence == .exactName {
                    finalConfidence = .versionMismatch
                }
            }
        }

        // Architecture compatibility validation (if appPath given)
        if let appPath {
            let archAnalysis = evaluateArchitectureCompatibility(appPath: appPath)
            if !archAnalysis.isCompatible {
                reviewReasons.append(archAnalysis.reason ?? "Architecture mismatch between binary and Homebrew default.")
                if finalConfidence.isVerifiedSafe {
                    finalConfidence = .architectureMismatch
                }
            }
        }

        let requiresReview = !reviewReasons.isEmpty || !finalConfidence.isVerifiedSafe

        return (best.cask, finalConfidence, requiresReview, reviewReasons)
    }

    // MARK: - Safety and Verification Helpers

    private nonisolated static func channelPenalty(caskID: String, appName: String, bundleID: String?) -> Int {
        var penalty = 0
        let channel = extractChannelOrLocale(caskID: caskID)
        let appChannel = extractAppChannelOrLocale(appName: appName, bundleID: bundleID)

        if channel != nil && appChannel == nil {
            penalty += 100 // Heavily penalize localized/forked casks when app has no channel
        }
        if caskID.contains("@") {
            penalty += 50
        }
        if caskID.contains("-cn") || caskID.contains("-zh") {
            penalty += 50
        }
        if caskID.contains("-beta") || caskID.contains("-nightly") || caskID.contains("-dev") {
            penalty += 30
        }
        return penalty
    }

    nonisolated static func extractChannelOrLocale(caskID: String) -> String? {
        let lower = caskID.lowercased()
        if lower.contains("@") {
            return lower.split(separator: "@").last.map(String.init)
        }
        let suffixes = ["-cn", "-zh", "-beta", "-nightly", "-dev", "-preview", "-canary", "-esr", "-lts"]
        for s in suffixes {
            if lower.hasSuffix(s) {
                return String(s.dropFirst())
            }
        }
        return nil
    }

    nonisolated static func extractAppChannelOrLocale(appName: String, bundleID: String?) -> String? {
        let nameLower = appName.lowercased()
        let bundleLower = bundleID?.lowercased() ?? ""

        let keywords = ["cn", "zh", "beta", "nightly", "dev", "developer", "preview", "canary", "esr", "lts"]
        for kw in keywords {
            if nameLower.contains(" \(kw)") || nameLower.hasSuffix("-\(kw)") || nameLower.hasSuffix("@\(kw)") ||
                bundleLower.hasSuffix(".\(kw)") || bundleLower.contains(".\(kw).") {
                return kw
            }
        }
        return nil
    }

    nonisolated static func evaluateVersionCompatibility(installed: String, caskVersion: String) -> (isCompatible: Bool, reason: String?) {
        let cleanInst = installed.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "v", with: "")
        let cleanCask = caskVersion.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "v", with: "")

        let instComponents = cleanInst.split(separator: ".").compactMap { Int($0.prefix(while: \.isNumber)) }
        let caskComponents = cleanCask.split(separator: ".").compactMap { Int($0.prefix(while: \.isNumber)) }

        if let instMajor = instComponents.first, let caskMajor = caskComponents.first {
            let diff = abs(instMajor - caskMajor)
            if diff >= 3 {
                return (false, "Major version difference of \(diff) versions (installed v\(cleanInst) vs cask v\(cleanCask)).")
            }
        }

        return (true, nil)
    }

    nonisolated static func evaluateArchitectureCompatibility(appPath: String) -> (isCompatible: Bool, reason: String?) {
        let fileManager = FileManager.default
        let execDir = (appPath as NSString).appendingPathComponent("Contents/MacOS")
        guard fileManager.fileExists(atPath: execDir) else {
            return (true, nil)
        }

        #if arch(arm64)
            let detectedArch = BrewStoreSecurityInspector.inspectAppBundleArchitecture(at: appPath)
            if detectedArch == .intel {
                return (false, "App is currently running under Rosetta 2 (Intel x86_64). Adopting Cask can upgrade to native Apple Silicon.")
            }
        #endif

        return (true, nil)
    }

    func adoptApp(item: ScannedAppItem, manager: HomebrewManager) {
        guard let cask = item.matchedCask else { return }
        manager.perform(package: cask, action: .adopt)
    }

    func adoptAll(items: [ScannedAppItem], manager: HomebrewManager) {
        // Strictly adopt only verified safe adoptable items, NEVER uncertain review items!
        let safeItems = items.filter { $0.isAdoptable && !$0.requiresManualReview && $0.matchConfidence.isVerifiedSafe }
        let adoptableCasks = safeItems.compactMap(\.matchedCask)
        guard !adoptableCasks.isEmpty else { return }
        manager.batchPerform(packages: adoptableCasks, action: .adopt)
    }

    /// Converts a Mac App Store application to Homebrew Cask management.
    func convertMASToHomebrew(item: ScannedAppItem, manager: HomebrewManager) {
        guard let cask = item.matchedCask else { return }
        manager.perform(package: cask, action: .adopt)
    }
}
