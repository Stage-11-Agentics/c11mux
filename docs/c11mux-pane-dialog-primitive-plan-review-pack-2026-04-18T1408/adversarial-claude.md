# Adversarial Review — c11mux Pane Dialog Primitive

- **Plan ID**: c11mux-pane-dialog-primitive-plan
- **Reviewer model**: Claude
- **Posture**: Adversarial. Not balanced — the Standard review covers balance.
- **Verdict up front**: The plan sounds tight and reads tight, but it is factually wrong on at least one load-bearing claim (the Cmd+D accept shortcut mechanism), it handwaves the single most likely technical failure (the Ghostty window-portal z-order), and it underestimates how much app-level behavior changes when `NSAlert.runModal()` becomes a non-modal pane overlay. There is a usable feature here, but shipping this plan as written is a near-certainty for at least one nasty regression in either (a) Cmd+D confirm, (b) z-order, or (c) the `NSApp.modalWindow` gating that a bunch of shortcut code implicitly depends on. Treat this as **not ready for execution**; roughly 30–60% rework before Phase 1.

---

## Executive Summary

**How worried should you be: moderately worried.** The primitive itself is small. The surrounding integration hazards are not.

Three structural problems:

1. **A load-bearing factual error about `acceptCmdD`.** §8 Q2 says the parameter is "plumbed through but not observably used in the modal code" and recommends keeping it for "signature parity." That is wrong. `acceptCmdD` as a semantic name is misleading *and* there **is** an observable Cmd+D code path — it is just wired at a different layer (`Sources/AppDelegate.swift:9020-9050`, `handleCustomShortcut`). That path walks `NSApp.windows` looking for an `NSPanel` whose `contentView` contains one of five hard-coded `closeConfirmation*.title` static-text strings, and on Cmd+D it calls `performClick` on the button titled `common.close`. A `CloseWorkspaceCmdDUITests.testCmdDConfirmsCloseWhenClosingLastWorkspaceClosesWindow` (`cmuxUITests/CloseWorkspaceCmdDUITests.swift:10-28`) asserts this exact flow. **Converting the workspace-close confirmation to a SwiftUI pane overlay breaks this test and the user behavior it represents.** There is no `NSPanel` to find, `findStaticText(in: NSView, equals:)` cannot traverse SwiftUI hosting content the same way, and the button title lookup in §3.1's `ConfirmContent` is `confirmLabel` (localized), not a `common.close` string the existing scanner expects. The plan does not mention any of this.

2. **The portal z-order "verify in Phase 4" is a known-outcome lookup, not a Schrödinger question.** CLAUDE.md §Pitfalls spells out the contract: `SurfaceSearchOverlay` *must* be mounted from `GhosttySurfaceScrollView` (the AppKit portal layer) because "portal-hosted terminal views can sit above SwiftUI during split/workspace churn." The plan proposes mounting `PaneDialogOverlay` in `Sources/Panels/TerminalPanelView.swift:19-41` (SwiftUI container) — the *exact opposite* side of the contract. The plan lists the fallback ("mount in GhosttySurfaceScrollView") as a risk mitigation, but that fallback is almost certainly the day-one requirement, not a contingency. Any Phase 3 smoke test that happens to look good before the first split/workspace churn is a false-positive waiting to hurt a user.

3. **`NSAlert.runModal()` → async non-modal is a behavior change, not just an API change.** When the alert was modal, `NSApp.modalWindow` was non-nil during the prompt. `Sources/AppDelegate.swift:9054` has a hard guard `if NSApp.modalWindow != nil || NSApp.keyWindow?.attachedSheet != nil { return false }` that short-circuits the custom-shortcut dispatcher. Dozens of shortcuts rely on this. Switching to a SwiftUI overlay silently removes that guard for the affected surface while keyboard input is supposed to be "suppressed" by `.allowsHitTesting(false)` — but that only blocks mouse events. Global NSEvent monitors (the path cmux actually uses for shortcuts) still fire. Expect key collisions: Cmd+W with the card up triggers a second close; Cmd+Option+T triggers textbox toggle; any terminal-routed shortcut fires.

If any one of the three lands, the "looks clean" PR costs a bad week of bug-hunting.

---

## How Plans Like This Fail

Pane-scoped modal primitives fail in a predictable family of ways. The plan is vulnerable to most of them.

1. **"Modal" leaks.** Pane-local modality is a lie the UI tells the user. The rest of the app is still fully interactive, which means *anything* that can reference, mutate, or destroy the anchor panel races with the dialog. In this plan specifically: what if the user closes the workspace from the sidebar (`Cmd+Shift+W` with multi-select → NSAlert path) while a per-panel card is up? The panel is torn down, the card's `completion(false)` fires from `clear()` — but the `async/await` continuation's caller in `closeRuntimeSurfaceWithConfirmation` does a `_ = tab.closePanel(surfaceId, force: true)` on `accepted == true` only. What if the user double-triggers the shortcut and two `confirmCloseInPanel` calls enqueue against the same panel? The plan says "FIFO queue." Good — but both completions resolve eventually. The caller-side flow was idempotent under `runModal()` because only one ran at a time; now you can have two back-to-back closes targeting the same surface, or a cancel that lands after the panel is already gone. Plan §7 dismisses "completion leaks" as Low risk with "unit-tested." The hard cases aren't in the presenter — they're in the callers.

2. **"Suppression" that only suppresses the obvious input.** The plan says "terminal/browser key input in the affected panel is suppressed." Suppressing `keyDown` to the `NSView` is one thing. What about: Ghostty's own surface input path; WKWebView's JS keyboard handlers (browser panels run JS that listens for keydown); the global shortcut dispatcher (see point 3 above); IME active with an in-progress composition. The plan mentions IME as a Phase 8 sanity check, which is too late — if IME is active on the terminal when the card mounts and keyboard "moves" to a SwiftUI `FocusState`, the composition state on the Ghostty surface is in a weird place and the next keystroke targeting the card may commit the composition instead.

3. **Tests that assert the old behavior still pass "somehow."** §Phase 7 says "do NOT remove the existing NSAlert detectors." Fine — but the existing tests detect an `NSAlert`/`NSPanel` hierarchy that *does not exist anymore* when the pane path is hit. The tests currently pass by falling through three detectors; the plan adds a fourth. But under the happy path, all three existing detectors return false and only the fourth matches. The tests therefore silently change shape: what used to be a real NSAlert assertion becomes a SwiftUI-accessibility assertion, and if the SwiftUI overlay is buggy (z-order hidden, `allowsHitTesting` swallows taps, accessibility identifier missing), the test passes because the *detection* happens but the *user flow* is broken. The test's bug-catching power degrades silently.

4. **"Reserved for later" API slots that quietly become permanent.** §1 Out of Scope, §5, and §8 Q1 all lean on the `.textInput` reservation. But the actual enum in §3.1 only has `.confirm`, and the presenter only handles `.confirm`. That means the primitive ships with a two-case enum where one case is commented out. Swift will happily let that stay forever; when the rename-follow-up comes, the author will discover the ergonomics of the `completion: (Bool) -> Void` shape don't work for a text-return value, and will either (a) widen to `Result<DialogReturn, Never>`, (b) add a second completion, or (c) rewrite the primitive. All three negate "subsequent rename refactor becomes additive." The plan is making a forward-compatibility claim that its own code sketch cannot support.

5. **Visual polish debt.** §8 Q3 and Q4 flag scrim opacity (0.55) and gold-vs-destructive button styling as "confirm against brand doc." Brand polishing during Phase 6 *after* the mechanics are wired is the wrong order — the gold-on-destructive question is not visual tweak, it is semantic (gold is "active," destructive is "danger"). Getting this wrong ships a dialog where the "safe" cancel button is less visually prominent than the "destructive" close — an accidental-close vector. The textbox-port plan at least calls out user-facing semantics before implementation. This plan doesn't.

6. **"Small primitive + small integration = small PR" arithmetic.** §Phase 9 says "Single PR; size is small enough that the textbox-port two-PR split does not apply." The plan authorizes itself to grep-and-guard every `makeFirstResponder` call site in `GhosttyTerminalView.swift` (~20 hits), wrap two panel views, flip async semantics at 9 callsites, add a new UI test, and localize into Japanese. The "small PR" framing is optimistic by at least 2x.

---

## Assumption Audit

**Load-bearing** assumptions (the plan breaks if these don't hold):

1. A SwiftUI overlay mounted in `TerminalPanelView` renders *above* the Ghostty portal. **Almost certainly false**, per CLAUDE.md §Pitfalls (`SurfaceSearchOverlay` moved out of SwiftUI for exactly this reason). The plan calls this "medium" risk; it should be "expected — design around it."
2. `acceptCmdD` is dead code and can be stubbed. **False.** Wired in `AppDelegate.swift:9020-9050`, asserted by `CloseWorkspaceCmdDUITests.swift:22`. See Executive Summary §1.
3. All 9 callsites listed in §4.6 are fire-and-forget. Four of the listed lines (`ContentView.swift:5694`, `cmuxApp.swift:1055, 1163`, `AppDelegate.swift:9506-9508, 9558`) are actually calls to `closeCurrentWorkspaceWithConfirmation`, `closeWorkspacesWithConfirmation`, or `closeOtherTabsInFocusedPaneWithConfirmation` — routes that keep NSAlert and are explicitly **not** being converted. The plan gives the impression the audit is needed for the new path, but the listed callsites are for the paths that aren't changing. The audit of callers of `closeRuntimeSurfaceWithConfirmation` is narrower and is NOT in the list (`Sources/GhosttyTerminalView.swift:1129`). The plan shows it has not actually walked the call graph.
4. `Panel.dialogPresenter` as a `let` stored property satisfies an `ObservableObject` protocol requirement with a `{ get }` signature across `TerminalPanel` (which is `@MainActor final class`) and `BrowserPanel` (`@MainActor final class`, confirmed at `Sources/Panels/BrowserPanel.swift:1710-1711`). This compiles, but the plan says "BrowserPanel needs verification" in §4.2 — easy enough to verify, which makes it strange it wasn't verified before writing the plan. Minor, but signals the plan was written with the research still pending.
5. `panel.dialogPresenter` being `@MainActor` lets `confirmCloseInPanel` call `present` from within `Task { @MainActor in }`. Works, but introduces a subtle timing window: between the `await withCheckedContinuation { cont in … panel.dialogPresenter.present(…) }` and the overlay rendering, the user can trigger a second shortcut. The plan's queue handles two confirmations — but it does not handle a workspace-destroy event *between* them.
6. Focus-restore "grep and guard every `makeFirstResponder`" is a practical approach. **Fragile.** `GhosttyTerminalView.swift` has ~20 `makeFirstResponder` + `scheduleAutomaticFirstResponderApply` hits (I counted: `5613, 5643, 5665, 5687, 5794, 6070, 6968, 7336, 7339, 7370, 7438, 7543, 7607, 7618, 7625, 7634, 7640, 7659, 7675, 7685, 7687, 7725 (definition), 7739 (definition), 7801, 7814, 7853-8001, 8001`). "Add a guard at every site" is a maintenance burden that will drift; the next person adding a focus-restore path will not know they need to check `dialogPresenter.current`. Better to invert: expose a single policy check inside `scheduleAutomaticFirstResponderApply`/`applyFirstResponder` and have every site flow through it. The plan does not propose that inversion.

**Cosmetic / safe** assumptions:
- Unique per-panel dialog IDs via `UUID` in `ConfirmContent.id`. Fine.
- `@Published private(set) var current` does not cause typing-latency regression. Fine — `TabItemView` uses `.equatable()` to opt out of body re-eval per CLAUDE.md; the overlay would only re-render on present/dismiss.

---

## Blind Spots

1. **Cmd+D and the window-hierarchy scanner.** Executive Summary §1. Not mentioned.
2. **`NSApp.modalWindow` gating disappears.** Executive Summary §3. Not mentioned. The `AppDelegate.swift:9054` guard is load-bearing; the plan needs a policy for what replaces it.
3. **Multi-window.** A window can host multiple workspaces. What happens if the user has window A with a card up on a panel, then Cmd+Tab away, Cmd+Tab back to window B, and triggers close? Does the card in A block the close in B? The plan says "other windows remain fully interactive" — good — but does not say what "suppressed" means for a *different* window's focus state.
4. **Browser JS dialogs.** `Sources/Panels/BrowserPanel.swift:1782-1819` has `dialogTelemetryHookBootstrapScriptSource` that intercepts `window.alert`, `window.confirm`, `window.prompt` from JS. The pane dialog primitive is orthogonal to these but the user won't know that — a page that calls `confirm()` will *not* use the new pane card. That is probably fine for now, but the plan does not call out the separation of concerns, which will lead to scope confusion ("why doesn't this browser's confirm() use the pretty card?").
5. **`NotificationStore.clearNotifications` in the current `closeRuntimeSurfaceWithConfirmation`.** `TabManager.swift:2490` calls `AppDelegate.shared?.notificationStore?.clearNotifications(forTabId:surfaceId:)` after close. The plan's rewritten snippet at §4.6 drops this line ("_ = tab.closePanel(surfaceId, force: true)" only). A silent behavior loss: a closed tab's unread notification badge persists. This is the kind of quiet data-quality regression that won't be caught by UI tests.
6. **Dragging a tab while a card is up.** A panel can be reparented across workspaces via bonsplit drag. What is the dialog's lifetime rule when the anchor panel moves windows mid-dialog? The plan says the card is panel-local and the `@Published current` follows the panel object, but `PaneDialogOverlay` is mounted from the panel's *view container* — moving a panel to another workspace reparents the SwiftUI view, which re-creates the overlay's hosting view, which either loses the presenter binding or re-binds to a new presenter instance if the view is identity-unstable. The plan relies on `.id(panel.id)` for identity stability; verify that holds across cross-workspace moves.
7. **Settings sheet confirmations.** The plan excludes them as already contextual. Fine. But there is at least one confirmation in `cmuxApp.swift` that is app-scoped ("enable open access"); the plan's §5 table is not exhaustive. Someone will ask "why is this one still an NSAlert" and the answer ("it's settings") is not obvious.
8. **Acceptance criteria `No typing-latency regression visible in the debug log`** — the baseline for "visible" is not defined. If the current typing-latency log jitters 2-3ms during normal typing, and the overlay mount adds 0.5-1ms of steady-state cost, that's not "visible" but it is real. Define the metric.
9. **The review pack does not include a plan for reverting.** If the overlay ships and z-order is wrong in production, what's the kill-switch? An `AppStorage` feature flag (`cmux.paneDialog.enabled`) would let Phase 9 ship and rollback per-install. Not mentioned.
10. **`closePanel(force: true)` vs. present-then-close race.** `TerminalPanel.close()` (`Sources/Panels/TerminalPanel.swift:147-173`) tears down the hosted view and detaches from the portal registry. The plan calls `dialogPresenter.clear()` at the top of `close()` — but if the card is mid-animation, the SwiftUI overlay might still be hosting when the panel view hierarchy is torn down. Phase 8 matrix should test close-during-animation explicitly.

---

## Challenged Decisions

1. **Per-panel FIFO queue.** Why queue? A second close on the same panel while a confirm is up is almost always a user-initiated retry ("oh wait, did that go through? let me try again"). Queueing the second shows the dialog twice in a row — once auto-resolved, once real. The user's mental model is "the second press is the same as the first." A stricter policy (drop duplicates, or require two distinct accepts) is more human. The plan chose FIFO because the primitive's API made it the natural shape, not because the user-experience analysis argued for it. This is a "deliberate default" masquerading as a decision.

2. **Scrim clicks don't dismiss.** §2 User-facing says this is to "prevent accidental cancel." But users model scrim-click-to-dismiss on every other macOS dialog (sheets, popovers, alerts). Blocking it trains users to hunt for the Cancel button. A softer approach: scrim click dismisses unless a destructive action is the default, or scrim click moves focus to Cancel (doesn't resolve). The plan picks the strictest policy with a one-line justification.

3. **Gold accent for default, destructive red for close.** §8 Q4 has this as an open question with "recommend destructive red." The answer is obviously destructive red for a close-confirmation; that `af12a1fe` gold is for active-tab state does not make it right here. The plan surfacing this as a question signals uncertainty that shouldn't exist — and the plan's §3.3 describes the card as using `BrandColor` gold for the confirm button, contradicting its own §8 Q4 recommendation. That's an internal inconsistency.

4. **Keyboard "Tab cycles buttons."** §2 and §8 Q5. This is fine for two buttons but a chore for a textInput variant (`.textInput` reserved). Once rename lands, Tab needs to move between field→confirm→cancel. The plan does not sketch how the tab-order policy evolves. Decide now.

5. **Fallback to `NSAlert` if the panel cannot be resolved.** §3.4, §4.6. That code path is defensive — but it ships two UIs for the same user intent. A user who triggers close on a panel that just got torn down sees a centered NSAlert; the next time, they see a pane card. That kind of inconsistency is confusing and hard to file-bug against. The fallback should be "no dialog; close is cancelled silently" or "always NSAlert for this specific caller" — picking based on panel resolvability is the worst of both.

6. **`confirmCloseInPanelHandler` test hook.** §3.4. The plan adds a second handler parallel to `confirmCloseHandler`. `cmuxTests/TabManagerUnitTests.swift:132-272` shows five tests using the old handler. Why two handlers rather than a tagged one? A single handler with a `DialogRoute` enum argument (`.nsAlert` vs `.panel(id:)`) is more expressive and avoids duplicating test scaffolding.

7. **The primitive is limited to one-panel scope but the name `PaneDialog` doesn't encode it.** If a future "broadcast" dialog is wanted (§2 explicitly excludes this now), the type name will have to change. A name like `PanelLocalConfirm` or `AnchoredDialog` tells the next engineer the constraint up front.

8. **Routing `closeWorkspaceIfRunningProcess` to the focused panel only.** §2, §Routing diagram. The plan says "consistent with today" because today's NSAlert also shows once. But today's NSAlert is *window-centered*, which is implicitly "about the window"; anchoring the new card on only the focused panel *claims* the confirmation is about that panel when it's actually about the workspace. Semantically misleading. A better option: if a workspace has multiple panels with running processes, either show a workspace-centered modal (fall through to NSAlert), or enumerate the affected panels in the card's message.

---

## Hindsight Preview

Two years from now, the things we'd say "we should have known":

1. **We should have just extracted the policy layer first.** The real problem is that `NSAlert.runModal()` is app-modal and that invariant flows through dozens of shortcut handlers. A plan that *first* extracted a `CloseConfirmationCoordinator` with a single policy (`NSApp.modalWindow`-like lock, `Cmd+D` accept translator, `esc`/`return` keymap) and *then* added a SwiftUI skin over it would have taken the same effort but avoided the behavior drift. By starting with the SwiftUI primitive and back-filling the policy, we'll reintroduce the app-modal behavior piece by piece under the overlay in weeks 3-6 post-ship.

2. **We should have feature-flagged it.** Not mentioned in the plan. A `cmux.paneDialog.enabled` toggle would have let us ship to TestFlight / Release and flip off without a code revert if the portal z-order was wrong.

3. **We should have tested on the 4×4 workspace layout the plan's "Why now" motivates.** The plan motivates the feature with 4×4 density and then does not include a Phase 8 matrix that explicitly tests 4×4. Add "4x4 workspace with running processes in all 16 surfaces, close all, verify each card anchors to its own surface" to acceptance criteria.

4. **We should have asked whether the card should be drag-movable.** §2 says "no drag-to-reposition. Card is centered." At density 4×4 on a 13" laptop, a centered card in a 400x250pt panel is *larger than the panel*. The card will overflow panel bounds. Either the card shrinks (and the copy needs to shrink with it), or the bound-to-panel promise breaks. The plan's min-width 260pt and max-width 420pt don't accommodate tiny panels.

5. **We should have noticed that the textbox-port plan and this plan both touch `TerminalPanelView.swift`.** The plan mentions this at §7 (Risk register) as "Low" and "merge order whichever lands first." For a ZStack vs. VStack restructure in the same file, the merge will conflict. Saying "rebases trivially" underestimates the combined change.

**Early warning signs to watch for during execution:**
- Phase 3 smoke test requires a *rapid split/merge sequence* to expose z-order issues, not a clean "open workspace, close panel, done" happy path.
- A `PaneDialogPresenterTests` unit test that only covers `present/resolveCurrent/clear` without exercising the caller-side continuation tells us nothing about the integration hazards.
- Any PR reviewer asking "how is this different from `.confirmationDialog`?" is a signal we have not clearly articulated why a custom primitive was needed over SwiftUI stock.

---

## Reality Stress Test

Three likely disruptions, in order of probability:

**A. Cmd+D test breaks on Phase 7.** High probability (~90%). `CloseWorkspaceCmdDUITests` targets the window-hierarchy-scanning path (`AppDelegate.swift:9020-9050`) that depends on an NSPanel with a specific static-text string. Once the workspace-close confirmation moves to a SwiftUI overlay, that path returns nil — Cmd+D stops accepting. The test fails in CI. The author then:
   - Option 1: Spends a day re-implementing the Cmd+D translator for the new SwiftUI overlay (needs an accessibility identifier, a new scanner that understands NSHostingView). Adds scope mid-PR.
   - Option 2: Reverts the workspace path to NSAlert and restricts the new primitive to `closeRuntimeSurfaceWithConfirmation` only. Halves the feature's reach.
   - Option 3: Drops Cmd+D entirely. Breaks the keyboard workflow a user has.
   None of these are in the plan.

**B. Portal z-order hides the card on split/workspace churn.** High probability (~80%). User reports "the card disappears after I drag a split." The author discovers the CLAUDE.md contract. Moves the overlay to `GhosttySurfaceScrollView`. That means:
   - The overlay is no longer a SwiftUI view under the SwiftUI panel container. It's an `NSHostingView<PaneDialogOverlay>` inside an AppKit scroll view.
   - `.focusable`, `.onKeyPress`, `FocusState` behave differently inside an `NSHostingView`. Keyboard integration needs rework.
   - Browser panels (which don't use the portal) don't need this. Now we have two overlay-mount strategies.
   - Phase 3 becomes two phases.

**C. Someone ships textbox-port first and breaks the ZStack wrap.** Moderate probability (~50%). `TextBoxInput.swift` mounts a text input below the terminal via a VStack around `TerminalPanelView`. This plan mounts a ZStack inside `TerminalPanelView`. If textbox-port lands first and adds a VStack that wraps a new `TerminalPanelView` caller, the ZStack wrap moves inside. Tractable but not trivial. The "rebases trivially" risk-register claim is optimistic.

**All three simultaneously:** Phase 7 reds the CI on Cmd+D. Author fixes by adding accessibility identifiers and a scanner. Author then discovers z-order hides the card. Author moves the overlay to the AppKit layer. The accessibility identifier added in the Cmd+D fix now points to a different hosting view. Repeat. Net cost: 1.5–2x the original estimate, landing mid-Phase-9 instead of end-of-Phase-8.

---

## The Uncomfortable Truths

1. **The plan is written at a level of detail that implies it has been code-walked, but hasn't been.** The `acceptCmdD` dead-code claim, the 9-callsite list that mostly points at functions that aren't being changed, the "verification" caveats in §4.2 ("BrowserPanel needs verification") — these are all tells that the plan's factual claims are based on skimming, not reading. That's the single strongest argument for a pre-Phase-1 pause.

2. **"Single PR, small enough, no two-PR split" is how scope creeps kill a week.** Compared to the textbox-port plan (explicitly two-PR) this plan's sense of its own size is unjustified. At minimum, split: (PR1) the primitive + Panel protocol + panel-overlay wiring with a feature flag off; (PR2) flip callers, wire Cmd+D, remove flag.

3. **The feature motivation ("4×4 density is disorienting") hasn't been pressure-tested.** Is the actual user pain here (a) "I can't tell which tab the alert is about" or (b) "the alert steals focus away from what I was doing"? If (a), maybe a title update ("Close tab '<name>'?") solves it without an overlay. If (b), the answer is a non-modal notification. The plan chose a panel-scoped overlay without testing cheaper alternatives.

4. **Nobody benchmarked typing latency with the overlay mounted-but-idle.** CLAUDE.md is explicit about typing latency being the #1 invariant. The plan asserts "Very Low" risk with a hand-wave ("publishes only when current changes"). But the overlay is a SwiftUI `View` inside the panel body. Its `body` evaluates on `@ObservedObject presenter` changes, and on `TerminalPanelView` body re-eval (which happens on every focus/size/theme change). `TabItemView` uses `.equatable()` for this reason. `TerminalPanelView` does not. The plan needs to either (a) benchmark, or (b) add the same `.equatable()` opt-out.

5. **The queue will find a corner case.** "Per-panel FIFO queue" is simple enough that its test cases look tautological, but in production the queue will see close-during-close, close-while-panel-reparenting, close-while-workspace-dying, and close-after-Cmd+Shift+Q. The plan's unit test coverage for queue semantics is four cases ("queue, resolve, clear, completion-fires-on-clear"). That's the happy path times three. It is not the hazard surface.

6. **The `.textInput` reservation is aesthetic.** Looking at §3.1, the completion type is `(Bool) -> Void` — explicitly the confirm shape. When textInput lands, the completion becomes `(String?) -> Void`. The enum's shared `completion` requirement on `PaneDialog` is not expressible in Swift without generics or an `Any` cast. The "reserved" comment in the enum will not carry the refactor — the "follow-up becomes additive" claim is not load-bearing truth, it's marketing.

---

## Hard Questions for the Plan Author

Numbered. Not softened.

1. **Cmd+D.** What is the behavior when the user presses Cmd+D on the new pane overlay? Where does the translator live? Does `CloseWorkspaceCmdDUITests` pass as-written, or does it need rewriting? If the latter, are you reducing or expanding test coverage of the accept-shortcut? *My belief: you have not thought about this. Answer: "we don't know" → problem.*
2. **`NSApp.modalWindow` replacement.** Since the new overlay is not app-modal, what replaces the `AppDelegate.swift:9054` guard for gating custom shortcuts while a confirmation is visible? Do we synthesize a "pseudo-modal-window" flag on `TabManager`? Do we gate shortcuts per-panel? What about a shortcut that targets a different window? *"We don't know" here means every shortcut needs manual audit.*
3. **Portal z-order.** Do you have a concrete plan for what to do if Phase 3 smoke confirms the SwiftUI mount fails? Or is Phase 3 going to discover it and stall the plan? Have you prototyped mounting from `GhosttySurfaceScrollView` and verified focus/keyboard work in that path?
4. **Multi-panel running processes.** If a workspace has three panels each with a running process, and the user hits Cmd+Shift+W, you anchor the confirm on the focused panel. The user now sees a card saying "This will close the workspace and all of its panels" anchored to *one* panel. Is that semantically honest? What if the focused panel has no running process but the others do — does the confirm still show on the focused one?
5. **Feature flag.** Is there one? If no, why not? How do we kill-switch this in a shipped release if portal z-order is wrong?
6. **Scope of Phase 5 focus-guard.** Which `makeFirstResponder` sites are in scope? All 20+? Any outside `GhosttyTerminalView.swift`? What's the invariant — "no first-responder change while any panel has a visible dialog" or "no first-responder change on the panel with a visible dialog"? These have different implementations.
7. **Overlay in 4×4.** If a panel's size is smaller than the card's min-width (260pt), what happens? Does the card shrink, overflow, or clip? Have you measured 13" laptop default layouts?
8. **Queue semantics under reparent.** Panel A is mid-dialog when the user drags its parent tab into window B. What happens to the card? What happens to the continuation? If the panel lives, the dialog follows — is that what we want?
9. **`confirmCloseHandler` vs. `confirmCloseInPanelHandler`.** Why two handlers instead of a tagged route? Have you confirmed the five existing `TabManagerUnitTests` that use the old handler won't need updates?
10. **Rename/textInput forward-compat.** Given `completion: (Bool) -> Void` is locked into `ConfirmContent`, what's the concrete type signature for `TextInputContent.completion`? Does `PaneDialog.id` stay `UUID` across variants? Walk me through what the rename PR's diff looks like.
11. **Notification clearing.** Does the new `closeRuntimeSurfaceWithConfirmation` still call `AppDelegate.shared?.notificationStore?.clearNotifications(forTabId:surfaceId:)` after accept? The plan's snippet omits it.
12. **Brand button styling.** §3.3 says gold accent; §8 Q4 says destructive red. Which is it? If destructive, what happens visually — a red confirm with a gold focus ring? Is that a one-off, or the general rule for destructive confirms?
13. **9-callsite audit.** The callsite lines cited in §4.6 mostly point at functions that are not being converted. Which callers of the two in-scope functions (`closeRuntimeSurfaceWithConfirmation`, `closeWorkspaceIfRunningProcess`) have you actually audited? I count one direct caller of `closeRuntimeSurfaceWithConfirmation` (`GhosttyTerminalView.swift:1129`) and two of `closeWorkspaceIfRunningProcess` (`TabManager.swift:2213, 2243`) — that is the real audit surface. Have you walked through each?
14. **Acceptance criteria metric.** "No typing-latency regression visible in the debug log" — what's the bound? What's the baseline measurement tool? Without this, the criterion cannot fail.
15. **`PaneDialog.id` from the switch.** §3.1 sketch forces a `switch` for one case. That's fine today; it breaks non-exhaustively when `.textInput` is added. Was the pattern chosen because it's safer than an ObjC-backed id, or because it's familiar? An `@Identifiable` struct wrapping the case would be cleaner.
16. **PR timing relative to M9 (textbox-port).** If M9 merges first, what's the rebase cost? You said "trivial." Show the diff.
17. **"Tests that use `confirmCloseHandler` keep working."** Are you certain? The five existing unit tests (`cmuxTests/TabManagerUnitTests.swift:132-272`) may call close paths that *now* route through `confirmCloseInPanelHandler`. Which tests hit which handler after the change?
18. **Japanese localization.** Two new keys, Phase 6. Are the translations human-reviewed or machine? Cmux has real Japanese users — "とじる" vs "キャンセル" matters.
19. **`dialogPresenter.clear()` in `BrowserPanel.close()`.** `BrowserPanel.close()` lives at `Sources/Panels/BrowserPanel.swift:3095`. Have you read it and confirmed no re-entrancy bugs when `clear()` fires a `(Bool) -> Void` completion that may itself trigger another close path?
20. **What happens if the dialog is still visible when the workspace is saved/restored?** Persistence (the tier-1 persistence plan) might snapshot a workspace with a dialog mid-flight. Is the dialog persisted? Almost certainly not — but does the restored workspace have a stale pending completion waiting to fire?

Where "we don't know" is the current answer — my estimate — the answer is "we don't know" for Q1, Q2, Q3, Q6, Q7, Q10, Q13, Q14, Q17, Q20. That is a lot of unknowns for a plan described as "small" and ready to execute.

---

## Bottom Line

This plan shows the right instinct — pane-scoped confirmation is the right direction at 4×4 density — but it is not execution-ready. It is *design-adjacent*. The `acceptCmdD` factual error and the portal z-order handwave both point at the same underlying problem: the plan describes what the primitive should be and then describes integration as mechanical. It isn't mechanical. The integration *is* the hard part, and the plan has not walked it.

**Before Phase 1:** fix the Cmd+D analysis, prototype the AppKit-layer overlay mount, pick gold-vs-red, add a feature flag, and either split the PR or commit to a larger review scope. Otherwise, expect a week of post-merge fixes.
