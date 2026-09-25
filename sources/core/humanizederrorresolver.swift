import AppKit
import Foundation
import SwiftUI

/// Structured, humanized representation of a Homebrew or system operation error.
public struct HumanizedErrorInfo: Equatable, Sendable, Identifiable {
    public var id: String { "\(category.rawValue)-\(title)" }

    /// Human-friendly headline explaining what went wrong in plain language.
    public let title: String

    /// Warm, informative summary of the underlying situation.
    public let summary: String

    /// Practical, actionable recommendation on how the user can resolve the issue.
    public let suggestion: String

    /// SF Symbol icon visually identifying the issue category.
    public let iconName: String

    /// High-level diagnostic category.
    public let category: ErrorCategory

    /// Whether this condition is typically transient and can be retried immediately.
    public let isRetryable: Bool

    /// Raw technical error details or stdout/stderr (retained for inspection).
    public let technicalDetails: String?

    public enum ErrorCategory: String, Equatable, Sendable, CaseIterable {
        case lock = "Database In Use"
        case permissions = "Permissions Required"
        case network = "Network Connection"
        case checksum = "Security & Integrity"
        case developerTools = "Apple Developer Tools"
        case appCollision = "Application Conflict"
        case dependencyConflict = "Package Dependencies"
        case notFound = "Package Availability"
        case kegOnly = "System Isolation"
        case quarantine = "macOS Gatekeeper"
        case timeout = "Operation Timeout"
        case cancelled = "User Cancellation"
        case malformedData = "Catalog Data"
        case generic = "System Diagnostic"
    }

    public init(
        title: String,
        summary: String,
        suggestion: String,
        iconName: String,
        category: ErrorCategory,
        isRetryable: Bool = true,
        technicalDetails: String? = nil
    ) {
        self.title = title
        self.summary = summary
        self.suggestion = suggestion
        self.iconName = iconName
        self.category = category
        self.isRetryable = isRetryable
        self.technicalDetails = technicalDetails
    }
}

/// Central resolver translating cryptic Homebrew CLI outputs, exit codes, and system errors into clear, human-centric explanations.
public enum BrewStoreHumanizedErrorResolver {

    /// Resolves raw Homebrew command output into a structured, humanized diagnostic (Int32 overload).
    public static func resolve(
        rawError: String,
        exitCode: Int32?,
        didTimeout: Bool = false,
        wasCancelled: Bool = false
    ) -> HumanizedErrorInfo {
        resolve(
            rawError: rawError,
            exitCode: exitCode.map(Int.init),
            didTimeout: didTimeout,
            wasCancelled: wasCancelled
        )
    }

    /// Resolves raw Homebrew command output into a structured, humanized diagnostic.
    public static func resolve(
        rawError: String,
        exitCode: Int? = nil,
        didTimeout: Bool = false,
        wasCancelled: Bool = false
    ) -> HumanizedErrorInfo {
        let cleaned = rawError.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()

        // 1. Explicit cancellation
        if wasCancelled || lower.contains("operation cancelled") || lower.contains("user cancelled") {
            return HumanizedErrorInfo(
                title: "Operation Cancelled",
                summary: "The requested Homebrew task was cancelled before completion.",
                suggestion: "You can restart this operation at any time whenever you're ready.",
                iconName: "xmark.circle.fill",
                category: .cancelled,
                isRetryable: true,
                technicalDetails: cleaned.isEmpty ? nil : cleaned
            )
        }

        // 2. Explicit timeout
        if didTimeout || lower.contains("timed out") || lower.contains("command timed out") {
            return HumanizedErrorInfo(
                title: "Operation Timed Out",
                summary: "Homebrew took longer than expected to complete this operation.",
                suggestion: "This usually happens during lengthy compilation or heavy network congestion. Verify your connection and try again.",
                iconName: "clock.badge.exclamationmark.fill",
                category: .timeout,
                isRetryable: true,
                technicalDetails: cleaned.isEmpty ? nil : cleaned
            )
        }

        // 3. Database lock errors
        if lower.contains("another active homebrew process") ||
           lower.contains("waiting on a lock") ||
           lower.contains("lock file exists") ||
           lower.contains("is locked by") ||
           lower.contains("homebrew is locked") {
            return HumanizedErrorInfo(
                title: "Homebrew is Busy",
                summary: "Another Homebrew process, background task, or Terminal tab is currently using the package database.",
                suggestion: "Wait for the ongoing task to finish, or click 'Clear Locks' in Diagnostics (⌥~) to remove stale locks.",
                iconName: "lock.shield.fill",
                category: .lock,
                isRetryable: true,
                technicalDetails: cleaned
            )
        }

        // 4. Permissions & Sudo errors
        if lower.contains("permission denied") ||
           lower.contains("not writable by your user") ||
           lower.contains("eacces") ||
           lower.contains("operation not permitted") ||
           lower.contains("privilege") ||
           lower.contains("must be run as root") {
            return HumanizedErrorInfo(
                title: "Administrator Privileges Required",
                summary: "macOS restricted write access to Homebrew directory files or system library folders.",
                suggestion: "Authenticate with your Mac password to grant elevated permissions, or adjust directory permissions in Terminal.",
                iconName: "key.fill",
                category: .permissions,
                isRetryable: true,
                technicalDetails: cleaned
            )
        }

        // 5. Network / Mirrors / SSL errors
        if lower.contains("could not resolve host") ||
           lower.contains("failed to connect") ||
           lower.contains("ssl connect error") ||
           lower.contains("connection reset by peer") ||
           lower.contains("curl: (6)") ||
           lower.contains("curl: (7)") ||
           lower.contains("curl: (28)") ||
           lower.contains("curl: (35)") ||
           lower.contains("unable to access") ||
           lower.contains("network is down") ||
           lower.contains("network error") {
            return HumanizedErrorInfo(
                title: "Network Connection Interrupted",
                summary: "Could not establish a reliable connection to GitHub or the package download mirror.",
                suggestion: "Check your Wi-Fi, VPN, or proxy settings. If the issue persists, the remote mirror may be temporarily unavailable.",
                iconName: "wifi.exclamationmark",
                category: .network,
                isRetryable: true,
                technicalDetails: cleaned
            )
        }

        // 6. Checksum / Integrity errors
        if lower.contains("checksum mismatch") ||
           lower.contains("sha256 mismatch") ||
           lower.contains("verification failed") ||
           lower.contains("hash mismatch") {
            return HumanizedErrorInfo(
                title: "Download Verification Failed",
                summary: "The downloaded installer package's cryptographic signature did not match Homebrew's published checksum.",
                suggestion: "The download may be corrupted or a mirror cache out of sync. Clear cache in Settings and retry the download.",
                iconName: "exclamationmark.shield.fill",
                category: .checksum,
                isRetryable: true,
                technicalDetails: cleaned
            )
        }

        // 7. Apple Developer Command Line Tools missing
        if lower.contains("xcode-select: error") ||
           lower.contains("install the command line tools") ||
           lower.contains("xcode-select --install") ||
           lower.contains("invalid active developer path") ||
           lower.contains("xcrun: error") {
            return HumanizedErrorInfo(
                title: "Apple Developer Tools Required",
                summary: "Compiling or linking this package requires Apple Command Line Developer Tools.",
                suggestion: "Open Terminal and run 'xcode-select --install' to set up the necessary developer toolchain.",
                iconName: "hammer.fill",
                category: .developerTools,
                isRetryable: false,
                technicalDetails: cleaned
            )
        }

        // 8. Application bundle collision (App already exists in /Applications)
        if lower.contains("already an app at") ||
           lower.contains("already exists") ||
           lower.contains("use --force to overwrite") {
            return HumanizedErrorInfo(
                title: "Application Already Installed",
                summary: "An application with this name already exists in your /Applications folder, possibly installed outside Homebrew.",
                suggestion: "Adopt the application in the Adoption view to track it, or reinstall with overwrite enabled to replace it.",
                iconName: "app.badge.checkmark",
                category: .appCollision,
                isRetryable: true,
                technicalDetails: cleaned
            )
        }

        // 9. Dependency conflicts
        if lower.contains("refusing to uninstall") ||
           lower.contains("is required by") ||
           lower.contains("needed by") ||
           lower.contains("broken dependencies") {
            let note = lower.contains("simulated") ? " (simulated lock or dependency failure)" : ""
            return HumanizedErrorInfo(
                title: "Refusing to Uninstall Package",
                summary: "Other software installed on your Mac depends on this package to function properly\(note).",
                suggestion: "Review the dependent packages in the Dependency Graph before removing, or uninstall dependent tools first.",
                iconName: "arrow.triangle.merge",
                category: .dependencyConflict,
                isRetryable: false,
                technicalDetails: cleaned
            )
        }

        // 10. Package not found / Typo / Missing tap
        if lower.contains("no available formula") ||
           lower.contains("no available cask") ||
           lower.contains("did you mean") ||
           lower.contains("could not find") {
            return HumanizedErrorInfo(
                title: "Package Not Found",
                summary: "This package does not exist in standard Homebrew repositories or may belong to a custom tap.",
                suggestion: "Verify the spelling of the package name, or add the developer's third-party tap in the Taps tab.",
                iconName: "questionmark.folder.fill",
                category: .notFound,
                isRetryable: false,
                technicalDetails: cleaned
            )
        }

        // 11. Keg-only isolation
        if lower.contains("is keg-only") ||
           lower.contains("not linked into") ||
           lower.contains("brew link --overwrite") {
            return HumanizedErrorInfo(
                title: "Package Kept Isolated",
                summary: "This package is intentionally isolated from your global PATH to prevent collisions with macOS system utilities.",
                suggestion: "Use the full binary path or export environment variables as shown in the package's Caveats section.",
                iconName: "shippingbox.and.arrow.backward",
                category: .kegOnly,
                isRetryable: false,
                technicalDetails: cleaned
            )
        }

        // 12. Gatekeeper / Quarantine
        if lower.contains("quarantine") ||
           lower.contains("damaged and can't be opened") ||
           lower.contains("unidentified developer") ||
           lower.contains("cannot check it for malicious software") {
            return HumanizedErrorInfo(
                title: "macOS Gatekeeper Block",
                summary: "Apple security quarantined this application because the developer hasn't registered a notarization ticket.",
                suggestion: "Open System Settings > Privacy & Security, scroll down to the Security section, and select 'Open Anyway'.",
                iconName: "hand.raised.fill",
                category: .quarantine,
                isRetryable: false,
                technicalDetails: cleaned
            )
        }

        // 13. Truncated output
        if lower.contains("truncated output") || lower.contains("buffer limit") {
            return HumanizedErrorInfo(
                title: "Command Output Exceeded Buffer",
                summary: "The command returned a larger volume of data than BrewStore's memory buffer allowed.",
                suggestion: "Run the command in Action Console with a specific filter or run it directly in Terminal.",
                iconName: "doc.badge.ellipsis",
                category: .malformedData,
                isRetryable: true,
                technicalDetails: cleaned
            )
        }

        // 14. Malformed JSON catalog
        if lower.contains("malformed json") || lower.contains("invalid json") {
            return HumanizedErrorInfo(
                title: "Catalog Index Needs Refresh",
                summary: "Homebrew returned unexpected or incomplete catalog data from the local cache.",
                suggestion: "Run 'brew update' in Action Console or tap Refresh in the sidebar to rebuild the index.",
                iconName: "curlybraces.square.fill",
                category: .malformedData,
                isRetryable: true,
                technicalDetails: cleaned
            )
        }

        // 15. Exit code fallback
        let exitStatusText = exitCode.map { " (exit code \($0))" } ?? ""
        let cleanDetail = cleaned.isEmpty ? nil : cleaned

        return HumanizedErrorInfo(
            title: "Operation Incomplete",
            summary: cleanDetail ?? "Homebrew was unable to finish the requested task\(exitStatusText).",
            suggestion: "Open the Action Console (⌥~) to inspect full execution logs, or run Homebrew Doctor in Settings.",
            iconName: "exclamationmark.triangle.fill",
            category: .generic,
            isRetryable: true,
            technicalDetails: cleanDetail
        )
    }

    /// Convenience helper returning a user-friendly string message directly.
    public static func humanizedMessage(
        from rawError: String,
        fallback: String = "Homebrew did not complete the operation."
    ) -> String {
        let info = resolve(rawError: rawError)
        if info.category == .generic, (info.technicalDetails == nil || info.technicalDetails?.isEmpty == true) {
            return fallback
        }
        return "\(info.title): \(info.summary) \(info.suggestion)"
    }
}
