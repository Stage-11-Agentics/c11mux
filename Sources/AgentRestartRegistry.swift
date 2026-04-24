import Foundation

/// Pure-value lookup table mapping a known terminal type + session hint to
/// the shell command that resumes it. Phase 1 ships a single row for
/// `claude-code`; rows for `codex`, `opencode`, `kimi` land in Phase 5
/// without schema changes.
///
/// The registry is **not Codable**. It flows through
/// `ApplyOptions.restartRegistry` as an in-process reference and is resolved
/// by name at the v2 handler boundary (`"phase1"` → `.phase1`). Keeping it
/// out of the wire format prevents snapshot files from locking in a specific
/// registry version — a snapshot written today stays restorable after Phase
/// 5 adds rows, because the registry is resolved app-side at restore time.
struct AgentRestartRegistry: Sendable {
    struct Row: Sendable {
        /// Canonical `terminal_type` string, matching the value written by
        /// `c11 set-agent --type <type>` and surfaced by the sidebar chip.
        let terminalType: String
        /// Pure resolver. Returns the command to run, or `nil` to decline
        /// (e.g., required session id missing). `metadata` is the full
        /// string-valued surface-metadata map; future rows may consult
        /// additional keys without schema changes.
        let resolve: @Sendable (_ sessionId: String?, _ metadata: [String: String]) -> String?

        init(
            terminalType: String,
            resolve: @escaping @Sendable (_ sessionId: String?, _ metadata: [String: String]) -> String?
        ) {
            self.terminalType = terminalType
            self.resolve = resolve
        }
    }

    private let rowsByType: [String: Row]

    init(rows: [Row]) {
        var map: [String: Row] = [:]
        for row in rows { map[row.terminalType] = row }
        self.rowsByType = map
    }

    /// Consult the registry. Returns `nil` when the type is unknown or the
    /// matching row declines. Pure; never mutates.
    func resolveCommand(
        terminalType: String?,
        sessionId: String?,
        metadata: [String: String]
    ) -> String? {
        guard let type = terminalType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !type.isEmpty,
              let row = rowsByType[type] else { return nil }
        return row.resolve(sessionId, metadata)
    }

    /// Names the executor handler accepts in `snapshot.restore` params.
    /// `"phase1"` → `.phase1`; unknown names resolve to `nil` so an
    /// unrecognised wire value silently falls back to Phase 0 behavior
    /// rather than erroring the restore.
    static func named(_ name: String?) -> AgentRestartRegistry? {
        switch name {
        case "phase1": return .phase1
        default: return nil
        }
    }

    /// Phase 1 ships cc resume only. Phase 5 adds codex / opencode / kimi
    /// rows here; adding a row is a one-line append to this literal.
    static let phase1: AgentRestartRegistry = .init(rows: [
        Row(terminalType: "claude-code") { sessionId, _ in
            guard let id = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty else { return nil }
            return "cc --resume \(id)"
        }
    ])
}
