import XCTest

#if canImport(c11_DEV)
@testable import c11_DEV
#elseif canImport(c11)
@testable import c11
#endif

final class HealthIPSParserTests: XCTestCase {

    private var fixturesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("health")
            .appendingPathComponent("ips", isDirectory: true)
    }

    func testParsesCrashFirstLine() throws {
        let url = fixturesURL.appendingPathComponent("sample-crash.ips")
        let body = try String(contentsOf: url, encoding: .utf8)
        guard let firstLine = body.split(separator: "\n").first else {
            XCTFail("fixture has no first line")
            return
        }
        let header = try XCTUnwrap(parseIPSFirstLine(String(firstLine)))
        XCTAssertEqual(header.bundleID, "com.stage11.c11")
        XCTAssertEqual(header.bugType, "309")
        XCTAssertEqual(header.incidentID, "00000000-0000-0000-0000-000000000001")
    }

    func testParsesHangFirstLine() throws {
        let url = fixturesURL.appendingPathComponent("sample-hang.ips")
        let body = try String(contentsOf: url, encoding: .utf8)
        guard let firstLine = body.split(separator: "\n").first else {
            XCTFail("fixture has no first line")
            return
        }
        let header = try XCTUnwrap(parseIPSFirstLine(String(firstLine)))
        XCTAssertEqual(header.bundleID, "com.stage11.c11")
        XCTAssertEqual(header.incidentID, "00000000-0000-0000-0000-000000000002")
    }

    func testRejectsMalformedFirstLine() {
        XCTAssertNil(parseIPSFirstLine(""))
        XCTAssertNil(parseIPSFirstLine("not json"))
        XCTAssertNil(parseIPSFirstLine("[\"array\"]"))
    }

    func testScanIPSPicksUpTopLevelC11File() throws {
        let tmp = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let reportsDir = tmp.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

        let crashFixture = try Data(contentsOf: fixturesURL.appendingPathComponent("sample-crash.ips"))
        let target = reportsDir.appendingPathComponent("c11-2026-05-03-151900.ips")
        try crashFixture.write(to: target)

        let events = scanIPS(home: tmp.path, since: Date.distantPast)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.rail, .ips)
        XCTAssertEqual(events.first?.severity, .crash)
        XCTAssertTrue(events.first?.summary.contains("com.stage11.c11") == true)
    }

    func testScanIPSPicksUpPerBundleSubdirFile() throws {
        let tmp = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let bundleDir = tmp.appendingPathComponent(
            "Library/Logs/DiagnosticReports/com.stage11.c11.debug.foo",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        let crashFixture = try Data(contentsOf: fixturesURL.appendingPathComponent("sample-crash.ips"))
        let target = bundleDir.appendingPathComponent("Crash-2026-05-03-151900.ips")
        try crashFixture.write(to: target)

        let events = scanIPS(home: tmp.path, since: Date.distantPast)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.rail, .ips)
    }

    func testScanIPSSkipsTopLevelNonC11File() throws {
        let tmp = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let reportsDir = tmp.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

        let crashFixture = try Data(contentsOf: fixturesURL.appendingPathComponent("sample-crash.ips"))
        let unrelated = reportsDir.appendingPathComponent("Safari-2026-05-03-151900.ips")
        try crashFixture.write(to: unrelated)

        let events = scanIPS(home: tmp.path, since: Date.distantPast)
        XCTAssertTrue(events.isEmpty, "non-c11 IPS files at top level must be ignored")
    }

    func testScanIPSRespectsSinceWindow() throws {
        let tmp = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let reportsDir = tmp.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

        let crashFixture = try Data(contentsOf: fixturesURL.appendingPathComponent("sample-crash.ips"))
        let target = reportsDir.appendingPathComponent("c11-2026-05-03-151900.ips")
        try crashFixture.write(to: target)

        // Backdate the file to one hour ago.
        let oneHourAgo = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes(
            [.modificationDate: oneHourAgo],
            ofItemAtPath: target.path
        )

        let recent = scanIPS(home: tmp.path, since: Date(timeIntervalSinceNow: -60))
        XCTAssertTrue(recent.isEmpty, "files older than the since-window must be filtered out")

        let wide = scanIPS(home: tmp.path, since: Date(timeIntervalSinceNow: -7200))
        XCTAssertEqual(wide.count, 1)
    }

    func testScanIPSGracefulOnMissingDirectory() {
        let events = scanIPS(home: "/nonexistent/path-that-cannot-exist-1234", since: Date.distantPast)
        XCTAssertTrue(events.isEmpty)
    }

    private func makeTempHome() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("c11-health-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
