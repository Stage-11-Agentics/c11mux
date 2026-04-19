import XCTest
@testable import cmux

@MainActor
final class ThemeManagerLifecycleTests: XCTestCase {
    func testManagerLoadsActiveThemeAndIncrementsVersionOnReload() {
        let center = NotificationCenter()
        let manager = ThemeManager(notificationCenter: center)

        XCTAssertFalse(manager.active.identity.name.isEmpty)

        let initialVersion = manager.version
        manager.reloadFromBundle(named: "stage11")
        XCTAssertGreaterThan(manager.version, initialVersion)
    }

    func testGhosttyBackgroundNotificationBumpsGenerationAndVersion() {
        let center = NotificationCenter()
        let manager = ThemeManager(notificationCenter: center)

        let initialGeneration = manager.ghosttyBackgroundGeneration
        let initialVersion = manager.version

        center.post(name: .ghosttyDefaultBackgroundDidChange, object: nil)

        XCTAssertEqual(manager.ghosttyBackgroundGeneration, initialGeneration + 1)
        XCTAssertGreaterThan(manager.version, initialVersion)
    }
}
