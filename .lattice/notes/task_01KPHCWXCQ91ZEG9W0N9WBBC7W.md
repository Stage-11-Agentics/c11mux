# CMUX-10 — Persistent, themable surface flash across pane and sidebar tab

Plan for the 2026-05-05 description rewrite. Supersedes the 2026-04-18 note (which only addressed asks 1–2 of the original ticket and used file:line anchors that have since drifted).

## TL;DR

- Asks 1 (sidebar fan-out) and partial-4 (single signal across surfaces) are **already wired** via `Workspace.triggerFocusFlash` → `panel.triggerFlash()` + `bonsplitController.flashTab(tabId)` + `sidebarFlashToken`. The remaining work is mostly recoloring, unifying the envelopes, and adding two new dimensions: **persistence** (stay-pulsing-until-clicked) and **configurable duration**.
- Persistent-flash state lives **per-Workspace in-process** (`Workspace.persistentFlashPanels: Set<UUID>`), with a thin metadata overlay (`flash_state` key, written only on start/cancel) for external agent observability. The animation timer is process-local; the manifest is not abused for per-frame state.
- 5 commits, ~350 LoC app + ~120 LoC tests. Strictly respects the three CLAUDE.md typing-latency hot paths.

## Current state (verified against worktree HEAD)

### Existing flash path

| Concern | Symbol | File:Line |
|---|---|---|
| Panel protocol | `Panel.triggerFlash()` | `Sources/Panels/Panel.swift:117` |
| Terminal conformance | `TerminalPanel.triggerFlash()` | `Sources/Panels/TerminalPanel.swift:278` |
| Browser conformance | `BrowserPanel.triggerFlash()` | `Sources/Panels/BrowserPanel.swift:3097` |
| Markdown conformance | `MarkdownPanel.triggerFlash()` | `Sources/Panels/MarkdownPanel.swift:134` |
| Workspace fan-out (3 channels) | `Workspace.triggerFocusFlash(panelId:)` | `Sources/Workspace.swift:9067` |
| Notification entry point | `Workspace.triggerNotificationFocusFlash(...)` | `Sources/Workspace.swift:9076` |
| Pane ring envelope | `FocusFlashPattern` (values `[0,1,0,1,0]` over 0.9 s) | `Sources/Panels/Panel.swift:41` |
| Sidebar pulse envelope | `SidebarFlashPattern` (peak 0.18 over 0.6 s) | `Sources/Panels/Panel.swift:68` |
| Pane ring renderer | `GhosttySurfaceScrollView.flashLayer` + `triggerFlash(style:)` | `Sources/GhosttyTerminalView.swift:6376, 7577, 8691` |
| Pane ring color (hardcoded) | `flashLayer.strokeColor = cmuxAccentNSColor()` | `Sources/GhosttyTerminalView.swift:6639` |
| Sidebar row pulse | `runSidebarFlashAnimation(token:)` | `Sources/ContentView.swift:11685` |
| Sidebar row fill | `RoundedRectangle.fill(cmuxAccentColor().opacity(sidebarFlashOpacity))` | `Sources/ContentView.swift:11598` |
| Token threading into `TabItemView` | `let sidebarFlashToken: Int` (in `==`) | `Sources/ContentView.swift:11034, 10961` |
| Settings toggle | `NotificationPaneFlashSettings` (UserDefaults `notificationPaneFlashEnabled`) | `Sources/TerminalNotificationStore.swift:535` |
| Settings UI row | "Pane Flash" toggle in Notifications panel | `Sources/c11App.swift:5753` |
| CLI command | `c11 trigger-flash [--workspace] [--surface] [--panel]` | `cli/c11.swift:2288, 8333` |
| Socket dispatch | `surface.trigger_flash` → `v2SurfaceTriggerFlash` | `Sources/TerminalController.swift:2351, 7726` |
| Command palette | `palette.triggerFlash` | `Sources/ContentView.swift:5036, 5313, 5936` |
| Pane click landing | `GhosttyNSView.mouseDown(with:)` | `Sources/GhosttyTerminalView.swift:5835` |
| Sidebar row click landing | `.onTapGesture { updateSelection() }` | `Sources/ContentView.swift:11663` |

### Mapping current state to the 5 asks

| # | Ask | Status |
|---|---|---|
| 1 | Sidebar tab flash alongside pane | **Done.** `Workspace.triggerFocusFlash` already bumps `sidebarFlashToken`. The legacy plan's premise ("today only the pane flashes") is stale. |
| 2 | Persistent mode + `cancel-flash` + click-dismiss | **Not done.** No persistence state, no programmatic cancel, no click-cancel hook. |
| 3 | Default yellow + per-call `--color` + theme key | **Not done.** Hardcoded `cmuxAccentNSColor()` (gold `#c9a84c`). The settings subtitle already says "yellow outline" — the copy lies, ship the truth. |
| 4 | Same color, same envelope, both surfaces | **Partial.** Same color (gold). Different envelopes — pane is a 2-peak ring at 100% opacity over 0.9 s, sidebar is a 1-peak fill at 18% peak over 0.6 s. The "gentle ambient nudge" comment in `SidebarFlashPattern` contradicts the rewritten spec. |
| 5 | Configurable longer one-shot tab duration | **Not done.** Hardcoded. |

### Bonsplit tab strip pulse

`bonsplitController.flashTab(tabId)` (called from `Workspace.triggerFocusFlash`) is a third channel — the tab pill in the in-pane Bonsplit tab strip. Its source lives in the `vendor/bonsplit` submodule (uninitialized in this worktree; pinned at `953c213`). Out of scope for this ticket — leave it alone unless its color lookup also hardcodes `cmuxAccentNSColor`. If it does, expose the same `--color` override; if it sources from a host callback, plumb the chosen color through. Verify in Impl.

## Decisions

1. **Persistent-flash state lives on `Workspace` in-process (Option B), with a thin manifest overlay for observability.** Add `@Published Workspace.persistentFlashPanels: Set<UUID>` plus a per-panel timer. **Why:** writing manifest entries every pulse frame would corrupt the manifest's "declarations, not animation" contract; meanwhile, agents asking "is this surface still calling for attention?" should be able to find out. Compromise: write `flash_state` to surface metadata only on start (`persistent`) and cancel (clear), not per pulse. `c11 cancel-flash` is the programmatic exit.

2. **Default color: yellow.** Lock to a Stage-11-tinted yellow distinct from the gold accent (`#c9a84c`) so the flash reads as "this is a signal, not just chrome." Recommend `#F5C518` (warm yellow, complements gold without colliding). Per-call override `--color <#hex>` validated as 6- or 8-digit hex. Theme key `flash.color` is a forward-compatible no-op: settings provide the default, theme engine (CMUX-9) layers on later.

3. **Full-flash visual unification (ask 4).** Retire `SidebarFlashPattern`'s ambient envelope; reuse `FocusFlashPattern` (or a unified `FlashEnvelope` struct) for both pane and sidebar. Sidebar row keeps the rounded-rect FILL geometry (don't try to ring it; it's a sidebar row, fill is the natural shape) but with the same color and 2-peak temporal pattern as the pane ring. Peak opacity 0.55–0.7 (full 1.0 fill on the row would be visually overbearing in the sidebar context — match envelope/color, scale visual weight).

4. **Click-to-dismiss = dismiss-and-focus.** Click on either pane content or sidebar row → existing focus/selection behavior runs **and** any persistent flash on the target surface clears. Reasoning: the operator clicked because they're acknowledging; give them the surface. Programmatic agents that need silent cancel use `c11 cancel-flash`.

5. **Persistent on focused surface = short one-shot + skip persistence.** If `--persistent` fires and the target is the focused panel of the focused workspace of the focused window, run a single one-shot pulse and decline to register persistent state. Rationale: persistence is "look at this when you eventually look back" — meaningless when the operator is already looking. Still honor `--color` so the signal isn't silenced.

6. **Default Tab Flash Duration: 1500 ms.** Slider bounds 500 – 4000 ms in the settings card. Both pane and sidebar one-shot pulses scale together (same envelope; one duration to tune). Persistent-mode pulse interval = duration + 600 ms gap so the eye registers a beat between repeats.

7. **Sidebar flash respects `paneFlash` toggle.** Already does (single guard at the top of `triggerFocusFlash`). Keep — no second user-facing toggle for v1. The setting subtitle should be retitled in copy (see Localization).

## Open questions for delegator

1. **Yellow shade.** Recommend `#F5C518` (warm, gold-distinct). Alternatives: Apple system yellow `#FFD60A` (sharper); a bespoke Stage-11 signal yellow drawn from the brand palette. Operator's call.
2. **Persistent safety cap.** Should `--persistent` flashes auto-stop after some hard cap (5 min? 30 min?) to avoid a forgotten flash pulsing all night, or trust the operator/agent to clear them? Recommend **no cap** — clarity over paternalism — but flag for review.
3. **Setting copy.** "Tab Flash Duration" is the prompt's suggested label, but in c11 internal copy "tab" = workspace row in sidebar AND pill in Bonsplit strip. Is "Flash Duration" (sans "Tab") cleaner now that it scales both surfaces? Recommend "Flash Duration."

## Implementation plan (commit-by-commit)

### Commit 1 — Refactor: unify flash appearance behind a single seam (~70 LoC)

Lift the hardcoded `cmuxAccentNSColor()` out of `flashLayer` + sidebar fill behind a `FlashAppearance` value type carrying `color: NSColor` + `envelope: FlashEnvelope`. Keep behavior identical (same gold, same envelopes). Pure refactor — passes tests with no spec changes.

- New: `Sources/FlashAppearance.swift` (struct `FlashAppearance`, enum `FlashEnvelope` wrapping the existing `FocusFlashPattern` + `SidebarFlashPattern` constants).
- Edit: `Sources/GhosttyTerminalView.swift` — flashLayer init reads from `FlashAppearance.current()`.
- Edit: `Sources/ContentView.swift` — sidebar fill reads from `FlashAppearance.current()`.

### Commit 2 — Default yellow + `--color` flag + theme key (~80 LoC)

- Edit: `Sources/FlashAppearance.swift` — `static var defaultColor: NSColor = NSColor(srgbRed: 0xF5/255, green: 0xC5/255, blue: 0x18/255, alpha: 1)`. Tag with comment referencing decision #2.
- Edit: `cli/c11.swift:2288` (`trigger-flash` case) — accept `--color <#hex>`; thread into params as `color: "#F5C518"`. Update help block at `cli/c11.swift:8333`. Reject malformed hex with a clear error.
- Edit: `Sources/TerminalController.swift:7726` (`v2SurfaceTriggerFlash`) — accept optional `color` param, validate hex, default to `FlashAppearance.defaultColor`, pass into a new `triggerFocusFlash(panelId:appearance:)` overload on `Workspace`.
- Edit: `Sources/Workspace.swift:9067` — overload accepts `appearance: FlashAppearance`; existing zero-arg overload calls through with `.current()`. Threads color into pane `triggerFlash`, sidebar render, bonsplit pulse if it accepts a color callback.
- Edit: `Sources/c11App.swift:5755` — settings subtitle update (English): "Briefly flash a yellow outline when c11 highlights a pane." stays correct; verify translator regen.
- Theme key `flash.color`: leave a TODO + 1-line read-from-theme-when-engine-lands shim. No theme engine touch this commit — explicit forward-compat no-op.

### Commit 3 — Full-flash visual unification (~50 LoC)

Retire `SidebarFlashPattern` in favor of a single `FlashEnvelope.unified` (the existing pane envelope at 0.9 s, with peak opacity scaled per-channel: 1.0 for the pane ring, 0.6 for the sidebar fill so it doesn't overpower the row).

- Delete: `SidebarFlashPattern` enum (`Sources/Panels/Panel.swift:68-87`).
- Edit: `Sources/ContentView.swift:11685` (`runSidebarFlashAnimation`) — drive from `FlashAppearance.current().envelope` + a per-channel peak scalar.
- Edit: `Sources/Panels/Panel.swift:64-67` — replace the "polite ambient nudge" comment with one referencing the unified-envelope decision.

### Commit 4 — Persistent mode + `cancel-flash` + click-to-dismiss (~120 LoC)

This is the load-bearing commit.

- Edit: `Sources/Workspace.swift:9067` — add `@Published var persistentFlashPanels: [UUID: PersistentFlashState] = [:]` (state = appearance + last-tick timestamp). Refactor `triggerFocusFlash` to accept `persistent: Bool`; if persistent and not the focused panel in the focused workspace in the focused window, register state + start a per-panel timer that re-fires the envelope every `flashDuration + 600 ms`. Cancel = remove from dict + invalidate timer + clear `flash_state` metadata.
- Edit: `cli/c11.swift` — add `--persistent` to `trigger-flash`; add new `cancel-flash` command with help block. Both thread to socket.
- Edit: `Sources/TerminalController.swift` — add `surface.cancel_flash` dispatch (mirror `v2SurfaceTriggerFlash` with cancel semantics). Off-main argument parsing per the socket-threading policy.
- Edit: `Sources/c11App.swift` (`handleSurfaceMetadata` style hook) — write surface metadata key `flash_state=persistent` on start, clear on cancel.
- Edit: `Sources/GhosttyTerminalView.swift:5835` (`GhosttyNSView.mouseDown`) — early hook: if owning workspace has a persistent flash for this panel, call `cancelPersistentFlash(panelId:)` before existing logic. No allocations on the keystroke path; `mouseDown` is mouse-only so the typing hot-path is unaffected.
- Edit: `Sources/ContentView.swift:11663` (`TabItemView.onTapGesture`) — call workspace's `cancelAllPersistentFlashes()` alongside `updateSelection()`.
- Edit: `Sources/Panels/BrowserPanel.swift` and `Sources/Panels/MarkdownPanel.swift` — add a parallel `persistentFlashActive: Bool` published flag (or similar) and click-to-dismiss in their respective view layers (`BrowserPanelView`, `MarkdownPanelView`). The pane ring renderer for these panels already lives in their SwiftUI views.

### Commit 5 — Configurable Flash Duration setting (~50 LoC)

- New: `NotificationFlashDurationSettings` enum in `Sources/TerminalNotificationStore.swift` (sibling of `NotificationPaneFlashSettings`). `enabledKey = "notificationFlashDurationMs"`, `defaultMs = 1500`, `minMs = 500`, `maxMs = 4000`.
- Edit: `Sources/c11App.swift:5763` — add `SettingsCardRow` with a `Slider(500…4000, step: 100)` after the Pane Flash toggle. Localized title/subtitle. AppStorage-backed.
- Edit: `Sources/FlashAppearance.swift` — `FlashEnvelope.duration` reads from `NotificationFlashDurationSettings.currentMs / 1000`. Re-export a helper that other call sites use.

### Commit 6 — Tests, CLI help text, docs touch (~120 LoC tests, ~30 LoC docs)

- New: `cmuxTests/WorkspaceFlashTests.swift` — exercises one-shot, persistent register/cancel, focused-surface short-circuit, color override.
- New: `cmuxTests/FlashColorParsingTests.swift` — `--color` hex validation.
- New: `tests_v2/test_trigger_flash_persistent.py` — round-trip socket integration: trigger + persistent + cancel. Connects to tagged-build socket per `CLAUDE.md` policy. Visual assertions are deferred to Validate phase.
- Edit: `cli/c11.swift` help blocks for `trigger-flash` (add `--persistent` and `--color`) and new `cancel-flash` block.
- Edit: `docs/c11mux-theming-plan.md` if it references flash color — note that `flash.color` is now a live key with a default, just not read from theme yet.

**Per CLAUDE.md: tests are NOT run locally.** Plan is to push and let the GitHub Actions / VM matrix run them. Impl phase pushes after green local typecheck only.

## Tests & validation plan

### Unit (CI-only)

- `WorkspaceFlashTests`:
  - `testTriggerFocusFlashFansOutToAllChannels` — bumps `sidebarFlashToken`, calls panel `triggerFlash`, calls `bonsplitController.flashTab` (mock).
  - `testPersistentFlashRegisters` — `persistent: true` adds to `persistentFlashPanels`.
  - `testCancelFlashClears` — direct cancel removes from set + clears metadata.
  - `testFocusedSurfacePersistentDegradesToOneShot` — when target is focused, no entry in `persistentFlashPanels` after trigger.
- `FlashColorParsingTests`:
  - Valid 6- and 8-digit hex parse to expected NSColor.
  - Malformed input returns nil / throws.

### Integration (CI / VM only)

- `tests_v2/test_trigger_flash_persistent.py`:
  - `c11 trigger-flash --surface <ref>` returns OK (existing path).
  - `c11 trigger-flash --surface <ref> --persistent` returns OK + writes `flash_state=persistent` in surface metadata.
  - `c11 cancel-flash --surface <ref>` returns OK + clears the metadata key.
  - `c11 trigger-flash --color #FF00FF` returns OK; (visual assertion deferred).

### Validate phase (computer use, fresh sibling surface)

Per the prompt's smoke list:

1. One-shot flash on focused pane (control case).
2. One-shot flash on a surface in a non-focused workspace → workspace row visibly flashes.
3. `--persistent` → pulses; click pane → dismisses; pulses again; click sidebar row → dismisses.
4. `c11 cancel-flash --surface <ref>` while pulsing → stops cleanly.
5. `--color #FF00FF` → magenta pulse renders.
6. Settings → Notifications → Flash Duration → adjust → next non-persistent flash visibly longer.
7. Typing latency on a focused terminal pane subjectively unchanged; objective check is "TabItemView still skips body re-eval" (verified by performance overlay or Instruments sampling).

Smoke is exercised in a tagged build (`./scripts/reload.sh --tag flash-cmux10`). The Validate sub-agent gets the tag + the smoke list + screenshot expectations; it reports artifacts back via Lattice comment.

## Hot path notes (CLAUDE.md compliance)

1. **`TabItemView` (`Sources/ContentView.swift:10940`).** Already includes `sidebarFlashToken: Int` in `==`. **Plan does not add any `@EnvironmentObject` / `@ObservedObject` / `@Binding` to `TabItemView`.** Click-cancel calls a method on the existing `tabManager` reference (already a plain reference, not observed). If the persistent state needs to render a different visual on the row (e.g. the row stays slightly tinted between pulses to signal "persistent in flight"), thread an additional precomputed scalar like `let sidebarFlashPersistentActive: Bool` through `TabItemView` and add it to `==`. Do NOT subscribe to a workspace-level `@Published` from within `TabItemView`'s body — read it via the same parent-ForEach precompute pattern that `sidebarFlashToken` uses.

2. **`WindowTerminalHostView.hitTest` (`Sources/TerminalWindowPortal.swift`).** Flash overlays are mounted as `GhosttyFlashOverlayView` instances which return nil from `hitTest` (`Sources/GhosttyTerminalView.swift:6321`). Any new persistent-flash visual must use the same passthrough pattern. The persistent-flash-cancel hook in `mouseDown` is gated to mouse events (not keyboard) by virtue of being on `mouseDown`, not `keyDown` — no work added to the keystroke path.

3. **`TerminalSurface.forceRefresh` (`Sources/GhosttyTerminalView.swift`).** The flash code path does NOT touch `forceRefresh` — flash is a sibling overlay layer animation, not a Ghostty surface redraw trigger. Confirmed by reading the call graph; new code stays out of `forceRefresh`.

## Localization checklist (Translator phase)

New / updated keys (English defaults shown; Translator regenerates ja, uk, ko, zh-Hans, zh-Hant, ru):

- `settings.notifications.flashDuration.title` = "Flash Duration"
- `settings.notifications.flashDuration.subtitle` = "How long the flash pulse lasts before fading."
- `settings.notifications.flashDuration.unit.ms` = "%d ms" (used in the slider value label)
- `cancel.flash.command.title` (if added to command palette) = "Cancel Flash" / `cancel.flash.command.subtitle` = "View"
- `flash.error.invalidColor` = "--color must be a hex value like #F5C518."
- Confirm `settings.notifications.paneFlash.subtitle` ("Briefly flash a yellow outline when c11 highlights a pane.") still reads correctly with the new behavior (it does).

CLI help text is English-only (consistent with the rest of `cli/c11.swift`'s help blocks) — not subject to xcstrings.

## Do NOT ship (out of scope)

- The full theming engine. `flash.color` is a forward-compat no-op key; CMUX-9 (when it lands) reads from theme. We do not ship a theme schema file in this PR.
- A second user-facing toggle for sidebar flash. Sidebar rides on the existing `paneFlash` toggle.
- Any sound / haptic. Spec is purely visual.
- Window-frame / traffic-light flash. Out of spec.
- Bonsplit submodule changes unless `flashTab` hardcodes color. If it does, that's a separate upstream PR.
- Per-workspace persistent-flash safety cap (operator can dismiss; agents have `cancel-flash`).

## Size estimate

5 commits, ~350 LoC app + ~120 LoC tests + ~30 LoC docs/help. Single PR.

## Plan pass 2026-05-05 by agent:claude-opus-4-7-cmux-10-plan
