# CMUX-5 — Tier 1 Phase 5: recovery UI

Plan note for whoever picks this up. Tier 1b closer — depends on Phase 4.

## The intent in one line

A restored surface offers a clear path to recreate what was running, with a copy-first safety gate that never blindly injects keystrokes into a pane.

## Source of truth

Phase 5 section of `docs/c11mux-tier1-persistence-plan.md` (lines 613–701). Deep reference. This note is the pick-up brief.

## Dependencies

- **Prerequisite:** Phase 4 (CMUX-4) merged — provides `agent.claude.session_id` under the namespaced key.
- **Re-justify before starting:** by the time Phases 1–4 land, is the operator already able to rebuild a workspace in ~30s from restored metadata + muscle memory? If yes, Phase 5 shrinks to a `cmux surface recreate` CLI and skips the chip UI.

## Deliverables

### 1. Title-bar resume chip

Renders on restored terminal surfaces. Fallback chain (most specific → least):

1. `agent.claude.session_id` → "Resume Claude session" chip.
2. `agent.codex.session_id` → "Resume Codex session" (when Codex adapter arrives — defer).
3. `directory` exists on disk → "Reopen in `<dir>`".
4. `directory` exists but command unknown → "Restore cwd".
5. `directory` deleted → disabled chip, tooltip: "path no longer exists".

M7 title-bar territory — mount in the existing title-bar chip strip, not a new container.

### 2. Shell-prompt safety gate (mandatory)

**Copy-first is the default.** No heuristic prompt detection in v1 — it requires Ghostty cooperation we don't have.

- Primary click: copy `claude --resume <id>` to clipboard. No injection.
- Menu item "Send to pane": opt-in, gated by one-time confirmation sheet with remember-per-workspace.
- Confirmation body: "This will type the command into your terminal. Continue only if your shell is at a prompt."

This is the "restore historical context" vs "drive active command execution" trust bar — v1 defaults to the former.

### 3. CLI mirror

`cmux surface recreate [<surface-id>]` — emits the command string to stdout. No pane injection, no heredoc, no sourced script. Shell-escape cwds via `ShellEscaping` helper (add if not present).

### 4. Sidebar

No changes. Stale status entries from Phase 3 already signal "pre-restart."

## Localization (all new strings)

Keys for `Resources/Localizable.xcstrings` (English + Japanese):

- `phase5.chip.resume_claude`
- `phase5.chip.reopen_in_dir`
- `phase5.chip.restore_cwd`
- `phase5.chip.unavailable`
- `phase5.menu.copy_command`
- `phase5.menu.send_to_pane`
- `phase5.confirm.send_title`
- `phase5.confirm.send_body`

Use `String(localized: "key.name", defaultValue: "…")` per project CLAUDE.md.

## Feature flag

Ships behind `CMUX_EXPERIMENTAL_SESSION_INDEX=1` (Phase 4's flag). Respects `CMUX_DISABLE_SESSION_INDEX=1`.

## Failure handling

If `claude --resume <id>` exits non-zero within 5s of a "Send to pane" dispatch, show a toast: "Resume failed. Try 'Start fresh Claude session.'" Only when we know we sent it — don't intercept terminal errors from other sources.

## Tests

- `cmuxTests/ResumeChipTests.swift` — chip renders under namespaced metadata; copy-first path; confirmation gate on send-to-pane; disabled state for deleted cwd.
- `cmuxTests/ShellEscapingTests.swift` — `cmux surface recreate` escapes spaces and special characters correctly.
- `tests_v2/test_surface_recreate_cli.py` — populate metadata (including deleted-cwd), run CLI, assert output.
- Localization smoke test: all keys resolve under English and Japanese.

## Size estimate

~200 LoC UI (chip + menu + confirm sheet) + ~80 LoC CLI + ~150 LoC tests + localization. Single PR.

## Open questions

- [ ] "Send to pane" default: permanently opt-in, or offer a workspace-level toggle to "always send without asking"?
- [ ] Codex adapter ordering: bundle with this PR, or land after Codex's session-index arrives in a follow-up?

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Expanded plan stub with the copy-first rationale, fallback chain anchors to restored metadata, localization key list, and CLI mirror spec.
