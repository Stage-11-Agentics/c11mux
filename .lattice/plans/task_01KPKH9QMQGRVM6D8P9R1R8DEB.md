# CMUX-26: Multi-window c11mux v2: display hotplug + affinity + auto-reconnect

Parent spike: CMUX-16 (task_01KPHHQZA4XZTQD4BQCGQYC7FR). v1 implementation: CMUX-25. Plan: .lattice/plans/task_01KPHHQZA4XZTQD4BQCGQYC7FR.md (§6 — Session restore / hotplug, "Deferred to v2" block).

## Why this is a separate ticket

v1 (CMUX-25) deliberately scopes hotplug behavior out. Users spawn windows and assign them to monitors manually; when a monitor disconnects, macOS auto-migrates the window to a surviving display and c11mux does nothing. This is fine for the v1 "just let me use multiple windows" envelope.

This ticket picks up the work once v1 has soaked and real usage tells us what's needed.

## Scope

- **Per-window display-affinity tracking.** Each window records the `NSScreen.cmuxDisplayID` it was last on. Persisted through session restore (schema already set up in CMUX-25 Phase 2).
- **Runtime `didChangeScreenParametersNotification` handling.** When a previously-seen display reappears, offer to move windows that originated there back to it.
  - Settings: auto-restore / prompt / never (default TBD based on v1 operator feedback).
- **Optional hibernation store.** For the "3 monitors → 1 monitor → back to 3" undock/redock flow, optionally hibernate windows from disappearing displays instead of relying on macOS migration. Only implement if v1 operator feedback asks for it.
- **Sidebar affordance.** If hibernation ships, add a "⎇ N hibernated windows" entry in the sidebar with a click-to-restore action.
- **`workspace.move_to_display` / `window.move_to_display` audit.** Ensure the v2 auto-restore behavior layers cleanly on top of the v1 manual commands without double-triggering.

## Non-goals (still)

- **Merge-two-windows-into-one.** Logged as a separate far-future wishlist (Atin's "advanced far future feature"). Not in this ticket.
- **Cross-machine displays** (Sidecar, DeX) — treat as regular NSScreens as with v1.

## Depends on

CMUX-25 (v1 Emacs-frames implementation) — this ticket can't start until the process-scoped registry and session-persistence schema from Phase 2 are on main.

## Estimate

~1 week + CI work. Hotplug is painful to test automatically; may need a scripted display-toggle rig (runtime swap of fake `NSScreen`s) or manual verification in review.

## Open question at pickup time

Re-survey v1 operator behavior before starting: do people want auto-restore-on-reconnect by default, or is manual re-assignment preferred? The default should be informed by real usage, not pre-specified here.
