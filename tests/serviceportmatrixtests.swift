import XCTest
@testable import BrewStore

final class ServicePortMatrixTests: XCTestCase {

    func testDefaultPortMappings() {
        let mapping = ServicePortMatrixManager.defaultPortMapping
        XCTAssertEqual(mapping[5432]?.contains("postgresql"), true)
        XCTAssertEqual(mapping[6379]?.contains("redis"), true)
        XCTAssertEqual(mapping[3306]?.contains("mysql"), true)
        XCTAssertEqual(mapping[8080]?.contains("nginx"), true)
    }

    func testParseLsofOutput() {
        let sampleLsof = """
        COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        postgres  12345 even   11u  IPv4 0x123      0t0  TCP 127.0.0.1:5432 (LISTEN)
        redis-ser 54200 even    6u  IPv4 0x456      0t0  TCP 127.0.0.1:6379 (LISTEN)
        nginx      8800 even    7u  IPv4 0x789      0t0  TCP *:8080 (LISTEN)
        """

        let entries = ServicePortMatrixManager.parseLsofOutput(sampleLsof, services: [])
        XCTAssertEqual(entries.count, 3)

        XCTAssertEqual(entries[0].port, 5432)
        XCTAssertEqual(entries[0].processName, "postgres")
        XCTAssertEqual(entries[0].pid, 12345)
        XCTAssertEqual(entries[0].associatedHomebrewService, "postgresql")

        XCTAssertEqual(entries[1].port, 6379)
        XCTAssertEqual(entries[1].processName, "redis-ser")

        XCTAssertEqual(entries[2].port, 8080)
        XCTAssertEqual(entries[2].displayAddress, "All Interfaces (0.0.0.0)")
    }

    func testConflictDetectionWhenStoppedServicePortOccupied() {
        let sampleLsof = """
        COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        rogue-app  9999 even   11u  IPv4 0xabc      0t0  TCP 127.0.0.1:5432 (LISTEN)
        """

        let stoppedPostgres = BrewStoreService(
            id: "postgresql",
            name: "postgresql",
            status: "stopped",
            user: "even",
            file: "/opt/homebrew/opt/postgresql/homebrew.mxcl.postgresql.plist"
        )

        let entries = ServicePortMatrixManager.parseLsofOutput(sampleLsof, services: [stoppedPostgres])
        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertTrue(entry.hasConflict)
        XCTAssertNotNil(entry.conflictDescription)
        XCTAssertTrue(entry.conflictDescription?.contains("preventing Homebrew 'postgresql' from starting") ?? false)
    }

    func testDeduplicationForDualStackListening() {
        let sampleLsof = """
        COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        redis-ser 54200 even    6u  IPv4 0x456      0t0  TCP 127.0.0.1:6379 (LISTEN)
        redis-ser 54200 even    7u  IPv6 0x789      0t0  TCP [::1]:6379 (LISTEN)
        """

        let entries = ServicePortMatrixManager.parseLsofOutput(sampleLsof, services: [])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].port, 6379)
        XCTAssertEqual(entries[0].pid, 54200)
    }
}
