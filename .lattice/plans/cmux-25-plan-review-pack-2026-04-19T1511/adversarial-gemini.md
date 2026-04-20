# Adversarial Plan Review

**Written against CMUX-25 (v1) and CMUX-26 (v2) Plan**
**Model:** Gemini
**Date:** 2026-04-19

### Executive Summary

This plan contains a fatal architectural flaw regarding macOS view hierarchies. It cleanly separates logical state (`Workspace`, `Pane`) from view state (`WorkspaceFrame`), but hallucinates the rendering capabilities of AppKit. By asserting that a single workspace (and its underlying `Pane`s/`GhosttyNSView`s) can be hosted in multiple windows simultaneously (e.g., the `all_on_each` spread mode or simply having two windows select the same workspace), it violates the strict invariant that an `NSView` can only have one superview. 

Beyond this load-bearing failure, the plan introduces actor-isolation into synchronous UI paths, creates a massive memory leak for closed windows in v1 by deferring hibernation to v2, and provisions future seams (like sidebar sync) that fundamentally contradict its own layout constraints.

### How Plans Like This Fail

Plans that refactor core ownership graphs (like moving from `TabManager` window-ownership to `PaneRegistry` process-ownership) usually fail in three ways:
1. **The "Clean Data, Messy UI" Trap:** Designing elegant, decoupled data structures that ignore the strict threading and hierarchy constraints of the UI framework rendering them.
2. **The "Deferred Cruft" Trap:** Pushing the "hard parts" (like what to do with orphaned state) to a "v2" ticket, effectively shipping a v1 that structurally leaks memory or state.
3. **The Asynchronous Migration Trap:** Introducing asynchronous boundaries (Actors) into previously synchronous, assumption-heavy paths (AppKit drag-and-drop, window teardown).

This plan hits all three.

### Assumption Audit

- **Load-Bearing:** *An NSView can be referenced and rendered by multiple WorkspaceFrames concurrently.* **False.** An `NSView` (and its backing `MTLLayer` for Ghostty) can only exist in one window hierarchy. If Window A and Window B both render Workspace 1, AppKit will aggressively rip the view out of Window A to place it in Window B. The `all_on_each` mode will violently tear the UI apart.
- **Load-Bearing:** *PaneRegistry can be actor-isolated without breaking UI.* **Highly Risky.** AppKit's `performDragOperation` and `windowWillClose` are synchronous. If determining what happens to a pane requires an async hop to the `PaneRegistry`, you either block the main thread (deadlock risk) or defer the action (use-after-free or visual glitch risks).
- **Cosmetic:** *Cross-window drag-drop is just an extension of intra-window drag.* **False.** macOS window management (Spaces, fullscreen, minimized windows) makes dragging between physical windows hostile unless you're on a single desktop space. Relying on `.ownProcess` pasteboard visibility solves the security boundary, not the UX physics.

### Blind Spots

- **The v1 Orphaned Pane Memory Leak:** The plan states: "Closing a window destroys its frames, never its panes — remaining-only-on-that-window panes either migrate to another frame of the same workspace or hibernate." But CMUX-26 explicitly defers hibernation to v2! In v1, if a user closes Window A, its panes are orphaned in the `PaneRegistry` with no UI to recover them and no hibernation store to flush them to disk. They will leak PTYs and memory until the app restarts.
- **Teardown Races:** What happens if Window A closes *while* a user is dragging a pane from it to Window B? The `TabTransferData` holds a `panelId`. If Window A closes, the `WorkspaceFrame` drops the pane. If it's the last frame, the pane is "orphaned" (or destroyed?). When the drop resolves in Window B asynchronously, the pane might be in a zombie state.
- **Silent Performance Regressions:** "No perf target at v1" ignores the cost of broadcast events. If 10 windows are listening to the process-scoped `WorkspaceRegistry`, a high-frequency telemetry burst (which the plan notes exists via `NotificationBurstCoalescer`) might trigger 10x the Combine updates and SwiftUI diffs on the main thread, stalling typing.

### Challenged Decisions

- **Independent Bonsplit Trees + Future Sync Mode:** The plan provisions a `.viewport` seam to "slave to the primary's selection." But because every window has its *own* `WorkspaceFrame` (its own Bonsplit tree), Workspace X in Window A has a completely different layout than Workspace X in Window B. If Window B syncs to Workspace X, it won't "mirror" Window A; it will just show Workspace X's panes in whatever arbitrary layout Window B last recorded for it. The sync seam is a footgun because the layout is explicitly not synced.
- **Feature Flag Retirement:** "Retires after Phase 3 soaks on main for a release cycle." Phase 2 alters the entire memory graph of the application. Leaks and subtle lifecycle bugs in terminal emulators often take weeks of continuous uptime to report. Retiring the flag before Phases 4-6 are even shipped leaves the team with no kill-switch when the orphaned-pane leak starts crashing user machines.
- **One-Release Deprecation Shim:** Deprecating `workspace.move_to_window` for only one release cycle is arrogant. Downstream consumers (shell aliases, custom scripts) don't read `deprecation_notice` JSON fields piped through `jq`. Breakage will be abrupt and frustrating for power users.

### Hindsight Preview

Two years from now, we will look back and realize:
- We should have known that separating `Workspace` from `Window` required rendering Ghostty to offscreen textures if we ever wanted the same workspace visible on two monitors.
- We will regret making `PaneRegistry` an actor, spending months chasing down async layout races, keyboard focus drops, and "Cannot update UI from background thread" crashes.
- We will wonder why we shipped a v1 that literally leaked memory every time a user pressed Cmd+W on a secondary window.

### Reality Stress Test

**Scenario:** A user has 3 windows across 2 monitors. They spread a workspace (`all_on_each`). They type a command. Mid-command, they unplug the external monitor.
**Result:** 
1. `all_on_each` attempts to mount the same `NSView` in 3 windows. AppKit throws exceptions or leaves 2 windows blank.
2. The monitor unplugs. macOS migrates the external windows to the primary display. 
3. Now 3 windows are stacked on the primary display, all fighting to render the exact same Ghostty surface layer. 
4. The user closes the two extra windows. The panes, having no hibernation logic in v1, enter a zombie state.

### The Uncomfortable Truths

- The "Emacs-frames" north star only works in Emacs because Emacs controls its own rendering pipeline down to the buffer level. You cannot staple Emacs-frames onto AppKit `NSView`s without massive rendering compromises.
- The plan explicitly allows states (like same workspace in multiple windows) that the underlying engine technically cannot render.
- The separation of CMUX-25 (v1) and CMUX-26 (v2) was drawn to ship faster, but the line was drawn straight through necessary cleanup logic, guaranteeing a degraded v1 state.

### Hard Questions for the Plan Author

1. Exactly what happens at the `NSView` / `CALayer` level when Window A and Window B both navigate to Workspace 1 simultaneously? 
2. Without v2's hibernation, what is the exact code path for a `Pane` in `PaneRegistry` when its last hosting `WorkspaceFrame` is destroyed by a window close? Does it leak, or does it die?
3. How does the synchronous `performDragOperation` in AppKit interact safely with the asynchronous, actor-isolated `PaneRegistry` when migrating a pane?
4. If a viewport window (in future sync mode) selects Workspace X, but has a completely different Bonsplit tree layout for Workspace X than the primary window, how does that fulfill the "walkthrough" use case?
5. Why is the feature flag being removed *before* Phases 4, 5, and 6 are deployed and validated?
6. Given `CMUX_DISABLE_STABLE_PANEL_IDS` exists as a rollback safety net today, how does Phase 2's sweeping refactor guarantee we don't break existing consumers who rely on current ID semantics?