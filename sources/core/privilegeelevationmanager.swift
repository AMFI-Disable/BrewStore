import AppKit
import Foundation

enum PrivilegeElevationStatus: Equatable, Sendable {
    case notRequired
    case required(reason: String)
}

final class BrewStorePrivilegeElevationManager: @unchecked Sendable {
    static let shared = BrewStorePrivilegeElevationManager()

    typealias ElevationRunner = @Sendable (_ script: String) -> (succeeded: Bool, output: String, error: String?)

    private let runner: ElevationRunner

    init(runner: ElevationRunner? = nil) {
        self.runner = runner ?? { script in
            let execute: () -> (Bool, String, String?) = {
                var errorDict: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let result = appleScript?.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "Authorization failed or cancelled by user."
                    return (false, "", errorMsg)
                }
                return (true, result?.stringValue ?? "", nil)
            }

            if Thread.isMainThread {
                return execute()
            } else {
                return DispatchQueue.main.sync(execute: execute)
            }
        }
    }

    /// Evaluates if a package operation is known to require administrator privileges.
    func requiresElevation(package: BrewStorePackage, action _: PackageAction) -> PrivilegeElevationStatus {
        // Casks with .pkg installer files or system drivers typically need root
        if package.kind == .cask {
            if let caveats = package.caveats?.lowercased(),
               caveats.contains("sudo") || caveats.contains("root") || caveats.contains("system extension") {
                return .required(reason: "This cask includes system extensions or requires root permissions.")
            }
        }
        return .notRequired
    }

    /// Checks if a command error indicates missing sudo / root privileges.
    func isPrivilegeError(errorMessage: String, outputLog: String) -> Bool {
        let combined = (errorMessage + "\n" + outputLog).lowercased()
        return combined.contains("sudo: a terminal is required") ||
            combined.contains("sudo: no tty present and no askpass program specified") ||
            combined.contains("need sudo access") ||
            combined.contains("must be run as root") ||
            (combined.contains("permission denied") && combined.contains("/library/"))
    }

    /// Sanitizes an argument for safe inclusion in an AppleScript / sh string.
    static func escapeShellArgument(_ arg: String) -> String {
        "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a Homebrew command with native macOS administrator privileges (Touch ID / password dialog).
    func runElevated(
        brewPath: String,
        arguments: [String]
    ) -> (succeeded: Bool, output: String, error: String?) {
        guard brewPath.hasPrefix("/"), ExecutionSecurityBoundary.isExecutableAllowed(executablePath: brewPath) else {
            return (false, "", "Executable path '\(brewPath)' is not permitted by BrewStore security boundaries.")
        }

        let escapedBrew = Self.escapeShellArgument(brewPath)
        let escapedArgs = arguments.map { Self.escapeShellArgument($0) }.joined(separator: " ")
        let fullCommand = "\(escapedBrew) \(escapedArgs)"

        // AppleScript string escaping (handling backslashes, quotes, and newlines)
        let escapedScriptCommand = fullCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")

        let script = "do shell script \"\(escapedScriptCommand)\" with administrator privileges"
        return runner(script)
    }
}
