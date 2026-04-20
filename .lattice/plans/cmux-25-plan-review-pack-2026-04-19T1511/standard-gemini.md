# CMUX-25 Plan Review (Gemini)

### Executive Summary
The plan is highly sound and well-considered. The shift to an "Emacs-frames" model (process-scoped panes and workspaces, window-scoped viewports) is the correct architectural choice for a multi-monitor terminal multiplexer. By deliberately scoping out runtime hotplug and display affinity to a separate v2 (CMUX-26), the v1 (CMUX-25) plan avoids the most treacherous system-integration rabbit holes, focusing squarely on data model refactoring and core spatial primitives. The phase breakdown is logical and provides a safe path to `main` via feature flags.

### The Plan's Intent vs. Its Execution
The intent is to allow users to manually distribute panes and workspaces across multiple windows/displays without artificial boundaries. The plan executes this perfectly by severing the `TabManager ↔ NSWindow` coupling. The execution respects the "manual v1" constraint entirely, providing the necessary manual commands (`cmux window new --display`, `workspace.spread`) while completely deferring automated behaviors.

### Architectural Assessment
**The Decomposition:**
The introduction of `PaneRegistry` and `WorkspaceRegistry` at the process scope, with `WorkspaceFrame` acting as the bridge between a workspace and a window, is elegant.
**Why it's right:** It preserves the `BonsplitController`'s assumption of a single contiguous layout tree per view, avoiding a high-risk rewrite of the layout engine. By treating `PaneID`s as opaque leaves that are resolved via the `PaneRegistry`, windows simply become viewports.
**Alternative framing:** Option A (one massive bonsplit tree spanning windows) would have required deep structural changes to Bonsplit's coordinate space and rendering assumptions. Option B (super-workspaces) would have been a UX band-aid. Option C (Hybrid) is the only architecture that genuinely models the problem domain.

### Is This the Move?
Yes. The most common failure pattern for multi-display window management features is attempting to outsmart the OS's own window manager (e.g., trying perfectly handle sleep/wake cycles, undocking, and external GPUs right out of the gate). This plan makes the extremely disciplined bet to push all of that to v2. The sequence of execution (Display Registry -> Registry Refactor -> Migration & Commands) is textbook and correctly handles feature flags.

### Key Strengths
- **Scope Discipline:** Pushing hotplug/hibernation to CMUX-26 is the strongest decision in the plan.
- **Bonsplit Preservation:** Keeping `bonsplit`'s contract intact and treating `WorkspaceFrame` as a wrapper saves weeks of UI refactoring.
- **Deprecation Strategy:** The 1-release shim for `workspace.move_to_window` is mature and respects existing automation scripts.
- **Cross-Window Drag-Drop:** Recognizing that `.ownProcess` pasteboard visibility already handles cross-window drops saves unnecessary custom event routing.

### Weaknesses and Gaps
- **Phase 2 Estimate Risk:** A 2-week estimate for Phase 2 (severing `TabManager` from `NSWindow`, introducing two registries, rewriting workspace serialization, and refactoring ~12 files) is highly optimistic. This is the "draw the rest of the owl" phase. It touches the core lifecycle of every pane and terminal surface.
- **Schema Specifics for `SessionWindowSnapshot`:** The plan mentions that `SessionWindowSnapshot` will carry a "`WorkspaceFrame` bonsplit tree for each workspace the window hosts", but the exact serialization structure isn't fully defined. The schema will likely need an intermediate mapping structure to reliably deserialize.

### Alternatives Considered
- **Spread Distribution:** The plan considers and rejects equal-spread with remainder on primary. `ceil(N/D)` fill-leftmost is deterministic and superior because it doesn't rely on the elusive concept of a "primary" display, which varies wildly between macOS setups.
- **Split Auto-Overflow:** Choosing opt-in over auto-overflow for splitting into new windows is correct; auto-spawning windows on other monitors is highly disruptive to user focus.

### Readiness Verdict
**Ready to execute.** The plan is robust, the phases are well-ordered, and the risks are contained. The minor gaps in the schema definition can be resolved during Phase 2 implementation.

### Questions for the Plan Author
1. **Session Schema Structure:** In Phase 2, exactly how are the `WorkspaceFrame` bonsplit trees serialized inside `SessionWindowSnapshot`? Will it be a dictionary of `[UUID: SessionWorkspaceLayoutSnapshot]` keyed by workspace ID?
2. **Phase 2 Scope:** Given that Phase 2 touches `AppDelegate`, `TabManager`, `Workspace`, `ContentView`, `TerminalController`, and `SessionPersistence`, is there a risk that 2 weeks is too tight? Would it make sense to split Phase 2 further (e.g., separate the registry creation from the UI/serialization updates)?
3. **Empty Window State:** If a window's selected workspace is deleted from another window, the plan says it "falls back to the first workspace... or an empty 'choose a workspace' state." Does the UI for an empty window state already exist, or does it need to be built in Phase 4?
4. **Display Addressing:** In `display.list`, the positional aliases are `left`, `center`, `right`. For a 4-monitor setup, how are the middle two addressed? Just by numeric `index` (`display:2`, `display:3`), or should there be `center-left`, `center-right`?
