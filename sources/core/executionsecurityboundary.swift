import Foundation

enum ExecutionSecurityBoundary {
    /// Approved system binary paths that BrewStore is permitted to execute.
    private static let approvedSystemBinaries: Set<String> = [
        "/usr/bin/pgrep",
        "/usr/bin/osascript",
        "/usr/bin/security",
        "/usr/bin/which",
        "/bin/ps",
        "/usr/bin/curl",
        "/usr/bin/codesign",
        "/usr/bin/file",
        "/usr/bin/xattr",
        "/bin/launchctl",
        "/bin/bash",
        "/bin/sleep",
        "/bin/echo",
        "/bin/cat"
    ]

    /// Dangerous environment variables that must be scrubbed before executing child processes.
    private static let dangerousEnvVariables: Set<String> = [
        "DYLD_INSERT_LIBRARIES",
        "DYLD_LIBRARY_PATH",
        "DYLD_FRAMEWORK_PATH",
        "LD_PRELOAD",
        "LD_LIBRARY_PATH"
    ]

    /// Validates whether an executable path is permitted under BrewStore's security boundary.
    static func isExecutableAllowed(executablePath: String, allowedPrefix: String? = nil) -> Bool {
        let normalized = (executablePath as NSString).standardizingPath

        // 1. Check approved system binaries
        if approvedSystemBinaries.contains(normalized) {
            return true
        }

        // 2. Check standard Homebrew locations
        if normalized == "/opt/homebrew/bin/brew" || normalized == "/usr/local/bin/brew" {
            return true
        }
        if normalized == "/opt/homebrew/bin/mas" || normalized == "/usr/local/bin/mas" {
            return true
        }
        if normalized == "/opt/homebrew/bin/speedtest" || normalized == "/usr/local/bin/speedtest" ||
            normalized == "/opt/homebrew/bin/speedtest-go" || normalized == "/usr/local/bin/speedtest-go" {
            return true
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if normalized == "\(homeDir)/.local/bin/speedtest" || normalized == "\(homeDir)/.local/bin/speedtest-go" {
            return true
        }

        // 3. Check custom prefix if provided
        if let prefix = allowedPrefix {
            let brewInPrefix = ((prefix as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent("brew")
            if normalized == brewInPrefix {
                return true
            }
            let masInPrefix = ((prefix as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent("mas")
            if normalized == masInPrefix {
                return true
            }
            let speedtestInPrefix = ((prefix as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent("speedtest")
            if normalized == speedtestInPrefix {
                return true
            }
            let speedtestGoInPrefix = ((prefix as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent("speedtest-go")
            if normalized == speedtestGoInPrefix {
                return true
            }
        }

        return false
    }

    /// Scrubs the current process environment to prevent dynamic linker and environment injection attacks.
    static func sanitizeEnvironment(_ environment: [String: String]) -> [String: String] {
        var cleanEnv = environment
        for key in dangerousEnvVariables {
            cleanEnv.removeValue(forKey: key)
        }

        // Ensure safe default PATH if missing
        if cleanEnv["PATH"] == nil {
            cleanEnv["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }

        // Prevent child subprocesses from hanging on interactive prompts or emitting ANSI escapes
        cleanEnv["HOMEBREW_NO_AUTO_UPDATE"] = cleanEnv["HOMEBREW_NO_AUTO_UPDATE"] ?? "1"
        cleanEnv["HOMEBREW_NO_INSTALL_CLEANUP"] = cleanEnv["HOMEBREW_NO_INSTALL_CLEANUP"] ?? "1"
        cleanEnv["HOMEBREW_NO_COLOR"] = cleanEnv["HOMEBREW_NO_COLOR"] ?? "1"
        cleanEnv["NONINTERACTIVE"] = "1"
        cleanEnv["CI"] = cleanEnv["CI"] ?? "1"

        return cleanEnv
    }
}
