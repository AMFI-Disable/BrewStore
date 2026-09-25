import XCTest
@testable import BrewStore

@MainActor
final class ServiceCrashDiagnosticianTests: XCTestCase {

    var tempDir: URL!
    var diagnostician: ServiceCrashDiagnostician!

    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BrewStoreCrashTests_\(uniqueID)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        diagnostician = ServiceCrashDiagnostician(commandExecutor: .shared)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testStalePIDLockDetectionViaLogText() async {
        let service = BrewStoreService(
            id: "postgresql",
            name: "postgresql",
            status: "error 256",
            user: "even",
            file: nil
        )

        let logLines = [
            "2026-09-25 09:00:00.123 UTC [1000] LOG: starting PostgreSQL 16.2",
            "2026-09-25 09:00:00.124 UTC [1000] FATAL: lock file \"postmaster.pid\" already exists",
            "2026-09-25 09:00:00.125 UTC [1000] HINT: Is another postmaster (PID 54321) running in data directory?"
        ]

        let diagnosis = await diagnostician.analyzeServiceState(
            service: service,
            logLines: logLines,
            logFilePath: nil,
            prefix: tempDir.path
        )

        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.issueType, .stalePIDLock)
        XCTAssertEqual(diagnosis?.serviceName, "postgresql")
        XCTAssertTrue(diagnosis?.headline.contains("Stale PID") ?? false)
    }

    func testStalePIDLockDetectionViaFileSystem() async throws {
        let service = BrewStoreService(
            id: "postgresql@15",
            name: "postgresql@15",
            status: "error",
            user: "even",
            file: nil
        )

        // Create var/postgresql@15/postmaster.pid with dead PID
        let postgresVar = tempDir.appendingPathComponent("var/postgresql@15", isDirectory: true)
        try FileManager.default.createDirectory(at: postgresVar, withIntermediateDirectories: true)
        let pidFile = postgresVar.appendingPathComponent("postmaster.pid")
        try "99999\n/tmp\n".write(to: pidFile, atomically: true, encoding: .utf8)

        let diagnosis = await diagnostician.analyzeServiceState(
            service: service,
            logLines: [],
            logFilePath: nil,
            prefix: tempDir.path
        )

        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.issueType, .stalePIDLock)
        XCTAssertEqual(diagnosis?.affectedFilePath, pidFile.path)
        XCTAssertEqual(diagnosis?.remediations.first?.isRecommended, true)
    }

    func testPortConflictDetection() async {
        let service = BrewStoreService(
            id: "redis",
            name: "redis",
            status: "error",
            user: "even",
            file: nil
        )

        let logLines = [
            "1234:M 25 Sep 2026 09:10:00.000 * Running mode=standalone, port=6379.",
            "1234:M 25 Sep 2026 09:10:00.001 # Could not create server TCP listening socket *:6379: bind: Address already in use"
        ]

        let diagnosis = await diagnostician.analyzeServiceState(
            service: service,
            logLines: logLines,
            logFilePath: nil,
            prefix: tempDir.path
        )

        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.issueType, .portConflict)
        XCTAssertEqual(diagnosis?.affectedPort, 6379)
        XCTAssertTrue(diagnosis?.headline.contains("Conflict") ?? false)
    }

    func testPermissionDeniedDetection() async {
        let service = BrewStoreService(
            id: "nginx",
            name: "nginx",
            status: "error 1",
            user: "even",
            file: nil
        )

        let logLines = [
            "nginx: [alert] could not open error log file: open() \"/opt/homebrew/var/log/nginx/error.log\" failed (13: Permission denied)"
        ]

        let diagnosis = await diagnostician.analyzeServiceState(
            service: service,
            logLines: logLines,
            logFilePath: "/opt/homebrew/var/log/nginx/error.log",
            prefix: tempDir.path
        )

        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.issueType, .permissionDenied)
        XCTAssertEqual(diagnosis?.affectedFilePath, "/opt/homebrew/var/log/nginx/error.log")
        let rec = diagnosis?.remediations.first
        XCTAssertNotNil(rec)
        if case let .fixDirectoryPermissions(path) = rec?.actionType {
            XCTAssertEqual(path, "/opt/homebrew/var/log/nginx/error.log")
        } else {
            XCTFail("Expected .fixDirectoryPermissions action")
        }
    }

    func testConfigurationSyntaxErrorDetection() async {
        let service = BrewStoreService(
            id: "nginx",
            name: "nginx",
            status: "error 1",
            user: "even",
            file: nil
        )

        let logLines = [
            "nginx: [emerg] unknown directive \"invalid_rule\" in /opt/homebrew/etc/nginx/nginx.conf:42",
            "nginx: configuration file /opt/homebrew/etc/nginx/nginx.conf test failed"
        ]

        let diagnosis = await diagnostician.analyzeServiceState(
            service: service,
            logLines: logLines,
            logFilePath: nil,
            prefix: tempDir.path
        )

        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.issueType, .configurationSyntaxError)
        let rec = diagnosis?.remediations.first
        XCTAssertNotNil(rec)
        if case let .openFileInEditor(path, line) = rec?.actionType {
            XCTAssertTrue(path.contains("nginx.conf"))
            XCTAssertEqual(line, 42)
        } else {
            XCTFail("Expected .openFileInEditor action")
        }
    }

    func testUninitializedDataDirectoryDetection() async {
        let service = BrewStoreService(
            id: "postgresql",
            name: "postgresql",
            status: "error",
            user: "even",
            file: nil
        )

        let logLines = [
            "postgres: database cluster has not been initialized",
            "Please run \"initdb\" or create a cluster before starting the server."
        ]

        let diagnosis = await diagnostician.analyzeServiceState(
            service: service,
            logLines: logLines,
            logFilePath: nil,
            prefix: tempDir.path
        )

        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.issueType, .uninitializedDataDirectory)
        XCTAssertTrue(diagnosis?.headline.contains("Uninitialized") ?? false)
    }

    func testExecuteStalePIDRemediationFileDeletion() async throws {
        let fm = FileManager.default
        let testPID = tempDir.appendingPathComponent("postmaster.pid")
        try "1234\n".write(to: testPID, atomically: true, encoding: .utf8)
        XCTAssertTrue(fm.fileExists(atPath: testPID.path))

        let service = BrewStoreService(
            id: "postgresql",
            name: "postgresql",
            status: "error",
            user: "even",
            file: nil
        )

        let action = ServiceCrashRemediationAction(
            title: "Clear Stale PID",
            subtitle: "Delete test file",
            actionType: .deleteFile(path: testPID.path)
        )

        let manager = HomebrewManager()
        try await diagnostician.executeRemediation(action, for: service, manager: manager)

        XCTAssertFalse(fm.fileExists(atPath: testPID.path), "PID lock file should have been deleted by remediation")
    }
}
