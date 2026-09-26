import Foundation
import Combine

enum HomebrewExecutionPhase: String, CaseIterable, Identifiable, Codable {
    case fetching = "Fetching"
    case configuring = "Configuring"
    case compiling = "Compiling"
    case testing = "Testing"
    case bottling = "Bottling"
    case linking = "Linking"
    case finishing = "Finishing"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fetching: "arrow.down.circle.fill"
        case .configuring: "gearshape.2.fill"
        case .compiling: "hammer.fill"
        case .testing: "checkmark.diamond.fill"
        case .bottling: "shippingbox.fill"
        case .linking: "link.circle.fill"
        case .finishing: "sparkles"
        }
    }

    var stepIndex: Int {
        switch self {
        case .fetching: 0
        case .configuring: 1
        case .compiling: 2
        case .testing: 3
        case .bottling: 4
        case .linking: 5
        case .finishing: 6
        }
    }
}

struct StreamTelemetrySnapshot: Equatable {
    var phase: HomebrewExecutionPhase = .fetching
    var currentThroughputMBs: Double = 0.0
    var throughputDisplay: String = "0.0 MB/s"
    var etaDisplay: String?
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var downloadPercentage: Double?
    var activeArtifactName: String?
    var compilationFileProgress: String?
}

@MainActor
final class BrewStoreExecutionTelemetryManager: ObservableObject {
    static let shared = BrewStoreExecutionTelemetryManager()

    @Published private(set) var currentPhase: HomebrewExecutionPhase = .fetching
    @Published private(set) var telemetry = StreamTelemetrySnapshot()
    @Published private(set) var throughputHistory: [Double] = []
    @Published private(set) var completedPhases: Set<HomebrewExecutionPhase> = []

    private let speedRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"([0-9\.]+)\s*(MB\/s|KB\/s|B\/s|GB\/s)"#, options: .caseInsensitive)
    }()

    private let etaRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"ETA:\s*([0-9]+[a-z0-9\s]*)"#, options: .caseInsensitive)
    }()

    private let bytesRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"([0-9\.]+)\s*(MB|KB|GB)\s*\/\s*([0-9\.]+)\s*(MB|KB|GB)"#, options: .caseInsensitive)
    }()

    private let percentRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"([0-9]{1,3}(?:\.[0-9]+)?)\%"#, options: [])
    }()

    private let cxxBuildRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\[\s*([0-9]+)\s*\/\s*([0-9]+)\s*\]"#, options: [])
    }()

    init() {}

    func reset() {
        currentPhase = .fetching
        telemetry = StreamTelemetrySnapshot()
        throughputHistory.removeAll()
        completedPhases.removeAll()
    }

    func markFinished() {
        currentPhase = .finishing
        completedPhases.formUnion(HomebrewExecutionPhase.allCases)
        telemetry.currentThroughputMBs = 0.0
        telemetry.throughputDisplay = "0.0 MB/s"
        telemetry.etaDisplay = nil
    }

    func processChunk(_ chunk: String) {
        let lines = chunk.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            processLine(trimmed)
        }
    }

    private func processLine(_ line: String) {
        let lower = line.lowercased()

        // 1. Detect Execution Phase Transitions
        if lower.contains("==> downloading") || lower.contains("==> fetching") || lower.contains("curl:") {
            transitionToPhase(.fetching)
        } else if lower.contains("./configure") || lower.contains("cmake") || lower.contains("meson setup") || lower.contains("configuring") {
            transitionToPhase(.configuring)
        } else if lower.contains("==> building") || lower.contains("make") || lower.contains("clang") || lower.contains("swiftc") || lower.contains("building cxx") || lower.contains("compiling") {
            transitionToPhase(.compiling)
        } else if lower.contains("==> testing") || lower.contains("brew test") || lower.contains("running tests") || lower.contains("passed tests") {
            transitionToPhase(.testing)
        } else if lower.contains("==> bottling") || lower.contains("==> pouring") || lower.contains("extracting") {
            transitionToPhase(.bottling)
        } else if lower.contains("==> linking") || lower.contains("brew link") {
            transitionToPhase(.linking)
        } else if lower.contains("==> summary") || lower.contains("🍺") {
            transitionToPhase(.finishing)
        }

        // 2. Extract Download Speed
        if let regex = speedRegex {
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 2 {
                let valueStr = ns.substring(with: match.range(at: 1))
                let unitStr = ns.substring(with: match.range(at: 2)).uppercased()
                if let rawVal = Double(valueStr) {
                    var mbs = rawVal
                    if unitStr.contains("KB") {
                        mbs = rawVal / 1024.0
                    } else if unitStr.contains("GB") {
                        mbs = rawVal * 1024.0
                    } else if unitStr == "B/S" {
                        mbs = rawVal / (1024.0 * 1024.0)
                    }
                    telemetry.currentThroughputMBs = mbs
                    telemetry.throughputDisplay = String(format: "%.1f MB/s", mbs)
                    throughputHistory.append(mbs)
                    if throughputHistory.count > 25 {
                        throughputHistory.removeFirst()
                    }
                }
            }
        }

        // 3. Extract ETA
        if let regex = etaRegex {
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 {
                telemetry.etaDisplay = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            }
        }

        // 4. Extract Percent Progress
        if let regex = percentRegex {
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            if let last = matches.last, last.numberOfRanges > 1 {
                let pStr = ns.substring(with: last.range(at: 1))
                if let p = Double(pStr), p >= 0.0, p <= 100.0 {
                    telemetry.downloadPercentage = p
                }
            }
        }

        // 5. Extract CXX / Build Step Progress (e.g. [14/120])
        if let regex = cxxBuildRegex {
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 2 {
                let cur = ns.substring(with: match.range(at: 1))
                let tot = ns.substring(with: match.range(at: 2))
                telemetry.compilationFileProgress = "[\(cur)/\(tot)]"
            }
        }
    }

    private func transitionToPhase(_ newPhase: HomebrewExecutionPhase) {
        guard newPhase != currentPhase else { return }
        if newPhase.stepIndex > currentPhase.stepIndex {
            for p in HomebrewExecutionPhase.allCases where p.stepIndex < newPhase.stepIndex {
                completedPhases.insert(p)
            }
        }
        currentPhase = newPhase
        telemetry.phase = newPhase
    }
}
