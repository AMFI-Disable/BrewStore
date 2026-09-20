import Foundation

enum EntitlementCategory: String, CaseIterable, Sendable, Codable {
    case sandbox = "Sandbox Isolation"
    case privacy = "Hardware & Privacy"
    case filesystem = "File System Access"
    case network = "Network Capabilities"
    case runtime = "Hardened Runtime"
}

struct EntitlementBadge: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let systemImage: String
    let colorName: String
    let category: EntitlementCategory
    let description: String
}

struct CaskEntitlementsReport: Identifiable, Hashable, Sendable {
    let id: String // packageID
    let applicationPath: String
    let isSandboxed: Bool
    let isHardenedRuntime: Bool
    let allowsJIT: Bool
    let allowsUnsignedExecutableMemory: Bool
    let disablesLibraryValidation: Bool
    let hasCameraAccess: Bool
    let hasMicrophoneAccess: Bool
    let hasBluetoothAccess: Bool
    let hasUSBAccess: Bool
    let hasLocationAccess: Bool
    let hasContactsAccess: Bool
    let hasCalendarsAccess: Bool
    let hasFullDiskAccess: Bool
    let hasUserSelectedFilesAccess: Bool
    let hasDownloadsFolderAccess: Bool
    let hasOutgoingNetworkAccess: Bool
    let hasIncomingNetworkServerAccess: Bool
    let badges: [EntitlementBadge]
    let totalEntitlementsCount: Int

    var securitySummary: String {
        if isSandboxed {
            return "App Sandbox Enforced"
        } else if isHardenedRuntime && !disablesLibraryValidation {
            return "Hardened Runtime Validated"
        } else if disablesLibraryValidation || allowsUnsignedExecutableMemory {
            return "Relaxed Security Flags"
        } else {
            return "Standard macOS Application"
        }
    }
}

@MainActor
final class CaskEntitlementsAuditor: ObservableObject {
    static let shared = CaskEntitlementsAuditor()

    @Published var reportsByPackageID: [String: CaskEntitlementsReport] = [:]
    @Published var isAuditing = false

    /// Audits an installed Cask application bundle and caches the parsed report.
    @discardableResult
    func audit(package: BrewStorePackage) async -> CaskEntitlementsReport? {
        guard package.kind == .cask else { return nil }

        var appPath: String?
        for name in package.applicationNames {
            let path = "/Applications/\(name).app"
            if FileManager.default.fileExists(atPath: path) {
                appPath = path
                break
            }
        }
        if appPath == nil {
            let fallback = "/Applications/\(package.name).app"
            if FileManager.default.fileExists(atPath: fallback) {
                appPath = fallback
            }
        }

        guard let validPath = appPath else { return nil }

        isAuditing = true
        defer { isAuditing = false }

        let report = await Task.detached(priority: .userInitiated) { () -> CaskEntitlementsReport in
            let result = BrewStoreCommandExecutor.shared.run(
                executablePath: "/usr/bin/codesign",
                arguments: ["-d", "--entitlements", "-", "--xml", validPath],
                timeout: 10,
                category: .readOnly
            )

            let output = result.standardOutput.isEmpty ? result.standardError : result.standardOutput
            let entitlements = Self.parseEntitlementsPlist(from: output)

            // Also check hardened runtime from codesign -dv
            let verboseResult = BrewStoreCommandExecutor.shared.run(
                executablePath: "/usr/bin/codesign",
                arguments: ["-dv", "--verbose=2", validPath],
                timeout: 10,
                category: .readOnly
            )
            let verboseOutput = verboseResult.standardError + "\n" + verboseResult.standardOutput
            let isHardened = verboseOutput.contains("runtime") || verboseOutput.contains("flags=0x10000(runtime)")

            return Self.generateReport(
                packageID: package.id,
                applicationPath: validPath,
                entitlements: entitlements,
                isHardenedRuntime: isHardened
            )
        }.value

        reportsByPackageID[package.id] = report
        return report
    }

    /// Parses the XML plist output from `codesign -d --entitlements - --xml` into a dictionary.
    nonisolated static func parseEntitlementsPlist(from text: String) -> [String: Any] {
        guard let plistStartIndex = text.range(of: "<plist")?.lowerBound,
              let plistEndIndex = text.range(of: "</plist>")?.upperBound else {
            return [:]
        }

        let xmlSubstring = String(text[plistStartIndex..<plistEndIndex])
        guard let data = xmlSubstring.data(using: .utf8) else { return [:] }

        do {
            var format = PropertyListSerialization.PropertyListFormat.xml
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            return (plist as? [String: Any]) ?? [:]
        } catch {
            return [:]
        }
    }

    /// Generates structured badges and security metadata from entitlements dictionary.
    nonisolated static func generateReport(
        packageID: String,
        applicationPath: String,
        entitlements: [String: Any],
        isHardenedRuntime: Bool = false
    ) -> CaskEntitlementsReport {
        func hasFlag(_ key: String) -> Bool {
            if let boolVal = entitlements[key] as? Bool {
                return boolVal
            }
            if let intVal = entitlements[key] as? Int {
                return intVal != 0
            }
            return entitlements[key] != nil
        }

        let isSandboxed = hasFlag("com.apple.security.app-sandbox")
        let allowsJIT = hasFlag("com.apple.security.cs.allow-jit")
        let allowsUnsignedMemory = hasFlag("com.apple.security.cs.allow-unsigned-executable-memory")
        let disablesLibraryVal = hasFlag("com.apple.security.cs.disable-library-validation")
        let hasCamera = hasFlag("com.apple.security.device.camera")
        let hasMic = hasFlag("com.apple.security.device.microphone") || hasFlag("com.apple.security.device.audio-input")
        let hasBluetooth = hasFlag("com.apple.security.device.bluetooth")
        let hasUSB = hasFlag("com.apple.security.device.usb")
        let hasLocation = hasFlag("com.apple.security.personal-information.location")
        let hasContacts = hasFlag("com.apple.security.personal-information.addressbook")
        let hasCalendars = hasFlag("com.apple.security.personal-information.calendars")
        let hasFullDisk = hasFlag("com.apple.security.files.all")
        let hasUserFiles = hasFlag("com.apple.security.files.user-selected.read-write") || hasFlag("com.apple.security.files.user-selected.read-only")
        let hasDownloads = hasFlag("com.apple.security.files.downloads.read-write")
        let hasNetClient = hasFlag("com.apple.security.network.client")
        let hasNetServer = hasFlag("com.apple.security.network.server")

        var badges: [EntitlementBadge] = []

        if isSandboxed {
            badges.append(EntitlementBadge(
                id: "sandbox",
                title: "App Sandbox",
                systemImage: "shippingbox.fill",
                colorName: "green",
                category: .sandbox,
                description: "Restricted to isolated container sandbox"
            ))
        }

        if isHardenedRuntime {
            badges.append(EntitlementBadge(
                id: "hardened_runtime",
                title: "Hardened Runtime",
                systemImage: "shield.checkered",
                colorName: "blue",
                category: .runtime,
                description: "Protected by Apple hardened runtime integrity checks"
            ))
        }

        if hasCamera {
            badges.append(EntitlementBadge(
                id: "camera",
                title: "Camera Access",
                systemImage: "camera.fill",
                colorName: "orange",
                category: .privacy,
                description: "Can capture video or photos via connected cameras"
            ))
        }

        if hasMic {
            badges.append(EntitlementBadge(
                id: "microphone",
                title: "Microphone Access",
                systemImage: "mic.fill",
                colorName: "orange",
                category: .privacy,
                description: "Can capture audio via connected microphones"
            ))
        }

        if hasLocation {
            badges.append(EntitlementBadge(
                id: "location",
                title: "Location Access",
                systemImage: "location.fill",
                colorName: "purple",
                category: .privacy,
                description: "Can access device geographic coordinates"
            ))
        }

        if hasFullDisk {
            badges.append(EntitlementBadge(
                id: "full_disk",
                title: "Full Disk Access",
                systemImage: "externaldrive.fill",
                colorName: "orange",
                category: .filesystem,
                description: "Can access protected files and user data across the system"
            ))
        }

        if hasNetServer {
            badges.append(EntitlementBadge(
                id: "network_server",
                title: "Inbound Network Server",
                systemImage: "network",
                colorName: "yellow",
                category: .network,
                description: "Listens for incoming network connections and host services"
            ))
        }

        if hasNetClient {
            badges.append(EntitlementBadge(
                id: "network_client",
                title: "Outbound Network",
                systemImage: "arrow.up.right.circle.fill",
                colorName: "blue",
                category: .network,
                description: "Connects to remote servers and the Internet"
            ))
        }

        if allowsJIT {
            badges.append(EntitlementBadge(
                id: "allow_jit",
                title: "JIT Execution",
                systemImage: "bolt.fill",
                colorName: "yellow",
                category: .runtime,
                description: "Employs Just-In-Time compiled code"
            ))
        }

        if allowsUnsignedMemory {
            badges.append(EntitlementBadge(
                id: "unsigned_memory",
                title: "Unsigned Executable Memory",
                systemImage: "exclamationmark.triangle.fill",
                colorName: "orange",
                category: .runtime,
                description: "Can allocate executable memory without code signatures"
            ))
        }

        if disablesLibraryVal {
            badges.append(EntitlementBadge(
                id: "disabled_lib_validation",
                title: "Library Validation Disabled",
                systemImage: "puzzlepiece.extension.fill",
                colorName: "orange",
                category: .runtime,
                description: "Can load third-party plug-ins and unsigned dynamic libraries"
            ))
        }

        return CaskEntitlementsReport(
            id: packageID,
            applicationPath: applicationPath,
            isSandboxed: isSandboxed,
            isHardenedRuntime: isHardenedRuntime,
            allowsJIT: allowsJIT,
            allowsUnsignedExecutableMemory: allowsUnsignedMemory,
            disablesLibraryValidation: disablesLibraryVal,
            hasCameraAccess: hasCamera,
            hasMicrophoneAccess: hasMic,
            hasBluetoothAccess: hasBluetooth,
            hasUSBAccess: hasUSB,
            hasLocationAccess: hasLocation,
            hasContactsAccess: hasContacts,
            hasCalendarsAccess: hasCalendars,
            hasFullDiskAccess: hasFullDisk,
            hasUserSelectedFilesAccess: hasUserFiles,
            hasDownloadsFolderAccess: hasDownloads,
            hasOutgoingNetworkAccess: hasNetClient,
            hasIncomingNetworkServerAccess: hasNetServer,
            badges: badges,
            totalEntitlementsCount: entitlements.count
        )
    }
}
