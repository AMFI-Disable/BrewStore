import Combine
import Foundation

struct BrewStoreDiscoveryItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let homepage: String
    let version: String
    let kind: BrewPackageKind
    let installCount30Days: Int
    let tap: String?
    let license: String?
    let aliases: [String]
    let dependencies: [String]
    let artifacts: [String]
    let category: String

    var iconURL: URL? {
        guard kind == .cask, let host = URL(string: homepage)?.host else { return nil }
        return URL(string: "https://\(host)/favicon.ico")
    }

    init(
        id: String,
        name: String,
        description: String,
        homepage: String,
        version: String,
        kind: BrewPackageKind,
        installCount30Days: Int,
        tap: String?,
        license: String?,
        aliases: [String],
        dependencies: [String],
        artifacts: [String],
        category: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.homepage = homepage
        self.version = version
        self.kind = kind
        self.installCount30Days = installCount30Days
        self.tap = tap
        self.license = license
        self.aliases = aliases
        self.dependencies = dependencies
        self.artifacts = artifacts
        self.category = category ?? BrewStoreDiscoveryCatalog.guessCategory(for: "\(name) \(id)", description: description)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, homepage, version, kind, installCount30Days, tap, license, aliases, dependencies, artifacts, category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let description = try container.decode(String.self, forKey: .description)
        let homepage = try container.decode(String.self, forKey: .homepage)
        let version = try container.decode(String.self, forKey: .version)
        let kind = try container.decode(BrewPackageKind.self, forKey: .kind)
        let installCount30Days = try container.decodeIfPresent(Int.self, forKey: .installCount30Days) ?? 0
        let tap = try container.decodeIfPresent(String.self, forKey: .tap)
        let license = try container.decodeIfPresent(String.self, forKey: .license)
        let aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        let dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        let artifacts = try container.decodeIfPresent([String].self, forKey: .artifacts) ?? []
        let category = try container.decodeIfPresent(String.self, forKey: .category)

        self.init(
            id: id,
            name: name,
            description: description,
            homepage: homepage,
            version: version,
            kind: kind,
            installCount30Days: installCount30Days,
            tap: tap,
            license: license,
            aliases: aliases,
            dependencies: dependencies,
            artifacts: artifacts,
            category: category
        )
    }

    var displayVersion: String {
        BrewStorePackage.formatDisplayVersion(version)
    }
}

@MainActor
final class BrewStoreDiscoveryCatalog: ObservableObject {
    static let shared = BrewStoreDiscoveryCatalog()

    nonisolated static let nonAlphanumericSet = CharacterSet.alphanumerics.inverted

    nonisolated static func guessCategory(for id: String, description: String) -> String {
        let text = "\(id) \(description)".lowercased()
        let words = Set(text.components(separatedBy: nonAlphanumericSet).filter { !$0.isEmpty })

        if words.contains("browser") || words.contains("web") || words.contains("chromium") || words.contains("firefox") || text.contains("web browser") {
            return "Browsers"
        }
        if words.contains("music") || words.contains("audio") || words.contains("video") || words.contains("photo") || words.contains("image") || words.contains("design") || words.contains("media") || words.contains("player") || words.contains("multimedia") || words.contains("font") || words.contains("typeface") {
            return "Media & Design"
        }
        if words.contains("developer") || words.contains("code") || words.contains("ide") || words.contains("terminal") || words.contains("git") || words.contains("editor") || words.contains("compiler") || words.contains("sdk") || words.contains("python") || words.contains("rust") || words.contains("golang") || words.contains("swift") || text.contains("source code") {
            return "Development"
        }
        if words.contains("game") || words.contains("emulator") || words.contains("gaming") {
            return "Games"
        }
        if words.contains("security") || words.contains("password") || words.contains("vpn") || words.contains("encrypt") || words.contains("auth") || words.contains("ssh") || words.contains("key") {
            return "Security & Privacy"
        }
        if words.contains("database") || words.contains("server") || words.contains("docker") || words.contains("kubernetes") || words.contains("cloud") || words.contains("redis") || words.contains("postgres") || words.contains("postgresql") || words.contains("nginx") || words.contains("sql") {
            return "Infrastructure & Cloud"
        }
        if words.contains("note") || words.contains("notes") || words.contains("task") || words.contains("calendar") || words.contains("mail") || words.contains("document") || words.contains("pdf") || words.contains("office") || words.contains("todo") || words.contains("markdown") {
            return "Productivity"
        }
        if words.contains("utility") || words.contains("tool") || words.contains("archive") || words.contains("zip") || words.contains("monitor") || words.contains("disk") || words.contains("menu") || words.contains("battery") {
            return "Utilities"
        }
        return "Utilities"
    }

    @Published private(set) var items: [BrewStoreDiscoveryItem] = []
    @Published private(set) var newlyDiscoveredIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?

    private let cacheURL: URL
    private var hasLoaded = false
    private var loadedCache = false
    private var cachedCaskETag: String?
    private var cachedCaskLastModified: String?
    private var cachedFormulaETag: String?
    private var cachedFormulaLastModified: String?
    private var loadGeneration: UInt64 = 0

    init(fileManager: FileManager = .default) {
        let baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let support = baseDir.appendingPathComponent("BrewStore", isDirectory: true)
        cacheURL = support.appendingPathComponent("discovery-cache.json")
    }

    func load(force: Bool = false) {
        guard !isLoading else { return }
        if !hasLoaded {
            loadCache()
        }
        hasLoaded = true
        isLoading = true
        errorMessage = nil

        loadGeneration &+= 1
        let generation = loadGeneration
        let cachedItems = items

        let caskETag = force ? nil : cachedCaskETag
        let caskLastMod = force ? nil : cachedCaskLastModified
        let formulaETag = force ? nil : cachedFormulaETag
        let formulaLastMod = force ? nil : cachedFormulaLastModified

        Task { [weak self] in
            do {
                let result = try await Self.fetchCatalog(
                    cachedItems: cachedItems,
                    caskETag: caskETag,
                    caskLastMod: caskLastMod,
                    formulaETag: formulaETag,
                    formulaLastMod: formulaLastMod
                )
                await MainActor.run {
                    self?.finish(
                        items: result.items,
                        caskETag: result.caskETag,
                        caskLastMod: result.caskLastMod,
                        formulaETag: result.formulaETag,
                        formulaLastMod: result.formulaLastMod,
                        generation: generation
                    )
                }
            } catch {
                await MainActor.run {
                    self?.fail(error.localizedDescription, generation: generation)
                }
            }
        }
    }

    private struct CatalogFetchResult {
        let items: [BrewStoreDiscoveryItem]
        let caskETag: String?
        let caskLastMod: String?
        let formulaETag: String?
        let formulaLastMod: String?
    }

    private nonisolated static func fetchCatalog(
        cachedItems: [BrewStoreDiscoveryItem],
        caskETag: String?,
        caskLastMod: String?,
        formulaETag: String?,
        formulaLastMod: String?
    ) async throws -> CatalogFetchResult {
        async let caskFetch: FetchResult = fetch(kind: .cask, etag: caskETag, lastModified: caskLastMod)
        async let formulaFetch: FetchResult = fetch(kind: .formula, etag: formulaETag, lastModified: formulaLastMod)
        let caskRes = try await caskFetch
        let formulaRes = try await formulaFetch

        let caskItems: [RawItem] = if caskRes.isNotModified {
            cachedItems.filter { $0.kind == .cask }.map { item in
                RawItem(
                    id: item.id,
                    name: item.name,
                    description: item.description,
                    homepage: item.homepage,
                    version: item.version,
                    kind: item.kind,
                    tap: item.tap,
                    license: item.license,
                    aliases: item.aliases,
                    dependencies: item.dependencies,
                    artifacts: item.artifacts
                )
            }
        } else {
            caskRes.items
        }

        let formulaItems: [RawItem] = if formulaRes.isNotModified {
            cachedItems.filter { $0.kind == .formula }.map { item in
                RawItem(
                    id: item.id,
                    name: item.name,
                    description: item.description,
                    homepage: item.homepage,
                    version: item.version,
                    kind: item.kind,
                    tap: item.tap,
                    license: item.license,
                    aliases: item.aliases,
                    dependencies: item.dependencies,
                    artifacts: item.artifacts
                )
            }
        } else {
            formulaRes.items
        }

        async let popularCaskFetch: [String: Int]? = try? fetchPopular(kind: .cask)
        async let popularFormulaFetch: [String: Int]? = try? fetchPopular(kind: .formula)
        let popularCasks = await popularCaskFetch
        let popularFormulae = await popularFormulaFetch
        let popular = (popularCasks ?? [:]).merging(popularFormulae ?? [:]) { first, _ in first }
        let merged = (caskItems + formulaItems).map { item in
            BrewStoreDiscoveryItem(
                id: item.id,
                name: item.name,
                description: item.description,
                homepage: item.homepage,
                version: item.version,
                kind: item.kind,
                installCount30Days: popular[item.id] ?? 0,
                tap: item.tap,
                license: item.license,
                aliases: item.aliases,
                dependencies: item.dependencies,
                artifacts: item.artifacts
            )
        }

        return CatalogFetchResult(
            items: merged,
            caskETag: caskRes.etag ?? caskETag,
            caskLastMod: caskRes.lastModified ?? caskLastMod,
            formulaETag: formulaRes.etag ?? formulaETag,
            formulaLastMod: formulaRes.lastModified ?? formulaLastMod
        )
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        items = cached.items
        lastUpdated = cached.updatedAt
        cachedCaskETag = cached.caskETag
        cachedCaskLastModified = cached.caskLastModified
        cachedFormulaETag = cached.formulaETag
        cachedFormulaLastModified = cached.formulaLastModified
        loadedCache = true
    }

    private func finish(
        items: [BrewStoreDiscoveryItem],
        caskETag: String?,
        caskLastMod: String?,
        formulaETag: String?,
        formulaLastMod: String?,
        generation: UInt64
    ) {
        guard generation == loadGeneration else { return }
        let previousIDs = Set(self.items.map(\.id))
        self.items = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        newlyDiscoveredIDs = loadedCache ? Set(items.map(\.id)).subtracting(previousIDs) : []
        lastUpdated = Date()
        cachedCaskETag = caskETag
        cachedCaskLastModified = caskLastMod
        cachedFormulaETag = formulaETag
        cachedFormulaLastModified = formulaLastMod
        isLoading = false
        saveCache()
    }

    private func fail(_ message: String, generation: UInt64) {
        guard generation == loadGeneration else { return }
        isLoading = false
        errorMessage = items.isEmpty ? message : "Using the last cached catalog. \(message)"
    }

    func clearCache() {
        loadGeneration &+= 1
        isLoading = false
        try? FileManager.default.removeItem(at: cacheURL)
        items = []
        lastUpdated = nil
        cachedCaskETag = nil
        cachedCaskLastModified = nil
        cachedFormulaETag = nil
        cachedFormulaLastModified = nil
        loadedCache = false
        hasLoaded = false
        newlyDiscoveredIDs = []
        errorMessage = nil
    }

    func mergeLocalPackages(_ packages: [BrewStorePackage]) {
        guard items.isEmpty else { return }
        let fallbackItems = packages.map { pkg in
            BrewStoreDiscoveryItem(
                id: pkg.id,
                name: pkg.name,
                description: pkg.description,
                homepage: pkg.homepage,
                version: pkg.version,
                kind: pkg.kind,
                installCount30Days: 0,
                tap: nil,
                license: nil,
                aliases: [],
                dependencies: pkg.dependencies,
                artifacts: pkg.applicationNames
            )
        }
        if !fallbackItems.isEmpty {
            self.items = fallbackItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func saveCache() {
        let cache = Cache(
            items: items,
            updatedAt: lastUpdated ?? Date(),
            caskETag: cachedCaskETag,
            caskLastModified: cachedCaskLastModified,
            formulaETag: cachedFormulaETag,
            formulaLastModified: cachedFormulaLastModified
        )
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private struct FetchResult {
        let items: [RawItem]
        let etag: String?
        let lastModified: String?
        let isNotModified: Bool
    }

    private nonisolated static func fetch(kind: BrewPackageKind, etag: String?, lastModified: String?) async throws -> FetchResult {
        let endpoint = kind == .cask ? "https://formulae.brew.sh/api/cask.json" : "https://formulae.brew.sh/api/formula.json"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if httpResponse.statusCode == 304 {
            return FetchResult(items: [], etag: etag, lastModified: lastModified, isNotModified: true)
        }

        guard httpResponse.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }

        let newETag = httpResponse.value(forHTTPHeaderField: "ETag")
        let newLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        let items: [RawItem] = entries.compactMap { entry in
            let id: String?
            let name: String
            let version: String

            if kind == .cask {
                id = (entry["token"] as? String) ?? (entry["full_token"] as? String) ?? (entry["name"] as? String)
                if let nameArray = entry["name"] as? [String], let first = nameArray.first {
                    name = first
                } else if let nameStr = entry["name"] as? String {
                    name = nameStr
                } else {
                    name = id ?? ""
                }
                version = (entry["version"] as? String) ?? ""
            } else {
                id = (entry["full_name"] as? String) ?? (entry["name"] as? String)
                name = (entry["name"] as? String) ?? (id ?? "")
                let versions = entry["versions"] as? [String: Any]
                version = (versions?["stable"] as? String) ?? ""
            }

            guard let id, !id.isEmpty else { return nil }
            var dependencies: [String] = []
            if let directDeps = entry["dependencies"] as? [String] {
                dependencies.append(contentsOf: directDeps)
            } else if let dependencyGroups = entry["dependencies"] as? [String: Any] {
                for value in dependencyGroups.values {
                    dependencies.append(contentsOf: value as? [String] ?? [])
                }
            } else if let dependsOn = entry["depends_on"] as? [String: Any] {
                if let formulae = dependsOn["formula"] as? [String] {
                    dependencies.append(contentsOf: formulae)
                }
                if let casks = dependsOn["cask"] as? [String] {
                    dependencies.append(contentsOf: casks)
                }
            }
            let artifacts = (entry["artifacts"] as? [[String: Any]])?.flatMap { artifact in
                artifact.keys.filter { $0 != "zap" && $0 != "uninstall" }
            } ?? []
            return RawItem(
                id: id,
                name: name.isEmpty ? id : name,
                description: (entry["desc"] as? String) ?? "",
                homepage: (entry["homepage"] as? String) ?? "",
                version: version,
                kind: kind,
                tap: entry["tap"] as? String,
                license: entry["license"] as? String,
                aliases: entry["aliases"] as? [String] ?? [],
                dependencies: dependencies,
                artifacts: artifacts
            )
        }

        return FetchResult(items: items, etag: newETag, lastModified: newLastModified, isNotModified: false)
    }

    private nonisolated static func fetchPopular(kind: BrewPackageKind) async throws -> [String: Int] {
        let repository = kind == .cask ? "homebrew-cask" : "homebrew-core"
        let primaryEndpoint = kind == .cask
            ? "https://formulae.brew.sh/api/analytics/cask-install/30d.json"
            : "https://formulae.brew.sh/api/analytics/install/30d.json"
        let secondaryEndpoint = kind == .cask
            ? "https://formulae.brew.sh/api/analytics/cask-install/\(repository)/30d.json"
            : "https://formulae.brew.sh/api/analytics/install/\(repository)/30d.json"

        let endpoints = [primaryEndpoint, secondaryEndpoint]
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            do {
                var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8.0)
                request.setValue("BrewStore/1.0.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let entries = root["items"] as? [[String: Any]], !entries.isEmpty else { continue }

                let result = entries.reduce(into: [String: Int]()) { map, entry in
                    let id = (entry["formula"] as? String) ?? (entry["cask"] as? String) ?? (entry["name"] as? String)
                    var count = (entry["count"] as? Int) ?? (entry["installs"] as? Int) ?? 0
                    if count == 0, let countStr = entry["count"] as? String {
                        let clean = countStr.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                        count = Int(clean) ?? 0
                    }
                    if count == 0, let countStr = entry["installs"] as? String {
                        let clean = countStr.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                        count = Int(clean) ?? 0
                    }
                    if let id, !id.isEmpty, count > 0 {
                        map[id] = count
                        let bare = id.components(separatedBy: "/").last ?? id
                        map[bare] = count
                    }
                }
                if !result.isEmpty {
                    return result
                }
            } catch {
                continue
            }
        }
        return [:]
    }

    private struct RawItem {
        let id: String
        let name: String
        let description: String
        let homepage: String
        let version: String
        let kind: BrewPackageKind
        let tap: String?
        let license: String?
        let aliases: [String]
        let dependencies: [String]
        let artifacts: [String]
    }

    private struct Cache: Codable {
        let items: [BrewStoreDiscoveryItem]
        let updatedAt: Date
        var caskETag: String?
        var caskLastModified: String?
        var formulaETag: String?
        var formulaLastModified: String?
    }
}
