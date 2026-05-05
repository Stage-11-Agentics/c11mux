import XCTest

#if canImport(c11_DEV)
@testable import c11_DEV
#elseif canImport(c11)
@testable import c11
#endif

/// Unit tests for the C11-25 lifecycle primitive — the transition
/// validator on `SurfaceLifecycleState`, the canonical metadata mirror
/// in `SurfaceMetadataStore`, and the controller's transition gating.
///
/// Per `CLAUDE.md`, never run locally — CI only.
final class SurfaceLifecycleTests: XCTestCase {

    // MARK: - Transition validator

    func testActiveCanTransitionToThrottledAndHibernated() {
        XCTAssertTrue(SurfaceLifecycleState.active.canTransition(to: .throttled))
        XCTAssertTrue(SurfaceLifecycleState.active.canTransition(to: .hibernated))
    }

    func testThrottledCanTransitionToActiveAndHibernated() {
        XCTAssertTrue(SurfaceLifecycleState.throttled.canTransition(to: .active))
        XCTAssertTrue(SurfaceLifecycleState.throttled.canTransition(to: .hibernated))
    }

    func testHibernatedCanResumeToActive() {
        XCTAssertTrue(SurfaceLifecycleState.hibernated.canTransition(to: .active))
    }

    func testHibernatedDoesNotAutoFlipToThrottled() {
        // Hibernated is operator-pinned. A workspace selection change
        // must not yank the surface back to throttled — the only legal
        // exit is to active (via "Resume Workspace").
        XCTAssertFalse(SurfaceLifecycleState.hibernated.canTransition(to: .throttled))
    }

    func testSuspendedIsReservedInC11_25() {
        // Defined in the enum so the metadata key has an upgrade path,
        // but no transitions are valid in C11-25 — guards against a
        // stale snapshot or a typo flipping a surface into a state the
        // dispatcher has no handler for.
        for from in SurfaceLifecycleState.allCases {
            if from == .suspended { continue }
            XCTAssertFalse(
                from.canTransition(to: .suspended),
                "expected \(from.rawValue) → suspended to be rejected"
            )
        }
        for to in SurfaceLifecycleState.allCases {
            if to == .suspended { continue }
            XCTAssertFalse(
                SurfaceLifecycleState.suspended.canTransition(to: to),
                "expected suspended → \(to.rawValue) to be rejected"
            )
        }
    }

    func testSelfTransitionsAreIdempotent() {
        for state in SurfaceLifecycleState.allCases {
            XCTAssertTrue(state.canTransition(to: state))
        }
    }

    func testIsOperatorPinnedOnlyHibernated() {
        XCTAssertFalse(SurfaceLifecycleState.active.isOperatorPinned)
        XCTAssertFalse(SurfaceLifecycleState.throttled.isOperatorPinned)
        XCTAssertFalse(SurfaceLifecycleState.suspended.isOperatorPinned)
        XCTAssertTrue(SurfaceLifecycleState.hibernated.isOperatorPinned)
    }

    // MARK: - Canonical metadata mirror

    func testStoreAcceptsValidLifecycleState() throws {
        let workspace = UUID()
        let surface = UUID()
        let store = SurfaceMetadataStore.shared
        defer { store.removeSurface(workspaceId: workspace, surfaceId: surface) }

        // C11-25 review fix I4: `.suspended` is reserved-only and rejected
        // at the validator. Walk only the runtime-acceptable set here.
        for state in SurfaceLifecycleState.allCases where state != .suspended {
            let result = try store.setMetadata(
                workspaceId: workspace,
                surfaceId: surface,
                partial: [MetadataKey.lifecycleState: state.rawValue],
                mode: .merge,
                source: .explicit
            )
            XCTAssertEqual(
                result.applied[MetadataKey.lifecycleState],
                true,
                "expected \(state.rawValue) to be accepted"
            )
        }
    }

    func testStoreRejectsSuspendedAsReservedOnly() {
        let workspace = UUID()
        let surface = UUID()
        let store = SurfaceMetadataStore.shared
        defer { store.removeSurface(workspaceId: workspace, surfaceId: surface) }

        XCTAssertThrowsError(
            try store.setMetadata(
                workspaceId: workspace,
                surfaceId: surface,
                partial: [MetadataKey.lifecycleState: SurfaceLifecycleState.suspended.rawValue],
                mode: .merge,
                source: .explicit
            )
        ) { error in
            guard let writeError = error as? SurfaceMetadataStore.WriteError else {
                return XCTFail("expected WriteError, got \(error)")
            }
            XCTAssertEqual(writeError.code, "reserved_key_invalid_type")
        }
    }

    func testStoreRejectsUnknownLifecycleStateValue() {
        let workspace = UUID()
        let surface = UUID()
        let store = SurfaceMetadataStore.shared
        defer { store.removeSurface(workspaceId: workspace, surfaceId: surface) }

        XCTAssertThrowsError(
            try store.setMetadata(
                workspaceId: workspace,
                surfaceId: surface,
                partial: [MetadataKey.lifecycleState: "frozen"],
                mode: .merge,
                source: .explicit
            )
        ) { error in
            guard let writeError = error as? SurfaceMetadataStore.WriteError else {
                return XCTFail("expected WriteError, got \(error)")
            }
            XCTAssertEqual(writeError.code, "reserved_key_invalid_type")
        }
    }

    func testStoreRejectsNonStringLifecycleState() {
        let workspace = UUID()
        let surface = UUID()
        let store = SurfaceMetadataStore.shared
        defer { store.removeSurface(workspaceId: workspace, surfaceId: surface) }

        XCTAssertThrowsError(
            try store.setMetadata(
                workspaceId: workspace,
                surfaceId: surface,
                partial: [MetadataKey.lifecycleState: 42],
                mode: .merge,
                source: .explicit
            )
        ) { error in
            guard let writeError = error as? SurfaceMetadataStore.WriteError else {
                return XCTFail("expected WriteError, got \(error)")
            }
            XCTAssertEqual(writeError.code, "reserved_key_invalid_type")
        }
    }

    func testLifecycleStateIsCanonicalKey() {
        XCTAssertTrue(MetadataKey.canonical.contains(MetadataKey.lifecycleState))
        XCTAssertTrue(SurfaceMetadataStore.reservedKeys.contains(MetadataKey.lifecycleState))
    }

    // MARK: - Controller

    @MainActor
    func testControllerStartsActiveByDefault() {
        let controller = SurfaceLifecycleController(
            workspaceId: UUID(),
            surfaceId: UUID()
        ) { _, _ in }
        XCTAssertEqual(controller.state, .active)
    }

    @MainActor
    func testControllerTransitionMirrorsToMetadata() throws {
        let workspace = UUID()
        let surface = UUID()
        let store = SurfaceMetadataStore.shared
        defer { store.removeSurface(workspaceId: workspace, surfaceId: surface) }

        let controller = SurfaceLifecycleController(
            workspaceId: workspace,
            surfaceId: surface
        ) { _, _ in }

        XCTAssertTrue(controller.transition(to: .throttled))
        let snapshot = store.getMetadata(workspaceId: workspace, surfaceId: surface)
        XCTAssertEqual(
            snapshot.metadata[MetadataKey.lifecycleState] as? String,
            SurfaceLifecycleState.throttled.rawValue
        )
    }

    @MainActor
    func testControllerRejectsInvalidTransition() {
        let controller = SurfaceLifecycleController(
            workspaceId: UUID(),
            surfaceId: UUID(),
            initial: .active
        ) { _, _ in }
        // active → suspended is not a legal transition in C11-25.
        XCTAssertFalse(controller.transition(to: .suspended))
        XCTAssertEqual(controller.state, .active)
    }

    @MainActor
    func testControllerFiresHandlerOnRealTransitionOnly() {
        var calls: [(SurfaceLifecycleState, SurfaceLifecycleState)] = []
        let controller = SurfaceLifecycleController(
            workspaceId: UUID(),
            surfaceId: UUID(),
            initial: .active
        ) { from, to in
            calls.append((from, to))
        }
        // Same-state transition is a no-op for the handler.
        XCTAssertTrue(controller.transition(to: .active))
        XCTAssertEqual(calls.count, 0)
        // Real transition fires the handler with (prior, target).
        XCTAssertTrue(controller.transition(to: .throttled))
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0, .active)
        XCTAssertEqual(calls[0].1, .throttled)
    }

    @MainActor
    func testUpdateWorkspaceIdRedirectsMetadataWrites() throws {
        let originalWorkspace = UUID()
        let newWorkspace = UUID()
        let surface = UUID()
        let store = SurfaceMetadataStore.shared
        defer {
            store.removeSurface(workspaceId: originalWorkspace, surfaceId: surface)
            store.removeSurface(workspaceId: newWorkspace, surfaceId: surface)
        }

        let controller = SurfaceLifecycleController(
            workspaceId: originalWorkspace,
            surfaceId: surface
        ) { _, _ in }

        controller.updateWorkspaceId(newWorkspace)
        XCTAssertTrue(controller.transition(to: .throttled))

        let newSnap = store.getMetadata(workspaceId: newWorkspace, surfaceId: surface)
        XCTAssertEqual(
            newSnap.metadata[MetadataKey.lifecycleState] as? String,
            SurfaceLifecycleState.throttled.rawValue
        )
        let oldSnap = store.getMetadata(workspaceId: originalWorkspace, surfaceId: surface)
        XCTAssertNil(oldSnap.metadata[MetadataKey.lifecycleState])
    }
}
