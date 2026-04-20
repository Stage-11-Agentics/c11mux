# CMUX-24: Multi-window c11mux: workspace/pane registry refactor

Parent: CMUX-16 (task_01KPHHQZA4XZTQD4BQCGQYC7FR). Plan: .lattice/plans/task_01KPHHQZA4XZTQD4BQCGQYC7FR.md (sub-ticket 16b — the biggest lift).

## Scope

Sever the TabManager↔NSWindow coupling. Introduce:

- `PaneRegistry` — process-scoped actor-isolated store for panes (PTY, Ghostty surface, MTL layer live here).
- `WorkspaceRegistry` — process-scoped store of workspaces (name, git branch, status pills, owns a set of pane IDs).
- `WorkspaceFrame` — one bonsplit tree per {workspace, window}; leaves reference pane IDs.
- Rename `TabManager` → `WindowScope` (per-window state: selected workspace, sidebar visibility/width, focused pane, tab history).

### Socket API

- Rename `workspace.move_to_window` → `workspace.move_frame_to_window`.
- Old name keeps working as a thin shim for one release: forwards to the new method, logs `dlog("deprecated: workspace.move_to_window → workspace.move_frame_to_window")`, adds `deprecation_notice` to the response so automation can grep.
- CHANGELOG entry at 16b ship: document the rename and the shim window.
- Shim removed one release after 16b lands.

### Session persistence

Schema bump on `AppSessionSnapshot`. Migration: re-normalise embedded workspace data from per-window `SessionTabManagerSnapshot` into a new top-level `AppSessionSnapshot.workspaces` collection. Window snapshots reference workspace IDs by value. Each window snapshot also carries `sidebarMode` (v1 always `.independent`; serialised for forward-compat with a future sync-mode).

## Feature flag

Ship behind `CMUX_MULTI_FRAME_V1=1`. Flag retires after 16c soaks on main for a release cycle.

## Preserved at this step

- Single-frame-per-workspace semantics. No visible multi-window behavior yet — 16b is pure internal ownership refactor.
- All existing socket commands continue to work (with renames where documented).

## Estimate

~2 weeks.

## Links

- Depends on: CMUX-16a (uses display refs in the new `WorkspaceFrame` API).
- Blocks: CMUX-16c, 16d, 16e, 16f (all need the refactored ownership model).
- Incidental finding: TabManager is 5,283 lines; this is the natural moment to split. `WindowScope` stays lean; workspace lifecycle moves to `WorkspaceRegistry`; tab history stays with the window.
