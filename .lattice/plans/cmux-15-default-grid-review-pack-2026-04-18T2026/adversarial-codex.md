### Executive Summary
This plan is high-risk in its current form. The biggest issue: it claims monitor-classed **pixel-based** behavior but anchors classification to `window.screen?.frame`, which is points in AppKit, not physical pixels. The second biggest issue: the proposed split algorithm does not produce a true equal-cell grid for 3x3; it produces recursively halved columns/rows (visually 50/25/25-like distributions). You are about to ship a strong default UX change with weak determinism, weak observability, and weak rollback ergonomics.

### How Plans Like This Fail
This class of plan (auto-layout defaults) usually fails through predictable patterns:

1. **Semantic mismatch between spec and actual signal.** “Pixel class” is promised, but point-space APIs are used.
2. **Algorithmic mismatch between intent and geometry.** “Grid” is promised, but binary split recursion creates skewed cells unless divider positions are normalized afterward.
3. **Default-on behavior without product safeguards.** Surprise behavior for every new workspace drives support churn.
4. **Race-based readiness orchestration.** Fixed delays/timeouts create nondeterministic behavior that users cannot reproduce.
5. **Silent partial-failure policy.** Users get odd intermediate layouts with no explanation, and engineers get no clear failure signal.

This plan is vulnerable to all five.

### Assumption Audit
Load-bearing assumptions (plan collapses if false):

1. **Assumption:** `window.screen?.frame` represents pixel dimensions.
Status: likely false in macOS UI coordinates (points).
Risk: monitor classing is wrong on Retina/high-DPI setups.

2. **Assumption:** Split sequence produces a real `cols x rows` grid.
Status: false unless divider positions are explicitly rebalanced.
Risk: 3x3 becomes unequal columns/rows; UX intent violated.

3. **Assumption:** Grid creation after “surface ready + delay” is deterministic.
Status: fragile.
Risk: behavior differs by machine load/startup timing.

4. **Assumption:** Applying this in `addWorkspace` means only user-initiated “new workspace” flows.
Status: questionable.
Risk: it may affect startup/fallback/internal creation paths not framed as “user asked for grid.”

5. **Assumption:** 4/6/9-pane auto-spawn is acceptable on all hardware.
Status: unproven.
Risk: startup CPU/RAM spikes, terminal init storms, degraded perceived responsiveness.

Non-load-bearing but still risky assumptions:

6. Hidden defaults-key toggles are acceptable UX for MVP.
7. Silent partial grids are preferable to explicit fallback.
8. Width/height threshold table will generalize well to ultrawide/portrait cases.
9. `NSScreen.main` fallback is a harmless proxy for the actual hosting display.

### Blind Spots
1. **No geometry correctness check:** there is no post-condition asserting target pane count and approximate cell balance.
2. **No behavior telemetry:** no counters for “grid attempted/succeeded/partial/aborted/timeout.”
3. **No performance budget:** no target for workspace creation latency or resource overhead.
4. **No user-facing recoverability:** no obvious in-app toggle, no one-click “open single pane by default.”
5. **No conflict matrix:** no explicit handling for future workspace templates/presets precedence.
6. **No product segmentation:** default is global, despite very different user preferences and hardware classes.
7. **No deterministic retry policy:** timeout exits without fallback strategy besides “do nothing.”
8. **No plan for window/screen ambiguity:** attaching to the wrong screen at creation time is treated as acceptable noise.

### Challenged Decisions
1. **Decision:** Ship default-enabled (`true`) immediately.
Counter: this is a behavior-breaking default; should be staged or opt-in first.

2. **Decision:** Use raw threshold constants in one file.
Counter: this hides product policy in code and invites churn without observability.

3. **Decision:** Accept partial grid silently.
Counter: this creates inconsistent UX and impossible debugging; at minimum log + metric + deterministic fallback.

4. **Decision:** No settings UI in MVP.
Counter: you are introducing a major opinionated default without discoverable control.

5. **Decision:** Delay-driven ready flow copied from welcome logic.
Counter: “works once” onboarding logic is not a strong basis for an every-workspace default path.

6. **Decision:** Use width/height thresholds as monitor proxy.
Counter: without physical pixel handling and aspect-aware rules, this is pseudo-precision.

### Hindsight Preview
Two years later, likely regrets:

1. “We called it pixel-classed but used points; classification was wrong on many common setups.”
2. “We called it a grid but users got uneven pane sizes on 3x3.”
3. “We made this default-on before we had telemetry, so we debugged via anecdotes.”
4. “Support burden was avoidable if we had an in-app toggle from day one.”

Early warning signs you should expect quickly:

1. Reports that new workspaces feel “slow/heavy/noisy.”
2. Complaints that pane count/layout differs across similar Macs.
3. Bug reports with non-reproducible “sometimes I get full grid, sometimes not.”
4. Frequent use of hidden defaults override by advanced users.

### Reality Stress Test
If these three likely disruptions hit together:

1. **Hardware diversity increases** (mixed Retina + ultrawide + external docks).
2. **Startup costs rise** (Ghostty/bonsplit changes increase per-pane overhead).
3. **Product priorities shift** toward explicit workspace templates/profiles.

Result: this plan becomes technical debt fast. You’ll be locked into a hidden heuristic default that conflicts with explicit user intent systems, while paying support/performance costs and lacking instrumentation to justify decisions.

### The Uncomfortable Truths
1. This is a product opinion disguised as an implementation detail.
2. “No UI toggle” is not MVP pragmatism here; it is deferred accountability for a major default change.
3. The current algorithmic description does not guarantee what the user-facing term “grid” implies.
4. The plan is overconfident about monitor detection correctness.
5. Silent failure handling protects crash rates, not user trust.

### Hard Questions for the Plan Author
1. Are you classifying by **actual display pixels** or AppKit points? If pixels, where is the conversion/source-of-truth defined?
2. How will you enforce equal-ish cell geometry for 3x3 within a binary split tree? If you won’t, why call it a grid?
3. What explicit success criteria define “good enough” for latency and memory overhead at 9 panes?
4. Which `addWorkspace` call sites are intentionally in-scope vs accidental? List them.
5. Why is this safe as default-on without staged rollout/telemetry?
6. What user-facing recovery path exists for non-technical users who dislike this behavior?
7. What is the deterministic behavior when initial terminal readiness times out: retry, downgrade, or abandon?
8. What observable signals will you log for partial builds and classification decisions?
9. How do you prevent this from conflicting with future workspace templates/policies?
10. Why is `NSScreen.main` an acceptable fallback when the workspace’s owning window/screen is unresolved?
11. What is the expected behavior for ultrawide and portrait monitors, exactly, and who owns that policy?
12. If this launches and support noise spikes, what is your rapid mitigation path besides asking users to run `defaults write`?
