# CMUX-16 — Multi-monitor support

Plan note for whoever picks this up.

## Quick orientation

The app already has a real display layer — you are not starting from zero.

- `NSScreen.cmuxDisplayID` — extension in `Sources/AppDelegate.swift` (~line 1452) that returns the macOS `NSScreenNumber` as a stable per-session ID.
- `SessionDisplayGeometry` (struct, ~line 1979) — `(displayID, frame, visibleFrame)`.
- `PersistedWindowGeometry` (struct, ~line 1985) — `(frame, display)`, stored at quit, restored at launch.
- `attemptStartupSessionRestoreIfNeeded` (~line 2854) — already tries to put a restored window back on its last display.
- `createMainWindow(...)` and `moveWorkspaceToNewWindow(...)` are the two spawn paths. Neither currently accepts a display argument.

Read those before proposing any new abstraction. The design space is constrained by what's already there — the right first move is usually "expose what exists" before "add a new layer."

## Suggested spike shape

Break the spike into three small investigations, each ending in a 1-page note:

1. **Addressing**: how do we talk about displays? Compare three options (numeric index by position; alias like `display:left/center/right`; user-assigned names) and pick one based on what Atin actually does day-to-day (32" center + flanking). Output: proposal + one concrete `cmux list-displays` shape.

2. **Targeting commands**: what's the minimum set? At least `cmux list-displays`, `cmux new-window --display`, and `cmux move-window --display`. Check whether the socket command surface in c11mux already has anything similar and mimic its shape. Output: command signatures + a tiny state diagram for what happens when the target display doesn't exist.

3. **Keyboard/menu**: does this feature need UI on day 1 or can it ship CLI-only? If UI, where does it live (Window menu probably). Output: a one-paragraph call on CLI-first vs UI-first, with rationale.

After the three investigations, split into implementable sub-tasks. Do NOT try to ship all of multi-monitor in one PR.

## Boundaries — what NOT to pull in

- **Per-display default grid (3x3 / 2x3 / 2x2)** — that's **CMUX-15**. Linked as `related_to`. This ticket's job is to get windows onto the right displays in the first place. The sibling ticket's job is to decide what each window looks like once it's there. Keep the concerns separate; they'll compose naturally at the end.
- **Mirror / span modes** — explicit non-goals in v1. Users who want that can just open multiple windows.
- **Sidecar / DeX / AirPlay** — treat as regular NSScreens. Don't special-case.

## Agent-facing value (why this matters beyond humans)

c11mux is host for parallel agents. Today, all agent panes pile into one window and one display. Multi-monitor addressing means an orchestrator can say "put my reviewers on display 2 so the operator can see them at a glance while I work on display 1." That's not a gimmick; it's how the operator stays in the loop on N agents at once without tab-juggling. Worth keeping in mind when choosing whether this is CLI-first (agents will use it immediately) vs UI-first (humans only).

## Starting reads

- `Sources/AppDelegate.swift`: all the prior-art referenced above.
- `cmux identify` / `cmux tree` output — if they gain display info, many downstream agent tools benefit for free.
- `docs/` — check if there's a spec for the socket/CLI surface that new commands should follow.

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Note already adequate for pick-up as a spike brief — boundaries, three-investigation shape, and the agent-facing value framing are all intact. No substantive expansion needed — added this footer for the grooming pass.
