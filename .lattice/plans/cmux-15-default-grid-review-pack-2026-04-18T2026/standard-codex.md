# Review: CMUX-15 Default Grid

- PLAN_ID: `cmux-15-default-grid`
- MODEL: `Codex`

## Executive Summary
This plan is directionally strong and close to the right shape, but it is not ready to ship as-is. The core flow (post-creation, surface-ready, welcome mutual exclusion, feature-flagged rollout) is solid. The two high-risk gaps are: (1) "pixel class" is specified using `NSScreen.frame`, which is points not guaranteed physical pixels; and (2) the proposed binary split fan-out does not produce a true uniform grid for 3x3/2x3 layouts. I would mark this **Needs revision** until those semantics are explicit and tested.

## The Plan's Intent vs. Its Execution
Intent is clear: new workspace should land in a monitor-appropriate parallel layout with minimal user action.

Where execution aligns well:
- Hooks at workspace creation time (not retroactive), matching goal/non-goals.
- Welcome-first precedence is explicit.
- Saved layout precedence is preserved by scoping to `addWorkspace`.
- Crash safety is prioritized (partial grid acceptable on split failure).

Where intent drifts:
- The document says "pixel dimensions" but references `window.screen?.frame`; on macOS this is typically logical points. That can misclassify Retina/external displays relative to stated thresholds.
- The plan calls the result a grid, but the split algorithm is a chained binary split. Without ratio control/rebalancing, 3-column and 3-row results are generally asymmetric (e.g., 50/25/25 distribution).
- "When a user opens a new workspace" is broader than the proposed `select && autoWelcomeIfNeeded` branch; background-created workspaces are excluded.

## Architectural Assessment
What is strong architecturally:
- Reusing the existing "initial terminal ready" pattern is the correct lifecycle seam.
- Keeping logic out of `Workspace.init` is a good separation-of-concerns decision.
- Central settings module + pure classifier is good decomposition.

What needs restructuring:
- Readiness orchestration should be single-sourced. Mirroring `sendWelcomeWhenReady` behavior in multiple places risks drift.
- Screen classification should take a well-defined display descriptor (pixel width/height, point frame, scale factor) rather than raw `NSRect` from whichever window lookup succeeds.
- Grid construction should state whether it targets pane count only or geometric uniformity. If uniformity is required, the current Bonsplit API surface likely needs ratio/rebalance support.

Alternative framing I would consider:
1. Define a `DefaultGridLayoutProfile` that returns both pane target and a construction strategy.
2. Make classification input explicit (`DisplayClassInput`) and testable.
3. Keep current split API for MVP only if product accepts non-uniform geometry.
4. If product requires true grid look, add a Bonsplit-level "rebalance pane tree" or ratio API before enabling 3x3 broadly.

## Is This the Move?
Mostly yes, with caveats. A default parallel layout is a high-leverage UX improvement for new workspaces. The plan also smartly avoids scope creep (no retroactive mutation, no multi-monitor migration logic).

What I would change before implementation:
- Resolve the points-vs-pixels ambiguity and lock thresholds to the chosen unit.
- Decide explicitly whether "grid" means uniform geometry or just pane cardinality.
- Add at least one behavior-level test that validates `addWorkspace` -> resulting pane topology, not only pure helper outputs.
- Consider rollout policy for existing users (default-on may surprise workflows built around single-pane start).

## Key Strengths
- Strong scope control: clear non-goals reduce hidden complexity.
- Good lifecycle placement: waits for surface readiness instead of forcing sync assumptions.
- Safety posture is pragmatic: no-crash, partial completion acceptable.
- Reversible rollout via UserDefaults flag.
- Reasonable alignment with existing Welcome pattern reduces novelty risk.

## Weaknesses and Gaps
- **Classification unit ambiguity (high):** thresholds are expressed as if physical pixels; implementation signal as written is likely points.
- **"Grid" fidelity gap (high):** binary fan-out without ratio control does not naturally produce equal cells for 3xN/Nx3.
- **Behavioral coverage gap (medium):** test plan focuses on pure helpers; missing runtime verification of pane tree outcome and focus preservation.
- **Duplication risk (medium):** near-copy async readiness flows can diverge over time.
- **Rollout risk (medium):** default-enabled for all users may be a UX regression for keyboard-heavy single-pane users.
- **Observability gap (low/medium):** split failure is "bail silently"; absence of debug logging/telemetry makes field diagnosis harder.

## Alternatives Considered
1. **Keep current proposal (monitor-classed default-on grid):**
   - Pros: immediate UX win, low implementation overhead.
   - Cons: classification and geometry semantics remain underspecified.

2. **Conservative MVP (always 2x2, default-on):**
   - Pros: avoids 3x3 asymmetry concerns, simpler testing.
   - Cons: under-utilizes large monitors.

3. **True-grid architecture (add Bonsplit ratio/rebalance support first):**
   - Pros: output matches user expectation of "grid".
   - Cons: larger dependency/scope; not a quick feature.

4. **Rollout by cohort (new installs default-on, existing users default-off):**
   - Pros: limits surprise regressions.
   - Cons: adds migration-state complexity.

## Readiness Verdict
**Needs revision** before execution.

Minimum changes to reach "Ready to execute":
1. Specify and implement the exact display unit for thresholding (points vs physical pixels).
2. Clarify product expectation for "grid" geometry and adjust algorithm/scope accordingly.
3. Add behavior-level tests for resulting pane topology and focus invariants.
4. Consolidate readiness orchestration to avoid duplicated async logic.

## Questions for the Plan Author
1. Are threshold values (`3840x2160`, `2560x1440`) intended to be in physical pixels or logical points?
2. Is a non-uniform 3x3/2x3 geometry acceptable, or must cells be visually close to equal size?
3. Should default grid apply when `addWorkspace(select: false)` creates a background workspace?
4. For existing users upgrading, do we still want default-enabled behavior immediately?
5. Should ultrawide/portrait handling be explicitly defined now (independent width/height classes), or intentionally deferred?
6. Do we want debug logging when a split in the sequence fails, even if we keep user-visible behavior silent?
7. Should the fallback path (no screen/window resolvable) remain 1x1, or use 2x2 as a better practical default?
8. Do remote workspaces require different behavior (e.g., avoid spawning many panes that each run startup commands)?
9. Should we centralize "run when initial terminal ready" in one shared helper to prevent drift between welcome/grid paths?
10. Is UserDefaults-only opt-out acceptable for this release, or is a Settings toggle required before enabling by default?
11. Do we need an artifact-level regression test around `TabManager.addWorkspace` to prove welcome-vs-grid mutual exclusion?
12. Should this feature emit a lightweight metric/event (enabled/disabled, chosen class) for rollout monitoring?
