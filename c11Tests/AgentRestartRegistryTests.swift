import XCTest

#if canImport(c11_DEV)
@testable import c11_DEV
#elseif canImport(c11)
@testable import c11
#endif

/// Pure, in-process tests for `AgentRestartRegistry`. The registry is a
/// value type with a closure-per-row; these tests exercise the Phase 1 `cc`
/// row and the lookup semantics that callers (the executor, the
/// `snapshot.restore` socket handler) rely on.
///
/// Per `CLAUDE.md`, never run locally — CI only.
final class AgentRestartRegistryTests: XCTestCase {

    // MARK: - Phase 1 cc row

    func testClaudeCodeWithSessionIdReturnsResumeCommand() {
        let registry = AgentRestartRegistry.phase1
        let cmd = registry.resolveCommand(
            terminalType: "claude-code",
            sessionId: "abc12345-ef67-890a-bcde-f0123456789a",
            metadata: [:]
        )
        XCTAssertEqual(cmd, "cc --resume abc12345-ef67-890a-bcde-f0123456789a")
    }

    func testClaudeCodeWithoutSessionIdDeclines() {
        let registry = AgentRestartRegistry.phase1
        let cmd = registry.resolveCommand(
            terminalType: "claude-code",
            sessionId: nil,
            metadata: [:]
        )
        XCTAssertNil(cmd, "missing session id → registry declines (nil)")
    }

    func testClaudeCodeWithEmptyWhitespaceSessionIdDeclines() {
        let registry = AgentRestartRegistry.phase1
        let cmd = registry.resolveCommand(
            terminalType: "claude-code",
            sessionId: "   \t ",
            metadata: [:]
        )
        XCTAssertNil(cmd, "whitespace-only session id → registry declines (nil)")
    }

    func testClaudeCodeWithEmptySessionIdDeclines() {
        let registry = AgentRestartRegistry.phase1
        XCTAssertNil(registry.resolveCommand(
            terminalType: "claude-code",
            sessionId: "",
            metadata: [:]
        ))
    }

    // MARK: - Type dispatch

    func testUnknownTerminalTypeReturnsNil() {
        let registry = AgentRestartRegistry.phase1
        XCTAssertNil(registry.resolveCommand(
            terminalType: "codex",
            sessionId: "anything",
            metadata: [:]
        ))
    }

    func testNilTerminalTypeReturnsNil() {
        let registry = AgentRestartRegistry.phase1
        XCTAssertNil(registry.resolveCommand(
            terminalType: nil,
            sessionId: "anything",
            metadata: [:]
        ))
    }

    func testEmptyTerminalTypeReturnsNil() {
        let registry = AgentRestartRegistry.phase1
        XCTAssertNil(registry.resolveCommand(
            terminalType: "  ",
            sessionId: "id",
            metadata: [:]
        ))
    }

    // MARK: - Named lookup (wire-format bridge)

    func testNamedPhase1ResolvesToPhase1Registry() throws {
        let registry = try XCTUnwrap(AgentRestartRegistry.named("phase1"))
        let cmd = registry.resolveCommand(
            terminalType: "claude-code",
            sessionId: "sess-xyz",
            metadata: [:]
        )
        XCTAssertEqual(cmd, "cc --resume sess-xyz")
    }

    func testNamedUnknownReturnsNilInsteadOfErroring() {
        XCTAssertNil(AgentRestartRegistry.named("phase99"))
        XCTAssertNil(AgentRestartRegistry.named(nil))
    }

    // MARK: - Custom row (Phase 5 shape preview)

    func testCustomRegistryCanCarryAdditionalRows() {
        let registry = AgentRestartRegistry(rows: [
            AgentRestartRegistry.Row(terminalType: "claude-code") { _, _ in "cc" },
            AgentRestartRegistry.Row(terminalType: "codex") { sid, _ in
                guard let sid else { return nil }
                return "codex resume \(sid)"
            }
        ])
        XCTAssertEqual(
            registry.resolveCommand(terminalType: "codex", sessionId: "c-42", metadata: [:]),
            "codex resume c-42"
        )
        XCTAssertEqual(
            registry.resolveCommand(terminalType: "claude-code", sessionId: nil, metadata: [:]),
            "cc"
        )
        XCTAssertNil(
            registry.resolveCommand(terminalType: "kimi", sessionId: "k-1", metadata: [:]),
            "unknown type still returns nil even with multi-row registry"
        )
    }
}
