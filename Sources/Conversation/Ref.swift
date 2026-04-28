import Foundation

/// Source that captured a `ConversationRef`. Used both for diagnostic
/// provenance and for the reconciliation-rule tiebreaker
/// (`hook > scrape > manual > wrapperClaim`).
public enum CaptureSource: String, Codable, Sendable {
    case hook
    case scrape
    case wrapperClaim
    case manual
}

/// Lifecycle state of a `ConversationRef`.
///
/// - `alive`: TUI is running and the strategy has confidence the ref is
///   the active conversation.
/// - `suspended`: c11 is shutting down or has shut down cleanly; resume
///   on next launch is expected.
/// - `tombstoned`: explicitly ended (operator action, or scrape confirmed
///   the session file is gone for a strategy that can be confident — e.g.
///   Claude with hook history). Not auto-resumable.
/// - `unknown`: the strategy cannot classify this ref; resume() returns
///   `.skip` until pull-scrape promotes it. Resting state for refs found
///   after a crash, ambiguous Codex matches, etc.
/// - `unsupported`: ref kind not registered in this binary's strategy
///   registry. Retain (don't tombstone) so a future c11 release with the
///   strategy can promote it.
public enum ConversationState: String, Codable, Sendable {
    case alive
    case suspended
    case tombstoned
    case unknown
    case unsupported
}

/// Persistable pointer to a continuation of agent work. Owned by c11,
/// lives across TUI process death, opaque-id keyed to a per-kind strategy.
///
/// `cwd` is core (not payload) — universal for local-process software-
/// engineering agents and load-bearing for the Codex scrape filter; nil
/// for cloud/remote/MCP strategies that don't have a meaningful cwd.
///
/// `placeholder` is `true` while only a wrapper-claim has been seen and
/// the real id has not been resolved yet. Strategies must replace before
/// any ResumeAction is emitted; `resume()` returns `.skip` if placeholder
/// remains true.
///
/// `diagnosticReason` is populated on every update so operators can answer
/// "why did this pane resume that session?" without instrumentation.
public struct ConversationRef: Codable, Sendable, Equatable {
    public var kind: String
    public var id: String
    public var placeholder: Bool
    public var cwd: String?
    public var capturedAt: Date
    public var capturedVia: CaptureSource
    public var state: ConversationState
    public var diagnosticReason: String?
    public var payload: [String: PersistedJSONValue]?

    public init(
        kind: String,
        id: String,
        placeholder: Bool = false,
        cwd: String? = nil,
        capturedAt: Date = Date(),
        capturedVia: CaptureSource,
        state: ConversationState,
        diagnosticReason: String? = nil,
        payload: [String: PersistedJSONValue]? = nil
    ) {
        self.kind = kind
        self.id = id
        self.placeholder = placeholder
        self.cwd = cwd
        self.capturedAt = capturedAt
        self.capturedVia = capturedVia
        self.state = state
        self.diagnosticReason = diagnosticReason
        self.payload = payload
    }
}

/// Surface ↔ Conversation mapping persisted on each `SessionPanelSnapshot`.
/// v1 only ever populates `active`; `history` is written explicitly as an
/// empty array (not omitted) so JSON output is stable across v1/v2.
public struct SurfaceConversations: Codable, Sendable, Equatable {
    public var active: ConversationRef?
    public var history: [ConversationRef]

    public init(active: ConversationRef? = nil, history: [ConversationRef] = []) {
        self.active = active
        self.history = history
    }

    public static let empty = SurfaceConversations(active: nil, history: [])
}

extension CaptureSource {
    /// Tiebreaker priority used by `ConversationStore` reconciliation
    /// when two writes carry close `capturedAt` timestamps. Higher wins.
    var priority: Int {
        switch self {
        case .hook:         return 4
        case .scrape:       return 3
        case .manual:       return 2
        case .wrapperClaim: return 1
        }
    }
}
