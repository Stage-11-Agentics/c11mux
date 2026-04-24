import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Acceptance fixture for `WorkspaceLayoutExecutor`. Runs each of five
/// `WorkspaceApplyPlan` JSON fixtures through the executor on a real
/// `TabManager` and asserts the workspace materializes in under 2 s —
/// the per-fixture budget from the Phase 0 plan.
///
/// Per `CLAUDE.md`, tests are never run locally by the impl agent; this file
/// is committed and exercised only in CI.
@MainActor
final class WorkspaceLayoutExecutorAcceptanceTests: XCTestCase {

    // MARK: - Fixtures

    private static let fixtureNames = [
        "welcome-quad",
        "default-grid",
        "single-large-with-metadata",
        "mixed-browser-markdown",
        "deep-nested-splits"
    ]

    /// Budget per fixture in milliseconds. Matches `ApplyOptions.perStepTimeoutMs`
    /// default and the plan's acceptance target.
    private static let perFixtureBudgetMs: Double = 2_000

    // MARK: - Setup

    private var tabManager: TabManager!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
    }

    override func tearDown() {
        tabManager = nil
        super.tearDown()
    }

    // MARK: - Per-fixture tests

    func testAppliesWelcomeQuadFixture() async throws {
        try await runFixture(named: "welcome-quad", expectedSurfaceIds: ["tl", "tr", "bl", "br"])
    }

    func testAppliesDefaultGridFixture() async throws {
        try await runFixture(named: "default-grid", expectedSurfaceIds: ["tl", "tr", "bl", "br"])
    }

    func testAppliesSingleLargeWithMetadataFixture() async throws {
        let result = try await runFixture(
            named: "single-large-with-metadata",
            expectedSurfaceIds: ["main"]
        )
        // Workspace-level metadata should land on the workspace.
        let workspaceId = try XCTUnwrap(UUID(uuidString: result.workspaceRef.replacingOccurrences(of: "workspace:", with: "")))
        let workspace = try XCTUnwrap(tabManager.tabs.first { $0.id == workspaceId })
        XCTAssertEqual(workspace.metadata["description"], "single-pane driver session with mailbox config")

        // Surface metadata round-trips through SurfaceMetadataStore.
        let mainPanelId = try XCTUnwrap(
            panelId(forSurfaceRef: result.surfaceRefs["main"], workspace: workspace)
        )
        let (surfaceMetadata, _) = SurfaceMetadataStore.shared.getMetadata(
            workspaceId: workspace.id,
            surfaceId: mainPanelId
        )
        XCTAssertEqual(surfaceMetadata["role"] as? String, "driver")
        XCTAssertEqual(surfaceMetadata["status"] as? String, "ready")
        XCTAssertEqual(surfaceMetadata["description"] as? String, "cc session with mailbox.* subscription")

        // mailbox.* pane metadata round-trips verbatim through PaneMetadataStore.
        let paneId = try XCTUnwrap(workspace.paneIdForPanel(mainPanelId)?.id)
        let (paneMetadata, _) = PaneMetadataStore.shared.getMetadata(
            workspaceId: workspace.id,
            paneId: paneId
        )
        XCTAssertEqual(paneMetadata["mailbox.delivery"] as? String, "stdin,watch")
        XCTAssertEqual(paneMetadata["mailbox.subscribe"] as? String, "build.*,deploy.green")
        XCTAssertEqual(paneMetadata["mailbox.retention_days"] as? String, "7")
    }

    func testAppliesMixedBrowserMarkdownFixture() async throws {
        try await runFixture(
            named: "mixed-browser-markdown",
            expectedSurfaceIds: ["docs", "notes", "tests", "build"]
        )
    }

    func testAppliesDeepNestedSplitsFixture() async throws {
        try await runFixture(
            named: "deep-nested-splits",
            expectedSurfaceIds: ["a", "b", "c", "d", "e"]
        )
    }

    // MARK: - Harness

    @discardableResult
    private func runFixture(
        named name: String,
        expectedSurfaceIds: [String]
    ) async throws -> ApplyResult {
        let plan = try loadFixture(named: name)
        let deps = WorkspaceLayoutExecutorDependencies(
            tabManager: tabManager,
            workspaceRefMinter: { "workspace:\($0.uuidString)" },
            surfaceRefMinter: { "surface:\($0.uuidString)" },
            paneRefMinter: { "pane:\($0.uuidString)" }
        )
        let result = await WorkspaceLayoutExecutor.apply(
            plan,
            options: ApplyOptions(select: true),
            dependencies: deps
        )

        XCTAssertFalse(result.workspaceRef.isEmpty, "workspaceRef populated for \(name)")
        XCTAssertEqual(
            Set(result.surfaceRefs.keys),
            Set(expectedSurfaceIds),
            "surfaceRefs cover all expected plan surface ids for \(name)"
        )
        XCTAssertEqual(
            Set(result.paneRefs.keys),
            Set(expectedSurfaceIds),
            "paneRefs cover all expected plan surface ids for \(name)"
        )
        XCTAssertTrue(
            result.failures.allSatisfy { $0.code != "validation_failed" },
            "no validation_failed entries in \(name): \(result.failures)"
        )

        let totalMs = result.timings.first { $0.step == "total" }?.durationMs ?? .infinity
        XCTAssertLessThan(
            totalMs,
            Self.perFixtureBudgetMs,
            "fixture \(name) exceeded \(Self.perFixtureBudgetMs) ms budget; total=\(totalMs)"
        )
        return result
    }

    private func loadFixture(named name: String) throws -> WorkspaceApplyPlan {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("workspace-apply-plans")
            .appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(WorkspaceApplyPlan.self, from: data)
    }

    private func panelId(forSurfaceRef ref: String?, workspace: Workspace) -> UUID? {
        guard let ref = ref,
              let uuidString = ref.split(separator: ":").last,
              let uuid = UUID(uuidString: String(uuidString)) else {
            return nil
        }
        return workspace.panels[uuid] != nil ? uuid : nil
    }
}
