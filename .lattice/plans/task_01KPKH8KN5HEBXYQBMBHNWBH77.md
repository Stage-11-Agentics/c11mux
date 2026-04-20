# CMUX-25: Multi-window c11mux: Emacs-frames implementation (phased)

Parent spike: CMUX-16 (task_01KPHHQZA4XZTQD4BQCGQYC7FR). Full plan: .lattice/plans/task_01KPHHQZA4XZTQD4BQCGQYC7FR.md.

**v1 envelope (this ticket):** one c11mux instance that spans all displays as one cohesive workspace — Emacs-frames for terminals. Per-window independent sidebars at v1. No runtime hotplug/hibernation (deferred to a separate v2 ticket).

## Primitive hierarchy (locked, use these terms)

**Window** (NSWindow) → **Sidebar** (window-local, selects workspace) → **Workspace** (process-scoped, owns pane IDs) → **WorkspaceFrame** (one bonsplit tree per {workspace, window}) → **Panes** (process-scoped in `PaneRegistry` — PTY + Ghostty + MTL live here) → **Surfaces** (terminal / browser / markdown; one or more per pane). Tabs are the UI affordance when a pane has >1 surface.

## Phases

Execute in order. Phase boundaries are natural PR boundaries — each should land on main, green on CI, before the next starts. Phase 1 blocks phase 2; phase 2 blocks phases 3–6 (3/4/5/6 can go in parallel after 2 lands).

### Phase 1 — Display registry + CLI surface (~1 week)

Foundation, no behavior change. Introduce `DisplayRegistry` enumerating current `NSScreen`s with:
- Stable `display:<cmuxDisplayID>` refs.
- Positional aliases `left` / `center` / `right` computed from sorted `frame.minX` (center only when N odd).
- Numeric indices `display:1` / `display:2` / ...

Socket API:
- New `display.list` command (schema in plan §Socket API additions).
- Extend `cmux identify`, `window.list`, `tree` with `display_ref` on every window entry.
- `tree --by-display` flag for display → windows → workspaces → panes projection.

No cross-window behavior yet. This phase enables manual window→monitor assignment via `cmux window new --display <ref>`.

### Phase 2 — Workspace/pane registry refactor (~2 weeks)

The biggest lift. Sever TabManager↔NSWindow coupling.

- Introduce `PaneRegistry` (process-scoped, actor-isolated): panes become first-class process objects. PTY / Ghostty surface / MTL layer move here from `Workspace`.
- Introduce `WorkspaceRegistry`: workspaces exist at process scope; carry name, git branch, status pills, pane-ID set.
- Introduce `WorkspaceFrame`: one bonsplit tree per {workspace, window} pair; leaves reference pane IDs.
- Rename `TabManager` → `WindowScope`: per-window state only (selected workspace, sidebar visibility/width, focused pane, tab history).

**Socket API rename:** `workspace.move_to_window` → `workspace.move_frame_to_window`. Old name keeps working as a shim for one release: forwards to new, logs `dlog("deprecated: workspace.move_to_window → workspace.move_frame_to_window")`, adds `deprecation_notice` field to response. CHANGELOG documents the rename and shim window. Shim removed one release after this phase ships.

**Session persistence schema bump.** Migration re-normalises embedded workspace data from `SessionTabManagerSnapshot` into a new top-level `AppSessionSnapshot.workspaces` collection. Window snapshots reference workspace IDs by value. Each window snapshot carries `sidebarMode` (v1 always `.independent`; seam for future sync-mode).

**Ships behind feature flag `CMUX_MULTI_FRAME_V1=1`.** Preserves single-frame-per-workspace semantics at this phase — no visible multi-window behavior, just refactored ownership. Flag retires after Phase 3 soaks on main for a release cycle.

### Phase 3 — Cross-window pane migration (~1 week)

With panes registry-owned, wire cross-window behavior:
- Drag-drop: bonsplit's `.ownProcess` pasteboard visibility already allows intra-process cross-window drops. Add one integration test that drags from window A's TabBarView onto window B's PaneContainerView.
- Audit `draggedOntoWindow` / `firstResponder` swizzles in `AppDelegate.swift` for accidental window-scoping.
- Socket: `pane.move` command (target by `window_ref` and/or `display_ref`; create target window if none exists on that display).
- Keyboard: `Cmd+Shift+Ctrl+<Arrow>` moves focused pane to the window on the neighboring display.
- Fallback: if a blocking AppKit issue surfaces, ship CLI-only cross-window move and reinstate drag at v1.1.

### Phase 4 — Per-window independent sidebar + sync-mode seam (~1 week)

Split `SidebarState` / `SidebarSelectionState`:
- **Process-scoped (shared):** workspace registry, pane registry summaries, notification counts. Single source of truth on `AppDelegate`; Combine publishers drive every window's sidebar.
- **Window-local:** sidebar visibility, sidebar width, selected workspace (drives which `WorkspaceFrame` the window renders), sidebar scroll position, `sidebarMode`.

At v1, `SidebarMode` enum has `.independent` wired; `.primary` and `.viewport` exist as seams. `broadcastSelection(from windowScope:, to targetMode:)` stubbed as no-op in `.independent`. Session persistence round-trips per-window selected workspace + sidebar mode; missing workspace on relaunch falls back to first in registry, no crash.

### Phase 5 — `workspace.spread` command (~3 days)

Socket: `workspace.spread` with modes:
- `one_pane_per_display` (default): round-robin existing panes across new windows, one per display.
- `existing_split_per_display`: preserve bonsplit tree; split along vertical dividers matched to display count.
- `all_on_each`: every pane on every display (rare; screen-share review).

**Distribution heuristic for uneven counts:** `ceil(N/D)` fill leftmost-first. 5 panes / 3 displays = `[2, 2, 1]`. Optional `--weights` CLI flag overrides.

Menu + keyboard entry point.

### Phase 6 — Split-into-new-window (opt-in) (~3 days)

- CLI: `cmux new-split <dir> --overflow-to-display <ref>` and `--spawn-window` flags. Creates a new window (on the given display if passed, positional to current otherwise) and places the new pane as its sole frame.
- Keyboard: `Cmd+Opt+Shift+<Arrow>` — "split overflow."
- Optional UI hint (post-v1): one-time toast when a regular split would leave any pane under ~480px width — "Panes are getting tight — split to display 2?" with a button.

## Deferred to v2 (tracked on a separate ticket)

Runtime hotplug handling, display-affinity memory, auto-reconnect, optional hibernation store, merge-two-windows-into-one command. See sibling ticket.

## Logged as v1.1 wishlist (no ticket yet)

Sidebar edge configurability (per-window left/right placement), primary-sidebar sync-mode UI, merge-windows command.

## Acceptance

- All six phases land on main behind the feature flag `CMUX_MULTI_FRAME_V1=1`; flag is retired after Phase 3 soaks.
- Existing single-window c11mux behavior unchanged with flag off.
- With flag on: `workspace.spread` works across 2+ monitors; cross-window drag-drop moves panes; `cmux window new --display left` opens on the left monitor.
- Session restore round-trips per-window workspace selection and `sidebarMode`.
- CHANGELOG documents the `workspace.move_to_window` → `workspace.move_frame_to_window` rename and shim window.
- No formal perf target at v1 (per resolved Q1); open a follow-up perf ticket if multi-display regressions surface.

## Links

- Spike / design home: CMUX-16 (stays in `review` until spike sign-off, independent of implementation).
- v2 follow-up: *Display hotplug + affinity + auto-reconnect* (separate backlog ticket).
