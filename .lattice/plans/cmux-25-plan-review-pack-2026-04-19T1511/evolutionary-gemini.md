# Evolutionary Plan Review: CMUX-25 (Multi-window c11mux)

## Executive Summary
The proposed "Emacs-frames for terminals" model is fundamentally sound, but its true potential isn't just letting humans spread their panes across monitors. The real opportunity is evolving c11mux into an **Agent-Native Spatial Window Manager**. By making `PaneRegistry` process-scoped and severing its tight coupling to `NSWindow`, c11mux stops being a terminal multiplexer and starts being an invisible backend service (a spatial orchestrator) that projects UI surfaces onto any available screen real estate based on task context and agent orchestration.

## What's Really Being Built
Beneath the surface of Phase 2's refactor, the plan is building a **Process-Scoped Surface Orchestrator**. What is actually evolving here is the definition of the "application boundary." Instead of a 1:1 bond between macOS windows and terminal instances, c11mux becomes a headless registry of active processes (Panes) that can be projected, mapped, and attached to arbitrary viewports (`WorkspaceFrames`) across local or virtual displays.

## How It Could Be Better
- **Frame Composition and Mirroring:** Instead of restricting one `WorkspaceFrame` to one window, architecture in Phase 2 should allow *mirroring*—two or more windows rendering the exact same `WorkspaceFrame` tree. This is invaluable for paired debugging, live streaming, or presenting an agent's reasoning process on a secondary "clean" display while keeping controls on the primary display.
- **Agent-Driven Target Displays:** Phase 5 introduces `workspace.spread` as a manual command. To be genuinely better, the socket API should allow agents to declare spatial intent: `layout_role: "reference"` (mapped to secondary display) or `layout_role: "focus"` (mapped to primary display). The human shouldn't have to manually manage window drops if the agent knows a browser surface is best viewed off to the side.

## Mutations and Wild Ideas
- **"GUI Session-Attach":** The `tmux attach` model but for native macOS windows. If the registry is independent of NSWindows, could c11mux run completely headless? A background daemon could hold all the panes and workspaces, and a separate lightweight UI client could "attach" to it, spawning windows across all available displays and snapping them to the physical geometry.
- **Pane Broadcasting (Stadium Mode):** What if a single pane could be broadcasted to multiple `WorkspaceFrames` across completely different workspaces? If an agent is running a long system-wide compilation, every window could show a small PiP (picture-in-picture) of that compilation pane in its sidebar.
- **Cross-Workspace Pane Sharing:** Currently, a pane belongs exclusively to one workspace. Evolving `panesByWorkspace: [UUID: Set<UUID>]` into a many-to-many relationship would allow a "Global Log" pane to exist in Workspace A and Workspace B simultaneously, giving the operator omnipresent visibility regardless of their focused context.

## What It Unlocks
- **Pane Hibernation without losing PTY:** A window can close entirely, but the pane stays alive in the process-scoped registry. It can instantly be resummoned in another window without losing any terminal state or process context. This fundamentally de-risks multi-monitor undocking.
- **Agent-to-Pane Absolute Addressing:** Since panes live in a global registry, agents can reliably target a specific pane ID (`pane.focus`) or surface no matter which window it currently resides in.
- **Unification with "Present Mode":** The sync-mode seam introduced in Phase 4 (where one window becomes the primary sidebar) unlocks a "Present Mode" where one window completely drives the viewport navigation of another.

## Sequencing and Compounding
The current phased rollout is safe but misses an opportunity for early compounding:
- **Bring Agent Workflows into Phase 5:** Phase 5 (Spread) relies entirely on human manual commands or broad brushstrokes (`all_on_each`). Exposing primitive spread controls to agents immediately (via the socket API) would turn the new architecture into a tool for autonomous self-organization, creating an unfair advantage for c11mux early on.
- **Defer less to v2:** "Merge-two-windows-into-one" is deferred, but it is the natural inverse of Phase 6 (Split-into-new-window). Doing it in Phase 6 validates the robustness of `WorkspaceFrame` transfer and forces edge cases to the surface earlier.

## The Flywheel
**The Context-Layout Flywheel:** An agent spins up a browser surface and a terminal surface. The operator manually drags the browser to display 2 (the right monitor). If c11mux tracks this through the registry, it learns this display affinity. The next time the agent runs a similar task, c11mux auto-spreads to that layout (the browser spawns immediately on display 2). The more the operator uses spatial placement, the less manual layout is needed, making the system increasingly predictive and magical.

## Concrete Suggestions
1. **Agent-Defined Layouts:** Add a `layout_role` or `preferred_display` argument to the socket API when an agent requests a new pane. Let c11mux map that to physical displays dynamically.
2. **Headless Registry Mode:** Architect `PaneRegistry` so it does not strictly require an active NSWindow to maintain its lifecycle. If all windows are closed but a long-running agent task is active, keep the registry alive.
3. **WorkspaceFrame Mirroring Support:** In Phase 2, ensure `WorkspaceFrame` data structures support a `mirrored_from` property, allowing a 1-to-many relationship between a bonsplit tree and NSWindows.
4. **Many-to-Many Panes:** Design `panesByWorkspace` to allow a single Pane ID to exist in multiple workspaces simultaneously for cross-context monitoring.

## Questions for the Plan Author
1. If a pane is detached from all `WorkspaceFrames`, does it enter a "headless PTY" state, or is it killed? How do agents interact with a headless pane?
2. Does the design of `WorkspaceFrame` support being rendered in multiple `NSWindows` simultaneously (mirroring), or is there a strict 1:1 mapping between a frame and a window?
3. How will `cmux identify` report the display of an agent running in a headless, hibernated, or mirrored pane?
4. Could the "sync mode" seam in Phase 4 be used to implement a "Present Mode" where one window's viewport navigation is fully slaved to another's?
5. Would allowing panes to belong to multiple workspaces break any assumptions in the Session Persistence schema bump?