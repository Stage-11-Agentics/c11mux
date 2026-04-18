# Adversarial Review Synthesis — c11mux Pane Dialog Primitive

- **Plan**: `docs/c11mux-pane-dialog-primitive-plan.md`
- **Reviewers**: Claude (Opus), Codex, Gemini — all adversarial posture
- **Synthesis date**: 2026-04-18
- **Verdict**: All three models converge on **not ready for execution**. Rework scope roughly 30–60% of current plan before Phase 1 is safe.

---

## Executive Summary

Three independent adversarial reviewers arrive at overlapping, load-bearing concerns. The plan reads tight but has not been code-walked deeply enough. The primitive is small; the **integration surface is the hard part**, and the plan's own claims on that surface are materially wrong in at least three places:

1. **Cmd+D accept shortcut is not dead code.** It is wired through `AppDelegate.swift:9020-9050` and asserted by `cmuxUITests/CloseWorkspaceCmdDUITests.swift:10-28`. A SwiftUI overlay breaks that path — a CI failure is near-certain.
2. **The portal z-order "verify in Phase 4" is not a Schrödinger question.** The CLAUDE.md Pitfalls contract already mandates AppKit-layer mounting for overlays sitting above Ghostty portals (`SurfaceSearchOverlay`). Mounting `PaneDialogOverlay` from the SwiftUI side is the opposite of that contract. The listed fallback is almost certainly the day-one requirement.
3. **Replacing `NSAlert.runModal()` with an async non-modal overlay is a behavior change, not an API change.** `NSApp.modalWindow` becomes `nil` during the prompt, silently removing the `AppDelegate.swift:9054` gating that dozens of shortcut handlers rely on. `.allowsHitTesting(false)` only blocks mouse events; keyboard events still flow via global NSEvent monitors and AppKit first responder.

Add to that the Codex-unique finding that **the plan targets the wrong seam entirely** for tab-close confirmations — the explicit tab close path flows through `Workspace.confirmClosePanel` via Bonsplit delegate, not `TabManager.confirmClose` — and the plan as written is likely to ship "pane dialogs" while leaving the most common close flow still on `NSAlert`.

If even one of these lands, the "small PR" is a bad week of bug-hunting.

---

## 1. Consensus Risks (flagged by 2+ models)

Ordered by severity.

1. **Portal z-order: SwiftUI overlay will be hidden by the AppKit Ghostty portal.** *(Claude, Codex, Gemini — unanimous)*
   - CLAUDE.md Pitfalls explicitly mandates that `SurfaceSearchOverlay` be mounted from `GhosttySurfaceScrollView` (AppKit) for exactly this reason.
   - Plan mounts `PaneDialogOverlay` on the SwiftUI side of the contract (`Sources/Panels/TerminalPanelView.swift:19-41`).
   - Codex adds: same hazard applies to Browser. `Sources/Panels/BrowserPanelView.swift:445-456, 1120-1145` documents portal layering hazards with `WKWebView` — the plan's "browser = low risk, no portal hazard" assertion is false.
   - Gemini adds: clipping-bounds mismatches and AppKit rendering over SwiftUI are the standard failure mode.
   - **Implication**: The listed "fallback" mount inside `GhosttySurfaceScrollView` is the day-one requirement — which invalidates the clean SwiftUI architecture of Phase 3 and roughly doubles that phase's scope.

2. **Cmd+D destructive-accept shortcut is broken by the migration.** *(Claude, Codex)*
   - Plan §8 Q2 claims `acceptCmdD` is "plumbed through but not observably used" — **wrong**.
   - Live wiring at `AppDelegate.swift:9020-9050` (specifically `:9036-9049`) walks `NSApp.windows` looking for an `NSPanel` with one of five hard-coded `closeConfirmation*.title` static-text strings, then calls `performClick` on the button titled `common.close`.
   - `cmuxUITests/CloseWorkspaceCmdDUITests.swift:10-28` asserts this exact flow.
   - A SwiftUI overlay has no `NSPanel`, no matching static-text string, and the button title in `ConfirmContent.confirmLabel` is localized ("Close"), not `common.close`.
   - **Plan has no replacement mechanism for Cmd+D. Phase 7 UI tests will red CI.**

3. **Focus/keyboard suppression is underspecified and probably insufficient.** *(Claude, Codex, Gemini)*
   - Plan relies on `.allowsHitTesting(false)` for input suppression. That only blocks mouse events.
   - Keyboard continues to flow via: (a) AppKit first responder still held by the terminal's `NSView`, (b) global `NSEvent` monitors that `cmux` uses for shortcuts, (c) WKWebView JS handlers in browser panels (`BrowserPanelView.swift:6220-6263` actively reassigns first responder to WKWebView), (d) IME composition state if active on the terminal at mount time.
   - Plan proposes "grep `makeFirstResponder` and add a guard" — but Codex notes those methods in `GhosttyTerminalView.swift:6125-6160, 7739-7818` do not have a `terminalPanel` reference in scope.
   - Plan never outlines how the SwiftUI overlay *acquires* AppKit first responder on appearance or *restores* it on dismissal.

4. **Sync → async control-flow flip has unexplored ripple effects.** *(Claude, Gemini)*
   - `NSAlert.runModal()` was a synchronization point. Replacing it with `Task { await confirmCloseInPanel(...) }` means callers return immediately, leaving a zombie "closing" state.
   - Gemini: what does `Cmd+Q` (Quit) do when `closeWorkspaceIfRunningProcess` returns immediately? Nothing waits for the dialog to resolve.
   - Claude: the `AppDelegate.swift:9054` guard `if NSApp.modalWindow != nil || NSApp.keyWindow?.attachedSheet != nil { return false }` silently stops gating custom shortcuts. Expect shortcut collisions while the card is up.
   - Plan audits "9 callsites" but the audit list (below, finding #5) is factually off.

5. **Feature leaves real close paths on NSAlert.** *(Codex, Gemini; Claude via different lens)*
   - Codex (factual): explicit tab close goes through `Workspace.confirmClosePanel` → `splitTabBar(_:shouldCloseTab:inPane:)` (`Sources/Workspace.swift:8931-8958, 9321-9394`), *not* `TabManager.confirmClose`. Plan does not migrate this path.
   - Gemini (UX): maintaining NSAlert for bulk closes is "corrosive" — once users learn the pane dialog, Cmd+Shift+W suddenly showing a window-centered alert will feel like a bug.
   - Claude (UX): anchoring a workspace-wide confirmation on a single focused panel is semantically misleading when multiple panels have running processes.

6. **UI test coverage degrades silently.** *(Claude, Codex)*
   - Existing tests detect an `NSAlert`/`NSPanel` hierarchy that no longer exists on the happy path.
   - Plan adds a "fourth detector" for the overlay but keeps the three NSAlert detectors as fallbacks. All three will now return false on the happy path; tests pass if *detection* succeeds even when the *user flow* is broken (scrim swallows taps, z-order hidden, accessibility id missing).
   - Codex: `cmuxUITests/CloseWorkspaceConfirmDialogUITests.swift:48-63` helpers are alert/dialog-centric and likely need broader updates than Phase 7 admits.

7. **Card width vs. dense layouts.** *(Claude, Gemini)*
   - Min 260pt, max 420pt. In a 4×4 layout on a 13" laptop, a panel can be narrower than 260pt.
   - Plan's "card centered in panel bounds" promise breaks. Either the card overflows (and scrim bounds break) or it clips.
   - Claude: the 4×4 density argument is the plan's motivation yet Phase 8 matrix doesn't test 4×4.

8. **Risk ratings are optimistic in the wrong places.** *(Codex, Claude)*
   - Portal hazard rated "Medium" in plan §7 — actually expected.
   - Browser rated "Low, no portal hazard" — wrong (see #1).
   - "Typing latency: Very Low" — unbenchmarked (see Claude Uncomfortable Truth #4; `TerminalPanelView` does not use `.equatable()` opt-out unlike `TabItemView`).
   - "Coordination with textbox-port: Low, rebases trivially" — a ZStack-vs-VStack restructure on the same file. Optimistic.

---

## 2. Unique Concerns (single-model)

### Claude-unique

1. **`NSApp.modalWindow` gating disappears app-wide.** `AppDelegate.swift:9054` is a hard guard for the custom-shortcut dispatcher; dozens of shortcuts rely on it. No replacement policy proposed. *(This is also flagged adjacent by Gemini's "focus trap" argument, but Claude cites the specific line.)*
2. **Notification clearing silently dropped.** `TabManager.swift:2490` calls `AppDelegate.shared?.notificationStore?.clearNotifications(forTabId:surfaceId:)` after close. Plan §4.6 rewrite shows only `_ = tab.closePanel(surfaceId, force: true)`. Unread badge persists after close.
3. **Multi-window behavior undefined.** Window A has a card on a panel; user Cmd+Tabs to window B and triggers close. Does A's card block B? Plan says "other windows remain fully interactive" but "suppressed" isn't defined across windows.
4. **Browser JS `window.confirm()` is orthogonal and will confuse users.** `BrowserPanelView.swift:1782-1819` has `dialogTelemetryHookBootstrapScriptSource`. Pages calling JS `confirm()` will not use the new card. Scope-confusion bug magnet.
5. **Panel reparent mid-dialog.** Dragging a tab across workspaces via bonsplit re-creates the hosting view; overlay's presenter binding may drop or re-bind. `.id(panel.id)` may not hold identity across cross-workspace moves.
6. **`.textInput` forward-compatibility claim is not load-bearing.** `ConfirmContent.completion: (Bool) -> Void` cannot generalize to `(String?) -> Void` without generics or `Any`. The "additive rename refactor" promise is marketing, not a proven type design.
7. **No feature flag / kill switch.** If portal z-order is wrong in a shipped release, there is no way to disable per-install short of a code revert. An `AppStorage("cmux.paneDialog.enabled")` would let Phase 9 ship safely.
8. **Per-panel FIFO queue is an API-shape default, not a UX decision.** Double-triggering a close is almost always user retry; showing two dialogs in sequence confuses. Stricter duplicate-drop policy is more humane but not considered.
9. **Two-handler test seam is over-engineered.** `confirmCloseHandler` + `confirmCloseInPanelHandler` duplicates test scaffolding. A single handler with a `DialogRoute` enum is more expressive.
10. **Scrim-click-to-dismiss blocking trains users to hunt for Cancel.** Every other macOS dialog allows it. Softer policy (focus Cancel instead of dismiss) is considered and dismissed in one line.
11. **Persistence interaction.** Tier-1 persistence plan might snapshot a workspace mid-dialog. Restored workspace may have a stale pending completion waiting to fire.
12. **Name encoding.** `PaneDialog` doesn't encode the one-panel constraint. `PanelLocalConfirm` or `AnchoredDialog` would.

### Codex-unique

1. **`Workspace.confirmClosePanel` is the missed seam.** Called from `splitTabBar(_:shouldCloseTab:inPane:)`. If untouched, "replace NSAlert" goal is incomplete for explicit tab close operations. *(Arguably the single most important factual finding in the pack.)*
2. **`MarkdownPanel` also conforms to `Panel` (`Sources/Panels/MarkdownPanel.swift:20-23`).** Plan claims only Terminal and Browser need presenter conformance. Adding `dialogPresenter` to the protocol forces markdown to add it too — or the plan must carve out a narrower capability.
3. **Access-control mismatch.** `public protocol Panel` adds `dialogPresenter: PaneDialogPresenter` (plan §210-214) while `PaneDialogPresenter` is declared non-public in §102-107. Won't compile as written.
4. **Duplicate localization keys.** New `dialog.pane.confirm.close` / `.cancel` unnecessary when `dialog.closeTab.close` / `.cancel` already exist translated at `Resources/Localizable.xcstrings:29376, 29489`. I18n debt + drift risk.
5. **Non-selected workspace close anchoring undefined.** Sidebar rows (`ContentView.swift:10900, 11138`) can target non-selected workspaces. Non-selected workspace views are non-hit-testable at `ContentView.swift:2075`. Plan anchors on `workspace.focusedPanelId` but no visibility/interaction fallback.

### Gemini-unique

1. **Zombie process race.** While a pane is waiting for a dialog response, what if the underlying process exits naturally? Does the dialog auto-dismiss? Does the pane close? Race between Cancel and natural termination unhandled.
2. **Overlapping modals.** If a settings-sheet NSAlert fires while a pane dialog is visible, z-order between the window-modal NSAlert and the pane-local SwiftUI overlay is undefined.
3. **Window resizing / Bonsplit reflow.** Rapid resize while dialog is up: bounds might shrink below min size, `.id(panel.id)` doesn't prevent layout-reflow-induced visual detach.
4. **VoiceOver trap risk.** Plan marks "Unknown" in risk register with a one-line mitigation. Gemini escalates to a probable regression class.
5. **User feedback for blocked input.** If user clicks the scrim (which doesn't dismiss), is there a flash/beep/focus cue? Plan is silent — users will think the app is frozen.

---

## 3. Factual Errors in the Plan

Every claim where a reviewer asserts the plan is wrong about how the code actually works.

1. **[§8 Q2] `acceptCmdD` is "plumbed through but not observably used."**
   - **False.** Wired at `Sources/AppDelegate.swift:9020-9050` (specifically `:9036-9049`); asserted by `cmuxUITests/CloseWorkspaceCmdDUITests.swift:10-28`.
   - *Reviewers: Claude, Codex.*

2. **[§4.6] 9-callsite audit list.**
   - Plan cites `ContentView.swift:5694`, `cmuxApp.swift:1055, 1163`, `AppDelegate.swift:9506-9508, 9558` as callsites needing audit.
   - **Most of those point at `closeCurrentWorkspaceWithConfirmation`, `closeWorkspacesWithConfirmation`, or `closeOtherTabsInFocusedPaneWithConfirmation`** — paths the plan explicitly does **not** convert.
   - Actual audit surface is one caller of `closeRuntimeSurfaceWithConfirmation` at `Sources/GhosttyTerminalView.swift:1129` and two of `closeWorkspaceIfRunningProcess` at `Sources/TabManager.swift:2213, 2243`.
   - *Reviewer: Claude.*

3. **[§4.5] Browser has no portal hazard.**
   - **False.** `Sources/Panels/BrowserPanelView.swift:445-456, 1120-1145` documents portal layering hazards and the search overlay is mounted in AppKit portal specifically to avoid being hidden by portal-hosted `WKWebView`.
   - *Reviewer: Codex.*

4. **[§1 / §2 / §3.4] Tab close confirmations live in `TabManager.confirmClose`.**
   - **Incomplete.** Explicit close confirmations route through `Workspace.confirmClosePanel` (`Sources/Workspace.swift:8931-8958, 9321-9394`) via Bonsplit delegate `splitTabBar(_:shouldCloseTab:inPane:)`. Plan does not migrate this path.
   - *Reviewer: Codex.*

5. **[§4.2] Only Terminal and Browser need presenter conformance.**
   - **False.** `MarkdownPanel` conforms to `Panel` (`Sources/Panels/MarkdownPanel.swift:20-23`). Plan's additive protocol requirement forces a third implementation.
   - *Reviewer: Codex.*

6. **[§3.1 / §3.2 / §4.2] Access-control consistency.**
   - `public protocol Panel` requires `dialogPresenter: PaneDialogPresenter` but the presenter in the code snippet is not declared `public`. Won't compile as shown.
   - *Reviewer: Codex.*

7. **[§4.7] Focus-guard pattern `if terminalPanel.dialogPresenter.current != nil { return }`.**
   - **Non-viable as written.** Methods in `Sources/GhosttyTerminalView.swift:6125-6160, 7739-7818` don't have a `terminalPanel` reference in scope.
   - *Reviewer: Codex.*

8. **[§4.6 rewrite] Notification clearing dropped.**
   - Current `TabManager.swift:2490` calls `AppDelegate.shared?.notificationStore?.clearNotifications(forTabId:surfaceId:)`. Plan's rewrite shows only `_ = tab.closePanel(surfaceId, force: true)`. Silent behavior loss.
   - *Reviewer: Claude.*

9. **[§7 Risk register] "Coordination with textbox-port: rebases trivially."**
   - Both plans touch `Sources/Panels/TerminalPanelView.swift` with structural restructures (ZStack vs. VStack wrap). Will conflict, not trivially.
   - *Reviewer: Claude.*

10. **[§3.3 vs §8 Q4] Internal inconsistency on button styling.**
    - §3.3 specifies gold-accent BrandColor for confirm. §8 Q4 recommends destructive red. Plan contradicts itself.
    - *Reviewer: Claude.*

---

## 4. Assumption Audit (merged and deduplicated)

### Load-bearing (plan breaks if false)

1. **A SwiftUI overlay mounted in `TerminalPanelView` / `BrowserPanelView` renders above the Ghostty portal / WKWebView.**
   Status: **Almost certainly false.** Contradicts CLAUDE.md Pitfalls contract; contradicts `BrowserPanelView.swift:445-456` comments.
   *(Claude, Codex, Gemini)*

2. **`acceptCmdD` is dead code; removing or stubbing is safe.**
   Status: **False.** See Factual Error #1. *(Claude, Codex)*

3. **`.allowsHitTesting(false)` suffices to suppress input to the panel beneath.**
   Status: **False for keyboard.** Blocks mouse only. AppKit first responder, NSEvent monitors, WKWebView JS handlers, IME composition all unaffected.
   *(Claude, Codex, Gemini)*

4. **Sync-to-async flip is safe because most callers are fire-and-forget.**
   Status: **Risky.** `Cmd+Q` quit, `NSApp.modalWindow` gating (`AppDelegate.swift:9054`), and any state-reading-after-call path break silently.
   *(Claude, Gemini)*

5. **Tab close confirmations flow through `TabManager.confirmClose`.**
   Status: **Incomplete.** `Workspace.confirmClosePanel` is the real seam for explicit closes. *(Codex)*

6. **Only Terminal and Browser conform to `Panel`.**
   Status: **False.** `MarkdownPanel` also conforms. *(Codex)*

7. **Grep-and-guard every `makeFirstResponder` callsite is practical maintenance.**
   Status: **Fragile.** ~20 sites in `GhosttyTerminalView.swift` alone; `terminalPanel` not in scope at key sites. Better: invert with a single policy check inside `scheduleAutomaticFirstResponderApply` / `applyFirstResponder`. *(Claude, Codex)*

8. **Panel min-width 260pt always fits within a panel's bounds.**
   Status: **False at dense layouts.** A 150pt-wide panel in 4×4 on a 13" laptop cannot hold a 260pt card. *(Claude, Gemini)*

9. **`.id(panel.id)` keeps the overlay stable across structural changes.**
   Status: **Unverified.** Cross-workspace reparenting via bonsplit may re-create the hosting view. *(Claude, Gemini)*

10. **`panel.dialogPresenter.present(...)` works from any `Task { @MainActor in }` without timing issues.**
    Status: **Unproven.** Race windows between await continuation and overlay render. Workspace-destroy mid-flight is undefined. *(Claude)*

11. **Presenter state is ephemeral; no persistence interaction.**
    Status: **Unverified.** Tier-1 persistence plan may snapshot workspace mid-dialog. *(Claude)*

### Cosmetic / likely safe

1. Unique per-panel dialog IDs via `UUID` in `ConfirmContent.id`.
2. `@Published private(set) var current` does not, in isolation, regress typing latency (but see Uncomfortable Truth #4 about unbenchmarked `TerminalPanelView` body re-eval).
3. Two new localization keys — technically safe but unnecessary duplication of existing `dialog.closeTab.*` keys. *(Codex flags as debt.)*

---

## 5. Uncomfortable Truths (recurring across models)

1. **"Pane-local modal" sounds scoped but crosses TabManager, Workspace/Bonsplit delegate, AppDelegate shortcut policy, terminal focus, browser portal layering, UI tests, i18n, and persistence.** This is a rewrite of the app's control-flow and focus hierarchy disguised as a visual refresh. *(Codex, Gemini)*

2. **The plan is written at a detail level that implies it has been code-walked, but hasn't.** The `acceptCmdD` claim, the 9-callsite list aimed at unchanging paths, the "BrowserPanel needs verification" caveat in §4.2, and the missed `Workspace.confirmClosePanel` seam all point to skimming rather than reading. This is the single strongest argument for a pre-Phase-1 pause. *(Claude; consistent with Codex's factual findings)*

3. **Risk ratings are optimistic in exactly the wrong places.** Portal hazard "Medium" → actually expected. Browser "Low, no portal hazard" → wrong. Typing latency "Very Low" → unbenchmarked. Coordination with textbox-port "Low, trivial rebase" → structural file conflict. *(Codex, Claude)*

4. **The "Phase 3 mitigation" (mount inside `GhosttySurfaceScrollView`) is not a fallback — it's the only path that works.** Once accepted, that invalidates the clean SwiftUI architecture of Phase 3, forces two overlay-mount strategies (terminal vs. browser), changes `FocusState`/`.onKeyPress` behavior inside an `NSHostingView`, and roughly doubles the phase. *(Claude, Gemini)*

5. **Shipping with only one consumer (confirm-close) while leaving NSAlert for other close paths makes the app look unfinished — and the `.textInput` "forward compat" reservation won't carry the rename refactor.** The `completion: (Bool) -> Void` shape doesn't generalize to `(String?) -> Void` without rewriting the primitive. *(Gemini UX, Claude type-theory)*

6. **`NSAlert.beginSheetModal(for:)` exists for a reason.** Building a custom pane-scoped modal introduces massive engineering overhead for a visual gain — responder chain, window dimming, accessibility, VoiceOver, IME all need to be re-solved. *(Gemini)*

7. **The plan should have been written as "extract the policy layer first, then skin with SwiftUI."** Starting with the SwiftUI primitive and back-filling policy means we'll reintroduce app-modal behavior piece by piece under the overlay in post-ship weeks. *(Claude)*

8. **"Small PR" sizing is unjustified.** At minimum: split into (PR1) primitive + protocol + wiring behind a feature flag; (PR2) flip callers, wire Cmd+D, remove flag. *(Claude)*

---

## 6. Consolidated Hard Questions for the Plan Author

Deduplicated, numbered, grouped by theme. Where a question was raised by multiple reviewers, attribution follows.

### Cmd+D and shortcut parity

1. What is the behavior when the user presses Cmd+D on the new pane overlay? Where does the translator live? Does `CloseWorkspaceCmdDUITests` pass as-written, or does it need rewriting? *(Claude, Codex)*
2. Since the new overlay is not app-modal, what replaces the `AppDelegate.swift:9054` guard (`NSApp.modalWindow != nil || attachedSheet != nil`) for gating custom shortcuts while a confirmation is visible? Is there a synthesized pseudo-modal-window flag on `TabManager`? Per-panel gating? What about shortcuts targeting a different window? *(Claude)*
3. What is the explicit replacement for the current NSPanel-specific shortcut forwarding at `AppDelegate.swift:9036-9049`? *(Codex)*

### Portal z-order and focus

4. Exactly how does `PaneDialogOverlay` steal AppKit first responder from the `GhosttyTerminalView` / `WKWebView` on appear? And how does it restore focus to the exact terminal surface on cancel? *(Gemini, Claude)*
5. Have you prototyped mounting the overlay from `GhosttySurfaceScrollView` (AppKit layer) and verified `FocusState` / `.onKeyPress` still work inside an `NSHostingView`? *(Claude)*
6. Why does the plan classify browser as "no portal hazard" when `BrowserPanelView.swift:445-456, 1120-1145` explicitly documents WKWebView portal layering? *(Codex)*
7. What is the concrete plumbing to let Ghostty focus code at `GhosttyTerminalView.swift:6125-6160, 7739-7818` check dialog state when those methods lack a direct panel reference? *(Codex)*

### Scope and missed seams

8. Are you intentionally leaving `Workspace.confirmClosePanel` (`Workspace.swift:8931-8958`) on NSAlert? If so, which user-triggered close paths remain NSAlert by design, and is that the intended end state? *(Codex)*
9. If `Panel` gets `dialogPresenter`, what is the intended behavior for `MarkdownPanel` (`MarkdownPanel.swift:20-23`)? *(Codex)*
10. Which callers of the two in-scope functions have you actually audited? Specifically `GhosttyTerminalView.swift:1129` (the one direct caller of `closeRuntimeSurfaceWithConfirmation`) and `TabManager.swift:2213, 2243` (callers of `closeWorkspaceIfRunningProcess`). *(Claude; Claude also notes the §4.6 "9 callsites" list mostly points at unchanged functions.)*
11. How will pane dialogs behave for non-selected workspace close actions from sidebar rows (`ContentView.swift:10900, 11138`) when non-selected workspaces are non-hit-testable (`ContentView.swift:2075`)? *(Codex)*
12. Do you want one primitive for both "panel close" and "workspace close," or should workspace close use a different affordance because the destructive scope is larger than one panel? *(Codex, Claude)*

### Async / control-flow

13. When `closeWorkspaceIfRunningProcess` returns immediately (spawning an async Task), how do callers like `Cmd+Q` (Quit) know to wait for the dialog to resolve before terminating the app? *(Gemini)*
14. Which unit tests (`cmuxTests/TabManagerUnitTests.swift:132-272`, `:259-281`) expect synchronous close effects, and where is their async adaptation called out in phases? *(Codex, Claude)*
15. If `dialogPresenter.clear()` fires completion with `false` because the pane is closing due to a process exit (not user action), what downstream side effects trigger in the `Task` spawned by `closeWorkspaceIfRunningProcess`? *(Gemini)*
16. Does the new `closeRuntimeSurfaceWithConfirmation` still call `AppDelegate.shared?.notificationStore?.clearNotifications(forTabId:surfaceId:)` after accept? Plan's snippet omits it. *(Claude)*

### Layout / UX

17. How will the dialog render if the panel is resized to 100pt, given the 260pt minimum-width constraint? Does the card shrink, overflow, or clip? Have you measured 13" laptop 4×4 default layouts? *(Gemini, Claude)*
18. What is the user feedback when the scrim is clicked (doesn't dismiss)? Flash? Beep? Focus ring pulse? Without feedback, users will think the app is frozen. *(Gemini)*
19. `§3.3` says gold confirm; `§8 Q4` says destructive red. Which is it, and what does a red-confirm-with-gold-focus-ring look like visually? *(Claude)*
20. Does the dialog auto-dismiss if the underlying process exits while the user is deciding? What is the race policy? *(Gemini)*
21. What is the behavior when a settings-sheet NSAlert fires while a pane dialog is visible? Z-order is undefined. *(Gemini)*
22. What is the behavior when the window is aggressively resized during a dialog, shrinking panel bounds below the card's minimum size? *(Gemini)*
23. Panel A is mid-dialog when the user drags its parent tab into window B via bonsplit. What happens to the card? The continuation? Does `.id(panel.id)` actually hold identity across cross-workspace moves? *(Claude, Gemini)*

### Forward-compat and follow-up

24. Given `completion: (Bool) -> Void` is locked into `ConfirmContent`, what's the concrete type signature for `TextInputContent.completion`? Walk me through what the rename PR's diff looks like without rewriting `PaneDialog`. *(Claude)*
25. Why two handlers (`confirmCloseHandler` + `confirmCloseInPanelHandler`) rather than a tagged `DialogRoute` enum? Which tests hit which handler after the change? *(Claude, Codex)*
26. What happens if the dialog is still visible when the workspace is saved/restored via the tier-1 persistence plan? Is the dialog persisted? Is there a stale pending completion on restore? *(Claude)*

### Safety and reversibility

27. Is there a feature flag / kill switch (e.g. `AppStorage("cmux.paneDialog.enabled")`)? If not, how do we disable this in a shipped release if portal z-order is wrong? *(Claude)*
28. What is the fallback policy when a panel-anchored dialog cannot be surfaced interactively (hidden workspace, retired workspace, non-owned pane host)? The plan's "fall back to NSAlert" ships two UIs for the same user intent. *(Codex, Claude)*

### Measurement

29. "No typing-latency regression visible in the debug log" — what is the bound? What is the baseline measurement tool? Without this, the criterion cannot fail. Has `TerminalPanelView` been opted out of body re-eval the way `TabItemView` is (via `.equatable()`)? *(Claude)*

### Localization

30. Why introduce new `dialog.pane.confirm.close` / `.cancel` keys instead of reusing existing translated `dialog.closeTab.close` / `.cancel` (`Resources/Localizable.xcstrings:29376, 29489`)? *(Codex)*
31. Are the Japanese translations for the new keys human-reviewed or machine-generated? cmux has real Japanese users — "とじる" vs "キャンセル" precision matters. *(Claude)*

---

## 7. Bottom Line

**Three independent adversarial passes converge on the same verdict**: the plan identifies the right direction (pane-scoped confirmation at 4×4 density) but is not execution-ready. It is design-adjacent. The factual errors (`acceptCmdD`, the missed `Workspace.confirmClosePanel` seam, the "browser = no portal hazard" claim, the access-control mismatch, the wrong callsite audit list) and the load-bearing handwaves (portal z-order, sync→async ripple, keyboard suppression) all share a root cause: **the plan describes what the primitive should be and then describes integration as mechanical. It isn't. The integration is the hard part, and the plan has not walked it.**

**Before Phase 1 begins, the author should:**

1. Re-audit the close-confirmation seams end-to-end — especially `Workspace.confirmClosePanel` and its Bonsplit delegate caller.
2. Prototype the `GhosttySurfaceScrollView` (AppKit-layer) overlay mount. Treat it as Phase 3, not a fallback.
3. Design a concrete replacement for the `NSApp.modalWindow` gating at `AppDelegate.swift:9054` and a concrete Cmd+D translator for the new overlay.
4. Rewrite the focus-guard strategy as a single inversion point in `scheduleAutomaticFirstResponderApply` rather than N grep-and-guard callsites.
5. Add an `AppStorage` feature flag for kill-switch safety.
6. Split the work into two PRs (primitive + flagged off → flip callers + remove flag).
7. Resolve the gold-vs-destructive-red styling contradiction.
8. Decide scope honestly: one consumer shipping with NSAlert for everything else is corrosive UX; commit to either broader scope or an explicit "Phase 1 of N" framing.

Without these, expect at least a week of post-merge fixes and a probable rollback conversation.
