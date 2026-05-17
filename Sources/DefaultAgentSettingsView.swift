import SwiftUI
import Combine

/// View-model for the Settings panel's "Default terminal agent" section.
/// Loads from `DefaultAgentConfigStore.shared` on init and writes back on every
/// edit. The store reads from UserDefaults; project `.c11/agents.json` is *not*
/// edited here — that file is operator-authored.
@MainActor
final class DefaultAgentSettingsViewModel: ObservableObject {
    @Published var agentType: DefaultAgentConfig.AgentType
    @Published var customCommand: String
    @Published var model: String
    @Published var extraArgs: String
    @Published var initialPrompt: String
    @Published var cwdMode: DefaultAgentConfig.CwdMode
    @Published var fixedCwd: String

    private let store: DefaultAgentConfigStore
    private var cancellables: Set<AnyCancellable> = []
    private var suppressSave = false

    init(store: DefaultAgentConfigStore = .shared) {
        self.store = store
        let cfg = store.current
        self.agentType = cfg.agentType
        self.customCommand = cfg.customCommand
        self.model = cfg.model
        self.extraArgs = cfg.extraArgs
        self.initialPrompt = cfg.initialPrompt
        self.cwdMode = cfg.cwdMode
        self.fixedCwd = cfg.fixedCwd

        // Persist on any field change. Env overrides aren't editable in the UI
        // for now — operators set them via `.c11/agents.json` or workspace
        // metadata. We preserve whatever the store currently has.
        $agentType.dropFirst().sink { [weak self] _ in self?.persist() }.store(in: &cancellables)
        $customCommand.dropFirst().sink { [weak self] _ in self?.persist() }.store(in: &cancellables)
        $model.dropFirst().sink { [weak self] _ in self?.persist() }.store(in: &cancellables)
        $extraArgs.dropFirst().sink { [weak self] _ in self?.persist() }.store(in: &cancellables)
        $initialPrompt.dropFirst().sink { [weak self] _ in self?.persist() }.store(in: &cancellables)
        $cwdMode.dropFirst().sink { [weak self] _ in self?.persist() }.store(in: &cancellables)
        $fixedCwd.dropFirst().sink { [weak self] _ in self?.persist() }.store(in: &cancellables)
    }

    private func persist() {
        guard !suppressSave else { return }
        let preservedEnv = store.current.envOverrides
        store.save(DefaultAgentConfig(
            agentType: agentType,
            customCommand: customCommand,
            model: model,
            extraArgs: extraArgs,
            initialPrompt: initialPrompt,
            cwdMode: cwdMode,
            fixedCwd: fixedCwd,
            envOverrides: preservedEnv
        ))
    }

    /// Preview of the command that will run. Useful sanity check for the
    /// operator authoring a flag string.
    var commandPreview: String {
        if agentType == .bash {
            return String(localized: "settings.defaultAgent.preview.bash",
                          defaultValue: "(bash — no startup command)")
        }
        return DefaultAgentResolver.buildCommand(for: DefaultAgentConfig(
            agentType: agentType,
            customCommand: customCommand,
            model: model,
            extraArgs: extraArgs,
            initialPrompt: initialPrompt,
            cwdMode: cwdMode,
            fixedCwd: fixedCwd,
            envOverrides: [:]
        ))
    }
}

private extension DefaultAgentConfig.AgentType {
    var displayName: String {
        switch self {
        case .bash:
            return String(localized: "settings.defaultAgent.type.bash", defaultValue: "Bash (no agent)")
        case .claudeCode:
            return String(localized: "settings.defaultAgent.type.claudeCode", defaultValue: "Claude Code")
        case .codex:
            return String(localized: "settings.defaultAgent.type.codex", defaultValue: "Codex")
        case .kimi:
            return String(localized: "settings.defaultAgent.type.kimi", defaultValue: "Kimi")
        case .opencode:
            return String(localized: "settings.defaultAgent.type.opencode", defaultValue: "OpenCode")
        case .custom:
            return String(localized: "settings.defaultAgent.type.custom", defaultValue: "Custom")
        }
    }
}

private extension DefaultAgentConfig.CwdMode {
    var displayName: String {
        switch self {
        case .inherit:
            return String(localized: "settings.defaultAgent.cwd.inherit", defaultValue: "Inherit from parent pane")
        case .fixed:
            return String(localized: "settings.defaultAgent.cwd.fixed", defaultValue: "Fixed path")
        }
    }
}

/// Self-contained Settings section for the C11-14 default terminal agent.
/// Wedged into the Agents & Automation page from `c11App.swift`.
struct DefaultAgentSettingsSection: View {
    @StateObject private var vm = DefaultAgentSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(selection: $vm.agentType) {
                ForEach(DefaultAgentConfig.AgentType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            } label: {
                Text(String(localized: "settings.defaultAgent.type.label", defaultValue: "Agent type"))
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("DefaultAgentTypePicker")

            if vm.agentType != .bash {
                if vm.agentType == .custom {
                    TextField(
                        String(localized: "settings.defaultAgent.customCommand.label", defaultValue: "Custom command"),
                        text: $vm.customCommand,
                        prompt: Text(String(localized: "settings.defaultAgent.customCommand.placeholder", defaultValue: "/usr/local/bin/myagent"))
                    )
                    .textFieldStyle(.roundedBorder)
                }

                TextField(
                    String(localized: "settings.defaultAgent.model.label", defaultValue: "Model"),
                    text: $vm.model,
                    prompt: Text(String(localized: "settings.defaultAgent.model.placeholder", defaultValue: "claude-opus-4-7"))
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    String(localized: "settings.defaultAgent.extraArgs.label", defaultValue: "Extra arguments"),
                    text: $vm.extraArgs,
                    prompt: Text(String(localized: "settings.defaultAgent.extraArgs.placeholder", defaultValue: "--dangerously-skip-permissions"))
                )
                .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.defaultAgent.initialPrompt.label", defaultValue: "Initial prompt (optional)"))
                        .font(.callout)
                    TextEditor(text: $vm.initialPrompt)
                        .frame(minHeight: 60, maxHeight: 120)
                        .font(.system(.body, design: .monospaced))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }

                Picker(selection: $vm.cwdMode) {
                    ForEach(DefaultAgentConfig.CwdMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    Text(String(localized: "settings.defaultAgent.cwd.label", defaultValue: "Working directory"))
                }
                .pickerStyle(.menu)

                if vm.cwdMode == .fixed {
                    TextField(
                        String(localized: "settings.defaultAgent.fixedCwd.label", defaultValue: "Fixed path"),
                        text: $vm.fixedCwd,
                        prompt: Text(String(localized: "settings.defaultAgent.fixedCwd.placeholder", defaultValue: "/Users/you/Projects"))
                    )
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.defaultAgent.preview.label", defaultValue: "Command preview"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(vm.commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}
