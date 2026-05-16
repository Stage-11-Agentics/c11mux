# C11-14: Default terminal agent: launch a configured agent on new-terminal

Let the operator configure a **default terminal agent** for new terminal surfaces. When set, 'new terminal' boots directly into that agent (claude, codex, kimi, opencode, …) with a configured parameter set instead of dropping into bash. The bash experience is still available via an explicit 'new bash terminal' action.

## Motivation

Surfaced while orchestrating C11-13: the delegator was launched via `claude --dangerously-skip-permissions` and quietly booted on Sonnet 4.6 because no `--model` was passed. The operator had no way to say 'every claude I launch in c11 should be Opus 4.7' without editing every prompt or wrapper. Most operators open dozens of terminals a day and want the same agent in the same shape every time.

## Scope (first PR — confirmed with operator 2026-05-16)

**In scope:**

- Single editable default agent config (not multiple named presets — those are a follow-up).
- Per-project `.c11/agents.json` override (project beats user).
- Initial-prompt-on-launch field.
- Per-workspace override via workspace metadata.
- CLI flags `--agent` and `--bash` on `new-split`, `new-pane`, `new-surface`.
- "New bash terminal" menu action that bypasses the default.
- Settings panel section "Default terminal agent" with form fields for: agent type, model, extra args, initial prompt, cwd inherit/fixed, env overrides.
- Localization of all new English strings + xcstrings sync for ja/uk/ko/zh-Hans/zh-Hant/ru.
- Logic-only tests via `c11-logic` scheme: codec round-trip, resolution function under all precedence cases, project-config discovery.

**Deferred (open questions, follow-up tickets):**

- Multiple named presets (`claude-opus`, `claude-haiku`, `codex-yolo` …).
- Sub-agent lineage composition (does the default apply to sibling surfaces spawned by a delegator?).
- A Settings UI for per-workspace override (this PR exposes per-workspace override via workspace metadata only; UI follows in a follow-up).

## Design

### Data model — `DefaultAgentConfig`

A single `Codable` struct, persisted as a JSON blob in UserDefaults (user-level) and read from `.c11/agents.json` (project-level). Project beats user.

```swift
struct DefaultAgentConfig: Codable, Equatable {
    enum AgentType: String, Codable, CaseIterable {
        case bash
        case claudeCode = "claude-code"
        case codex
        case kimi
        case opencode
        case custom
    }
    enum CwdMode: String, Codable {
        case inherit       // use TerminalController-computed cwd (default)
        case fixed         // use `fixedCwd`
    }

    var agentType: AgentType   // .bash means "fall through to bash"
    var customCommand: String  // used when agentType == .custom
    var model: String          // free text; passed as `--model <value>` (or per-agent flag) when non-empty
    var extraArgs: String      // free-text additional flags, appended as-is
    var initialPrompt: String  // optional; piped via `<<<` if non-empty
    var cwdMode: CwdMode
    var fixedCwd: String       // used when cwdMode == .fixed
    var envOverrides: [String: String]
}
```

**File locations:**

- `Sources/DefaultAgentConfig.swift` — model + UserDefaults persistence helper (`DefaultAgentConfigStore.shared`).
- `Sources/DefaultAgentResolver.swift` — pure resolution function.
- `Sources/DefaultAgentProjectConfig.swift` — walks up from cwd looking for `.c11/agents.json`.

### Per-project `.c11/agents.json` discovery

Walk up from cwd looking for `.c11/agents.json` (priority over user default). Mirrors the existing `WorkspaceBlueprintStore` walk pattern. File format identical to the UserDefaults JSON blob.

If the file exists and parses, it wins; otherwise fall back to user default.

### Resolution function — `DefaultAgentResolver.resolve(...)`

```swift
struct ResolvedAgent {
    let command: String?       // nil → bash (no initialCommand)
    let envOverrides: [String: String]
    let workingDirectory: String?  // nil → inherit
}

static func resolve(
    explicitAgent: String?,     // from `--agent <name>` flag
    forceBash: Bool,            // from `--bash` flag
    workspaceOverride: WorkspaceAgentOverride,
    userDefault: DefaultAgentConfig,
    projectConfig: DefaultAgentConfig?
) throws -> ResolvedAgent
```

**Precedence (highest wins):**

1. `--bash` → `command = nil` (always bash, period).
2. `--agent <name>` → for now, only `default` is recognized; others reserved for follow-up. Unknown name → throw.
3. workspace metadata `workspace.use_bash` = `true` → bash.
4. workspace metadata `workspace.default_agent_inline` (Codable JSON) → use that config.
5. project `.c11/agents.json` → use that config.
6. user default → use that config.
7. If the chosen config's `agentType == .bash` → bash (initialCommand = nil).

Command builder for non-bash types:
- claude-code: `claude` + (model? `--model 'model'` : '') + (extraArgs) + (initialPrompt? `<<< 'prompt'` : '')
- codex: `codex` + same shape
- kimi / opencode: same shape (binary name + args)
- custom: `customCommand` + (extraArgs) + (initialPrompt as `<<<` here-string)

The wrappers under `Resources/bin/` already handle session-id capture; we don't touch them.

### CLI flags

Add `--agent=<name>` and `--bash` parsing to:

- `TerminalController.newSurface(_:)` at TerminalController.swift:18697
- `TerminalController.newSplit(_:)` at TerminalController.swift:15358
- `TerminalController.newPane(_:)` at TerminalController.swift:17158

Default (no flags) = consult precedence chain. With `--bash`, always bash. With `--agent=default`, use the precedence chain's resolved non-bash config.

### Workspace plumbing

Extend `Workspace.newTerminalSurface(...)` and `Workspace.newTerminalSplit(...)` to accept an optional `agentOverride: ResolvedAgent?` parameter. When non-nil, replace `remoteTerminalStartupCommand` and add env overrides + working dir. When nil, use the current behavior.

`TabManager.newSurface()` gains an optional `forceBash:` and consults `DefaultAgentResolver` internally for menu-driven creation.

### Settings UI

New `SettingsNavigationTarget.defaultTerminalAgent` case. The page is a single `Form` with:

- Agent type picker (Bash, Claude Code, Codex, Kimi, OpenCode, Custom).
- Model text field.
- Extra arguments text field.
- Initial prompt multiline text area.
- Cwd mode picker (Inherit, Fixed) + conditional fixed-path field.
- Env overrides editable list (rows of key + value).
- Custom command text field (visible when agent type == Custom).

All strings via `String(localized:)`. Persist via `DefaultAgentConfigStore.shared.save(_:)` on change.

### Menu wiring

Add **"New Bash Terminal"** menu item in `c11App.swift` (near the existing "New Surface" block) that calls into the bash path. The existing "New Surface" / "Split Right" / "Split Down" items resolve via the precedence chain.

### Per-workspace override

A workspace can carry one of two metadata keys:

- `workspace.use_bash` = `"true"` → forces bash regardless of user default.
- `workspace.default_agent_inline` = JSON blob of `DefaultAgentConfig` → overrides user default.

Set via the existing `c11 set-metadata --workspace <id> --key <key> --value <value>`. No UI for this in the first PR; documented in release notes / skill.

### Localization

All new strings via `String(localized:)` with English `defaultValue:`. After implementation, a translator sub-agent syncs `Resources/Localizable.xcstrings` for ja, uk, ko, zh-Hans, zh-Hant, ru.

### Tests (c11-logic only)

`c11Tests/DefaultAgentConfigTests.swift` and `c11Tests/DefaultAgentResolverTests.swift` (logic target):

- Codec round-trip.
- Resolver precedence under all 7 source combinations.
- Project config discovery: file present → parsed; file missing → nil; malformed JSON → nil; deep nested cwd walks upward.
- Command builder: covers each agent type, with/without model, with/without initialPrompt, with/without extraArgs, single-quote escaping in initial prompt.
- Cwd resolution: inherit → nil, fixed → path, fixed-empty → nil.

UI/event-path code (Settings view, menu items, CLI flag plumbing) is exercised via the standard `xcodebuild build` + tagged-reload iteration loop and validated via CI's `c11-unit` scheme on the PR.

## File-level change list

| File | Change | New / Modify |
|------|--------|--------------|
| `Sources/DefaultAgentConfig.swift` | model + UserDefaults store | New |
| `Sources/DefaultAgentResolver.swift` | resolution function + command builder | New |
| `Sources/DefaultAgentProjectConfig.swift` | `.c11/agents.json` walk | New |
| `Sources/DefaultAgentSettingsView.swift` | Settings UI page | New |
| `Sources/c11App.swift` | wire SettingsNavigationTarget + page + menu item | Modify |
| `Sources/TerminalController.swift` | `--agent` / `--bash` parsing in newSplit/newPane/newSurface | Modify |
| `Sources/Workspace.swift` | accept agent override in newTerminalSurface/Split | Modify |
| `Sources/TabManager.swift` | `forceBash:` in newSurface, propagate override | Modify |
| `Resources/Localizable.xcstrings` | English entries (translator pass after impl) | Modify |
| `c11Tests/DefaultAgentConfigTests.swift` | codec + persistence + project-config tests | New |
| `c11Tests/DefaultAgentResolverTests.swift` | resolver precedence + builder + cwd tests | New |
| `scripts/c11-14-register-files.rb` | idempotent xcodeproj registration | New |

## Implementation order

1. **Data model + resolver + tests** (logic-only, no UI). Get the core right first; CI can run logic tests locally via `c11-logic` scheme. ✅
2. **CLI flag parsing**. Add `--agent` / `--bash` to all three socket handlers. Wire to the resolver.
3. **Workspace plumbing**. Thread the resolved command/env/cwd through `Workspace.newTerminalSurface` and `newTerminalSplit`.
4. **Menu wiring**. Add "New Bash Terminal" item + connect.
5. **Settings UI**. Add the page; bind to the store.
6. **Localization sync**. Translator sub-agent.
7. **PR**. Open via gh, paste URL.

## Out of scope (explicit, surfaced in PR body)

- Multiple named presets — follow-up.
- Sub-agent lineage composition — follow-up.
- Per-workspace UI — follow-up; this PR exposes the override only via workspace metadata + CLI.
- `c11 install <tui>` — explicitly rejected by CLAUDE.md (c11 is unopinionated about TUI config); we do not write into `~/.claude/`, `~/.codex/`, etc.

## Risk register

- **Typing-latency hot paths** (`WindowTerminalHostView.hitTest`, `TabItemView`, `TerminalSurface.forceRefresh`). None of this work touches them. No new allocations on the keystroke path.
- **Socket command threading**. CLI parsing is pure string work, off-main. The actual terminal creation goes through `v2MainSync` as today.
- **Localization regression**. Six translations need syncing; the translator sub-agent pattern is well-established.
- **Tests must run via `c11-logic` scheme locally**. Per CLAUDE.md, never run `xcodebuild test` on the host scheme locally; the full host suite goes to CI.
- **Submodule pointer**. The c11 main's `vendor/bonsplit` SHA is `f765de29` — keep the submodule synced (the working tree was checked out at an earlier SHA initially and produced compile errors that vanished after `git submodule update`).

## Notes on the abandoned branches

- `c11-14/phase-1-followup` (PR #78, merged 2026-04-26) and `c11-14/stage-3-full-primitive` (local-only, base in old main) carried the C11-14 prefix but were CMUX-37 workspace-snapshot work, not default-terminal-agent work. The ticket was orphaned in commit `ec4e69472`. Starting fresh from `main` on branch `c11-14/default-terminal-agent`.

## Plan-review v1 response (2026-05-16)

Auto-fired triple plan-review verdict: FAIL (plan-level). Concrete issues addressed in-implementation rather than via plan rewrite + re-review:

- **CRITICAL — herestring stdin for interactive TUIs**: launch mechanism switched from Ghostty `initialCommand` startup hook to `TerminalPanel.sendText(command + "\n")` *after* the panel is created. Matches the existing `AgentLauncherSettings.launchAgentSurface` + welcome-workspace pattern: the operator's login shell stays alive, the agent runs as a child, quitting the agent leaves the shell. Initial-prompt herestring removed: claude-code appends `initialPrompt` as a single-quoted positional argument; other agents preserve the field in config but do not auto-append (different TUIs have different delivery contracts — codex specifically ignores piped stdin per CLAUDE.md). Operators who want a per-agent prompt today can put it inline via `extraArgs`.
- **CRITICAL — test-target placement**: `scripts/c11-14-register-files.rb` adds the new test files to **both** `c11Tests` and `c11LogicTests` source phases. `xcodebuild -scheme c11-logic` includes them. Verified locally via the c11-logic scheme.
- **CRITICAL — shell quoting**: execution model pinned to **shell-string-shaped** (passed via `sendText` into the login shell, which is the existing `AgentLauncherSettings` contract). `extraArgs: String` is parsed by the shell as the operator typed it. `model` is single-quoted; `initialPrompt` (claude-code path only) is single-quoted with the standard `'\''` escape. Tests cover spaces, embedded single quotes, empty fields.
- **MAJOR — AgentLauncherSettings reconciliation**: kept separate as a deliberate UX call. The "A" button is a per-pane quick-launch shortcut (operator clicks A → instant agent in that pane). DefaultAgentConfig is "what every new terminal opens with." The settings card carries a note explicitly distinguishing them. Unification into one canonical agent-default model is a follow-up.
- **MAJOR — remote-terminal interaction**: policy pinned. `Workspace.newTerminalSurface`/`newTerminalSplit` still pass `remoteTerminalStartupCommand()` to the Ghostty startup hook. The agent command (when non-nil) is delivered via `sendText` *after* the relay startup command runs, so remote workspaces compose: relay first, then operator's agent. `trackRemoteTerminalSurface` continues to fire only when `initialCommand != nil` (i.e. only for the relay path), which is the historical behavior.
- **MAJOR — `newTerminalSurfaceInFocusedPane` plumbing**: extended to take `agentOverride: ResolvedAgent? = nil`. The menu's "New Terminal" path now resolves via the workspace before calling `newTerminalSurfaceInFocusedPane(focus:agentOverride:)`.
- **MAJOR — `--agent` semantics**: dropped from the first PR. Only `--bash` is wired on `new-split`, `new-pane`, `new-surface`. The resolver still accepts `explicitAgent: String?` (and the test for "default" / unknown names is preserved) for the named-presets follow-up.
- **MAJOR — cwd disambiguation**: every call path uses the same `Workspace.resolverCwdForNewSurface()` (focused panel's directory → workspace `currentDirectory` → process cwd). Documented inline.
- **MINOR — JSON-in-metadata blob**: dropped `workspace.default_agent_inline`. Only `workspace.default_agent_use_bash` is recognized; richer inline workspace config is a follow-up (likely via `.c11/blueprints/`-style file rather than a metadata string).
- **MINOR — `.cmux/agents.json` legacy**: intentionally NOT checked. This feature is c11-only.
- **MINOR — `CwdMode` resolver collapse**: documented. The two-field shape (`cwdMode` + `fixedCwd`) is preserved in the Settings UI layer for clean form ergonomics; `DefaultAgentResolver.resolve(...)` collapses them to a single `workingDirectory: String?` for downstream code.
- **MINOR — menu wording**: "New Bash Terminal" lands as a fourth Button alongside "New Terminal", "New Browser", "New Markdown". No keyboard shortcut in this PR (avoids collision with any future shift-cmd-T binding).
- **MINOR — AgentDetector / AgentChip / AgentRestartRegistry**: launched-agent processes are detected via the normal AgentDetector path; the existing `Resources/bin/claude` wrapper calls `c11 set-agent` and provides session-id capture. No new code needed here. Manual chip + restart validation lands during PR review.

The plan-review's CRITICAL findings around launch semantics turned out to be the most important — they reshaped the implementation from "pass a shell command to the terminal as a startup hook" (which would have broken every interactive TUI in subtle ways) to "open a login shell, then type the launch command into it." That's the right shape and matches what already works elsewhere in c11.
