import Foundation

struct BrewStoreMirrorPreset: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let description: String
    let testURL: String
    let brewApiDomain: String
    let brewBottlesDomain: String
    let coreGitURL: String
    let caskGitURL: String

    static let official = BrewStoreMirrorPreset(
        id: "official",
        name: "Official (GitHub & Fastly CDN)",
        description: "Default official Homebrew repositories and bottles.",
        testURL: "https://formulae.brew.sh/api/formula.json",
        brewApiDomain: "https://formulae.brew.sh/api",
        brewBottlesDomain: "https://ghcr.io/v2/homebrew/core",
        coreGitURL: "https://github.com/Homebrew/homebrew-core.git",
        caskGitURL: "https://github.com/Homebrew/homebrew-cask.git"
    )

    static let tsinghua = BrewStoreMirrorPreset(
        id: "tuna",
        name: "Tsinghua University (TUNA)",
        description: "High-speed mirror hosted by Tsinghua University Open Source Mirror.",
        testURL: "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api/formula.json",
        brewApiDomain: "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api",
        brewBottlesDomain: "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles",
        coreGitURL: "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git",
        caskGitURL: "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-cask.git"
    )

    static let ustc = BrewStoreMirrorPreset(
        id: "ustc",
        name: "USTC Mirror",
        description: "University of Science and Technology of China mirror.",
        testURL: "https://mirrors.ustc.edu.cn/homebrew-bottles/api/formula.json",
        brewApiDomain: "https://mirrors.ustc.edu.cn/homebrew-bottles/api",
        brewBottlesDomain: "https://mirrors.ustc.edu.cn/homebrew-bottles",
        coreGitURL: "https://mirrors.ustc.edu.cn/homebrew-core.git",
        caskGitURL: "https://mirrors.ustc.edu.cn/homebrew-cask.git"
    )

    static let aliyun = BrewStoreMirrorPreset(
        id: "aliyun",
        name: "Aliyun Mirror",
        description: "Alibaba Cloud open-source mirror service.",
        testURL: "https://mirrors.aliyun.com/homebrew/homebrew-bottles/api/formula.json",
        brewApiDomain: "https://mirrors.aliyun.com/homebrew/homebrew-bottles/api",
        brewBottlesDomain: "https://mirrors.aliyun.com/homebrew/homebrew-bottles",
        coreGitURL: "https://mirrors.aliyun.com/homebrew/homebrew-core.git",
        caskGitURL: "https://mirrors.aliyun.com/homebrew/homebrew-cask.git"
    )

    static let allPresets: [BrewStoreMirrorPreset] = [.official, .tsinghua, .ustc, .aliyun]
}

@MainActor
final class BrewStoreMirrorManager: ObservableObject {
    @Published var selectedPresetID: String {
        didSet {
            UserDefaults.standard.set(selectedPresetID, forKey: mirrorKey)
        }
    }

    @Published var latencies: [String: TimeInterval] = [:]
    @Published var isTestingLatency = false

    private let mirrorKey = "BrewStoreSelectedMirrorID"

    init() {
        self.selectedPresetID = UserDefaults.standard.string(forKey: mirrorKey) ?? BrewStoreMirrorPreset.official.id
    }

    var currentPreset: BrewStoreMirrorPreset {
        BrewStoreMirrorPreset.allPresets.first { $0.id == selectedPresetID } ?? .official
    }

    func testLatencies() {
        guard !isTestingLatency else { return }
        isTestingLatency = true

        Task {
            let results = await withTaskGroup(of: (String, TimeInterval?).self) { group -> [String: TimeInterval] in
                for preset in BrewStoreMirrorPreset.allPresets {
                    guard let url = URL(string: preset.testURL) else { continue }
                    group.addTask {
                        var request = URLRequest(url: url)
                        request.httpMethod = "HEAD"
                        request.timeoutInterval = 4

                        let start = CFAbsoluteTimeGetCurrent()
                        if await (try? URLSession.shared.data(for: request)) != nil {
                            let elapsed = CFAbsoluteTimeGetCurrent() - start
                            return (preset.id, elapsed)
                        }
                        return (preset.id, nil)
                    }
                }

                var map: [String: TimeInterval] = [:]
                for await (id, elapsed) in group {
                    if let elapsed {
                        map[id] = elapsed
                    }
                }
                return map
            }

            await MainActor.run {
                self.latencies = results
                self.isTestingLatency = false
            }
        }
    }

    func formattedLatency(for preset: BrewStoreMirrorPreset) -> String? {
        guard let seconds = latencies[preset.id] else { return nil }
        return String(format: "%.0f ms", seconds * 1000)
    }
}
