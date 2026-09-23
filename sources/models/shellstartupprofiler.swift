import Foundation

enum ShellPerformanceGrade: String, CaseIterable, Sendable, Codable {
    case gradeA = "A (Instant)"
    case gradeB = "B (Responsive)"
    case gradeC = "C (Noticeable Lag)"
    case gradeD = "D (Severe Bottleneck)"

    var badgeColor: String {
        switch self {
        case .gradeA: "green"
        case .gradeB: "blue"
        case .gradeC: "orange"
        case .gradeD: "red"
        }
    }

    static func evaluate(latencyMs: Double) -> ShellPerformanceGrade {
        switch latencyMs {
        case ..<100: .gradeA
        case 100..<250: .gradeB
        case 250..<600: .gradeC
        default: .gradeD
        }
    }
}

struct ShellBenchmarkSegment: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let commandTested: String
    let latencyMs: Double
    let impactPercentage: Double
    let description: String
}

struct ShellOptimizationTip: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let estimatedSavingsMs: Double
    let detail: String
    let recommendedActionSnippet: String?
}

struct ShellBenchmarkResult: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let timestamp: Date
    let shellName: String
    let shellPath: String
    let totalStartupLatencyMs: Double
    let cleanShellLatencyMs: Double
    let userConfigOverheadMs: Double
    let grade: ShellPerformanceGrade
    let segments: [ShellBenchmarkSegment]
    let tips: [ShellOptimizationTip]
    let cachedShellenvSnippet: String

    var formattedTotalLatency: String {
        String(format: "%.1f ms", totalStartupLatencyMs)
    }

    var formattedOverhead: String {
        String(format: "+%.1f ms overhead", userConfigOverheadMs)
    }
}

@MainActor
final class ShellStartupProfiler: ObservableObject {
    static let shared = ShellStartupProfiler()

    @Published var isProfiling = false
    @Published var latestResult: ShellBenchmarkResult?
    @Published var statusMessage = "Ready to profile shell startup."

    /// Executes shell startup profiling and returns a complete diagnostic report.
    @discardableResult
    func runProfile(customShellPath: String? = nil) async -> ShellBenchmarkResult {
        isProfiling = true
        statusMessage = "Measuring interactive shell launch latency…"

        let detectedShell = customShellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (detectedShell as NSString).lastPathComponent.lowercased()

        let result = await Task.detached(priority: .userInitiated) { () -> ShellBenchmarkResult in
            Self.performBenchmark(shellPath: detectedShell, shellName: shellName)
        }.value

        self.latestResult = result
        self.isProfiling = false
        self.statusMessage = "Profile complete: \(result.formattedTotalLatency) (\(result.grade.rawValue))"
        return result
    }

    nonisolated static func performBenchmark(shellPath: String, shellName: String) -> ShellBenchmarkResult {
        // 1. Measure clean baseline shell without user dotfiles
        let cleanLatency = measureCommandLatency(executable: shellPath, arguments: ["-f", "-c", "exit"], runs: 3)

        // 2. Measure interactive login shell (loads .zprofile, .zshrc, etc.)
        let totalLatency = measureCommandLatency(executable: shellPath, arguments: ["-i", "-c", "exit"], runs: 3)
        let overhead = max(0, totalLatency - cleanLatency)

        // 3. Measure specific Homebrew components
        var segments: [ShellBenchmarkSegment] = []

        // Benchmark dynamic brew shellenv
        let brewPath = HomebrewManager.detectBrewPath() ?? "/opt/homebrew/bin/brew"
        let brewShellenvLatency = measureCommandLatency(
            executable: shellPath,
            arguments: ["-c", "eval \"$(\(brewPath) shellenv)\""],
            runs: 2
        )

        segments.append(ShellBenchmarkSegment(
            id: "brew_shellenv",
            name: "brew shellenv",
            commandTested: "eval \"$(\(brewPath) shellenv)\"",
            latencyMs: brewShellenvLatency,
            impactPercentage: totalLatency > 0 ? min(100, (brewShellenvLatency / totalLatency) * 100) : 0,
            description: "Spawns subshell to calculate PATH, MANPATH, and INFOPATH environment variables."
        ))

        // Check for starship prompt if installed
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/starship") ||
           FileManager.default.isExecutableFile(atPath: "/usr/local/bin/starship") {
            let starshipLatency = measureCommandLatency(
                executable: shellPath,
                arguments: ["-c", "eval \"$(starship init \(shellName))\""],
                runs: 2
            )
            segments.append(ShellBenchmarkSegment(
                id: "starship_init",
                name: "starship prompt init",
                commandTested: "starship init \(shellName)",
                latencyMs: starshipLatency,
                impactPercentage: totalLatency > 0 ? min(100, (starshipLatency / totalLatency) * 100) : 0,
                description: "Initializes Starship cross-shell prompt theme engine."
            ))
        }

        // Check for zoxide if installed
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/zoxide") ||
           FileManager.default.isExecutableFile(atPath: "/usr/local/bin/zoxide") {
            let zoxideLatency = measureCommandLatency(
                executable: shellPath,
                arguments: ["-c", "eval \"$(zoxide init \(shellName))\""],
                runs: 2
            )
            segments.append(ShellBenchmarkSegment(
                id: "zoxide_init",
                name: "zoxide directory jumping",
                commandTested: "zoxide init \(shellName)",
                latencyMs: zoxideLatency,
                impactPercentage: totalLatency > 0 ? min(100, (zoxideLatency / totalLatency) * 100) : 0,
                description: "Initializes smart cd directory indexer hook."
            ))
        }

        // 4. Generate static cached shellenv snippet
        let prefix = HomebrewManager.detectBrewPrefix() ?? "/opt/homebrew"
        let cachedSnippet = generateStaticShellenvSnippet(prefix: prefix, shellName: shellName)

        // 5. Generate tailored optimization tips
        var tips: [ShellOptimizationTip] = []

        if brewShellenvLatency > 25.0 {
            tips.append(ShellOptimizationTip(
                id: "cache_brew_shellenv",
                title: "Replace dynamic 'brew shellenv' with static exports",
                estimatedSavingsMs: brewShellenvLatency * 0.85,
                detail: "Dynamic 'eval \"$(brew shellenv)\"' spawns Ruby/Bash subprocesses on every terminal launch. Hardcoding exports saves ~\(Int(brewShellenvLatency)) ms instantly.",
                recommendedActionSnippet: cachedSnippet
            ))
        }

        if totalLatency > 250.0 {
            tips.append(ShellOptimizationTip(
                id: "defer_completions",
                title: "Defer completion and hook initializations",
                estimatedSavingsMs: 80.0,
                detail: "Large completion folders can be compiled with 'zcompile ~/.zcompdump' to eliminate parsing overhead on startup.",
                recommendedActionSnippet: "autoload -Uz compinit && compinit -C"
            ))
        }

        let grade = ShellPerformanceGrade.evaluate(latencyMs: totalLatency)

        return ShellBenchmarkResult(
            id: UUID().uuidString,
            timestamp: Date(),
            shellName: shellName,
            shellPath: shellPath,
            totalStartupLatencyMs: totalLatency,
            cleanShellLatencyMs: cleanLatency,
            userConfigOverheadMs: overhead,
            grade: grade,
            segments: segments,
            tips: tips,
            cachedShellenvSnippet: cachedSnippet
        )
    }

    /// Measures execution time in milliseconds over a series of test runs.
    nonisolated static func measureCommandLatency(executable: String, arguments: [String], runs: Int) -> Double {
        guard runs > 0 else { return 0 }
        var totalMs: Double = 0

        for _ in 0..<runs {
            let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: executable,
                arguments: arguments,
                timeout: 5,
                category: .readOnly
            )
            let end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let durationMs = Double(end - start) / 1_000_000.0
            totalMs += durationMs
        }

        return max(0.5, totalMs / Double(runs))
    }

    /// Creates an optimized static export block that avoids running Homebrew CLI on shell startup.
    nonisolated static func generateStaticShellenvSnippet(prefix: String, shellName: String) -> String {
        let cellar = "\(prefix)/Cellar"
        let repository = prefix

        if shellName == "fish" {
            return """
            # --- Cached BrewStore Environment (Zero Process Spawn Overhead) ---
            set -gx HOMEBREW_PREFIX "\(prefix)"
            set -gx HOMEBREW_CELLAR "\(cellar)"
            set -gx HOMEBREW_REPOSITORY "\(repository)"
            fish_add_path "\(prefix)/bin" "\(prefix)/sbin"
            """
        } else {
            return """
            # --- Cached BrewStore Environment (Zero Process Spawn Overhead) ---
            export HOMEBREW_PREFIX="\(prefix)"
            export HOMEBREW_CELLAR="\(cellar)"
            export HOMEBREW_REPOSITORY="\(repository)"
            export PATH="\(prefix)/bin:\(prefix)/sbin:$PATH"
            [ -d "\(prefix)/share/man" ] && export MANPATH="\(prefix)/share/man:$MANPATH"
            [ -d "\(prefix)/share/info" ] && export INFOPATH="\(prefix)/share/info:$INFOPATH"
            """
        }
    }
}
