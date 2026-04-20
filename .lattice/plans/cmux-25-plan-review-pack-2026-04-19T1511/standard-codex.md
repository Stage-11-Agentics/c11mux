# Standard Plan Review: cmux-25-plan (Codex)

Reviewed: 2026-04-19

## Executive Summary

The plan is directionally sound. The Emacs-frames model is the right north star, and the core architectural choice - process-scoped workspace/pane state with per-window frame state - matches the product goal better than either a single cross-window bonsplit tree or a loose "super-workspace" label layer. The v1/v2 boundary is also mostly correct: v1 should let users manually create windows on displays and move/spread panes; runtime hotplug and affinity should wait for real usage.

The plan is not ready to execute as written. It needs revision, not rethinking. The single most important issue is Phase 2: it combines object-model inversion, registry introduction, `TabManager` renaming, `WorkspaceFrame`, session schema migration, socket API rename, and feature-flag compatibility into one estimated two-week phase. That is the failure point. In the current code, `Workspace` owns both `bonsplitController` and `panels` (`Sources/Workspace.swift:4979`, `Sources/Workspace.swift:4983`), `TabManager` owns per-window `[Workspace]` (`Sources/TabManager.swift:687`, `Sources/TabManager.swift:691`), session persistence embeds workspaces inside each window (`Sources/SessionPersistence.swift:447`, `Sources/SessionPersistence.swift:452`), and the socket resolver is built around resolving a `TabManager` (`Sources/TerminalController.swift:3486`). Phase 2 is not one refactor; it is the migration of the app's core ownership model.

My verdict: needs revision before implementation. The plan should keep the architecture, but tighten invariants, split Phase 2 into smaller PR-grade slices, clarify snapshot migration and feature flag rollback, and explicitly decide whether panes are single-homed or can be referenced by multiple `WorkspaceFrame`s.

## The Plan's Intent vs. Its Execution

The intent is clear: one c11mux process, one coherent workspace graph, multiple NSWindow "frames" over that state. The plan mostly serves that intent. The rejected alternatives are also right. A single bonsplit tree spanning windows would force Bonsplit to understand AppKit window boundaries, which is the wrong abstraction. A workspace-per-window plus super-workspace label would preserve the current duplication problem.

Where execution drifts is in the data ownership wording. The primitive hierarchy says `Pane -> Surface -> Tab`, and says panes live in `PaneRegistry` with PTY, Ghostty surface, and MTL layer state. But a pane can hold multiple surfaces, and today the live terminal/browser/markdown objects are the `Panel` instances stored in `Workspace.panels`, while bonsplit panes are layout leaves. A terminal surface, not a pane, owns a PTY/Ghostty surface/MTL-backed view. If Phase 2 implements the wording literally, it will put lifecycle on the wrong object.

The plan needs an explicit old-to-new mapping:

- Current `Workspace` becomes process-scoped workspace metadata plus zero or more `WorkspaceFrame`s.
- Current `Workspace.panels` entries become process-scoped `Surface` objects, or at minimum a clearly named surface registry.
- Current Bonsplit `PaneID`s become frame-local layout leaves, or process-scoped pane records that own ordered surface IDs.
- Current Bonsplit `TabID` remains a UI/layout identifier for a surface within a pane.

That mapping is load-bearing. Without it, implementers can build a `PaneRegistry` that conflicts with the locked hierarchy.

The v1/v2 boundary is also mostly held, but there are two leaks. First, the code-change sketch still says to add `hibernatedFrames` to `AppSessionSnapshot` even though hibernation was explicitly removed from v1 (`.lattice/plans/task_01KPHHQZA4XZTQD4BQCGQYC7FR.md:153`). Second, CMUX-26 says per-window display-affinity tracking is "schema already set up in CMUX-25 Phase 2", while CMUX-25 Phase 2 only commits to `sidebarMode` and workspace IDs. Decide exactly what forward-compat field Phase 2 carries, or state that CMUX-26 owns its own schema bump.

## Architectural Assessment

The central decomposition is right: keep Bonsplit as one tree per rendered frame, and move shared state out from under window-local managers. This preserves Bonsplit's current contract and gives c11mux the "multiple windows are viewports" property.

The most important missing invariant is whether a pane is single-homed or multi-homed.

The plan mostly describes single-homed panes: moving a pane across windows means unlinking it from frame A and linking it into frame B, without restarting the underlying surface. That is plausible. But `workspace.spread` includes `all_on_each`, which would show every pane on every display. That implies either one pane can appear in multiple `WorkspaceFrame`s at once, or `all_on_each` clones/mirrors surfaces. If panes own AppKit views, MTL layers, or Ghostty views, multi-homing is not a small extension; AppKit views/layers are normally single-parent objects. If v1 is single-homed, remove or defer `all_on_each`. If multi-homed is a required future seam, Phase 2 needs a representation for frame references, view attachment, and focus semantics across multiple renderings of the same surface.

The second architectural gap is closing windows. The plan says closing a window destroys its frames, never its panes, and that remaining-only-on-that-window panes either migrate to another frame or hibernate. But v1 explicitly has no hibernation. The v1 behavior must be specified: choose a destination window, create a frame in another window, prompt, or block close when it would orphan panes. This is not a UX afterthought; it determines registry invariants and persistence shape.

The third gap is the relationship between `WorkspaceRegistry`, `PaneRegistry`, and sidebar/notification state. The plan says process-scoped shared store publishes and every sidebar subscribes, with "reconciliation model: zero." That is the right goal, but there will still be reconciliation at the boundaries: window-local selection pointing at deleted workspaces, frames referencing removed pane IDs, pane metadata for panes removed by close, active focus pointing to a pane no longer hosted in that window, and session restore rehydrating workspaces before frames. The plan mentions a missing-workspace fallback, but the same style of fallback should be documented for stale panes and stale frames.

## Is This the Move?

Yes, this is the move architecturally. The plan chooses the higher-cost model because the cheaper one would not deliver the product. That is appropriate for this feature.

The execution bet that worries me is trying to land a very large ownership inversion as one Phase 2. Large state-model migrations fail when they are both semantically broad and hard to bisect. Phase 2 should be decomposed into internal checkpoints that can each land green:

1. Introduce IDs and registry shells without moving ownership. Add lookup APIs and adapters over the current `TabManager`/`Workspace` shape.
2. Introduce `WorkspaceFrame` while preserving one frame per workspace, still no visible multi-window behavior.
3. Move surface/panel lifecycle out of `Workspace` behind a registry or adapter. Keep existing UI behavior.
4. Convert `TabManager` to `WindowScope` semantics: hosted workspace IDs and selected workspace ID, with a compatibility layer for existing call sites.
5. Land session persistence schema v2 with migration tests and rollback/flag behavior defined.
6. Land socket rename and deprecation shim after the model is stable.

Those can still be grouped under "Phase 2" in the ticket, but the plan should not ask one PR to do all of it.

The "Phases 3-6 can go in parallel after Phase 2" claim is only partially true. Phase 4 can probably parallelize with Phase 3 once the registry interfaces are stable. Phase 5 and Phase 6 should either depend on Phase 3's internal pane placement/move service or explicitly share a lower-level `PanePlacementService` created in Phase 2. `workspace.spread`, `pane.move`, and split-to-new-window are three entry points into the same operation: create/find target frame, remove pane leaf from source frame, insert leaf in target frame, reconcile focus, persist. If these are implemented independently in parallel, they will drift.

## Key Strengths

The plan correctly keeps Bonsplit unmodified at the contract level. One `BonsplitController` per `WorkspaceFrame` is the right boundary. It lets c11mux own cross-window semantics while Bonsplit remains a pane/tree primitive.

The plan correctly scopes hotplug out of v1. Runtime display changes, reconnect affinity, and optional hibernation are system-integration work with unpleasant testability. Keeping v1 manual lets the team validate the core model first.

The per-window focus decision is right. It matches macOS and the parallel-agent workflow. A global focused pane would make multi-window c11mux feel remote-controlled rather than native.

The socket rename from `workspace.move_to_window` to `workspace.move_frame_to_window` is conceptually right. In the new model, windows do not own workspaces. Keeping the old name as the canonical API would encode the old architecture in the public surface.

The plan notices the right current-code seams. `AppDelegate.moveSurface` and `locateSurface` already traverse windows (`Sources/AppDelegate.swift:4085`, `Sources/AppDelegate.swift:4782`), and Bonsplit already has external drop hooks (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:407`, `vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:428`). Those are real assets.

## Weaknesses and Gaps

### 1. Phase 2 Is Under-Scaffolded

Phase 2 is described as the biggest lift, but it still reads like a list of final nouns rather than a migration path. The plan should say how the app remains shippable after each sub-step, especially under `CMUX_MULTI_FRAME_V1=1`.

Specific missing scaffolding:

- Adapter APIs that let old call sites continue to ask "workspace containing panel" while the registry becomes canonical.
- A temporary compatibility shape for `TabManager.tabs` or a search/replace strategy for the many call sites currently indexing `tabs`.
- A model-level invariant checker for registry/frame consistency in DEBUG.
- A focused-pane/focused-surface migration rule per window.
- Explicit ownership of current `Workspace` responsibilities: remote workspace state, git probes, metadata/status/log/progress, recently closed browser restore, pane interaction runtime, title bar state, panel subscriptions, and terminal inheritance data.

The current `Workspace` is not just "layout plus panels"; it is also a status, metadata, remote, notification, and panel lifecycle hub. The plan should enumerate which fields remain on `Workspace`, which move to `WorkspaceFrame`, and which move to `Surface`/registry.

### 2. Persistence Needs a Real Schema Design

The current persistence store rejects any version other than `SessionSnapshotSchema.currentVersion` (`Sources/SessionPersistence.swift:5`, `Sources/SessionPersistence.swift:471`). The plan says "schema version bump; add migration", but it does not define the v2 shape with enough precision.

The key split is this:

- Workspace-level snapshot: workspace ID, title/custom title/color/pin, current directory/default context, workspace metadata, status/log/progress/git, surface IDs or surface snapshots.
- Surface-level snapshot: terminal/browser/markdown state, custom titles, pinned/unread state, directories, listening ports, surface metadata.
- Frame-level snapshot: window ID, workspace ID, bonsplit tree/layout, selected pane/surface for that frame, zoom state if any, pane metadata if pane is frame-local.
- Window-level snapshot: frame geometry/display snapshot, sidebar visibility/width/mode/selection, hosted workspace IDs or frame snapshots.

Right now `SessionWorkspaceSnapshot` contains both workspace data and layout (`Sources/SessionPersistence.swift:428` to `Sources/SessionPersistence.swift:444`). In the new model, layout belongs to `WorkspaceFrame`, not the process-scoped workspace. The plan mentions this in prose, but the schema section should spell it out and define migration from the old embedded window snapshots.

Feature flag rollback also needs an answer. If the new binary can be launched with `CMUX_MULTI_FRAME_V1=0`, does it read/write old snapshots or new snapshots? If a user flips the flag off after Phase 2 has written a v2 snapshot, do we preserve their session? If the answer is one-way migration with a backup file, say so. If the answer is dual read/write during the soak, design that explicitly.

### 3. Feature Flag Retirement Is Contradictory

The ticket says all six phases land behind `CMUX_MULTI_FRAME_V1=1`, and also says the flag retires after Phase 3 soaks on main for a release cycle. That is ambiguous. If Phase 4-6 are still in flight, retiring the flag after Phase 3 either exposes later work unguarded or means "flag" refers only to the Phase 2/3 internal model.

Recommendation: use two concepts:

- A model migration flag/kill switch for Phase 2 and Phase 3.
- A user-facing feature availability gate for spread, pane.move-to-display, and split-to-new-window until Phase 6 is complete.

Or keep one flag until all six phases land and soak. The current text should not remain as-is.

### 4. Phase 1 Is Not Purely "No Behavior Change"

Phase 1 is called foundation/no behavior change, but CMUX-25 says it enables manual window-to-monitor assignment via `cmux window new --display <ref>`, and the full plan includes `window.move_to_display`. Creating/moving windows on a selected display is behavior. That is fine, but the phase should name it and include acceptance criteria:

- `display.list`
- `window.create` with `display_ref`
- CLI aliases for display refs
- possibly `window.move_to_display`, or an explicit later phase for it
- display refs in `identify`, `window.list`, and `tree`

Without that, implementation may land only display enumeration and leave Phase 1 unable to satisfy CMUX-25 acceptance.

### 5. Socket Focus Policy Needs To Be Designed In

Repo policy says socket/CLI commands must not steal macOS focus unless they are explicit focus-intent commands. Existing v2 workspace move defaults focus through `v2FocusAllowed(requested: v2Bool(params, "focus") ?? false)` (`Sources/TerminalController.swift:3784`). The new `pane.move` example includes `"focus": true`, and current `AppDelegate.moveSurface` has `focusWindow: true` as a default (`Sources/AppDelegate.swift:4085` to `Sources/AppDelegate.swift:4092`).

The plan should specify defaults for every new command:

- `pane.move` should default to no macOS activation and probably no focus change unless `focus: true` is explicitly requested and allowed.
- `workspace.spread` should preserve the user's current focus unless invoked from a focus-intent UI action.
- `window.create --display` should not activate/raise unless the command is explicitly a focus command or a UI action.

This is easier to get right if there is one internal move/spread service that takes a focus policy object, rather than each phase deciding independently.

### 6. Cross-Window Drag-Drop Is Plausible, But Not Minimal Under The New Model

The plan is right that `.ownProcess` and `sourceProcessId` make same-process cross-window drops possible. Bonsplit's drop path already falls back to decoded transfer data when local observable drag state is absent, then calls `onExternalTabDrop` (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:407` to `vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:433`). Current `Workspace.handleExternalTabDrop` routes through `AppDelegate.moveBonsplitTab` (`Sources/Workspace.swift:9344`, `Sources/Workspace.swift:9380`).

The "minimal code change" claim should be softened because Phase 3 happens after the ownership inversion. Under the new model, the hard part is not pasteboard visibility; it is reconciling frame-local pane IDs, target frames, pane/surface registries, and focus/window policy. Keep the fallback-to-CLI clause, but treat drag-drop as a consumer of the shared move primitive, not as its own path.

### 7. Estimates Are Optimistic

The estimates are credible only if Phase 2 is split internally and implementation is steady with little review churn. As written:

- Phase 1: one week is credible if it includes display registry and `window.create --display`; add time if `window.move_to_display` and CLI polish are included.
- Phase 2: two weeks is not credible for one owner given the current coupling. Three to four weeks is more realistic, possibly more if schema rollback and CI fixtures are built properly.
- Phase 3: one week is credible after a stable pane placement primitive exists; otherwise it inherits Phase 2 risk.
- Phase 4: one week is plausible for wiring if registry publishers are already clean, but 1.5 weeks is safer.
- Phase 5: three days for the core socket command is plausible; menu, keyboard, localization, tests, and edge cases make one week safer.
- Phase 6: three days is plausible only if it reuses Phase 3 move/create primitives; otherwise one week.

Total realistic envelope: about seven to nine focused weeks, not five, unless multiple agents split independent implementation buckets with very clear ownership and no shared-file collisions.

## Alternatives Considered

I would keep the plan's Hybrid C architecture. The alternative I would seriously consider is not a different architecture but a staged compatibility architecture:

- Introduce a process-scoped registry facade first, backed by the current `TabManager`/`Workspace` structure.
- Convert call sites to the facade before moving storage.
- Then move storage behind the facade.

That costs a little temporary indirection but reduces the risk of a giant flag day.

For `workspace.spread`, I would defer `all_on_each` until the team has explicitly designed multi-homing/mirroring. The practical v1 modes are "partition panes across displays" and maybe "preserve/slice existing split tree." Mirroring every pane onto every display is a different capability.

For the deprecation shim, one release may be acceptable if this app has tight operator control and the response includes `deprecation_notice`. For a socket API used by scripts and agents, two releases or "one release after telemetry/logs show no known internal callers" would be safer. At minimum, add tests for both route names and advertise the deprecation in `system.capabilities`.

For session persistence, I would prefer a v2 snapshot that can be read regardless of feature flag state once Phase 2 lands, plus a one-time backup of the last v1 snapshot before migration. Dual-writing v1 and v2 during the soak is possible but expensive and easy to get wrong.

## Readiness Verdict

Needs revision before execution.

Do not reopen the big design decisions. The plan's architecture is sound. But before CMUX-25 starts, revise the plan with:

- A precise old-to-new object mapping for Workspace, WorkspaceFrame, Pane, Surface, and Tab.
- A single-home vs multi-home pane decision.
- A v1 window-close/orphan-pane rule.
- A concrete session snapshot v2 schema and migration story.
- A feature flag/rollback policy that accounts for persistence.
- A dependency graph that makes Phase 5/6 reuse the Phase 3 move primitive.
- Socket focus defaults aligned with repo policy.
- Revised estimates, especially Phase 2.

Once those changes are made, this is ready to break into implementation PRs.

## Questions for the Plan Author

1. Are panes single-homed in v1, meaning a pane ID may appear in exactly one `WorkspaceFrame` at a time? If yes, should `workspace.spread all_on_each` be deferred or redefined as clone/mirror behavior?

2. In the locked hierarchy, which object owns PTY/Ghostty/MTL lifecycle: `Pane` or `Surface`? The current plan text says pane, but the hierarchy and current code imply surface.

3. Should Phase 2 introduce a `SurfaceRegistry` separately from `PaneRegistry`, or should `PaneRegistry` contain pane records that own ordered surface IDs while a separate registry owns live surface objects?

4. What exactly happens when the user closes a window whose frame contains panes that are not hosted anywhere else, given v1 has no hibernation?

5. Should v1 allow a workspace to be selected in a window even when no frame exists yet? If yes, does selecting create an empty frame, rehost an existing frame, or show a "choose/spread panes" state?

6. What is the exact v2 session schema? Which fields move from `SessionWorkspaceSnapshot` to `SessionWorkspaceFrameSnapshot`, and what fields remain process-scoped?

7. Is `hibernatedFrames` intentionally in the Phase 2 schema, or is that leftover text that should be removed from v1?

8. Does CMUX-26 require a Phase 2 field for display affinity, or can it add its own schema bump later? If Phase 2 carries a field, what is the field and what writes it in v1?

9. What is the feature-flag rollback behavior after a v2 snapshot has been written? Is migration one-way with backup, dual-read/write, or something else?

10. When exactly does `CMUX_MULTI_FRAME_V1` retire: after Phase 3, after Phase 6, or after a full release containing all v1 behavior?

11. Should Phase 5 and Phase 6 wait for Phase 3's `pane.move` implementation, or should Phase 2 define a shared internal pane placement service that all three can consume in parallel?

12. Which display commands belong to Phase 1: only `display.list` and display refs in existing outputs, or also `window.create --display` and `window.move_to_display`?

13. What are the default focus semantics for `pane.move`, `workspace.spread`, `window.create --display`, and split-to-new-window? They should be explicit because of the socket focus policy.

14. Is one release enough for the `workspace.move_to_window` deprecation shim, or should removal wait until internal callers and documented automation have had a longer migration window?

15. What CI coverage is required before Phase 2 merges? I would expect at least snapshot migration tests, flag-off/flag-on launch behavior, single-window regression tests, and model invariant tests.

16. Should `workspace.spread existing_split_per_display` ship in v1, or is it too algorithmically ambiguous compared with `one_pane_per_display`?

17. Do menu and keyboard entry points in Phases 5/6 include localization work in the estimate?

18. Who owns the compatibility adapters during Phase 2, and who is allowed to touch `TabManager.swift`, `Workspace.swift`, `AppDelegate.swift`, and `TerminalController.swift` if multiple agents work in parallel?
