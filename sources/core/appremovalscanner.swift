import Foundation

final class BrewStoreAppRemovalScanner: @unchecked Sendable {
    func scan(
        application: BrewStoreAppIdentity,
        zapTrashPaths: [String] = [],
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) -> BrewStoreRemovalPlan {
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        let bundleID = application.bundleIdentifier.lowercased()
        let appName = application.name.lowercased().hasSuffix(".app")
            ? String(application.name.dropLast(4)).lowercased()
            : application.name.lowercased()
        let roots: [(BrewStoreRemovalCandidateKind, URL)] = [
            (.applicationSupport, home.appendingPathComponent("Library/Application Support")),
            (.cache, home.appendingPathComponent("Library/Caches")),
            (.container, home.appendingPathComponent("Library/Containers")),
            (.groupContainer, home.appendingPathComponent("Library/Group Containers")),
            (.preference, home.appendingPathComponent("Library/Preferences")),
            (.log, home.appendingPathComponent("Library/Logs"))
        ]
        var candidates: [BrewStoreRemovalCandidate] = []
        var seenPaths = Set<String>()

        if fileManager.fileExists(atPath: application.applicationURL.path), !isSymbolicLink(application.applicationURL) {
            candidates.append(BrewStoreRemovalCandidate(url: application.applicationURL, kind: .applicationBundle, size: size(of: application.applicationURL, fileManager: fileManager), confidence: .exactBundleIdentifier))
            seenPaths.insert(application.applicationURL.standardizedFileURL.path)
        }

        for (kind, root) in roots {
            guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { continue }
            for child in children {
                guard !isSymbolicLink(child) else { continue }
                let lower = child.lastPathComponent.lowercased()
                let matchesBundle = matchesBundleIdentifier(lower, bundleID: bundleID)
                let matchesName = matchesApplicationName(lower, appName: appName)
                guard matchesBundle || matchesName else { continue }
                let standardized = child.standardizedFileURL.path
                guard !seenPaths.contains(standardized) else { continue }
                seenPaths.insert(standardized)
                candidates.append(BrewStoreRemovalCandidate(url: child, kind: kind, size: size(of: child, fileManager: fileManager), confidence: matchesBundle ? .exactBundleIdentifier : .exactApplicationName))
            }
        }

        // Process developer-specified zap directives
        let allowedRoots = roots.map(\.1)
        let validator = BrewStorePathSafetyValidator(allowedRoots: allowedRoots)
        for rawZap in zapTrashPaths {
            let expandedPath = rawZap.hasPrefix("~/") ? home.path + String(rawZap.dropFirst(1)) : rawZap
            let zapURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
            let standardized = zapURL.path
            guard !seenPaths.contains(standardized),
                  fileManager.fileExists(atPath: standardized),
                  !isSymbolicLink(zapURL),
                  (try? validator.validate(zapURL, fileManager: fileManager)) != nil
            else { continue }

            seenPaths.insert(standardized)
            let kind: BrewStoreRemovalCandidateKind = standardized.contains("/Caches/") ? .cache : (standardized.contains("/Preferences/") ? .preference : .applicationSupport)
            candidates.append(BrewStoreRemovalCandidate(url: zapURL, kind: kind, size: size(of: zapURL, fileManager: fileManager), confidence: .exactBundleIdentifier))
        }

        return BrewStoreRemovalPlan(application: application, candidates: candidates.sorted { $0.url.path < $1.url.path })
    }

    private func matchesBundleIdentifier(_ value: String, bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        return value == bundleID || value == "group.\(bundleID)" || value.hasPrefix(bundleID + ".") || value.hasSuffix(".\(bundleID)")
    }

    private func matchesApplicationName(_ value: String, appName: String) -> Bool {
        guard !appName.isEmpty else { return false }
        return value == appName || value == appName + ".app"
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func size(of url: URL, fileManager: FileManager) -> Int64 {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        var total: Int64 = 0
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsPackageDescendants]) {
            for case let child as URL in enumerator {
                total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }
}
