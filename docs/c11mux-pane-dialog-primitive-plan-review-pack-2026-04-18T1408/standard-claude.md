# Standard Plan Review — c11mux-pane-dialog-primitive-plan

**Model**: Claude (Opus 4.7)
**Plan ID**: c11mux-pane-dialog-primitive-plan
**Reviewed**: 2026-04-18T14:08

---

## Executive Summary

This is a well-shaped, well-scoped plan. It replaces a genuinely disorienting UX (a window-centered `NSAlert` blaming an unknown tab) with a pane-anchored card, and it does so by introducing the smallest primitive that will also absorb the next two or three similar surfaces (rename, custom-color) without a redesign. The author has clearly internalized the c11mux conventions: typing-latency hot paths, portal layering hazard, localization-everywhere, the test-seam pattern from `confirmCloseHandler`, and the two-PR textbox-port precedent. The risk register is honest, the out-of-scope list is deliberate, and the phased execution is sized correctly for one PR.

**The single most important thing**: this plan intentionally flips `closeRuntimeSurfaceWithConfirmation` and `closeWorkspaceIfRunningProcess` from synchronous-modal to asynchronous-non-modal. That's the correct move, and the plan calls it out (§4.6), but the depth of the audit needed is understated. These functions are called from a Ghostty C callback (`close_surface_cb` in `GhosttyTerminalView.swift:1104`), from menu handlers, from the Ghostty runtime, and from UI test scaffolding. A few of those callers today rely on the side effect that by the time the call returns, the close has happened (or been rejected) — most visibly in UI tests that issue `typeKey("w", modifiers: [.command, .shift])` and immediately poll for the alert. The plan says "most are menu-action fire-and-forget — safe," but doesn't list which ones it verified and which it assumes. That's the one area I'd expect revisions before merge. Everything else is ship-ready.

**Verdict**: Proceed to execution after resolving the open questions in §8 plus the async-audit concerns raised below.

---

## The Plan's Intent vs. Its Execution

**Intent**: make tab-close confirmations unambiguously scoped to the tab they belong to, and do it with a primitive rather than a one-off, so the follow-up rename/color refactor slots in cleanly.

**Execution fidelity**: High. The plan explicitly:
- Picks the smallest possible primitive (`enum PaneDialog { case confirm }`) and reserves `.textInput` as a commented-out case — so the primitive's signature is designed for the follow-up, not just the current use.
- Anchors on the `Panel` protocol rather than some new concept, which is the right layer (panels already own focus, lifecycle, and view surface).
- Keeps the legacy `confirmClose` NSAlert path alive for genuine bulk/no-anchor cases. No forced homogenization.
- Introduces a test hook (`confirmCloseInPanelHandler`) that matches the existing `confirmCloseHandler` idiom (`TabManager.swift:800`), so UI tests stay deterministic.

**Where intent drifts**: Two places.

1. **"pane dialog" vs. "panel dialog" terminology.** The plan calls it a *pane* dialog but the primitive anchors on a *panel*. In c11mux's vocabulary, a pane is a bonsplit compartment that can contain multiple tab panels; a panel is the per-tab content surface. The plan's mechanism is correctly panel-scoped (good — you want the card pinned to the running-process surface, not the pane that could tab-switch out from under it). The naming is pane-flavored, though, because that reads as the user-facing concept. Worth an explicit callout in the doc or a rename of the primitive to `PanelDialog*`. Confusion will compound when the rename follow-up introduces dialogs that *are* pane-scoped (e.g., a workspace-level confirmation that naturally belongs to the focused pane's current tab). This is worth deciding up front.

2. **"Pane-local modality" undersells concurrency semantics.** The plan says cards on different panels show concurrently, which is correct for the 2×2 case. But consider: a user closes Workspace A, gets the card anchored on A's focused panel, then switches to Workspace B and closes it too. Both workspaces now have cards visible on their respective focused panels, but only one is in the visible window at a time. That's not "concurrent" — it's "one visible, one latent." The plan doesn't say what happens when the user returns to Workspace A. The spec probably wants: the card persists, still waiting for input. Confirmed (§2 "Window focus loss does not dismiss") but not tested in the matrix.

---

## Architectural Assessment

**The decomposition is correct.** Primitive + presenter + overlay + protocol requirement is the minimal set:

- `PaneDialog` (value-type enum) = *what* the dialog is.
- `PaneDialogPresenter` (per-panel reference type, `ObservableObject`) = *who* owns and serializes requests.
- `PaneDialogOverlay` (SwiftUI view) = *how* it renders.
- `Panel.dialogPresenter` (protocol requirement) = *where* it lives.

This is the same shape as the TextBox primitive described in the sibling plan, and it matches how `searchState` is already threaded through `TerminalPanel` (the `@Published searchState` pattern at `TerminalPanel.swift:26`). Good consistency.

**Alternative framings considered (and correctly rejected):**

1. **AppKit `NSWindow` overlay panel**. Would give you real OS-level modal semantics and unequivocal z-order above the Ghostty portal. But it comes with window-management overhead, window-focus/key-window issues, and loses the SwiftUI-composable design that makes the rename follow-up trivial. The plan's SwiftUI-ZStack approach is correct *provided* §7's portal z-order risk actually resolves in favor of SwiftUI-on-top. If it doesn't, the fallback (mount inside `GhosttySurfaceScrollView`, AppKit layer) is explicitly listed — which is the right escape hatch.

2. **Single app-level presenter with a panel-id selector**. Would give you a central place to coordinate cross-panel state (e.g., "don't stack cards when they'd overlap" or "dim all non-active cards"). But it would force every consumer to look up their panel's card state by ID, which is worse for SwiftUI reactivity and worse for encapsulation. Per-panel presenter is the right call for day one. If cross-panel coordination is ever needed, a parent coordinator that observes all presenters is an additive move.

3. **Extend `searchState` pattern** — use a generic "panel overlay" slot on `TerminalPanel` that can hold either a find overlay or a dialog. Tempting because it unifies two very similar concepts (modal-ish overlay on a panel). But find and dialog have fundamentally different modality: find is non-blocking and co-exists with panel input; dialog blocks panel input and claims focus. Merging them would force "overlay kind" dispatch in every consumer. Keeping them separate is better.

4. **Reuse `.confirmationDialog`/`.alert` SwiftUI modifiers** bound to the panel's view. This would be free in terms of code but visually identical to `NSAlert` — still window-centered (SwiftUI alerts on macOS are window-modal), which defeats the whole point. Correctly not proposed.

**The protocol-requirement approach is the right call.** The alternative (add presenter on the abstract "panel view" layer, not the model) would require panel views to own the presenter, but panel views are recreated by SwiftUI across identity changes — the presenter's queue would be lost. Anchoring on the model layer (`TerminalPanel`/`BrowserPanel`) keeps the presenter's state stable across view recreations, which is essential for the "card stays visible during bonsplit churn" requirement.

**One architectural weakness**: the plan's completion callback is not `@Sendable` and not weak-ref'd. If `TerminalPanel` strong-refs the `ConfirmContent` (via `PaneDialogPresenter.current`), and the completion captures `tabManager` or `self`, you can create a retain cycle that outlives panel close. The `clear()` path mitigates this (fires pending with `false`, drains the queue), but only if `panel.close()` actually runs before the panel is deallocated. For safety, the completion should be careful about captures — ideally it's a short closure that calls `continuation.resume` on a checked continuation, with the continuation owned by the caller's `Task`, not by the panel. The `TabManager.confirmCloseInPanel` code in §4.6 shows this pattern, which is correct. Worth adding an explicit line in the plan: "completions must not capture the panel or presenter strongly; they run on the `Task` that called `present`."

---

## Is This the Move?

**Yes, strongly.** The 4×4 disorientation is a real user-facing problem and it will get worse as workspaces densify. Anchoring confirmations to their surface is the obvious right answer; the question is just "how much scaffolding is worth it." The plan's answer — a tight, reusable primitive sized for this PR plus two follow-ups — is well-calibrated. It's not over-architected (no ceremony, no visitor pattern, no event bus), and it's not under-architected (the presenter + queue handles the real concurrency cases without hand-waving).

**Common failure patterns this plan avoids:**

- **Not accidentally boiling the ocean**: the plan explicitly leaves `closeOtherTabsInFocusedPaneWithConfirmation` and `closeWorkspacesWithConfirmation` on `NSAlert` because they lack a single anchor. That's discipline. Many plans would have tried to anchor the bulk-close on "the focused pane's card" or "a card on every affected panel," and both are worse UX than a system alert.
- **Not prematurely generalizing the textInput path**: the `.textInput` case is reserved but not implemented. If you shipped it now, you'd be designing the API without real consumers and it would be wrong. Shipping a confirm-only primitive with a known-next-consumer is the right sequencing.
- **Not reinventing the test seam**: the plan reuses the `confirmCloseHandler` pattern by adding a sibling handler. UI tests keep running without flake and without needing to drive real UI.

**What I'd do differently**: I'd shift the audit of the async-flip in §4.6 from "planned work" to "verified before Phase 1 starts." The plan lists 9 callsites across 3 files but doesn't attest that each was inspected and classified. That's exactly the kind of thing that bites you in Phase 8 when the UI matrix test fails and you're halfway into the branch. A short appendix mapping each callsite to `fire-and-forget` / `reads-state-after` / `re-fires-on-failure` would de-risk the whole thing for an hour of research. See Questions section.

---

## Key Strengths

1. **Primitive sized for its real consumers.** The plan deliberately builds enough primitive to absorb rename-tab, rename-workspace, and custom-color prompts without redesign, but no more. The `.textInput` reservation is right-sized — a comment and an enum slot, no speculative code.

2. **Test-seam continuity with `confirmCloseHandler`.** Adding `confirmCloseInPanelHandler` that mirrors the existing pattern (`TabManager.swift:800`) is the right move. UI tests stay deterministic and can be updated in one pass. The `cmuxTests/TabManagerUnitTests.swift` patterns that already exercise `confirmCloseHandler` (5 call sites) port over mechanically.

3. **Honest portal-layering risk.** Calling out the `SurfaceSearchOverlay` precedent (`TerminalPanelView.swift:20` explicitly warns about this) is exactly what a careful reviewer wants to see. The fallback (mount in `GhosttySurfaceScrollView` AppKit layer) is listed, not just hoped-for.

4. **Focus-restore guard is called out by name.** §4.7 names `reassertTerminalSurfaceFocus` and the grep-target (`makeFirstResponder(`) — and a quick grep shows ~15 call sites in `GhosttyTerminalView.swift` alone. The plan flags this as medium risk, which matches reality. Many plans would have said "we'll handle focus" and then been surprised.

5. **FIFO per-panel queue.** The presenter design handles the realistic concurrency cases (second-close-while-card-up) without punting to "last write wins" or "show two cards." Small, correct, testable.

6. **Localization keys reused where possible.** `dialog.closeTab.title` / `dialog.closeTab.message` / `dialog.closeWorkspace.*` are all reused verbatim. Only the two new primitive-level button labels are added. This is the right trade — you don't want three parallel localization key families for "close tab."

7. **Explicit "does not dismiss on scrim click"** prevents a common source of data loss on destructive confirmations. Matches the NSAlert behavior users already have.

---

## Weaknesses and Gaps

1. **Async-flip audit is under-specified.** The plan lists 9 callsites across 3 files but doesn't classify them. In particular:
   - `GhosttyTerminalView.swift:1129` calls `closeRuntimeSurfaceWithConfirmation` from inside a `DispatchQueue.main.async` block inside Ghostty's `close_surface_cb` C callback (`GhosttyTerminalView.swift:1104–1140`). That's safe for the async-flip (the callback doesn't await the return value), but: what happens if the user triggers `close_surface_cb` twice in rapid succession against the same surface? Today the second call's `NSAlert` would block on the first; with the new design, both closes enter the panel's FIFO queue. That's probably fine (user accepts the first, the second card shows) but worth confirming the Ghostty runtime doesn't rely on synchronous close-acceptance semantics.
   - `AppDelegate.swift:9506` and `9558` — the plan points to these but the grep shows these are `closeOtherTabsInFocusedPaneWithConfirmation`, which is **explicitly kept on NSAlert**. So those 2 of the 9 callsites aren't actually affected. Narrows the audit.
   - `ContentView.swift:6863, 11536` and `cmuxApp.swift:1055` are `closeWorkspacesWithConfirmation` (multi), also kept on NSAlert. Another 3 callsites not affected.
   - So the real audit surface is ~4 callsites, not 9. The plan would be tighter for naming the specific ones.

2. **No explicit async cancellation semantics.** The `confirmCloseInPanel` function uses `withCheckedContinuation` (not `withCheckedThrowingContinuation`), which means there's no way to cancel a pending confirmation from the Swift concurrency side. If the Task calling `confirmCloseInPanel` is cancelled mid-dialog, the card stays up and the completion still fires `false` (via `clear()`), but the awaiting Task is already dead. That's an OK design, but should be stated: "task cancellation does not dismiss the card; the card only dismisses when the user interacts or the panel closes." Otherwise a reviewer will ask.

3. **`acceptCmdD` is plumbed but unused.** The plan's Q2 flags this, and I agree with the recommendation to keep it. But the plan doesn't describe what `acceptCmdD` is supposed to do in the future — it's a ghost parameter. Add a one-line comment in the code explaining the intended future semantic, not just "reserved."

4. **"Keyboard focus captured by card" is under-specified.** SwiftUI `.focusable(true)` on macOS is finicky in 14+ / 15+. Specifically:
   - `.onKeyPress(.return)` is new (macOS 14+) and interacts with `@FocusState` in specific ways.
   - Ghostty's surface view holds first responder via `makeFirstResponder(self)`, which is an AppKit concept. SwiftUI's focus system and AppKit's first-responder chain don't always coordinate cleanly.
   - The plan says "grabs first responder via a hidden `FocusState` anchor." That's one approach, but it might actually need a dedicated `NSViewRepresentable` that wraps an `NSView` whose `acceptsFirstResponder` returns true. Worth prototyping early in Phase 3 to avoid a Phase-5 surprise.

5. **Overlay mount point risks `GeometryReader`-style sizing issues.** The plan shows:
   ```swift
   ZStack {
       GhosttyTerminalView(...)
       PaneDialogOverlay(presenter: panel.dialogPresenter)
   }
   ```
   `GhosttyTerminalView` is an `NSViewRepresentable` for the portal-hosted terminal. SwiftUI's layout system will measure the ZStack's container size, then lay out the overlay at that size. But terminal views can exhibit unusual intrinsic sizing during bonsplit churn. If the overlay's frame is ever larger than the panel rect (e.g., during a resize animation), the scrim will bleed. Worth an explicit `.frame(maxWidth: .infinity, maxHeight: .infinity)` and a manual clip. Or mount the overlay *inside* a geometry-reader that captures the terminal view's exact bounds.

6. **VoiceOver modal trap is listed as "Unknown."** Honest, but: in practice, SwiftUI `.accessibilityAddTraits(.isModal)` on macOS doesn't always suppress VoiceOver focus traversal outside the overlay — that's an iOS-strong behavior and macOS-weak. The Phase 8 VoiceOver check might reveal this needs an AppKit backstop (explicit `NSAccessibility` attribute setting, or a hosting view that locks accessibility focus). Worth noting in the risk register as "likely requires fallback."

7. **No mention of multi-window handling.** c11mux supports multiple windows; each window has its own `TabManager`. If a user has Workspace A in Window 1 and triggers `close_surface_cb` for a surface there, the card should appear on the Window-1 panel. The plan's `confirmCloseInPanel(workspaceId:panelId:…)` doesn't take a window parameter — it relies on `tabs.first(where: { $0.id == workspaceId })` resolving within the calling `TabManager`, which is per-window. This is probably fine because `close_surface_cb` uses `app.tabManagerFor(tabId: callbackTabId)` (`GhosttyTerminalView.swift:1125`) to find the right manager, but it deserves a one-line sanity check in the plan.

8. **No regression test for the async-flip itself.** §7 lists "UI tests break because NSAlert is no longer the UI." Right. But what about unit tests for the async-flip semantics? E.g., does `confirmCloseInPanel` clean up its continuation when the panel closes mid-dialog? This is testable without SwiftUI — in `PaneDialogPresenterTests`. Worth adding an explicit test: "present → panel.close → completion fires false → continuation resumes."

9. **CHANGELOG copy is tentative.** "Tab close confirmations now appear anchored to the specific tab instead of a window-centered dialog" — good, but this is M10-level user-facing change. Worth a before/after screenshot or GIF in the PR (not the changelog). Flag in Phase 9.

10. **No mention of `cmuxApp.swift` settings-sheet confirmations being inspected.** The plan's §1 "Out of scope" mentions them correctly but doesn't verify that none of them are called *from* a panel context. Presumed safe but not attested.

---

## Alternatives Considered

### Alternative 1: Render the card via a native `NSPanel` positioned over the panel rect

**Approach**: Use `NSPanel` (a borderless, non-activating `NSWindow`) sized to the panel's screen coordinates, owned by the parent window. Sends events through normal AppKit chain.

**Pros**: Real OS-level focus/z-order, no portal-layer conflict. Works reliably with Ghostty's surface view because it's a separate window.

**Cons**: Window management is painful (position-tracking on resize, miniaturize, workspace switch, Spaces). SwiftUI composition is harder (you'd host via `NSHostingView`, lose the panel's SwiftUI context). The follow-up `.textInput` variant becomes an `NSTextField` dance.

**Verdict**: Worse. The plan's SwiftUI approach is cleaner *if* the portal layering resolves. The plan correctly lists `GhosttySurfaceScrollView` AppKit mounting as the fallback — which is the middle ground between SwiftUI-ZStack and full `NSPanel`.

### Alternative 2: Replace NSAlert everywhere, no fallback path

**Approach**: Make the pane-dialog primitive handle bulk-close and "close other tabs" too, by picking an arbitrary anchor panel.

**Pros**: API uniformity. One code path.

**Cons**: UX wrong. A card anchored to a random panel when you're bulk-closing 5 workspaces is more confusing than a window-centered alert — it misleads the user into thinking the confirmation is about *that panel*. The plan's decision to keep `NSAlert` for no-anchor cases is correct.

**Verdict**: Plan's choice is better.

### Alternative 3: Inline banner within the panel (non-modal)

**Approach**: Instead of a modal card, show a non-modal banner at the top of the panel: "Close this tab? [Close] [Cancel]."

**Pros**: Less intrusive. User can keep typing in the panel while deciding.

**Cons**: For a destructive confirmation that's likely to be answered in 2 seconds, modal is correct. Non-modal invites the user to forget the prompt is pending. Also, you still need the input-blocking behavior to prevent accidental typed dismissal — which brings you back to modal semantics.

**Verdict**: Plan's choice is better. Modal is the right pattern for destructive confirmations.

### Alternative 4: Synchronous presenter with `RunLoop` spinning

**Approach**: Keep the sync-modal signature by having `confirmCloseInPanel` spin a nested `RunLoop` until the user resolves the card.

**Pros**: Zero callsite changes. Drop-in replacement for `confirmClose`.

**Cons**: Re-entrancy hell. You'd be spinning the main run loop while the app continues receiving events, including more Ghostty callbacks. Nested `runModal` is exactly what `NSAlert` does, and is the source of many of the problems the plan is trying to solve. Would also block Ghostty rendering.

**Verdict**: Plan's async-flip is better, even with the callsite audit burden.

---

## Readiness Verdict

**Ready to execute with minor revisions.** Specifically:

1. Before Phase 1: resolve the 6 open questions in §8 (particularly Q1 rename-timing, Q4 button color, Q6 module numbering).
2. Before Phase 4: classify each of the 9 callsites listed in §4.6 into `fire-and-forget` / `state-reads-after` / `no-longer-affected` buckets. Appendix it in the plan.
3. During Phase 3: prototype the focus-capture mechanism early (§4.3) — this is where SwiftUI/AppKit focus integration can surprise you.
4. Update risk register: VoiceOver modal trap is likely to require an AppKit backstop; note this explicitly.

The plan does not need rethinking. It does not need a major revision. The architecture is sound, the scope is right, and the sequencing is good. The changes above are incremental sharpening.

---

## Questions for the Plan Author

1. **Rename timing (plan Q1)**: The plan recommends shipping rename as a follow-up PR. Agree. But how soon after? If the follow-up is ~1 week away, the primitive's `.textInput` reservation is well-motivated. If it's 3+ months out, the reservation is speculative and I'd remove the comment (YAGNI). What's the target follow-up date?

2. **Naming — `PaneDialog` vs. `PanelDialog`**: The primitive is panel-scoped, not pane-scoped. c11mux's pane/panel distinction matters. Is the user-facing concept intentionally "pane dialog" (because users see it as a pane-local thing), or should the code/type names be `PanelDialog*`?

3. **Async-flip callsite classification**: Please annotate §4.6's 9 callsites with their classification (`fire-and-forget` / `state-reads-after` / `no-longer-affected`). From my quick read, 5 of the 9 are actually `closeWorkspacesWithConfirmation` or `closeOtherTabsInFocusedPaneWithConfirmation` — which keep NSAlert — so they're unaffected. The real audit surface is smaller than the plan implies.

4. **Ghostty callback double-fire**: `close_surface_cb` (`GhosttyTerminalView.swift:1104`) can fire twice for the same surface under some conditions (e.g., a rapid Cmd+W double-press while a process is blocking). Today the second fire would block on the first NSAlert's modal loop. With the async-flip, both enter the panel's FIFO queue. Is that the intended behavior, or should the presenter dedupe-by-surface? (I lean toward dedupe.)

5. **Focus-capture mechanism**: §4.3 says "grabs first responder via a hidden `FocusState` anchor." Have you validated this approach works in a c11mux-like context where an `NSViewRepresentable` (`GhosttyTerminalView`) is a sibling in the ZStack? On macOS, SwiftUI `@FocusState` and AppKit `firstResponder` are famously tricky together. Worth a small spike in Phase 3.

6. **Scrim behavior across bonsplit resize**: What happens to the card if the user resizes the bonsplit divider while a card is up? The card is centered in the panel rect — does it reposition smoothly, or does it jump? Should it just stay visible and reflow, or should divider-drag temporarily hide it? (I'd vote for "stays visible and reflows.")

7. **Button ordering**: The plan says Cancel first, Confirm last (trailing). On macOS, the convention varies: `NSAlert` puts the default button on the trailing side (right). SwiftUI `.alert` also puts default trailing. Good. But for the destructive role, some designs put destructive on the *left* with cancel on the right (so accidental Enter is less destructive). Is this deliberately matching NSAlert convention, or should destructive be demoted to left?

8. **Accessibility focus and VoiceOver**: `.accessibilityAddTraits(.isModal)` on SwiftUI is iOS-strong, macOS-weak. Are we comfortable with VoiceOver potentially being able to focus elements outside the card on macOS? If not, the plan needs an AppKit backstop (`NSAccessibilityProtocol` overrides on the hosting view). This is Phase 8 work but worth flagging now.

9. **Card palette lock-in**: Q3 says "confirm against the brand visual-aesthetic doc." The gold-on-black-void treatment from `af12a1fe` is canonical for active-tab emphasis. Is the dialog's *confirm button* using the same gold? For a destructive confirm, that's semantically odd (gold = "approved/emphasized" vs. destructive = "red"). Q4 proposes a compromise (destructive red tint + gold focus ring). Please confirm this is the chosen treatment — it affects Phase 3 view code.

10. **CHANGELOG wording + PR screenshots**: The CHANGELOG bullet is tentative. For an M10-sized UX change, please include before/after visuals in the PR description (not changelog). Is that a team convention you'd like noted explicitly in Phase 9?

11. **Unit test for continuation cleanup**: Should `PaneDialogPresenterTests` include a test that verifies the `withCheckedContinuation`-based path in `TabManager.confirmCloseInPanel` cleans up when `panel.close()` fires mid-dialog? That's a different layer than the presenter tests but is the actual failure mode that would matter in production (leaked continuation = hung Task).

12. **Multi-window sanity check**: `confirmCloseInPanel` looks up the workspace via `tabs.first(where:…)` which is per-`TabManager` (per-window). Ghostty's `close_surface_cb` resolves the right `TabManager` via `app.tabManagerFor(tabId:)` before calling. Can you add a one-line note in §4.6 attesting that the multi-window case works, just to close the loop?

13. **`m9-textbox` merge-order coordination**: §7 mentions both plans touch `TerminalPanelView`. Textbox wants a VStack (terminal on top, TextBox below); pane-dialog wants a ZStack (terminal + overlay). These compose fine (`VStack { ZStack { terminal; dialogOverlay }; textBox }`), but if textbox lands first with its own VStack, the pane-dialog PR needs to wrap the terminal subtree in the ZStack, not the whole VStack (so the dialog doesn't overlay the TextBox). Is this coordination understood? Who confirms the merge-order outcome?

14. **Ghostty portal z-order fallback — what's the decision criterion?** §7 says "Fallback: mount overlay inside `GhosttySurfaceScrollView` (AppKit layer) for terminal panels." That's a meaningful architectural change (it moves the overlay from SwiftUI to AppKit, forks the terminal and browser code paths). What's the threshold for triggering the fallback? "If the card is ever hidden by the portal" is vague — is it "on any visible bug" or "only if the SwiftUI approach fails Phase 3 smoke test"? I'd tighten this.

15. **`acceptCmdD` ghost parameter**: Q2 says keep for signature parity. Fine. But the code would be clearer if the comment explained what the future semantic is. Today it's `_ = acceptCmdD` in `confirmClose`. Is the intention that a future "Don't show this again" checkbox is gated on this flag? If so, say that. If not, mark it as strictly vestigial and drop it from `confirmCloseInPanel`.

---

## Miscellaneous Observations

- The §3.5 routing diagram is clear. Keep it in the final doc.
- The phased execution tracks the "primitive scaffolding → protocol integration → overlay view → caller wiring → focus guards → localization → tests → validation → PR" pattern used in the textbox-port plan, which is a good house style to maintain.
- Phase 3 calls for a "TestSupport / debug menu to present a sample dialog." Good idea. Worth being explicit about whether this is a `#if DEBUG` Debug Menu entry that persists in the codebase, or a scratch harness that gets removed before PR. I'd vote for keeping it (as a Debug Menu item) — it's useful for future iterations of the primitive.
- The Phase 7 UI-test plan correctly keeps both the NSAlert and the overlay detectors in the existing tests, which is exactly right given the plan's fallback strategy. Well-considered.
- `cmuxUITests/CloseWorkspaceConfirmDialogUITests.swift` currently falls through three detectors (dialog/alert/staticText). Adding a fourth for the overlay matches the existing progressive-detection idiom. Good.
- Risk register is accurate and well-calibrated. I'd elevate "VoiceOver modal trap" from Unknown to Medium likelihood.

---

## What Would Change My Verdict

**To "Needs revision":** if the async-flip audit reveals 2+ callsites that genuinely read state after the sync-modal call, or if the portal z-order turns out to reliably hide the SwiftUI card (forcing the AppKit fallback before Phase 3 completes).

**To "Needs rethinking":** if the rename follow-up turns out to require a fundamentally different modal shape (e.g., needs a file picker, not just text input) — which would mean `.textInput` was the wrong reservation and the primitive is over-fit to this one use. Unlikely given the stated follow-ups (rename, custom-color) are all small content variants.

Neither of these is likely. Proceed.
