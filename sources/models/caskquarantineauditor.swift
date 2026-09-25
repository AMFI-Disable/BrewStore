import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

enum QuarantineStatus: String, Codable, CaseIterable, Equatable {
    case clean = "Clean & Verified"
    case quarantined = "Quarantined by Gatekeeper"
    case adHocSigned = "Ad-Hoc Signed"
    case invalidSignature = "Invalid / Unsigned"
    case uninspected = "Pending Audit"

    var badgeColor: Color {
        switch self {
        case .clean: .green
        case .quarantined: .orange
        case .adHocSigned: .purple
        case .invalidSignature: .red
        case .uninspected: .secondary
        }
    }

    var iconName: String {
        switch self {
        case .clean: "checkmark.shield.fill"
        case .quarantined: "exclamationmark.shield.fill"
        case .adHocSigned: "signature"
        case .invalidSignature: "xmark.shield.fill"
        case .uninspected: "questionmark.circle"
        }
    }
}

struct QuarantineDetails: Identifiable, Hashable, Codable {
    var id: String { rawString }
    let rawString: String
    let flags: String
    let timestampDate: Date?
    let agent: String?
    let uuid: String?

    init(rawString: String) {
        self.rawString = rawString
        let parts = rawString.components(separatedBy: ";")
        self.flags = parts.indices.contains(0) ? parts[0] : ""
        if parts.indices.contains(1), let hex = Int(parts[1], radix: 16) {
            self.timestampDate = Date(timeIntervalSince1970: TimeInterval(hex))
        } else {
            self.timestampDate = nil
        }
        if parts.indices.contains(2), !parts[2].trimmingCharacters(in: .whitespaces).isEmpty {
            self.agent = parts[2].trimmingCharacters(in: .whitespaces)
        } else {
            self.agent = nil
        }
        if parts.indices.contains(3), !parts[3].trimmingCharacters(in: .whitespaces).isEmpty {
            self.uuid = parts[3].trimmingCharacters(in: .whitespaces)
        } else {
            self.uuid = nil
        }
    }

    var formattedDate: String {
        guard let date = timestampDate else { return "Unknown timestamp" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct CaskQuarantineItem: Identifiable, Hashable, Codable {
    let id: String
    let caskName: String
    let bundleURL: URL
    var isQuarantined: Bool
    var quarantineDetails: QuarantineDetails?
    var isNotarized: Bool
    var isAdHoc: Bool
    var signingAuthority: String?
    var teamIdentifier: String?
    var status: QuarantineStatus
    var lastAudited: Date

    init(
        id: String,
        caskName: String,
        bundleURL: URL,
        isQuarantined: Bool,
        quarantineDetails: QuarantineDetails? = nil,
        isNotarized: Bool = false,
        isAdHoc: Bool = false,
        signingAuthority: String? = nil,
        teamIdentifier: String? = nil,
        status: QuarantineStatus,
        lastAudited: Date = Date()
    ) {
        self.id = id
        self.caskName = caskName
        self.bundleURL = bundleURL
        self.isQuarantined = isQuarantined
        self.quarantineDetails = quarantineDetails
        self.isNotarized = isNotarized
        self.isAdHoc = isAdHoc
        self.signingAuthority = signingAuthority
        self.teamIdentifier = teamIdentifier
        self.status = status
        self.lastAudited = lastAudited
    }
}

struct QuarantineSummary: Equatable {
    let totalAudited: Int
    let quarantinedCount: Int
    let cleanCount: Int
    let adHocCount: Int
    let invalidCount: Int

    var isFullyClean: Bool {
        quarantinedCount == 0 && invalidCount == 0
    }
}

@MainActor
final class BrewStoreCaskQuarantineAuditor: ObservableObject {
    static let shared = BrewStoreCaskQuarantineAuditor()

    @Published var auditedItems: [CaskQuarantineItem] = []
    @Published var isAuditing: Bool = false
    @Published var auditProgress: Double = 0.0
    @Published var activeOperationItem: String? = nil
    @Published var lastAuditDate: Date? = nil

    init() {}

    var summary: QuarantineSummary {
        calculateSummary(for: auditedItems)
    }

    func calculateSummary(for items: [CaskQuarantineItem]) -> QuarantineSummary {
        let total = items.count
        let quarantined = items.filter { $0.status == .quarantined }.count
        let clean = items.filter { $0.status == .clean }.count
        let adHoc = items.filter { $0.status == .adHocSigned }.count
        let invalid = items.filter { $0.status == .invalidSignature }.count
        return QuarantineSummary(
            totalAudited: total,
            quarantinedCount: quarantined,
            cleanCount: clean,
            adHocCount: adHoc,
            invalidCount: invalid
        )
    }

    func auditPackage(package: BrewStorePackage, prefix: String? = nil) async -> CaskQuarantineItem? {
        guard package.kind == .cask, package.isInstalled else { return nil }
        guard let bundleURL = resolveBundleURL(for: package, prefix: prefix) else { return nil }

        let rawQuarantine = Self.readQuarantineAttribute(at: bundleURL.path)
        let isQuarantined = rawQuarantine != nil
        let quarantineDetails = rawQuarantine.map { QuarantineDetails(rawString: $0) }

        let codesignInfo = await Self.inspectCodesign(bundleURL: bundleURL)
        let status = Self.resolveStatus(
            isQuarantined: isQuarantined,
            isSigned: codesignInfo.isSigned,
            isAdHoc: codesignInfo.isAdHoc,
            authority: codesignInfo.authority
        )

        let isNotarized = (codesignInfo.authority?.contains("Developer ID Application") ?? false) ||
                          (codesignInfo.authority?.contains("Apple Mac OS Application Signing") ?? false)

        return CaskQuarantineItem(
            id: package.id,
            caskName: package.name,
            bundleURL: bundleURL,
            isQuarantined: isQuarantined,
            quarantineDetails: quarantineDetails,
            isNotarized: isNotarized,
            isAdHoc: codesignInfo.isAdHoc,
            signingAuthority: codesignInfo.authority,
            teamIdentifier: codesignInfo.teamID,
            status: status,
            lastAudited: Date()
        )
    }

    func auditAllInstalledCasks(casks: [BrewStorePackage], prefix: String? = nil) async -> [CaskQuarantineItem] {
        let installedCasks = casks.filter { $0.kind == .cask && $0.isInstalled }
        guard !installedCasks.isEmpty else {
            auditedItems = []
            return []
        }

        isAuditing = true
        auditProgress = 0.0
        var results: [CaskQuarantineItem] = []

        let total = Double(installedCasks.count)
        for (index, cask) in installedCasks.enumerated() {
            activeOperationItem = cask.name
            if let item = await auditPackage(package: cask, prefix: prefix) {
                results.append(item)
            }
            auditProgress = Double(index + 1) / total
        }

        auditedItems = results
        lastAuditDate = Date()
        isAuditing = false
        activeOperationItem = nil
        return results
    }

    func removeQuarantine(for item: CaskQuarantineItem) async -> Result<Void, Error> {
        activeOperationItem = item.caskName
        let success = Self.removeQuarantineAttribute(at: item.bundleURL.path, recursive: true)
        activeOperationItem = nil

        if success {
            if let idx = auditedItems.firstIndex(where: { $0.id == item.id }) {
                var updated = auditedItems[idx]
                updated.isQuarantined = false
                updated.quarantineDetails = nil
                updated.status = Self.resolveStatus(
                    isQuarantined: false,
                    isSigned: !updated.isAdHoc && updated.signingAuthority != nil,
                    isAdHoc: updated.isAdHoc,
                    authority: updated.signingAuthority
                )
                updated.lastAudited = Date()
                auditedItems[idx] = updated
            }
            return .success(())
        } else {
            return .failure(NSError(
                domain: "BrewStoreQuarantineAuditor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to remove quarantine attribute from \(item.bundleURL.path). Ensure permissions allow modifying the bundle."]
            ))
        }
    }

    func removeQuarantineAll(items: [CaskQuarantineItem]) async -> (cleared: Int, failed: Int) {
        var cleared = 0
        var failed = 0
        let targets = items.filter { $0.isQuarantined }
        for target in targets {
            let res = await removeQuarantine(for: target)
            switch res {
            case .success:
                cleared += 1
            case .failure:
                failed += 1
            }
        }
        return (cleared, failed)
    }

    func resolveBundleURL(for package: BrewStorePackage, prefix: String? = nil) -> URL? {
        let names = package.applicationNames.isEmpty ? [package.name] : package.applicationNames
        if let localApp = BrewStoreAppIconResolver.localAppURL(for: names) {
            return localApp
        }

        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for dir in appDirs {
            let candidate = dir.appendingPathComponent(package.name.hasSuffix(".app") ? package.name : "\(package.name).app")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let effectivePrefix = prefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let caskroom = URL(fileURLWithPath: effectivePrefix).appendingPathComponent("Caskroom").appendingPathComponent(package.id)

        if let enumerator = FileManager.default.enumerator(at: caskroom, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "app" {
                    return fileURL
                }
            }
        }

        return nil
    }

    // MARK: - Static POSIX & Inspection Helpers

    nonisolated static func readQuarantineAttribute(at path: String) -> String? {
        let attr = "com.apple.quarantine"
        let size = getxattr(path, attr, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        let readSize = getxattr(path, attr, &buffer, size, 0, 0)
        guard readSize > 0 else { return nil }
        return String(cString: buffer)
    }

    @discardableResult
    nonisolated static func setQuarantineAttribute(at path: String, value: String) -> Bool {
        let attr = "com.apple.quarantine"
        let result = value.withCString { cStr in
            setxattr(path, attr, cStr, strlen(cStr), 0, 0)
        }
        return result == 0
    }

    @discardableResult
    nonisolated static func removeQuarantineAttribute(at path: String, recursive: Bool = true) -> Bool {
        let attr = "com.apple.quarantine"
        let topResult = removexattr(path, attr, 0)
        if recursive {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            process.arguments = ["-rd", attr, path]
            try? process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 || topResult == 0
        }
        return topResult == 0
    }

    nonisolated static func parseCodesignOutput(_ output: String) -> (isSigned: Bool, isAdHoc: Bool, authority: String?, teamID: String?) {
        if output.contains("code object is not signed at all") {
            return (false, false, nil, nil)
        }

        var authority: String?
        var teamID: String?
        var isAdHoc = false

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Authority=") {
                if authority == nil {
                    authority = String(trimmed.dropFirst("Authority=".count))
                }
            } else if trimmed.hasPrefix("TeamIdentifier=") {
                let id = String(trimmed.dropFirst("TeamIdentifier=".count))
                if id != "not set" {
                    teamID = id
                }
            } else if trimmed.contains("Signature=adhoc") || trimmed.contains("flags=0x10002(adhoc") {
                isAdHoc = true
            }
        }

        let isSigned = authority != nil || isAdHoc
        return (isSigned, isAdHoc, authority, teamID)
    }

    nonisolated static func resolveStatus(isQuarantined: Bool, isSigned: Bool, isAdHoc: Bool, authority: String?) -> QuarantineStatus {
        if isQuarantined {
            return .quarantined
        }
        if !isSigned {
            return .invalidSignature
        }
        if isAdHoc {
            return .adHocSigned
        }
        return .clean
    }

    nonisolated static func inspectCodesign(bundleURL: URL) async -> (isSigned: Bool, isAdHoc: Bool, authority: String?, teamID: String?) {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["-d", "--verbose=2", bundleURL.path]

            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                return parseCodesignOutput(output)
            } catch {
                return (false, false, nil, nil)
            }
        }.value
    }
}
