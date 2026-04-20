# CMUX-25 Evolutionary Review - Codex

PLAN_ID: cmux-25-plan
MODEL: Codex
Review timestamp: 20260419-1527

## Executive Summary

The biggest opportunity is to treat CMUX-25 as the birth of a process-scoped pane runtime and viewport graph, not merely as multi-window support. The plan already points there with `PaneRegistry`, `WorkspaceFrame`, process-scoped workspace state, and the Emacs-frames north star. If those primitives are shaped carefully in Phase 2, c11mux gets a foundation that tmux, iTerm2, Ghostty tabs, WezTerm, Zellij, and JetBrains-style detached windows do not have: addressable live terminal/browser/markdown work objects that can be moved, mirrored, grouped, broadcast to, parked headlessly, and rendered through many native Mac windows without losing identity.

My strongest recommendation: keep the six-phase CMUX-25 sequence, but use Phase 2 to add two small, explicit seams that are not in the plan yet:

1. Give `WorkspaceFrame` its own stable `FrameID` and role, even if v1 still enforces one active frame per `{workspace, window}`.
2. Introduce a first-class `PanePlacement` / `PaneAttachment` ledger between `PaneRegistry` and `WorkspaceFrame` leaves, even if v1 supports only one primary render attachment per pane.

Those two seams prevent v1 from accidentally becoming "move tabs between windows" instead of "frames onto shared process state." They unlock mirror mode, present mode, pane groups, headless panes, agent addressing, frame synchronization, display profiles, and session flywheels without breaking the locked primitive hierarchy.

## What's Really Being Built

The surface feature is "multi-window c11mux." The underlying capability is a separation between runtime identity and visual placement.

Today those are fused:

- `TabManager` is the window-owned manager and carries `@Published var tabs: [Workspace]` in `Sources/TabManager.swift:649`.
- `Workspace` owns both the logical workspace state and the visual/runtime guts: `let bonsplitController: BonsplitController` plus `panels: [UUID: any Panel]` in `Sources/Workspace.swift:4961`.
- Session persistence embeds `SessionTabManagerSnapshot` inside each `SessionWindowSnapshot` in `Sources/SessionPersistence.swift:452`, so windows still serialize ownership of their workspaces.
- `AppDelegate.moveWorkspaceToWindow` literally detaches a `Workspace` from one `TabManager` and attaches it to another at `Sources/AppDelegate.swift:4026`.
- The more promising seam already exists in `AppDelegate.moveSurface` at `Sources/AppDelegate.swift:4085`: it locates a surface globally, detaches it from one workspace, and attaches it elsewhere.
- The socket layer also already wants this world: `v2ResolveTabManager` in `Sources/TerminalController.swift:3486` falls back through window, workspace, surface, tab, and panel identity, then active window state.
- Bonsplit already has the intra-process drag primitive: `TabTransferData` carries a source process id, and TabBar/PaneContainer routes external drops through `BonsplitController.ExternalTabDropRequest`.

CMUX-25 is therefore really building:

- A process-level object plane: workspaces, panes, surfaces, metadata, agents, ports, progress, notifications.
- A window/frame view plane: NSWindows, sidebars, selected workspace, bonsplit trees, focus state, display placement.
- A routing plane: socket commands and drag/drop that resolve identities across all windows.

That is more valuable than display spanning by itself. It is a local, native, agent-aware object graph for live work.

## How It Could Be Better

### 1. Split `Pane` into runtime plus attachment

The plan says `PaneRegistry` owns panes and panes hold "PTY, Ghostty surface, MTL layer." That is the right v1 mental model for moves, but it risks baking in a one-pane-one-renderer assumption too deeply.

A more future-proof shape:

```swift
struct PaneRuntime {
    let paneId: UUID
    let workspaceId: UUID
    let surfaces: [SurfaceID]
    let metadata: SurfaceManifest
    let processState: TerminalOrBrowserRuntime
}

struct PaneAttachment {
    let attachmentId: UUID
    let paneId: UUID
    let frameId: UUID
    let role: PaneAttachmentRole // primary, mirror, observer, headless
    var viewportState: PaneViewportState
}
```

In v1, c11mux can enforce exactly one `.primary` attachment per pane and no true mirror rendering. That is fine. The important part is to avoid making "the pane is the view" a permanent invariant. Ghostty may not allow one surface or MTL layer to be hosted by multiple AppKit view hierarchies at once; if so, `PaneAttachment` becomes the place to represent separate viewport/render adapters over one process/runtime.

This one distinction unlocks pane-as-primary with many viewports later without forcing a second registry refactor.

### 2. Give frames identity beyond `{workspace, window}`

The plan defines `WorkspaceFrame` as one bonsplit tree per `{workspace, window}`. That is clean for v1, but it should not be the storage identity. Use:

```swift
struct WorkspaceFrame {
    let frameId: UUID
    let workspaceId: UUID
    let windowId: UUID
    var role: WorkspaceFrameRole // independent, primary, viewport, mirror, presentation
    var bonsplitController: BonsplitController
}
```

Then v1 can enforce "at most one active normal frame for a workspace in a window" at the API layer. Future features can allow:

- Two frames for the same workspace in one window, for side-by-side compare.
- A read-only mirror frame on a projector.
- A synchronized follower frame for a pair programming or review flow.
- A nested or composited frame for "workspace dashboard" layouts.

This stays inside the locked hierarchy: Window -> Sidebar -> Workspace -> WorkspaceFrame -> Pane -> Surface -> Tab. It simply prevents the `{workspace, window}` tuple from becoming an accidental ceiling.

### 3. Add a placement ledger in Phase 2

`workspace.spread`, `pane.move`, drag/drop, hotplug, present mode, and hibernation all need the same fact table:

```swift
struct PanePlacement {
    let placementId: UUID
    let paneId: UUID
    let workspaceId: UUID
    let frameId: UUID?
    let windowId: UUID?
    let displayRef: String?
    let state: PanePlacementState // attached, headless, hibernated, migrating
    let role: PanePlacementRole // primary, mirror, observer
}
```

If Phase 2 creates this internally, later phases become much smaller:

- `tree --by-display` is just a projection.
- `pane.move` mutates placement.
- `workspace.spread` computes a batch of placements.
- CMUX-26 hotplug moves or suspends placements.
- Sidebar badges derive "which windows host this workspace" without scanning view hierarchies.
- Agents can address panes without caring where they currently render.

The plan already has the data implicitly. The evolution is to make it explicit.

### 4. Make selectors a first-class socket concept

The socket plan adds concrete refs: `pane_ref`, `window_ref`, `display_ref`, `workspace_ref`. The agent-native leap comes when commands can target by manifest and placement selectors:

```bash
cmux pane.list --where 'role=build && status=idle'
cmux pane.broadcast --group review-runners 'git status'
cmux pane.move --where 'task=CMUX-25 && role=browser-validator' --display right
cmux workspace.spread --by role
```

This compounds with c11mux's existing sidebar status/log/progress and surface metadata. Once agents self-report role, task, status, progress, branch, and ports, the pane registry can become a queryable live work graph.

### 5. Treat window close as a first-class semantic event

CMUX-25 says no runtime hibernation at v1, which is sensible for display hotplug. But the core Emacs-frame property requires a crisp answer when a user closes a window that hosts the only frame for a live pane.

Do not leave this as implicit UI behavior. Pick a v1 rule and encode it in the registry:

- Migrate orphaned panes to the nearest surviving frame for the same workspace.
- Or put them into a headless/parked placement state, even if the UI only exposes "restore parked panes" later.
- Or make close-window prompt if it would destroy the last placement of running panes.

This is less about hotplug and more about preserving the new object model's trust: closing a viewport must not accidentally mean destroying the work object.

## Mutations and Wild Ideas

### Pane-as-primary, many viewports

Let one pane be the canonical runtime while many frames observe it. The side monitor can show a read-only follow view of a build pane. A presentation window can mirror the command pane while the operator keeps a private frame with notes and agents. A reviewer can open the same browser surface and terminal log in a second frame without moving them away from the original layout.

Possible commands:

```bash
cmux pane.mirror pane:7 --window window:2 --mode follow
cmux pane.attach pane:7 --frame frame:3 --role observer
cmux pane.detach --attachment attachment:9
```

The mechanism is `PaneRuntime` plus `PaneAttachment`.

### Frame mirror and frame follow

If panes can be attached through frames, whole frames can be mirrored:

```bash
cmux frame.mirror frame:1 --display right --follow focus
cmux frame.follow frame:2 --source frame:1 --sync layout,selection
cmux frame.unlink frame:2
```

Modes worth distinguishing:

- Layout mirror: same tree, independent focus and scroll.
- Focus follow: secondary frame follows primary focused pane.
- Read-only observer: input is blocked in the follower.
- Review mirror: input allowed only in selected panes.

This is the bigger version of the plan's future primary-sidebar mode.

### `workspace.present`

Present mode is probably the first high-value user-facing mutation after v1:

```bash
cmux workspace.present --source current --display right --mode follow-focus
```

It creates a second frame on a target display, mirrors the primary frame's layout, follows focus, and renders only selected panes or surfaces. A presenter can keep their private window with agents, notes, and scratch panes while the audience sees the terminal/browser flow.

c11mux has an advantage here because browser and markdown surfaces are first-class alongside terminals. Present mode can show a browser validation surface, a markdown checklist, and a terminal log as one coherent frame.

### Pane groups and broadcast

A process-scoped `PaneRegistry` naturally supports pane groups:

```bash
cmux pane.group create test-runners --where 'task=CMUX-25 && role=test'
cmux pane.broadcast test-runners 'git pull && ./scripts/reload.sh --tag cmux-25'
cmux pane.group spread test-runners --displays all
```

This is tmux synchronize-panes generalized through metadata, workspaces, windows, and displays. It should be selector-based, not just "all panes in this grid."

### Headless panes and parking

Once panes are registry-owned, rendering should be optional. A pane can be:

- Attached to a frame.
- Headless but running.
- Hibernated with PTY/process state preserved if possible.
- Archived as scrollback plus manifest if process state is gone.

Possible commands:

```bash
cmux pane.park pane:4
cmux pane.wake pane:4 --display left
cmux pane.list --state headless
```

This makes window churn safe and gives CMUX-26 a cleaner hotplug story.

### Cross-workspace pane sharing

The plan says a workspace owns a set of Pane IDs. That can later become "a workspace owns primary membership, but frames may reference shared panes." A build monitor pane could appear in both "Backend" and "Release" workspaces. A browser validation pane could be shared between an implementation workspace and a review workspace.

This needs discipline to avoid confusion. The mechanism is the same: placement and attachment roles. Start with read-only shared placements.

### Agent rooms

c11mux already has process-scoped socket control, sidebar status/log/progress, and the cmux skill. With `PaneRegistry`, a workspace can become an agent room:

- Coordinator pane.
- Worker panes tagged by task bucket.
- Browser panes tagged as validators.
- Markdown panes tagged as plan/spec.
- Group broadcast to all workers.
- `pane.watch` subscriptions for completion/status.

No other terminal multiplexer has a native GUI object graph and agent status plane to make this feel first-class.

## What It Unlocks

### Agent-to-pane addressing

Instead of "send to surface 3 in workspace 2," agents can address intent:

```bash
cmux send --where 'role=reviewer && task=CMUX-25 && status=idle' 'Read /tmp/prompt.md'
cmux pane.focus --where 'role=browser-validator && task=CMUX-25'
```

The underlying mechanism is stable pane identity plus metadata. The user sees named work. Agents see queryable objects.

### Zellij session-attach for native GUI

Zellij can attach clients to a session. c11mux can do the native GUI version: multiple NSWindows are clients/frames over one process-scoped session graph. The differentiator is that each client is not a terminal emulator instance. It is a native Mac viewport with sidebars, browser/markdown surfaces, notifications, and socket metadata.

### Pane hibernation without losing PTY state

Even if true process hibernation is deferred, "headless attached runtime" is valuable by itself. Panes can survive window close, display disconnect, layout collapse, or workspace hiding. Operators learn that panes are durable work objects, not rectangles.

### Display topology as compute topology

With display refs and frame placements, displays become part of automation:

- Left display: agents and logs.
- Center display: active coding shell.
- Right display: browser validation and docs.

`workspace.spread` can evolve from a geometric command into a role-aware placement engine:

```bash
cmux workspace.spread --profile review-loop
cmux workspace.spread --by role --weights left=agents,center=active,right=validation
```

### Frame composability

Once `WorkspaceFrame` is first-class, frames can be saved, cloned, mirrored, synchronized, nested, or treated as named views:

```bash
cmux frame.save current --name review-driver
cmux frame.apply review-driver --workspace CMUX-25 --display center
cmux frame.clone frame:1 --display right --role mirror
```

This is where "Emacs frames, for terminals" becomes bigger than Emacs frames.

### Process-scoped sidebar as command center

Phase 4 should not just split local/shared sidebar state. It sets up a command center over the object graph:

- Which windows host this workspace?
- Which panes are running?
- Which panes are headless?
- Which agents are idle or stuck?
- Which panes belong to the current Lattice task?
- Which frame is primary?

The sidebar can become the operator's live inventory of work, not just a tab list.

## Sequencing and Compounding

### Before Phase 1: freeze identity vocabulary

Add the vocabulary to the plan before implementation starts:

- `FrameID`
- `PaneID`
- `SurfaceID`
- `PlacementID` or `AttachmentID`
- `PaneRuntime`
- `PaneAttachment`
- `WorkspaceFrameRole`
- `PanePlacementState`

This is cheap and prevents Phase 2 churn.

### Phase 1: make display refs projection-ready

Phase 1 should keep its "no behavior change" scope, but the `tree` and `identify` additions should include enough shape for future placement projections. If a window gets `display_ref`, make sure the debug/schema language can naturally extend to frame and placement refs.

Suggested early output direction:

```json
{
  "window_ref": "window:1",
  "display_ref": "display:left",
  "frames": []
}
```

Even if frames are not wired until Phase 2, avoid a Phase 1 schema that assumes windows directly own workspaces forever.

### Phase 2: invest slightly more in the object model

Phase 2 is the leverage point. Add `WorkspaceRegistry`, `PaneRegistry`, `WorkspaceFrame`, and the session schema bump as planned, but include:

- `FrameID`.
- A placement/attachment table.
- Headless/parked placement state, even if hidden.
- Debug-only `frame.list` / `pane.list` or equivalent `tree --json` fields.
- A compatibility layer for old `TabManager`-centric socket resolution.

This is the one phase where small extra design saves large future rework.

### Phase 3: make moves emit placement events

Cross-window drag/drop and `pane.move` should not only mutate state. They should emit debug/socket-visible placement events:

- `pane.placement.created`
- `pane.placement.moved`
- `pane.placement.detached`
- `pane.placement.headless`

c11mux already has a strong debug event log culture. Placement events will make multi-window bugs tractable and give future agents a stream to observe.

### Phase 4: make sidebar mode a frame mode, not just UI mode

The plan's `SidebarMode` seam is good. The bigger version is a relation between frames:

- independent frame
- primary frame
- viewport frame
- mirror frame
- presentation frame

The sidebar can expose only `.independent` in v1, but the model should not imply that synchronization is only sidebar selection. Future sync wants layout, focus, pane visibility, and input mode as separate dimensions.

### Phase 5: make `workspace.spread` selector-aware soon after v1

The v1 spread modes are good. The first post-v1 extension should be metadata-aware spread:

```bash
cmux workspace.spread --by role
cmux workspace.spread --where 'status=running'
cmux workspace.spread --profile last-good
```

That compounds directly with agent metadata and makes c11mux feel agent-native rather than display-native.

### Phase 6: define overflow as frame creation

`cmux new-split --spawn-window` should be described internally as "create a new frame and attach the new pane there," not "special-case split into a new NSWindow." That phrasing keeps it aligned with the registry model and makes later frame mirroring/composition natural.

## The Flywheel

### Metadata -> placement -> better metadata

Agents already report status, progress, ports, git branch, and task metadata. Once panes are registry objects, those metadata fields can drive placement:

1. Agent reports `role=builder`, `task=CMUX-25`, `status=running`.
2. c11mux spreads builders to the left display and validators to the right.
3. The sidebar shows grouped live work.
4. Agents and users rely on those groups, so they report better metadata.
5. Better metadata enables better layout, routing, and automation.

This is the core agent-native flywheel.

### Session restore -> trust -> more ambitious layouts

If panes survive window churn and restore with stable identity, users will create bigger spatial workspaces. Bigger workspaces make `workspace.spread`, profiles, and frame roles more valuable. More use produces more real topologies to encode into profiles.

### Placement logs -> regression tests -> safer refactors

Placement events give the team observable behavior for multi-window flows. That makes it easier to test drag/drop, move, spread, close-window migration, and hotplug later. Safer tests make the registry more reliable, which increases trust in durable panes.

### Saved profiles -> repeated workflows -> product memory

Every successful multi-display setup can become a reusable profile:

```bash
cmux profile.save review-loop
cmux profile.apply review-loop --task CMUX-25
```

As users and agents reuse profiles, c11mux becomes faster to set up for the next task. That is a real product memory loop without needing cloud intelligence.

### Agent rooms -> more agent work -> stronger cmux primitives

The more c11mux can host clear/coordinator/worker/validator panes with stable identities, the more agents will use c11mux-specific primitives. The more agents use those primitives, the more valuable the process-scoped socket and metadata plane become.

## Concrete Suggestions

1. Add `FrameID` to Phase 2. Do not let `{workspace_id, window_id}` be the only identity. Enforce one normal frame per tuple in v1 if needed, but store frames as objects.

2. Add a `PanePlacement` or `PaneAttachment` table in Phase 2. Make it the source for `tree`, sidebar hosted-window counts, `pane.move`, `workspace.spread`, and later CMUX-26 hotplug behavior.

3. Separate pane runtime state from viewport state in names and code. Treat PTY/Ghostty/browser runtime, surface metadata, and process identity as pane/surface runtime; treat scroll position, focus, frame leaf, zoom, follow mode, and render host as attachment/viewport state.

4. Add debug-only or socket-visible `frame.list` and `pane.list` after Phase 2. Even if user-facing docs wait, implementers and agents will need to inspect the new graph.

5. Extend `tree --json` with `frame_ref`, `pane_ref`, `placement_ref`, `display_ref`, and `attachment_role` as soon as the model exists. Avoid making `tree` a window-first shape that must be broken again later.

6. Define the v1 close-window rule before implementation. Prefer "last attached panes migrate to another frame in the same workspace, otherwise become headless/parked" over accidental destruction.

7. Add `pane.group` and `pane.broadcast` as the first post-v1 agent-native feature. This is small, practical, and showcases the registry better than mirror mode does.

8. Add selector support to `workspace.spread` post-v1: `--by role`, `--where`, and `--profile`. This turns display spreading into workflow spreading.

9. Add `frame.mirror` before full sidebar sync mode. Mirroring one frame to one display is a tighter, more demonstrable step than designing the whole primary-sidebar UX.

10. Add `workspace.present` as a composed command over `frame.mirror`, focus-follow, and read-only input. It is a crisp differentiator and gives "Emacs frames, for terminals" a visible story.

11. Preserve `moveSurface` DEBUG logging style during Phase 2. The existing `surface.move.*` logs are exactly the kind of breadcrumbs that cross-window placement bugs will need.

12. Make every new non-focus socket command preserve focus by default. This aligns with the repo policy and is especially important once agents can rearrange panes across windows while the operator is typing.

13. Consider `PaneRegistry` as actor-isolated but keep UI mutations minimal and main-actor explicit. The repo's socket threading policy already warns against hot telemetry on main. Placement queries and selector resolution should be off-main where possible; frame/render mutations can hop to main.

14. Add a tiny "placement profile" file format after spread lands. It can be local-only and simple: display refs, frame roles, selectors, and split hints. This starts the workflow memory flywheel.

15. Document the distinction between `Surface`, `Tab`, `Pane`, `PaneAttachment`, and `WorkspaceFrame` in developer docs immediately. The current plan locks the primitive hierarchy; adding the runtime/view distinction will prevent future contributors from re-fusing the layers.

## Questions for the Plan Author

1. Can one `PaneID` legally appear in more than one `WorkspaceFrame` leaf in the future? If v1 says no, should the Phase 2 data model still allow it?

2. Is `WorkspaceFrame` identity permanently `{workspace_id, window_id}`, or can it have a `FrameID` with `{workspace_id, window_id}` as fields?

3. What is the exact v1 behavior when a user closes the only window/frame that hosts a running pane?

4. Which state is pane runtime state, and which state is viewport state? Specifically: scroll position, search overlay state, zoom, focused surface, title-bar collapsed state, and browser focus.

5. Should cross-window `pane.move` default to preserving macOS focus unless `focus: true` is passed? The socket focus policy suggests yes.

6. Do agents get a blessed metadata vocabulary for `role`, `task`, `status`, `owner`, `group`, and `capabilities`, or is that intentionally left loose?

7. Should `workspace.spread` distribute by pane creation order, current bonsplit order, last focus order, or selector order when metadata is unavailable?

8. Should `SidebarMode.primary` / `.viewport` be modeled as sidebar behavior only, or as frame synchronization roles that can later include layout/focus/input sync?

9. Is the `CMUX_MULTI_FRAME_V1` flag intended as a user-visible feature flag, a migration guard, or both? What state is allowed to persist while the flag is off?

10. Should Phase 2 persist placement history, or only current placement? History would help hotplug, restore, and profile suggestions later.

11. For browser and markdown surfaces, is "pane runtime" the right abstraction, or should `SurfaceRuntime` be the deeper unit and `Pane` mostly group surfaces/tabs?

12. What is the smallest acceptable present mode? A read-only mirror of the focused frame on a target display may be enough to validate the whole frame-sync direction.

13. Should there be a user-visible "parked panes" affordance in v1, or can it remain a hidden recovery/debug surface until CMUX-26?

14. How much of this should be surfaced through v2 socket APIs immediately versus held as internal model seams until after CMUX-25 lands?

15. What would prove that CMUX-25 is not merely parity with terminal multiplexer multi-window features, but a new c11mux-native capability? My answer: selector-addressable panes plus frame mirroring/present mode.
