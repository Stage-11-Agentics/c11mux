# Adversarial Review: CMUX-25 Plan

PLAN_ID=cmux-25-plan
MODEL=Codex

Reviewed:
- `.lattice/plans/task_01KPHHQZA4XZTQD4BQCGQYC7FR.md`
- `lattice show CMUX-25 --full`
- `lattice show CMUX-26 --full`
- `lattice show CMUX-16 --full`
- `CLAUDE.md`
- `Sources/AppDelegate.swift`
- `Sources/TabManager.swift`
- `Sources/Workspace.swift`
- `Sources/SessionPersistence.swift`
- `Sources/TerminalController.swift`
- `vendor/bonsplit/`

## Executive Summary

This plan should not proceed to Phase 2 until it explicitly defines the invariants for a workspace hosted in multiple windows at once. The locked hierarchy is fine; the missing part is the behavioral contract. The plan says a workspace is process-scoped and each window renders it through "one bonsplit tree per {workspace, window}", but much of the current app assumes a workspace ID has exactly one owning `TabManager`, one selected/focused context, one notification jump target, and one persistence location.

The single biggest issue is that the plan treats `PaneRegistry` as the boundary that solves ownership, but the existing product routes behavior through window-scoped managers everywhere. A registry actor can serialize a dictionary; it cannot by itself make `WorkspaceRegistry`, `WorkspaceFrame`, Bonsplit, AppKit first responder state, session snapshots, notification routing, and socket responses move atomically. Without an explicit transaction model, CMUX-25 risks producing a hybrid where the data model says "shared workspace" but the UI and socket layer keep picking "first window that mentions this workspace."

The plan is directionally plausible, but it is under-specified around exactly the places most likely to break: multi-hosted workspace ambiguity, drag/drop lifecycle, window teardown, focus, persistence migration, and performance under agent telemetry.

## How Plans Like This Fail

Plans like this usually fail by underestimating how many old uniqueness assumptions survive a data-model refactor. The ticket calls Phase 2 "the biggest lift", but it describes types more than invariants. That is backwards for this change. The hard problem is not adding `PaneRegistry`; it is proving every call site that takes a `workspace_id`, `surface_id`, `pane_id`, `window_id`, or "active window" has an unambiguous answer when a workspace appears in more than one window.

This plan is vulnerable to a half-new, half-old architecture. Current code has a per-window `MainWindowContext` with a `TabManager`, `SidebarState`, and `SidebarSelectionState` (`Sources/AppDelegate.swift:1943`, `Sources/AppDelegate.swift:2126`). Phase 2 proposes process-scoped registries, but the socket layer currently resolves through `v2ResolveTabManager` (`Sources/TerminalController.swift:3486`) and a global active `tabManager`. If Phase 2 leaves compatibility shims that resolve "workspace -> first matching window", later phases will build on ambiguity rather than remove it.

It also risks treating drag/drop as a transport problem instead of a lifecycle problem. The plan leans on ".ownProcess pasteboard visibility already allows intra-process cross-window"; the code does have `.ownProcess` payloads (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift:705`), but the actual drag state is Bonsplit-controller-local (`vendor/bonsplit/Sources/Bonsplit/Internal/Controllers/SplitViewController.swift:17`) with a payload fallback for external controllers (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:407`). The pasteboard type is necessary. It is not sufficient.

Finally, this plan can fail slowly through performance regressions rather than obvious crashes. The plan explicitly accepts "No formal perf target at v1", while the change moves hot routing paths from local arrays to process registries and cross-window projections. Existing socket code already uses main-thread synchronous hops (`Sources/TerminalController.swift:3198`), and existing lookup paths scan windows/workspaces/panels (`Sources/AppDelegate.swift:4782`). More panes and windows can silently make telemetry and UI responsiveness worse.

## Assumption Audit

### Load-bearing assumptions

1. Quote: "WorkspaceFrame (one bonsplit tree per {workspace, window}, leaves reference pane IDs)."

This assumes a workspace can be selected in multiple windows without every existing `workspace_id -> owner` lookup becoming ambiguous. Today `contextContainingTabId` returns the first context whose `TabManager.tabs` contains the ID (`Sources/AppDelegate.swift:11286`), and `tabManagerFor(tabId:)` simply wraps that (`Sources/AppDelegate.swift:11295`). Notification opening uses the same first-match context and then brings that window forward (`Sources/AppDelegate.swift:11319`, `Sources/AppDelegate.swift:11364`). `mainWindowContainingWorkspace` also returns the first matching window (`Sources/AppDelegate.swift:4389`). In a multi-frame world, these are not implementation details; they are broken invariants unless the plan defines selection rules for "workspace appears in windows A, B, and C."

2. Quote: "Panes become first-class process objects. PTY / Ghostty surface / MTL layer move here from Workspace."

This assumes a pane object can be cleanly referenced from multiple frames. Moving one pane between frames is plausible. Showing the same pane in multiple frames is not addressed. The ticket includes `workspace.spread` mode `all_on_each` where "every pane [is] on every display"; if the Pane owns a Ghostty surface and MTL layer, this implies either the same AppKit/Metal view is mounted in multiple windows or each frame needs a view/proxy around shared process state. AppKit views and layers do not have multiple superviews. The plan needs to either ban duplicate pane references across live frames in v1 or define a separate render-host abstraction.

3. Quote: "Closing a window destroys its frames, never its panes - remaining-only-on-that-window panes either migrate to another frame of the same workspace or hibernate."

The v1 plan also says "No runtime hotplug/hibernation" and "windows stay alive" for hotplug, but user-initiated window close still exists. Current close behavior is destructive at the window/workspace level: `TabManager.closeWorkspace` tears down all panels (`Sources/TabManager.swift:2206`), and `unregisterMainWindow` clears notifications for every workspace in that window (`Sources/AppDelegate.swift:11235`). If a user closes one of several frames for the same workspace, the plan does not define:
- whether panes unique to that frame migrate to another frame automatically,
- what happens if there is no other frame for that workspace,
- whether closing the final frame closes the workspace or creates a hidden frame,
- whether close confirmation lists panes, frames, or workspaces,
- whether notification/read state survives frame destruction.

4. Quote: "`PaneRegistry` - process-scoped actor-isolated store."

Actor isolation is not a transaction model. A `pane.move` operation mutates at least: the registry's pane membership, the source `WorkspaceFrame` Bonsplit tree, the destination `WorkspaceFrame` tree, window focus state, selected surface, sidebar badges, notification state, session autosave fingerprint, and possibly AppKit first responder. Some of these are `@MainActor`; Bonsplit itself is `@MainActor` (`vendor/bonsplit/Sources/Bonsplit/Internal/Controllers/SplitViewController.swift:5`). If the registry actor is not main-actor-bound, every move becomes a cross-actor, multi-object transaction with rollback risk. If it is main-actor-bound, the "actor-isolated" phrase adds little and may create false confidence.

5. Quote: "Cross-window drag-drop should work at v1 with minimal code change."

This assumes the existing external-drop path is robust enough to become a product feature. The fallback path decodes a transfer and calls `onExternalTabDrop` (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:411`, `vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:428`); cmux then calls `app.moveBonsplitTab` (`Sources/Workspace.swift:9344`, `Sources/Workspace.swift:9380`). That still relies on global lookup of the source tab and a live source context. It does not answer what happens if the source window closes mid-drag, the target window is minimized, the target is in another Space/fullscreen context, the drag crosses windows with portal-hosted browser views, or the source controller's local mouse-up cleanup fires before the destination finishes.

6. Quote: "No formal perf target at v1."

This assumes regressions will be obvious enough to catch after the fact. They may not be. c11mux is typing-latency-sensitive by project policy. The plan touches socket routing, sidebar publishing, notification counts, tree/identify output, pane moves, focus reconciliation, and session autosave. Existing code already has sync main-thread reads for socket helpers (`Sources/TerminalController.swift:3198`) and scans all windows/workspaces for surface lookup (`Sources/AppDelegate.swift:4782`). A no-target plan can ship a version that "works" but adds enough latency to make multi-agent operation feel worse.

7. Quote: "`SidebarMode` enum on `WindowScope`: `.independent` / `.primary` / `.viewport` (values exist, only `.independent` is wired at v1)."

Persisting unwired future states is a compatibility risk. The plan says session persistence serializes `sidebarMode` per window, while only `.independent` is implemented. If a later branch, test fixture, or downgrade writes `.primary` or `.viewport`, v1 needs a defined decode/fallback behavior. More importantly, future sync mode is not just selection broadcast. It touches sidebar visibility, command palette scoping, notification jump behavior, window close semantics, focus ownership, and socket `workspace.select`. A no-op `broadcastSelection` seam can become a footgun if it trains the codebase to think sync mode is a small callback instead of a mode that changes ownership.

8. Quote: "flag retires after Phase 3 soaks on main for a release cycle."

This assumes Phase 3 is the right retirement point. It is not obviously true. Phase 4 changes sidebar state, Phase 5 spreads workspaces across displays, and Phase 6 changes split creation. If the flag retires after Phase 3, then later high-risk user-facing behavior may land without a rollback switch. If "after Phase 3" means "after Phase 3 plus all later phases", the ticket should say that. If Phase 3 ships a subtle race that appears in week two, removing the flag after one release cycle eliminates the easiest containment mechanism.

9. Quote: "`workspace.move_to_window` keeps working for one release cycle."

This assumes downstream consumers are few and easy to migrate. The codebase has CLI/socket users, UI tests, Lattice agents, skills, and likely human scripts. The plan proposes a DEBUG log and a response `deprecation_notice`, but that only helps clients that read and surface the field. For automations, one release is short unless there is telemetry proving actual use is near zero. The old name is semantically imperfect but cheap to preserve as an alias compared with the risk of breaking operator scripts.

## Blind Spots

### Multi-hosted workspace invariants are absent

The plan needs an explicit invariant table for every ID relation:
- Can one `WorkspaceFrame` contain a pane ID that is also in another frame?
- Can one pane appear in multiple frames simultaneously?
- If a workspace is selected in two windows, which frame receives `workspace.select`, `surface.focus`, `pane.focus`, `read-screen`, `send`, `tree`, and notification jumps?
- Is focus per window, per workspace frame, per pane, or per surface?
- Is a pane "owned by" a workspace, a frame, or the registry plus zero/more frame references?
- What is the last-reference behavior when a frame is closed?

Without this, implementers will infer local answers and the system will get inconsistent.

### `PaneRegistry` race conditions are under-specified

The prompt asks specifically about this, and the plan does not answer it. Concrete races:

- Two concurrent `pane.move` socket calls for the same pane can both validate against the same source frame, then detach/attach in conflicting order.
- A drag-drop move and a keyboard move for the focused pane can race, especially if the keyboard shortcut fires while the drag source window is still key.
- Source window close during drag can unregister the context (`Sources/AppDelegate.swift:11222`) while the target drop still calls `moveBonsplitTab`.
- Destination frame close during a move can make the target Bonsplit pane disappear after registry validation but before attach.
- An old focus reassert can run after a newer move. Current code already has delayed reassert after cross-window surface moves (`Sources/AppDelegate.swift:5015`, `Sources/AppDelegate.swift:5044`). Multi-frame pane moves multiply the stale-callback surface area.
- Session autosave can snapshot between detach and attach if the move is not one main-actor transaction. Today detach removes panel mappings (`Sources/Workspace.swift:10045`) and attach re-adds them later (`Sources/Workspace.swift:8013`).

The registry needs move leases or transaction IDs, pane lifecycle states (`live`, `moving`, `closing`, `orphaned`), and idempotent rollback/commit semantics. "Actor-isolated" alone is not enough.

### Window teardown semantics are missing

The plan says closing a window destroys frames, not panes, but it does not define the product behavior. This is not a v2 hotplug problem; it is a v1 close-window problem. Existing close confirmation says "This will close the current window and all of its workspaces" (`Sources/AppDelegate.swift:4917`), which becomes wrong under the new hierarchy. The user needs to know whether closing a window closes a viewport, closes panes only visible there, migrates panes, or hides them.

### Persistence migration is much harder than stated

Current persistence has `version = 1` and rejects any version mismatch instead of migrating (`Sources/SessionPersistence.swift:5`, `Sources/SessionPersistence.swift:466`). The current snapshot stores workspaces inside each window's `SessionTabManagerSnapshot` (`Sources/SessionPersistence.swift:447`, `Sources/SessionPersistence.swift:452`). The plan says "Schema version bump; add migration from v(current) that synthesises workspace entries from each window's embedded list." That is not just a bump. It needs a migration framework, duplicate-workspace merge rules, stable frame IDs, conflict resolution for focused panel/selected workspace, and a way to preserve panel IDs while splitting layout from pane data.

The biggest persistence risk is duplicate logical workspace data. In v1 snapshots, each window has independent workspace objects. In the new world, a workspace can be hosted in multiple windows. Migration must decide when two workspaces with the same title/path are the same logical workspace versus separate workspaces. Stable workspace IDs help only after the new model exists; old snapshots do not encode "same workspace, multiple frames."

### Cross-window drag-drop needs an AppKit failure matrix

The plan's "one integration test" is too weak. The failure modes are platform-specific:
- target window minimized,
- target window hidden behind another app,
- source/target in different Spaces,
- one window fullscreen,
- source window closes during drag,
- target frame destroyed during drag,
- drag crosses over WKWebView/browser portal layers,
- drag starts in a window that loses key status,
- drop onto inactive workspace views kept alive in a ZStack,
- stale drag pasteboard contains both file URL and internal types.

Some of these already have defensive code in `DragOverlayRoutingPolicy` (`Sources/ContentView.swift:335`) and `CmuxWebView` (`Sources/Panels/CmuxWebView.swift:1150`). That defensive code is a warning sign: drag routing is already tricky inside one window.

### The socket surface remains window-first

The plan says v2 socket handlers already accept `window_ref` / `workspace_ref` and can swap `v2ResolveTabManager` to `v2ResolveWindowScope`. That understates the ambiguity. `v2ResolveTabManager` currently resolves by explicit window, then workspace, then surface, then panel, then active manager (`Sources/TerminalController.swift:3486`). In a multi-frame model, `workspace_ref` alone does not identify a frame. `surface_ref` may identify a pane that is visible in more than one frame. `pane_ref` may be in a registry but not visible in the caller's window. Existing response payloads include one `window_ref`; they will need either a frame ref, a visibility list, or a caller-scoped resolution rule.

### Test strategy is too thin

The acceptance criteria say cross-window drag-drop moves panes and session restore round-trips selection. The plan does not require tests for:
- duplicate hosting of the same workspace,
- closing one frame while another frame remains,
- moving the same pane twice concurrently,
- stale drag source teardown,
- socket focus policy across windows,
- no app activation from non-focus socket commands,
- autosave during move transactions,
- `all_on_each` rendering or explicit non-support,
- old `workspace.move_to_window` client compatibility.

Given the repo's test quality policy, these should be runtime/behavioral tests or debug harnesses, not source-shape tests.

## Challenged Decisions

### "No formal perf target at v1"

This is the wrong consequence from "v1 is narrow." A narrow v1 still needs guardrails on the hot paths it touches. It does not need a grand benchmark suite, but it needs minimum targets:
- socket `identify` and `tree` latency with 3 windows and 30 panes,
- no added keystroke latency in `TerminalSurface.forceRefresh` paths,
- sidebar update coalescing under high-frequency status/log/progress writes,
- no main-thread blocking for telemetry commands,
- bounded cost for `locateSurface`, `locatePane`, and notification routing.

The project already has a socket threading policy that warns against `DispatchQueue.main.sync` for telemetry hot paths. CMUX-25 adds more global data to return from exactly those commands. "Measure later" is how regressions slip through silently.

### The sync-mode seam is premature in the wrong way

Keeping internal data structures capable of future sync mode is good. Persisting `.primary` / `.viewport` and adding a no-op `broadcastSelection` method is risky unless v1 also has strict fallback behavior and tests that prove unwired modes cannot leak into runtime. The cleaner v1 seam is probably:
- store only `.independent` in released snapshots,
- decode unknown/future values to `.independent` with a warning,
- keep any future-mode enum internal or feature-flagged,
- document the full future ownership model separately before adding public modes.

### Feature flag retirement after Phase 3 is unsafe

The feature flag should survive until all user-facing v1 phases have soaked, not just registry refactor plus pane migration. Phase 4 sidebar changes can break daily navigation; Phase 5 and Phase 6 create new cross-window topology. If the flag is removed before those, the team loses rollback for the pieces most users will actually exercise.

The plan also needs a "bug found during soak" rule. If Phase 3 shows a week-two race, does the flag stay, does Phase 4 pause, does the release cycle reset, and who owns the rollback decision?

### One-release deprecation shim is too short

Renaming to `workspace.move_frame_to_window` is semantically correct, but one release is not enough unless usage is instrumented. This is an automation-facing API, and automations are often unowned. Keep the alias longer, maybe indefinitely, unless there is a concrete maintenance cost. At minimum:
- add deprecation notice in docs and CHANGELOG,
- include the notice in CLI stderr as well as JSON,
- log usage in a way release owners can count,
- remove only after observed usage is zero for a release.

### `workspace.spread all_on_each` should be cut or explicitly designed

`all_on_each` is described as rare and useful for screen-share review, but it creates the hardest rendering problem: the same pane/surface visible in multiple windows. That is not needed for the v1 north star of distributing panes across displays. Unless there is a defined multi-renderer model for Ghostty/browser/markdown surfaces, this mode should be removed from v1. Otherwise it will contaminate the invariants for every pane reference.

## Hindsight Preview

Two years from now, the likely "we should have known" statements are:

- We should have written a resolver contract before implementing registries. The code kept answering ambiguous workspace lookups with "first match" and it took months to unwind.
- We should have treated pane moves as transactions. The bugs were not in dictionary mutation; they were in half-applied moves visible to focus, autosave, drag callbacks, and socket responses.
- We should not have shipped duplicate pane rendering in `all_on_each`. Moving panes was tractable; showing one live AppKit/Metal surface in multiple frames was a different feature.
- We should have kept the feature flag longer. The worst issues only appeared after real multi-monitor workdays, not in the first smoke pass.
- We should have instrumented old API usage before removing the alias.
- We should have set a small perf budget. Nobody noticed the regression in CI because everything still passed.

Early warning signs:
- Any code path still named `tabManagerFor(tabId:)` after Phase 2.
- Any `workspace_ref` socket command that returns exactly one `window_ref` without stating caller-scoped resolution.
- Any move implementation with separate public `detach` and `attach` calls but no transaction object.
- Any persistence migration that does not have duplicate/merge fixtures.
- Any drag test that only covers two visible normal windows on the same Space.
- Any snapshot schema bump that still rejects older versions instead of migrating them.
- Any feature-flag removal PR before Phases 4-6 have soaked.

## Reality Stress Test

### Disruption 1: A user keeps the same workspace open in two windows all day

This is not an edge case; it is the point of Emacs frames. They select the same workspace on left and right displays, move panes around, receive notifications, use keyboard focus, and run socket commands from agents. Without explicit invariants, the app will randomly route notification jumps and socket commands to whichever context `mainWindowContexts.values` returns first. The user will see wrong-window focus, stale sidebar counts, or command output that says a pane is in window A while the visible pane they care about is in window B.

### Disruption 2: A drag/drop move races a window close

User drags a terminal tab from window A toward window B, then closes or loses window A due to a workspace cleanup, app quit, or accidental close. Existing unregister logic removes the context and clears notifications. Target drop still has a pasteboard payload and may call `moveBonsplitTab`; source lookup can fail, or worse, succeed against stale data. The plan needs a pane move lifecycle that can say "source gone, cancel cleanly" or "pane lease survives source frame close."

### Disruption 3: Agents hammer the socket while the operator types

Multiple agents call `identify`, `tree`, `surface.list`, metadata updates, and pane moves. The plan adds display/window/frame data to common responses and central registries. Without a perf target and hot-path policy, main-thread sync calls and broad scans can degrade typing or focus. The regression may be intermittent and invisible in tests unless measured.

If all three happen together, the current plan has no containment story. The user is in the flagship multi-monitor workflow, a pane is mid-move, a frame closes, and socket telemetry is active. That is exactly where this feature must be most reliable.

## The Uncomfortable Truths

The plan is more confident about the existing code than the code warrants. The phrase "natural generalisation" hides a lot. Current `moveSurface` is a detach/attach transaction between workspaces (`Sources/AppDelegate.swift:4084`, `Sources/AppDelegate.swift:4208`, `Sources/AppDelegate.swift:4221`) layered on top of workspace-owned panels. That is not the same operation as moving a process-scoped pane between frame references.

The plan's v1/v2 boundary is inconsistent. Hotplug is correctly deferred, but close-window, minimized-window drag, fullscreen/Spaces drag, and last-frame pane survival are not v2 hotplug problems. They are direct consequences of v1 multi-window hosting.

The current persistence system is not ready for the proposed schema migration. It has a version constant and a hard equality check, not a migration pipeline. Treating migration as a bullet in Phase 2 is optimistic.

The `all_on_each` spread mode is a trap. It sounds like a minor option, but it forces the hardest possible interpretation of "pane references": simultaneous multi-frame rendering of live surfaces. It should not be in v1 unless the implementation deliberately supports multi-view rendering.

The feature flag plan is underpowered. This feature changes the core mental model of the app. Removing the flag after Phase 3 because it soaked for one release cycle is arbitrary unless the later phases are also behind a separate flag or Phase 3 is redefined as the complete v1 behavioral boundary.

## Hard Questions for the Plan Author

1. When the same workspace is hosted in windows A and B, what should `workspace_ref` alone resolve to for every socket command? Caller window? Focused window? All frames? Error requiring `window_ref`?

2. Can the same pane ID appear in two live `WorkspaceFrame`s simultaneously? If yes, how are Ghostty surface, MTL layer, browser WKWebView, first responder, and input ownership represented? If no, why does `workspace.spread all_on_each` exist?

3. What is the exact close-window behavior for a window containing frames with panes that are not referenced by any other frame?

4. What is the exact close-window behavior for a window containing a frame of a workspace that is also visible in another window?

5. Does `PaneRegistry` run on the main actor, its own actor, or both? What is the transaction boundary for `pane.move` across registry, frame, focus, sidebar, and persistence state?

6. How does the plan prevent two concurrent moves of the same pane from both succeeding partially?

7. What state does a pane enter while it is being dragged but not yet dropped? Is it still owned by its source frame, leased, moving, or duplicated?

8. What happens if the drag source window closes before the target drop executes?

9. What happens if the target window/frame closes after drop validation but before attach?

10. What AppKit drag/drop matrix must pass before claiming cross-window drag as v1-ready? Visible same-Space windows are not enough.

11. Is `all_on_each` required for v1? If yes, where is the rendering design for one pane in multiple windows?

12. What are the minimum performance budgets for `identify`, `tree`, `pane.move`, sidebar updates, and typing latency with 3 windows and 30 panes?

13. Which socket commands are allowed to activate or order-front windows under the new model, and how is the socket focus policy preserved?

14. How will old snapshots migrate when they contain independent per-window workspaces that happen to have the same name/path? Are they merged or kept separate?

15. What is the migration framework for `SessionSnapshotSchema.currentVersion = 1` snapshots, given current load rejects version mismatches?

16. Why does the feature flag retire after Phase 3 rather than after all six phases soak?

17. If a Phase 3 race appears in week two of soak, what is the explicit rollback/hold policy?

18. Who are the known consumers of `workspace.move_to_window`, including scripts, skills, Lattice, tests, and human aliases? What evidence says one release is enough?

19. Should `workspace.move_to_window` remain as a permanent alias if the only downside is semantic ugliness?

20. What must be true before Phase 2 is considered complete besides "the code compiles and old behavior still works"? The acceptance criteria need invariant-level proof, not just green CI.

## Minimum Changes I Would Require Before Implementation

1. Add a multi-hosted workspace invariant section to the plan. Include resolver rules for `workspace_ref`, `pane_ref`, `surface_ref`, `window_ref`, and future `frame_ref` if needed.

2. Remove `workspace.spread all_on_each` from v1 or explicitly design multi-renderer panes.

3. Define `pane.move` as a transaction with lifecycle states, idempotency, rollback, and stale-callback handling.

4. Define close-window semantics for non-final and final frames.

5. Add a persistence migration design with fixtures for old nested window snapshots and new shared workspace/frame snapshots.

6. Keep the feature flag until all six phases have soaked, or split flags by risk area.

7. Set small but concrete perf budgets for socket and typing-sensitive paths.

8. Extend the deprecation window or instrument usage before removal.

9. Expand the drag/drop acceptance matrix beyond one happy-path integration test.

10. Make Phase 2 acceptance depend on removing first-match workspace ownership lookups, not merely introducing new registry types.
