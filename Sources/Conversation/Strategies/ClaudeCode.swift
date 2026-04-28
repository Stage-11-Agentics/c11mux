import Foundation

/// Push-primary strategy for Claude Code. The wrapper at
/// `Resources/bin/claude` injects `--session-id` and the SessionStart hook
/// reports the real session id via `c11 conversation push --kind claude-code`.
/// Identity is deterministic; resume types
/// `claude --dangerously-skip-permissions --resume <id>`.
///
/// Id grammar: UUID v4 (8-4-4-4-12 hex, anchored, case-insensitive). Mirrors
/// the existing `claudeSessionIdUUIDPattern` so the legacy
/// `claude.session_id` reserved-key validator and the new strategy share
/// one grammar.
struct ClaudeCodeStrategy: ConversationStrategy {
    let kind: String = "claude-code"

    init() {}

    func capture(inputs: ConversationStrategyInputs) -> ConversationRef? {
        // Push-primary: hook value wins on the live path.
        if let push = inputs.push, !push.placeholder {
            return push
        }
        // Pull-fallback: scrape produced a candidate (top-1 by mtime,
        // optionally cwd-filtered). Filename carries the session id
        // (Claude session filename pattern).
        if let candidate = inputs.scrapeCandidates.first,
           isValidConversationUUID(candidate.id) {
            return ConversationRef(
                kind: kind,
                id: candidate.id,
                placeholder: false,
                cwd: candidate.cwd ?? inputs.cwd,
                capturedAt: candidate.mtime,
                capturedVia: .scrape,
                state: .unknown,
                diagnosticReason: "scrape: top-by-mtime in ~/.claude/sessions"
            )
        }
        // Wrapper-claim only: nothing to resume yet.
        if let claim = inputs.wrapperClaim {
            return claim
        }
        return nil
    }

    func resume(ref: ConversationRef) -> ResumeAction {
        guard !ref.placeholder else {
            return .skip(reason: "placeholder; no real session id captured yet")
        }
        guard ref.state == .alive || ref.state == .suspended else {
            return .skip(reason: "state=\(ref.state.rawValue) not auto-resumable")
        }
        guard isValidConversationUUID(ref.id) else {
            return .skip(reason: "invalid id grammar")
        }
        let quoted = conversationShellQuote(ref.id)
        let text = "claude --dangerously-skip-permissions --resume \(quoted)"
        return .typeCommand(text: text, submitWithReturn: true)
    }

    func isValidId(_ id: String) -> Bool {
        isValidConversationUUID(id)
    }
}
