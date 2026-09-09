import Foundation

struct BrewStorePathSafetyValidator: Sendable {
    let allowedRoots: [URL]

    init(allowedRoots: [URL]) {
        self.allowedRoots = allowedRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL }
    }

    func validate(_ url: URL, fileManager: FileManager = .default) throws {
        let rawPath = url.path
        guard !rawPath.isEmpty else { throw BrewStorePathSafetyError.emptyPath }
        guard fileManager.fileExists(atPath: rawPath) else { throw BrewStorePathSafetyError.targetDoesNotExist(url) }

        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedPath = resolvedURL.path
        let parentResolvedPath = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path

        let protectedPaths = [
            "/",
            fileManager.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL.path,
            "/System",
            "/Applications",
            "/System/Applications",
            "/Library",
            "/System/Library",
            "/usr",
            "/bin",
            "/sbin",
            "/private"
        ].map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }

        if protectedPaths.contains(resolvedPath) {
            throw BrewStorePathSafetyError.protectedPath(url)
        }

        let matchingRoot = allowedRoots.first(where: {
            resolvedPath == $0.path || resolvedPath.hasPrefix($0.path + "/") ||
                parentResolvedPath == $0.path || parentResolvedPath.hasPrefix($0.path + "/")
        })

        guard let root = matchingRoot else {
            throw BrewStorePathSafetyError.outsideAllowedRoots(url)
        }

        if isSymbolicLink(url) || containsIntermediateSymbolicLink(target: url, relativeTo: root, fileManager: fileManager) {
            throw BrewStorePathSafetyError.symbolicLink(url)
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        var statInfo = stat()
        if lstat(url.path, &statInfo) == 0 {
            return (statInfo.st_mode & S_IFMT) == S_IFLNK
        }
        return false
    }

    private func containsIntermediateSymbolicLink(target: URL, relativeTo root: URL, fileManager _: FileManager) -> Bool {
        let rootPath = root.path
        let targetPath = target.path
        if targetPath.hasPrefix(rootPath) {
            let relative = targetPath.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var current = root
            for component in relative.split(separator: "/") {
                current.appendPathComponent(String(component))
                if isSymbolicLink(current) {
                    return true
                }
            }
        }
        return false
    }
}

enum BrewStorePathSafetyError: LocalizedError, Equatable {
    case emptyPath
    case targetDoesNotExist(URL)
    case protectedPath(URL)
    case outsideAllowedRoots(URL)
    case symbolicLink(URL)

    var errorDescription: String? {
        switch self {
        case .emptyPath: "The target path is empty."
        case let .targetDoesNotExist(url): "The target does not exist: \(url.path)"
        case let .protectedPath(url): "The target is protected from removal: \(url.path)"
        case let .outsideAllowedRoots(url): "The target is outside the allowed removal scope: \(url.path)"
        case let .symbolicLink(url): "The target or one of its parent paths is a symbolic link: \(url.path)"
        }
    }
}
