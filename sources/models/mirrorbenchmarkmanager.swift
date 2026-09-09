import Foundation

struct MirrorEndpoint: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let bottleDomain: String
    let coreGitRemote: String
    let caskGitRemote: String
    let testURL: String
    var latencyMs: Double?
    var isFastest: Bool = false

    var formattedLatency: String {
        guard let ms = latencyMs else { return "Untested" }
        return String(format: "%.0f ms", ms)
    }
}

@MainActor
final class BrewStoreMirrorBenchmarkManager: ObservableObject {
    static let shared = BrewStoreMirrorBenchmarkManager()

    @Published var mirrors: [MirrorEndpoint] = [
        MirrorEndpoint(
            id: "official",
            name: "Official GitHub / Fastly CDN",
            bottleDomain: "https://ghcr.io/v2/homebrew/core",
            coreGitRemote: "https://github.com/Homebrew/homebrew-core.git",
            caskGitRemote: "https://github.com/Homebrew/homebrew-cask.git",
            testURL: "https://ghcr.io/v2/"
        ),
        MirrorEndpoint(
            id: "ustc",
            name: "USTC (University of Science and Technology of China)",
            bottleDomain: "https://mirrors.ustc.edu.cn/homebrew-bottles",
            coreGitRemote: "https://mirrors.ustc.edu.cn/homebrew-core.git",
            caskGitRemote: "https://mirrors.ustc.edu.cn/homebrew-cask.git",
            testURL: "https://mirrors.ustc.edu.cn/homebrew-bottles"
        ),
        MirrorEndpoint(
            id: "tsinghua",
            name: "Tsinghua TUNA (Tsinghua University)",
            bottleDomain: "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles",
            coreGitRemote: "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git",
            caskGitRemote: "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-cask.git",
            testURL: "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
        ),
        MirrorEndpoint(
            id: "aliyun",
            name: "Aliyun (Alibaba Cloud)",
            bottleDomain: "https://mirrors.aliyun.com/homebrew/homebrew-bottles",
            coreGitRemote: "https://mirrors.aliyun.com/homebrew/homebrew-core.git",
            caskGitRemote: "https://mirrors.aliyun.com/homebrew/homebrew-cask.git",
            testURL: "https://mirrors.aliyun.com/homebrew/homebrew-bottles"
        )
    ]

    @Published var isBenchmarking = false
    @Published var fastestMirror: MirrorEndpoint?
    @Published var lastBenchmarkedDate: Date?

    func benchmarkAll() async {
        isBenchmarking = true

        let currentMirrors = self.mirrors
        let pingResults = await withTaskGroup(of: (String, Double?).self) { group -> [String: Double?] in
            for mirror in currentMirrors {
                group.addTask {
                    let latency = await Self.pingMirror(urlString: mirror.testURL)
                    return (mirror.id, latency)
                }
            }

            var map: [String: Double?] = [:]
            for await (id, latency) in group {
                map[id] = latency
            }
            return map
        }

        var updatedMirrors = currentMirrors.map { m -> MirrorEndpoint in
            var copy = m
            copy.latencyMs = pingResults[m.id]?.flatMap { $0 }
            copy.isFastest = false
            return copy
        }

        // Determine fastest only after benchmark completes
        let tested = updatedMirrors.filter { $0.latencyMs != nil }
        if !tested.isEmpty, let fastest = tested.min(by: { ($0.latencyMs ?? 99999) < ($1.latencyMs ?? 99999) }) {
            for i in 0 ..< updatedMirrors.count {
                updatedMirrors[i].isFastest = (updatedMirrors[i].id == fastest.id)
            }
            self.fastestMirror = fastest
        } else {
            self.fastestMirror = nil
        }

        self.mirrors = updatedMirrors
        self.lastBenchmarkedDate = Date()
        self.isBenchmarking = false
    }

    nonisolated static func pingMirror(urlString: String) async -> Double? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4.0

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200 ... 399).contains(http.statusCode) {
                return (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            }
        } catch {
            return nil
        }
        return nil
    }

    static func generateShellExportSnippet(mirror: MirrorEndpoint) -> String {
        """
        # Homebrew Mirror Configuration (\(mirror.name))
        export HOMEBREW_BOTTLE_DOMAIN="\(mirror.bottleDomain)"
        export HOMEBREW_BREW_GIT_REMOTE="\(mirror.coreGitRemote.replacingOccurrences(of: "-core.git", with: ".git"))"
        export HOMEBREW_CORE_GIT_REMOTE="\(mirror.coreGitRemote)"
        export HOMEBREW_PIP_INDEX_URL="https://pypi.org/simple"
        """
    }
}
