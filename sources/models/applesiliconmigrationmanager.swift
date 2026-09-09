import AppKit
import Foundation

struct MigrationCandidate: Identifiable, Hashable {
    var id: String {
        package.id
    }

    let package: BrewStorePackage
    let architecture: BinaryArchitectureType
    let binaryPath: String?
    let needsMigration: Bool
}

struct AppleSiliconMigrationReport: Hashable {
    let isAppleSiliconHost: Bool
    let totalChecked: Int
    let nativeArm64Count: Int
    let universalCount: Int
    let rosettaIntelCount: Int
    let candidates: [MigrationCandidate]

    var migrationRequiredCandidates: [MigrationCandidate] {
        candidates.filter(\.needsMigration)
    }

    var isFullyOptimized: Bool {
        rosettaIntelCount == 0
    }
}

@MainActor
final class BrewStoreAppleSiliconMigrationManager: ObservableObject {
    static let shared = BrewStoreAppleSiliconMigrationManager()

    @Published var report: AppleSiliconMigrationReport?
    @Published var isScanning = false
    @Published var isMigrating = false
    @Published var migrationStatusMessage: String?
    @Published var architectureMap: [String: BinaryArchitectureType] = [:]

    func architecture(for packageID: String) -> BinaryArchitectureType? {
        architectureMap[packageID]
    }

    func scanMigrationCandidates(manager: HomebrewManager) {
        isScanning = true

        let installedPackages = manager.packages.filter(\.isInstalled)

        Task.detached(priority: .userInitiated) {
            #if arch(arm64)
                let isAppleSilicon = true
            #else
                let isAppleSilicon = false
            #endif

            var candidates: [MigrationCandidate] = []
            var map: [String: BinaryArchitectureType] = [:]
            var armCount = 0
            var universalCount = 0
            var intelCount = 0

            for pkg in installedPackages {
                var arch = BinaryArchitectureType.unknown
                var targetPath: String?

                if pkg.kind == .formula {
                    if let cellar = pkg.cellarURL() {
                        let binURL = cellar.appendingPathComponent("bin")
                        if let files = try? FileManager.default.contentsOfDirectory(atPath: binURL.path) {
                            for file in files {
                                let execPath = binURL.appendingPathComponent(file).path
                                let detectedArch = BrewStoreSecurityInspector.inspectBinaryArchitecture(at: execPath)
                                if detectedArch != .unknown {
                                    targetPath = execPath
                                    arch = detectedArch
                                    if detectedArch == .appleSilicon || detectedArch == .universal2 {
                                        break
                                    }
                                }
                            }
                        }
                    }
                } else {
                    let candidatesPaths = [
                        "/Applications/\(pkg.name).app",
                        "/Applications/\(pkg.id).app",
                        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(pkg.name).app").path
                    ]
                    for path in candidatesPaths where FileManager.default.fileExists(atPath: path) {
                        targetPath = path
                        arch = BrewStoreSecurityInspector.inspectAppBundleArchitecture(at: path)
                        break
                    }
                }

                switch arch {
                case .appleSilicon:
                    armCount += 1
                case .universal2:
                    universalCount += 1
                case .intel:
                    intelCount += 1
                default:
                    break
                }

                map[pkg.id] = arch

                let needsMigration = isAppleSilicon && arch == .intel
                candidates.append(MigrationCandidate(
                    package: pkg,
                    architecture: arch,
                    binaryPath: targetPath,
                    needsMigration: needsMigration
                ))
            }

            let sorted = candidates.sorted { a, b in
                if a.needsMigration != b.needsMigration {
                    return a.needsMigration && !b.needsMigration
                }
                return a.package.name.localizedCaseInsensitiveCompare(b.package.name) == .orderedAscending
            }

            let result = AppleSiliconMigrationReport(
                isAppleSiliconHost: isAppleSilicon,
                totalChecked: installedPackages.count,
                nativeArm64Count: armCount,
                universalCount: universalCount,
                rosettaIntelCount: intelCount,
                candidates: sorted
            )

            let finalMap = map
            await MainActor.run { [weak self] in
                self?.architectureMap = finalMap
                self?.report = result
                self?.isScanning = false
            }
        }
    }

    func migrateCandidate(_ candidate: MigrationCandidate, manager: HomebrewManager) {
        isMigrating = true
        migrationStatusMessage = "Upgrading \(candidate.package.name) to native Apple Silicon…"
        manager.perform(package: candidate.package, action: .reinstall) { [weak self] _ in
            self?.isMigrating = false
            self?.migrationStatusMessage = nil
            self?.scanMigrationCandidates(manager: manager)
        }
    }

    func migrateAllRosettaPackages(manager: HomebrewManager) {
        guard let report else { return }
        let toMigrate = report.migrationRequiredCandidates.map(\.package)
        guard !toMigrate.isEmpty else { return }

        isMigrating = true
        migrationStatusMessage = "Migrating \(toMigrate.count) Rosetta apps to Apple Silicon…"
        manager.batchPerform(packages: toMigrate, action: .reinstall) { [weak self] _ in
            self?.isMigrating = false
            self?.migrationStatusMessage = nil
            self?.scanMigrationCandidates(manager: manager)
        }
    }
}
