import Foundation

/// Workspace-level override carried as workspace metadata.
struct WorkspaceAgentOverride: Equatable {
    /// Forces bash regardless of any other configuration.
    var useBash: Bool
    /// If non-nil, replaces the user-default config entirely.
    var inlineConfig: DefaultAgentConfig?

    static let none = WorkspaceAgentOverride(useBash: false, inlineConfig: nil)
}

/// The fully-resolved decision for a new terminal: what command (if any) to
/// run, what environment overrides to apply, and what working directory to
/// switch to.
struct ResolvedAgent: Equatable {
    /// Command string passed to the terminal's startup hook. `nil` ⇒ no command
    /// (pristine bash / login shell), preserving the historical behavior.
    let command: String?
    let envOverrides: [String: String]
    /// `nil` ⇒ inherit whatever cwd the terminal would otherwise use.
    let workingDirectory: String?

    static let bash = ResolvedAgent(command: nil, envOverrides: [:], workingDirectory: nil)
}

enum DefaultAgentResolverError: Error, Equatable {
    case unknownAgentName(String)
}

/// Pure resolver. No I/O; callers pass in the user default + project config +
/// workspace override and the resolver picks a winner.
enum DefaultAgentResolver {

    /// Precedence (highest wins):
    ///
    /// 1. `forceBash` (the `--bash` CLI flag) → always bash.
    /// 2. `explicitAgent` (`--agent <name>`): only `"default"` is recognized in
    ///    this first cut. Any other name throws `.unknownAgentName`.
    ///    `"default"` falls through to step 3+ but treats `agentType == .bash`
    ///    as bash.
    /// 3. `workspaceOverride.useBash` → bash.
    /// 4. `workspaceOverride.inlineConfig` → that config.
    /// 5. `projectConfig` → that config.
    /// 6. `userDefault` → that config.
    /// 7. If the chosen config's `agentType == .bash` → bash.
    static func resolve(
        explicitAgent: String?,
        forceBash: Bool,
        workspaceOverride: WorkspaceAgentOverride,
        userDefault: DefaultAgentConfig,
        projectConfig: DefaultAgentConfig?
    ) throws -> ResolvedAgent {
        if forceBash { return .bash }

        if let name = explicitAgent {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized == "default" else {
                throw DefaultAgentResolverError.unknownAgentName(name)
            }
        }

        if workspaceOverride.useBash { return .bash }

        let chosen: DefaultAgentConfig
        if let inline = workspaceOverride.inlineConfig {
            chosen = inline
        } else if let project = projectConfig {
            chosen = project
        } else {
            chosen = userDefault
        }

        if chosen.agentType == .bash {
            return .bash
        }

        let command = buildCommand(for: chosen)
        let workingDirectory: String?
        switch chosen.cwdMode {
        case .inherit:
            workingDirectory = nil
        case .fixed:
            let trimmed = chosen.fixedCwd.trimmingCharacters(in: .whitespacesAndNewlines)
            workingDirectory = trimmed.isEmpty ? nil : trimmed
        }
        return ResolvedAgent(
            command: command,
            envOverrides: chosen.envOverrides,
            workingDirectory: workingDirectory
        )
    }

    /// Build the shell command string for a non-bash config. The returned
    /// string is intended to be **typed into the user's login shell** (via
    /// `TerminalPanel.sendText`), not handed to Ghostty's startup-command
    /// hook — that way interactive TUIs keep a live stdin and quitting the
    /// agent leaves the shell available, matching the existing
    /// `AgentLauncherSettings.launchAgentSurface` and welcome-workspace
    /// patterns.
    ///
    /// Initial-prompt delivery:
    /// - `claude-code`: appended as a single-quoted positional argument
    ///   (`claude … 'prompt'`). `claude` accepts an initial prompt that way.
    /// - All other agents: `initialPrompt` is preserved in the persisted
    ///   config but **not** auto-appended. Different TUIs have different
    ///   contracts (codex specifically ignores piped stdin and needs a
    ///   post-ready file-reference) and we ship per-agent prompt delivery in
    ///   a follow-up rather than guessing. Operators who want it today can
    ///   include it inline via `extraArgs`.
    ///
    /// Visible for testing.
    static func buildCommand(for cfg: DefaultAgentConfig) -> String {
        let binary: String
        switch cfg.agentType {
        case .bash:
            return ""
        case .claudeCode:
            binary = "claude"
        case .codex:
            binary = "codex"
        case .kimi:
            binary = "kimi"
        case .opencode:
            binary = "opencode"
        case .custom:
            binary = cfg.customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var parts: [String] = []
        if !binary.isEmpty {
            parts.append(binary)
        }
        let model = cfg.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            parts.append("--model")
            parts.append(shellQuote(model))
        }
        let extra = cfg.extraArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            parts.append(extra)
        }

        let prompt = cfg.initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty && cfg.agentType == .claudeCode {
            parts.append(shellQuote(prompt))
        }

        return parts.joined(separator: " ")
    }

    /// Single-quote a value for /bin/sh, escaping embedded single quotes via
    /// the standard `'\''` close-reopen trick. Visible for testing.
    static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
