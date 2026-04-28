import Foundation

/// Transient action returned by `ConversationStrategy.resume(...)`. Executed
/// by `Workspace` against a live `TerminalPanel`.
///
/// Strategies prefer `launchProcess(argv:env:)` over `typeCommand` where the
/// surface model permits, since argv avoids shell parsing entirely.
///
/// Every strategy that emits `typeCommand` MUST validate `ConversationRef.id`
/// against a documented grammar (regex or validator) and apply explicit
/// shell-quoting/escaping before interpolation. If the id fails validation
/// or the ref is still a placeholder, the strategy MUST return
/// `.skip(reason:)` rather than synthesizing a command.
public enum ResumeAction: Sendable, Equatable {
    /// Type `text` into the surface. If `submitWithReturn` is true, dispatch
    /// a real synthetic Return key event after the paste so line discipline
    /// executes the line outside bracketed-paste mode.
    case typeCommand(text: String, submitWithReturn: Bool)
    /// Launch a fresh process (argv form, no shell parsing) inside the panel.
    case launchProcess(argv: [String], env: [String: String])
    /// Sequence of actions executed in order against the same panel.
    indirect case composite([ResumeAction])
    /// Strategy declined to resume. `reason` is recorded via Diagnostics.log.
    case skip(reason: String)
}
