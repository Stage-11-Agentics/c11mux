# CMUX-15 — Default pane grid sized to monitor class

Plan note for whoever picks this up.

## The intent in one line

When a workspace opens, c11mux should already be split into a grid appropriate for the current monitor — so a hyperengineer lands in a parallel-work layout without manual splits.

## Starting-point table (Atin's proposal, not final)

| Monitor class         | Default grid          |
|-----------------------|-----------------------|
| 32" / 4K and larger   | 3 wide × up to 3 tall |
| ~27" (middle class)   | 2 wide × 3 tall       |
| Smaller than ~27"     | 2 wide × 2 tall       |

## Where to look in the codebase

- Workspace creation path — search for where a new workspace is instantiated and the root pane is created. Likely near bonsplit workspace/session bootstrap.
- `NSScreen.main` / `NSScreen.screens` for detecting display dimensions on macOS. Pixel dimensions (`frame.size`) are the reliable signal; `backingScaleFactor` and `deviceDescription[NSDeviceResolution]` give DPI if needed.
- Split APIs live in `vendor/bonsplit` (forked submodule). See `project_c11mux_bonsplit_submodule` memory — tab bar / splits / drag-drop code is NOT in cmux `Sources/`.

## Detection — recommended approach

- Use pixel dimensions of the screen hosting the workspace window at creation time.
- Suggested thresholds (tune empirically):
  - ≥ 3840×2160 (4K) → large class → 3×3
  - ≥ 2560×1440 (QHD, typical 27") → middle class → 2×3
  - otherwise → small class → 2×2
- Do NOT rely on physical inches — Apple's APIs expose diagonal inches only indirectly via EDID and it's unreliable across external displays.

## Suggestion vs. auto-spawn

Recommendation: **auto-spawn the grid**, because the ergonomic payoff is the layout already existing on workspace open. A config flag (`defaults.gridAutoSpawn: true`) lets users opt out.

## Interaction with saved layouts

Saved workspace layouts always win. Defaults only apply when there's no saved layout for that workspace.

## Open questions (carried from the ticket)

- [ ] Detection signal: pixel dimensions vs. DPI vs. physical inches — recommend pixel dimensions.
- [ ] Global override vs. per-workspace-creation only.
- [ ] Suggestion flow (confirm dialog) vs. auto-spawn (recommend auto-spawn).
- [ ] Saved-layout precedence (recommend: saved always wins).
- [ ] Monitor class change between sessions (laptop undocked, workspace migrated between displays) — reshuffle, keep, or prompt?
- [ ] Per-class grid configurability (user-overrideable table).

## Related work

- Multi-monitor support ticket — sibling agent is creating in parallel. Once it exists, add a `related_to` link. That ticket owns the "what happens when the user has multiple displays and moves windows between them" surface; this ticket is scoped only to default-on-open sizing.

## Scope guardrails

- Do NOT touch multi-monitor routing logic.
- Do NOT change how existing workspaces behave — defaults apply only at creation.
- Saved layouts are sacred; don't overwrite them.

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Note already adequate for pick-up; plan doc at `.lattice/plans/task_01KPHHQ6T4K09KE9YF20KPT8VS.md` is the deeper trident-review-ready spec. No substantive expansion needed — added this footer for the grooming pass.
