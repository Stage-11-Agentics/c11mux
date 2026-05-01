import XCTest

#if canImport(c11_DEV)
@testable import c11_DEV
#elseif canImport(c11)
@testable import c11
#endif

/// Pure tests for `ShutdownSentinel`. Per `CLAUDE.md`, never run locally —
/// CI only.
final class ShutdownSentinelTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShutdownSentinelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testMissingSentinelReturnsMissing() {
        let prior = ShutdownSentinel.readPriorShutdown(bundleId: "com.test", directory: tempDir)
        XCTAssertEqual(prior, .missing)
    }

    func testWriteDirtyThenReadReturnsDirtyWithLaunchTime() {
        let when = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(ShutdownSentinel.writeDirty(bundleId: "com.test", at: when, directory: tempDir))
        let prior = ShutdownSentinel.readPriorShutdown(bundleId: "com.test", directory: tempDir)
        switch prior {
        case .dirty(let at):
            XCTAssertEqual(at?.timeIntervalSince1970, 1000)
        default:
            XCTFail("expected .dirty, got \(prior)")
        }
    }

    func testPromoteToCleanRemovesDirtyAndPersistsCleanTimestamp() {
        XCTAssertTrue(ShutdownSentinel.writeDirty(bundleId: "com.test", at: Date(timeIntervalSince1970: 1000), directory: tempDir))
        XCTAssertTrue(ShutdownSentinel.promoteToClean(bundleId: "com.test", at: Date(timeIntervalSince1970: 2000), directory: tempDir))
        let prior = ShutdownSentinel.readPriorShutdown(bundleId: "com.test", directory: tempDir)
        switch prior {
        case .clean(let at):
            XCTAssertEqual(at.timeIntervalSince1970, 2000)
        default:
            XCTFail("expected .clean, got \(prior)")
        }
        // Dirty file should be gone.
        let dirtyURL = ShutdownSentinel.dirtyURL(bundleId: "com.test", directory: tempDir)!
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirtyURL.path))
    }

    func testWriteDirtyOverwritesPreviousCleanSentinel() {
        XCTAssertTrue(ShutdownSentinel.writeDirty(bundleId: "com.test", at: Date(timeIntervalSince1970: 1000), directory: tempDir))
        XCTAssertTrue(ShutdownSentinel.promoteToClean(bundleId: "com.test", at: Date(timeIntervalSince1970: 2000), directory: tempDir))
        // New launch: writeDirty should remove the prior clean marker so
        // a subsequent crash before promote classifies as dirty (this run).
        XCTAssertTrue(ShutdownSentinel.writeDirty(bundleId: "com.test", at: Date(timeIntervalSince1970: 3000), directory: tempDir))
        let prior = ShutdownSentinel.readPriorShutdown(bundleId: "com.test", directory: tempDir)
        switch prior {
        case .dirty(let at):
            XCTAssertEqual(at?.timeIntervalSince1970, 3000)
        default:
            XCTFail("expected .dirty after re-write, got \(prior)")
        }
    }

    func testBundleScopingPreventsCrossContamination() {
        XCTAssertTrue(ShutdownSentinel.writeDirty(bundleId: "com.stage11.c11", directory: tempDir))
        XCTAssertTrue(ShutdownSentinel.promoteToClean(bundleId: "com.stage11.c11", directory: tempDir))
        // A different bundle id (e.g. debug build) should still classify
        // as missing — it has its own pair of sentinels.
        let other = ShutdownSentinel.readPriorShutdown(bundleId: "com.stage11.c11.dev", directory: tempDir)
        XCTAssertEqual(other, .missing)
    }

    func testBundleIdSanitisedAgainstPathTraversal() {
        // Path-shape characters are stripped/replaced so a malicious
        // bundle id cannot escape the runtime dir.
        XCTAssertTrue(ShutdownSentinel.writeDirty(
            bundleId: "../../etc/passwd",
            directory: tempDir
        ))
        // Sanitised file name doesn't contain ../
        let url = ShutdownSentinel.dirtyURL(bundleId: "../../etc/passwd", directory: tempDir)!
        XCTAssertFalse(url.path.contains(".."), "bundle id must be sanitised: \(url.path)")
    }
}
