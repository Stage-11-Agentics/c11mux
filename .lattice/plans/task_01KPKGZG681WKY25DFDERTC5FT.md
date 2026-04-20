# CMUX-23: Multi-window c11mux: display registry + CLI surface

Parent: CMUX-16 (task_01KPHHQZA4XZTQD4BQCGQYC7FR). Plan: .lattice/plans/task_01KPHHQZA4XZTQD4BQCGQYC7FR.md (sub-ticket 16a).

## Scope

Introduce a process-scoped `DisplayRegistry` that enumerates the current `NSScreen`s and exposes them via:

- Stable `display:<cmuxDisplayID>` refs, positional aliases `left` / `center` / `right` computed from sorted `frame.minX` (`center` only when N is odd), and numeric indices `display:1` / `display:2` / ... .
- New socket command `display.list` (schema documented in the plan's Socket API additions section).
- Extend `cmux identify`, `window.list`, and `tree` to include `display_ref` for every window.
- `tree --by-display` flag for a display → windows → workspaces → panes projection.

## Out of scope

- No runtime hotplug response (v2 follow-up).
- No cross-window / cross-display behavior changes — this ticket is pure metadata enrichment + enumeration. Lays the ground truth that later sub-tickets and manual `cmux window new --display <ref>` flows depend on.

## Estimate

~1 week.

## Links

- Blocks: CMUX-16b, 16c, 16d, 16e, 16f (all reference display refs).
- Ground truth for manual window→monitor assignment flows in 16b+.
