import Foundation
import SwiftUI

enum VulnerabilitySeverity: String, CaseIterable, Identifiable, Codable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String {
        rawValue
    }

    var color: Color {
        switch self {
        case .critical: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        }
    }

    var symbol: String {
        switch self {
        case .critical: "exclamationmark.triangle.fill"
        case .high: "exclamationmark.shield.fill"
        case .medium: "shield.lefthalf.filled"
        case .low: "info.circle.fill"
        }
    }
}

struct CVEAdvisory: Identifiable, Hashable, Codable {
    let id: String
    let packageID: String
    let title: String
    let severity: VulnerabilitySeverity
    let affectedRange: String
    let fixedVersion: String
    let advisoryURL: String
}

@MainActor
final class BrewStoreCVEScanningManager: ObservableObject {
    static let shared = BrewStoreCVEScanningManager()

    @Published var activeAdvisories: [CVEAdvisory] = []
    @Published var isScanning = false
    @Published var lastScanDate: Date?

    /// Curated high-impact Homebrew vulnerability database
    nonisolated static let knownAdvisories: [CVEAdvisory] = [
        CVEAdvisory(
            id: "CVE-2024-3094",
            packageID: "xz",
            title: "Malicious upstream backdoor found in liblzma / xz-utils 5.6.0/5.6.1",
            severity: .critical,
            affectedRange: "5.6.0 - 5.6.1",
            fixedVersion: "5.6.2",
            advisoryURL: "https://nvd.nist.gov/vuln/detail/CVE-2024-3094"
        ),
        CVEAdvisory(
            id: "CVE-2024-32002",
            packageID: "git",
            title: "Remote Code Execution via recursive submodules on case-insensitive filesystems",
            severity: .critical,
            affectedRange: "< 2.45.1",
            fixedVersion: "2.45.1",
            advisoryURL: "https://nvd.nist.gov/vuln/detail/CVE-2024-32002"
        ),
        CVEAdvisory(
            id: "CVE-2023-38545",
            packageID: "curl",
            title: "Heap buffer overflow in SOCKS5 proxy handshake resolution",
            severity: .high,
            affectedRange: "7.69.0 - 8.3.0",
            fixedVersion: "8.4.0",
            advisoryURL: "https://curl.se/docs/CVE-2023-38545.html"
        ),
        CVEAdvisory(
            id: "GHSA-openssl-1-1-eol",
            packageID: "openssl@1.1",
            title: "OpenSSL 1.1.1 has reached Official End of Life (EOL) with no further security fixes",
            severity: .high,
            affectedRange: "1.1.1*",
            fixedVersion: "Upgrade to openssl@3",
            advisoryURL: "https://www.openssl.org/blog/blog/2023/09/11/eol-111/"
        ),
        CVEAdvisory(
            id: "CVE-2024-27351",
            packageID: "go",
            title: "Direct CPU infinite loop denial of service in net/http chunked transfer parser",
            severity: .medium,
            affectedRange: "< 1.22.1",
            fixedVersion: "1.22.1",
            advisoryURL: "https://nvd.nist.gov/vuln/detail/CVE-2024-27351"
        )
    ]

    func scanInstalledPackages(manager: HomebrewManager) {
        isScanning = true
        let installedPackages = manager.packages.filter(\.isInstalled)

        var detected: [CVEAdvisory] = []
        for pkg in installedPackages {
            let matches = Self.advisories(for: pkg)
            detected.append(contentsOf: matches)
        }

        self.activeAdvisories = detected
        self.lastScanDate = Date()
        self.isScanning = false
    }

    nonisolated static func isPackageVulnerable(package: BrewStorePackage, advisory: CVEAdvisory) -> Bool {
        guard advisory.packageID.lowercased() == package.id.lowercased() else { return false }

        // EOL packages like openssl@1.1 have reached end of life with no upstream fix on the 1.1 line
        if advisory.id == "GHSA-openssl-1-1-eol" || advisory.fixedVersion.lowercased().contains("upgrade to") {
            return true
        }

        let currentVer = package.installedVersion ?? package.version
        guard !currentVer.isEmpty else { return true }

        return BrewStoreAppUpdateChecker.isNewerVersion(remote: advisory.fixedVersion, local: currentVer)
    }

    nonisolated static func advisories(for package: BrewStorePackage) -> [CVEAdvisory] {
        knownAdvisories.filter { adv in
            isPackageVulnerable(package: package, advisory: adv)
        }
    }
}
