import XCTest
import AppKit

#if canImport(c11_DEV)
@testable import c11_DEV
#elseif canImport(c11)
@testable import c11
#endif

/// CMUX-10: persistent-flash registration + cancel + sidebar fan-out.
@MainActor
final class WorkspaceFlashTests: XCTestCase {
    /// A short pulse duration so persistent timers can't fire mid-test if the
    /// run is slower than expected. The tests don't assert on the timer
    /// firing — they assert on the registration/cancel state machine.
    private let pinnedMs: Int = 600

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(pinnedMs, forKey: NotificationFlashDurationSettings.enabledKey)
        UserDefaults.standard.set(true, forKey: NotificationPaneFlashSettings.enabledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: NotificationFlashDurationSettings.enabledKey)
        UserDefaults.standard.removeObject(forKey: NotificationPaneFlashSettings.enabledKey)
        super.tearDown()
    }

    func testOneShotFlashFansOutToSidebarTokenWithoutRegisteringPersistentState() {
        let workspace = Workspace(title: "flash-test")
        let panelId = UUID()
        let initialToken = workspace.sidebarFlashToken

        workspace.triggerFocusFlash(
            panelId: panelId,
            appearance: FlashAppearance.current(envelope: .paneRing)
        )

        XCTAssertEqual(workspace.sidebarFlashToken, initialToken &+ 1)
        XCTAssertNil(workspace.persistentFlashPanels[panelId])
    }

    func testPersistentFlashRegistersStateAndKeepsRegistrationUntilCancel() {
        let workspace = Workspace(title: "flash-test")
        let panelId = UUID()

        workspace.triggerFocusFlash(
            panelId: panelId,
            appearance: FlashAppearance.current(envelope: .paneRing),
            persistent: true
        )

        let registered = workspace.persistentFlashPanels[panelId]
        XCTAssertNotNil(registered, "Persistent flash should register state on the workspace")

        workspace.cancelPersistentFlash(panelId: panelId)
        XCTAssertNil(workspace.persistentFlashPanels[panelId])
    }

    func testCancelAllPersistentFlashesClearsEveryRegistration() {
        let workspace = Workspace(title: "flash-test")
        let panelA = UUID()
        let panelB = UUID()

        workspace.triggerFocusFlash(
            panelId: panelA,
            appearance: FlashAppearance.current(envelope: .paneRing),
            persistent: true
        )
        workspace.triggerFocusFlash(
            panelId: panelB,
            appearance: FlashAppearance(color: .red, envelope: .paneRing),
            persistent: true
        )
        XCTAssertEqual(workspace.persistentFlashPanels.count, 2)

        workspace.cancelAllPersistentFlashes()
        XCTAssertTrue(workspace.persistentFlashPanels.isEmpty)
    }

    func testCancelOnUnregisteredPanelIsIdempotent() {
        let workspace = Workspace(title: "flash-test")
        let panelId = UUID()
        // No prior persistent flash; cancel should not crash or alter state.
        workspace.cancelPersistentFlash(panelId: panelId)
        XCTAssertTrue(workspace.persistentFlashPanels.isEmpty)
    }

    func testRetriggerPersistentReplacesExistingTimerWithoutLeaking() {
        let workspace = Workspace(title: "flash-test")
        let panelId = UUID()

        workspace.triggerFocusFlash(
            panelId: panelId,
            appearance: FlashAppearance.current(envelope: .paneRing),
            persistent: true
        )
        let firstTimer = workspace.persistentFlashPanels[panelId]?.timer

        workspace.triggerFocusFlash(
            panelId: panelId,
            appearance: FlashAppearance(color: .blue, envelope: .paneRing),
            persistent: true
        )
        let secondTimer = workspace.persistentFlashPanels[panelId]?.timer

        XCTAssertNotNil(firstTimer)
        XCTAssertNotNil(secondTimer)
        XCTAssertFalse(firstTimer === secondTimer, "Re-trigger should replace the timer instance")

        workspace.cancelPersistentFlash(panelId: panelId)
    }

    func testPaneFlashDisabledGuardSilencesAllChannels() {
        UserDefaults.standard.set(false, forKey: NotificationPaneFlashSettings.enabledKey)
        defer { UserDefaults.standard.set(true, forKey: NotificationPaneFlashSettings.enabledKey) }

        let workspace = Workspace(title: "flash-test")
        let panelId = UUID()
        let initialToken = workspace.sidebarFlashToken

        workspace.triggerFocusFlash(
            panelId: panelId,
            appearance: FlashAppearance.current(envelope: .paneRing),
            persistent: true
        )

        XCTAssertEqual(workspace.sidebarFlashToken, initialToken)
        XCTAssertNil(workspace.persistentFlashPanels[panelId])
    }
}
