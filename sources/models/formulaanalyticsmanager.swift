import Foundation

struct PackageInstallAnalytics: Codable, Hashable {
    let packageID: String
    let install7d: Int
    let install30d: Int
    let install90d: Int
    let install365d: Int
    let installOnRequest30d: Int?
    let installOnRequest90d: Int?
    let installOnRequest365d: Int?

    var formatted7d: String {
        Self.formatCount(install7d)
    }

    var formatted30d: String {
        Self.formatCount(install30d)
    }

    var formatted90d: String {
        Self.formatCount(install90d)
    }

    var formatted365d: String {
        Self.formatCount(install365d)
    }

    enum CodingKeys: String, CodingKey {
        case packageID, install7d, install30d, install90d, install365d
        case installOnRequest30d, installOnRequest90d, installOnRequest365d
    }

    init(
        packageID: String,
        install7d: Int? = nil,
        install30d: Int,
        install90d: Int,
        install365d: Int,
        installOnRequest30d: Int? = nil,
        installOnRequest90d: Int? = nil,
        installOnRequest365d: Int? = nil
    ) {
        self.packageID = packageID
        self.install30d = install30d
        self.install90d = install90d
        self.install365d = install365d
        self.install7d = install7d ?? Int(round(Double(install30d) * 7.0 / 30.0))
        self.installOnRequest30d = installOnRequest30d
        self.installOnRequest90d = installOnRequest90d
        self.installOnRequest365d = installOnRequest365d
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.packageID = try container.decode(String.self, forKey: .packageID)
        self.install30d = try container.decode(Int.self, forKey: .install30d)
        self.install90d = try container.decode(Int.self, forKey: .install90d)
        self.install365d = try container.decode(Int.self, forKey: .install365d)
        if let decoded7d = try container.decodeIfPresent(Int.self, forKey: .install7d) {
            self.install7d = decoded7d
        } else {
            self.install7d = Int(round(Double(self.install30d) * 7.0 / 30.0))
        }
        self.installOnRequest30d = try container.decodeIfPresent(Int.self, forKey: .installOnRequest30d)
        self.installOnRequest90d = try container.decodeIfPresent(Int.self, forKey: .installOnRequest90d)
        self.installOnRequest365d = try container.decodeIfPresent(Int.self, forKey: .installOnRequest365d)
    }

    /// Monthly run rate velocity relative to the 90-day baseline average
    var velocityPercent: Double {
        guard install90d > 0 else { return 0 }
        let expected30d = Double(install90d) / 3.0
        return ((Double(install30d) - expected30d) / expected30d) * 100.0
    }

    /// Ratio of direct on-request installs vs automatic dependency installs (0.0 to 1.0)
    var directRequestRatio: Double {
        guard install30d > 0 else { return 1.0 }
        let onRequest = Double(installOnRequest30d ?? install30d)
        return min(max(onRequest / Double(install30d), 0.0), 1.0)
    }

    var momentumBadge: (title: String, symbol: String, isPositive: Bool) {
        let v = velocityPercent
        if v >= 10.0 {
            return ("Fast Growing (+\(String(format: "%.1f", v))%)", "arrow.up.right.circle.fill", true)
        } else if v <= -10.0 {
            return ("Declining (\(String(format: "%.1f", v))%)", "arrow.down.right.circle.fill", false)
        } else {
            return ("Steady Growth", "equal.circle.fill", true)
        }
    }

    static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            "\(count)"
        }
    }
}

@MainActor
final class BrewStoreAnalyticsManager: ObservableObject {
    static let shared = BrewStoreAnalyticsManager()

    static func formatCount(_ count: Int) -> String {
        PackageInstallAnalytics.formatCount(count)
    }

    @Published var cachedAnalytics: [String: PackageInstallAnalytics] = [:]
    @Published var isLoading: [String: Bool] = [:]

    private let cacheDirectory: URL = {
        let fm = FileManager.default
        let baseDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = baseDir.appendingPathComponent("com.amfi-disable.BrewStore/analytics", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func cachedOrBaseline(packageID: String, kind: BrewPackageKind) -> PackageInstallAnalytics? {
        let key = "\(kind.rawValue):\(packageID)"
        if let existing = cachedAnalytics[key] {
            return existing
        }

        // Check disk cache
        if let diskCached = loadFromDisk(key: key) {
            cachedAnalytics[key] = diskCached
            return diskCached
        }

        let bare = packageID.split(separator: "/").last.map(String.init)?.lowercased() ?? packageID.lowercased()
        if let item = BrewStoreDiscoveryCatalog.shared.items.first(where: { $0.id.lowercased() == bare || $0.id.lowercased() == packageID.lowercased() }),
           item.installCount30Days > 0 {
            let count30 = item.installCount30Days
            return PackageInstallAnalytics(
                packageID: packageID,
                install7d: max(1, Int(round(Double(count30) * 7.0 / 30.0))),
                install30d: count30,
                install90d: count30 * 3,
                install365d: count30 * 12
            )
        }
        return nil
    }

    func fetchAnalytics(packageID: String, kind: BrewPackageKind) async -> PackageInstallAnalytics? {
        let key = "\(kind.rawValue):\(packageID)"
        if let existing = cachedAnalytics[key] {
            return existing
        }

        // Check disk cache
        if let diskCached = loadFromDisk(key: key) {
            cachedAnalytics[key] = diskCached
            return diskCached
        }

        isLoading[key] = true
        defer { isLoading[key] = false }

        let bareID = packageID.split(separator: "/").last.map(String.init)?.lowercased() ?? packageID.lowercased()
        let endpoint = kind == .cask ? "cask" : "formula"
        guard let url = URL(string: "https://formulae.brew.sh/api/\(endpoint)/\(bareID).json") else {
            return cachedOrBaseline(packageID: packageID, kind: kind)
        }

        do {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 5.0)
            request.setValue("BrewStore/1.0.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse)?.statusCode == 200,
               let parsed = Self.parseJSON(data: data, packageID: packageID, kind: kind) {
                cachedAnalytics[key] = parsed
                saveToDisk(key: key, analytics: parsed)
                return parsed
            }
        } catch {
            // Silently handle offline/timeout
        }

        return cachedOrBaseline(packageID: packageID, kind: kind)
    }

    nonisolated static func parseJSON(data: Data, packageID: String, kind _: BrewPackageKind) -> PackageInstallAnalytics? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let analytics = json["analytics"] as? [String: Any],
              let install = analytics["install"] as? [String: Any]
        else {
            return nil
        }

        func extractCount(from dict: [String: Any], key: String, subkey: String) -> Int {
            guard let period = dict[key] as? [String: Any] else { return 0 }
            if let val = period[subkey] as? Int {
                return val
            }
            if let valStr = period[subkey] as? String, let intVal = Int(valStr) {
                return intVal
            }
            let bare = subkey.split(separator: "/").last.map(String.init)?.lowercased() ?? subkey.lowercased()
            if let val = period[bare] as? Int {
                return val
            }
            if let valStr = period[bare] as? String, let intVal = Int(valStr) {
                return intVal
            }
            var sum = 0
            var found = false
            for (k, v) in period {
                let lowerK = k.lowercased()
                if lowerK == bare || lowerK.hasPrefix("\(bare) ") {
                    if let intV = v as? Int {
                        sum += intV
                        found = true
                    } else if let strV = v as? String, let intV = Int(strV) {
                        sum += intV
                        found = true
                    }
                }
            }
            if found {
                return sum
            }
            if period.count == 1, let single = period.values.first as? Int {
                return single
            }
            return 0
        }

        let raw7 = extractCount(from: install, key: "7d", subkey: packageID)
        let i30 = extractCount(from: install, key: "30d", subkey: packageID)
        let i90 = extractCount(from: install, key: "90d", subkey: packageID)
        let i365 = extractCount(from: install, key: "365d", subkey: packageID)
        let i7 = raw7 > 0 ? raw7 : Int(round(Double(i30) * 7.0 / 30.0))

        var onRequest30: Int?
        var onRequest90: Int?
        var onRequest365: Int?

        if let onReq = analytics["install_on_request"] as? [String: Any] {
            onRequest30 = extractCount(from: onReq, key: "30d", subkey: packageID)
            onRequest90 = extractCount(from: onReq, key: "90d", subkey: packageID)
            onRequest365 = extractCount(from: onReq, key: "365d", subkey: packageID)
        }

        return PackageInstallAnalytics(
            packageID: packageID,
            install7d: i7,
            install30d: i30,
            install90d: i90,
            install365d: i365,
            installOnRequest30d: onRequest30,
            installOnRequest90d: onRequest90,
            installOnRequest365d: onRequest365
        )
    }

    private func diskURL(for key: String) -> URL {
        let safeName = key.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent("\(safeName).json")
    }

    private func loadFromDisk(key: String) -> PackageInstallAnalytics? {
        let url = diskURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let analytics = try? JSONDecoder().decode(PackageInstallAnalytics.self, from: data)
        else {
            return nil
        }
        return analytics
    }

    private func saveToDisk(key: String, analytics: PackageInstallAnalytics) {
        let url = diskURL(for: key)
        if let data = try? JSONEncoder().encode(analytics) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
