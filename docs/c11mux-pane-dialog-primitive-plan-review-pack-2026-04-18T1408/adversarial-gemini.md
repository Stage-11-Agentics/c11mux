# TP-c11mux-pane-dialog-primitive-plan-Gemini-Adversarial-20260418-1408

### Executive Summary

This plan is walking into a classic macOS view-hierarchy and focus-management trap, compounded by a dangerous shift from synchronous to asynchronous control flow. The single biggest issue is the naive assumption that a SwiftUI `ZStack` overlay will correctly composite above, and reliably steal keyboard focus from, a heavily AppKit-bound `NSView` (the Ghostty terminal portal) without explicit `NSHostingView` and `NSResponder` coordination. If implemented as written, users will see the dialog but their keystrokes will continue routing to the terminal beneath it, or the terminal will render on top of the dialog. 

### How Plans Like This Fail

Plans that introduce "in-window" or "in-pane" custom modals over complex native hierarchies typically fail in three ways:
1. **Z-Order/Compositing Disasters:** Mixing SwiftUI and AppKit views often results in clipping, clipping-bounds mismatches, or the AppKit view aggressively rendering over the SwiftUI layer. 
2. **The Focus Trap:** SwiftUI's `@FocusState` and AppKit's `NSResponder` chain are effectively two different worlds. Attempting to suppress input via `.allowsHitTesting(false)` only blocks mouse events; it does nothing to stop the AppKit first responder from gobbling up keyboard events.
3. **The Sync-to-Async Ripple:** Changing a blocking, modal `NSAlert` call to a non-blocking `async` continuation breaks every upstream caller that implicitly relied on the function returning *only after* the user had made a decision.

This plan is vulnerable to all three.

### Assumption Audit

- **Assumption:** A SwiftUI `ZStack` can cleanly overlay an `NSViewRepresentable` (the Ghostty portal) and reliably block input.
  - **Status:** **Load-bearing, highly likely to fail.** `allowsHitTesting(false)` blocks clicks, but if the `NSView` already holds `firstResponder`, it will continue receiving keystrokes. The SwiftUI overlay must actively steal `NSResponder` focus, which the plan does not outline.
- **Assumption:** The async shift in `closeWorkspaceIfRunningProcess` only affects "fire-and-forget" callers.
  - **Status:** **Load-bearing, risky.** Returning immediately from a close request means the workspace is left in a zombie "closing" state. If any script, automation, or subsequent user action (like quitting the app) queries the tab state immediately after triggering a close, it will incorrectly see the tab as still alive.
- **Assumption:** Maintaining `NSAlert` for bulk closes is an acceptable UX inconsistency.
  - **Status:** **Cosmetic, but corrosive.** Users will learn to expect the pane-local dialog. When they hit `Cmd+Shift+W` and get a massive window-centered AppKit alert, it will feel like a bug or a legacy remnant.
- **Assumption:** The panel minimum width of 260pt will always fit.
  - **Status:** **False.** Users can resize panels aggressively in a 4x4 or denser grid. A 260pt minimum width dialog in a 150pt wide panel will blow out the bounds or clip awkwardly.

### Blind Spots

- **Focus Resignation:** The plan mentions guarding `makeFirstResponder` to prevent *re-stealing* focus, but it entirely omits how the SwiftUI overlay actually *acquires* AppKit focus when it appears, and how it *restores* it to the exact same terminal surface when dismissed (if cancelled).
- **The "Zombie" State:** While a pane is waiting for a dialog response, what happens if the underlying process exits naturally? Does the dialog auto-dismiss? Does the pane close? The plan doesn't handle the race condition between the user clicking "Cancel" and the terminal process terminating on its own.
- **Overlapping Modals:** What if the app triggers a settings-sheet `NSAlert` while the pane dialog is visible? The z-order between the window-modal `NSAlert` and the pane-local SwiftUI overlay is undefined.
- **Window Resizing/Bonsplit Reflow:** If the window is aggressively resized while the dialog is up, the bounds might shrink below the dialog's minimum size. The plan assumes `.id(panel.id)` keeps it stable, but layout reflows could detach the overlay visually.

### Challenged Decisions

- **Decision:** Moving from `NSAlert` to a custom SwiftUI modal per pane.
  - **Counterargument:** `NSAlert.beginSheetModal(for:)` exists for a reason. It handles the AppKit responder chain, window dimming, and accessibility flawlessly. Building a custom modal primitive just to scope it to a *pane* instead of a *window* introduces massive engineering overhead for a slight aesthetic gain.
- **Decision:** Returning immediately from `closeWorkspaceIfRunningProcess`.
  - **Counterargument:** This should either remain a synchronous block (which is impossible with SwiftUI continuations) or the caller signature must be refactored all the way up the chain to `await`, ensuring that the app knows the close operation is pending. Faking a sync return while spawning an async Task is a classic recipe for race conditions.

### Hindsight Preview

Two years from now, we will look back and say: "Why did we reinvent modals?" We will have a backlog of 15 bugs related to "Dialog gets stuck," "Keystrokes leak to terminal," "Dialog renders behind terminal," and "Accessibility VoiceOver gets trapped." The early warning sign will be the Phase 3 smoke test where the SwiftUI card is invariably hidden behind the AppKit portal layer, forcing a messy, rushed bridging of the `PaneDialogPresenter` down into the `GhosttySurfaceScrollView` AppKit code.

### Reality Stress Test

Imagine these three disruptions hit simultaneously:
1. **User triggers a workspace close (dialog appears).**
2. **A background script force-kills the terminal process in that pane.**
3. **The user resizes the window rapidly, squishing the pane.**

**Result:** The terminal process dies, which might trigger a generic pane close event. The pane calls `close()`, which calls `dialogPresenter.clear()`. This fires the completion with `false` (Cancel). But the process is dead, so the pane is closing anyway. The rapid resize causes the ZStack to recalculate while the teardown is happening, potentially crashing the SwiftUI render loop or leaving a ghost dialog overlay on a sibling pane as Bonsplit re-allocates the view IDs. 

### The Uncomfortable Truths

- This isn't just a UI change; it's a fundamental rewrite of the app's control flow and focus hierarchy disguised as a visual refresh.
- The mitigation for the AppKit z-order issue ("mount overlay inside `GhosttySurfaceScrollView`") isn't a fallback; it's almost certainly the *only* way this will work, which completely invalidates the clean SwiftUI architecture proposed in Phase 3.
- Shipping this with only one consumer (confirm close) and leaving `NSAlert` for other close paths makes the app look unfinished. 

### Hard Questions for the Plan Author

1. Exactly how does the SwiftUI `PaneDialogOverlay` steal the AppKit `firstResponder` status from the `GhosttyTerminalView` when it appears?
2. If `dialogPresenter.clear()` fires the completion with `false` (Cancel), and the pane is closing due to a process exit (not a user action), will the `false` return trigger any unintended side effects in the `Task` spawned by `closeWorkspaceIfRunningProcess`?
3. How will the dialog render if the panel width is resized to 100pt, given the 260pt minimum width constraint?
4. When `closeWorkspaceIfRunningProcess` returns immediately (spawning an async Task), how do callers like `Cmd+Q` (Quit) know to wait for the dialog to resolve before terminating the app?
5. If the user clicks the dimmed `allowsHitTesting(false)` scrim, does it flash or beep to indicate focus? What is the user feedback that input is blocked?