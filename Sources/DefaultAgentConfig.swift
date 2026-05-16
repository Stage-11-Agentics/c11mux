import Foundation

/// User-configurable default terminal agent. When a new terminal surface is
/// created without an explicit `--bash` override, c11 consults this config to
/// decide whether to drop into bash or boot a configured agent (claude-code,
/// codex, kimi, opencode, custom).
///
/// Persisted at the user level via UserDefaults (`defaultsKey`) and optionally
/// overridden per project via `.c11/agents.json` (see DefaultAgentProjectConfig).
/// Workspace-level overrides are carried as workspace metadata; see
/// DefaultAgentResolver for the full precedence chain.
struct DefaultAgentConfig: Codable, Equatable {
    enum AgentType: String, Codable, CaseIterable, Identifiable {
        case bash
        case claudeCode = "claude-code"
        case codex
        case kimi
        case opencode
        case custom

        var id: String { rawValue }
    }

    enum CwdMode: String, Codable, CaseIterable, Identifiable {
        case inherit
        case fixed

        var id: String { rawValue }
    }

    var agentType: AgentType
    /// Used only when `agentType == .custom`. Shell-quoted as-is.
    var customCommand: String
    /// Free-text model identifier (e.g. `claude-opus-4-7`). Empty → omit.
    var model: String
    /// Free-text additional flags (e.g. `--dangerously-skip-permissions`). Empty → omit.
    var extraArgs: String
    /// Optional initial prompt; non-empty → piped to the agent via stdin (`<<< '...'`).
    var initialPrompt: String
    var cwdMode: CwdMode
    /// Used only when `cwdMode == .fixed`.
    var fixedCwd: String
    var envOverrides: [String: String]

    static let bash = DefaultAgentConfig(
        agentType: .bash,
        customCommand: "",
        model: "",
        extraArgs: "",
        initialPrompt: "",
        cwdMode: .inherit,
        fixedCwd: "",
        envOverrides: [:]
    )

    /// Lenient decoder: missing fields fall back to defaults so older serialized
    /// blobs or hand-edited `.c11/agents.json` files don't break.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.agentType = (try? c.decode(AgentType.self, forKey: .agentType)) ?? .bash
        self.customCommand = (try? c.decode(String.self, forKey: .customCommand)) ?? ""
        self.model = (try? c.decode(String.self, forKey: .model)) ?? ""
        self.extraArgs = (try? c.decode(String.self, forKey: .extraArgs)) ?? ""
        self.initialPrompt = (try? c.decode(String.self, forKey: .initialPrompt)) ?? ""
        self.cwdMode = (try? c.decode(CwdMode.self, forKey: .cwdMode)) ?? .inherit
        self.fixedCwd = (try? c.decode(String.self, forKey: .fixedCwd)) ?? ""
        self.envOverrides = (try? c.decode([String: String].self, forKey: .envOverrides)) ?? [:]
    }

    init(
        agentType: AgentType,
        customCommand: String,
        model: String,
        extraArgs: String,
        initialPrompt: String,
        cwdMode: CwdMode,
        fixedCwd: String,
        envOverrides: [String: String]
    ) {
        self.agentType = agentType
        self.customCommand = customCommand
        self.model = model
        self.extraArgs = extraArgs
        self.initialPrompt = initialPrompt
        self.cwdMode = cwdMode
        self.fixedCwd = fixedCwd
        self.envOverrides = envOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case agentType, customCommand, model, extraArgs, initialPrompt, cwdMode, fixedCwd, envOverrides
    }
}

/// UserDefaults-backed singleton store for the user-level default agent config.
///
/// Read/write are cheap (JSON encode/decode). `current` is recomputed on each
/// access so changes from another process or hand-edited defaults propagate
/// without a full app restart.
final class DefaultAgentConfigStore {
    static let shared = DefaultAgentConfigStore(defaults: .standard)

    static let defaultsKey = "defaultTerminalAgentConfig.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var current: DefaultAgentConfig {
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            return .bash
        }
        guard let cfg = try? JSONDecoder().decode(DefaultAgentConfig.self, from: data) else {
            return .bash
        }
        return cfg
    }

    func save(_ cfg: DefaultAgentConfig) {
        guard let data = try? JSONEncoder().encode(cfg) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
