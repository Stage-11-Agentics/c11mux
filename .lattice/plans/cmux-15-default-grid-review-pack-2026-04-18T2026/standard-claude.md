# Standard Plan Review — CMUX-15 Default pane grid sized to monitor class

- PLAN_ID: cmux-15-default-grid
- MODEL: Claude
- Reviewer: PlanReview-Standard (Claude Opus 4.7)
- Date: 2026-04-18

---

## Executive Summary

This plan is fundamentally sound and the bets are reasonable. It's a small, bounded feature with a clear integration point, a good precedent to mirror (WelcomeSettings.performQuadLayout), and a sensible escape hatch. The core architectural decision — "fire after workspace creation via the same surface-ready dance as welcome" — is the right one given what's actually in the codebase. The decomposition into `DefaultGridSettings` (classifier + performer) + `spawnDefaultGridWhenReady` (orchestrator) + `TabManager` wiring is the right three-part split.

The single most important thing: **the plan underweights the UX cost of "user opens a new workspace and suddenly nine terminals appear."** That's a big behavior change to ship as an opt-out default (`defaultEnabled = true`). The classifier and mechanics are fine; the *defaulting* decision deserves a second look, because once users have mental models formed around "new workspace = 1 pane," defaulting to 9 on 4K rewrites that muscle memory the first time they hit Cmd-T. A more conservative rollout (ship behind a flag default-off, or default to a smaller grid like 2x2 everywhere for MVP) would de-risk this without sacrificing the feature.

Secondary concern: the grid construction algorithm as drawn in Phase 1 / Phase 2 produces visually uneven splits in bonsplit's binary-tree model. The plan asserts "cols × rows" but doesn't reason about what bonsplit actually *does* when you call horizontal split repeatedly on the same root chain — you don't get equal columns, you get a right-heavy cascade. This is an implementation detail the plan has not confirmed and is the most likely way the MVP ships visibly wrong.

Verdict: **Needs minor revision** — default-on decision should be reconsidered or explicitly justified, and grid construction needs a concrete bonsplit sanity check before coding. Most of the plan is ready to execute as-is.

---

## The Plan's Intent vs. Its Execution

**Intent:** "When a user opens a new workspace, land them in a parallel-work layout sized to their screen, so they don't have to manually split."

**Execution faithfulness:** Mostly good. The trigger (new-workspace), the gating (after welcome, via toggle), the mechanics (bonsplit splits), and the escape hatch (UserDefaults) all match the intent.

**Where execution drifts:**

1. **"Parallel-work layout" is an assertion, not a requirement.** The plan assumes a uniform grid of terminals is what parallel work wants. Many parallel workflows are heterogeneous: one terminal + one browser + one notes pane + one agent. The welcome quad gets this right (mixed content). By committing the default grid to all-terminals, the plan may ship something that *looks* like parallel work but doesn't actually serve it — and the user will close 6 of 9 panes every time. Open question #4 flags this but doesn't resolve it; resolving it is higher stakes than the plan frames.

2. **"Sized to the monitor" is doing a lot of work.** The plan classifies by pixel count, but the thing that actually matters for "how many panes fit legibly" is *points per pane* after the split, which depends on font size, Ghostty cell width, and chrome. A 3×3 on a 3840×2160 display at 125% scale is very different from 3×3 at 100%. The plan should either (a) classify by logical points (`window.screen?.frame` is already in points on macOS, good — but the thresholds are stated in "pixel dimensions" which is ambiguous for Retina), or (b) classify by *effective terminal cells per pane* post-split. As written, "3840×2160" is ambiguous — is that the retina backing store or the logical frame? macOS `NSScreen.frame` is in points.

3. **"User opens a new workspace" is every workspace after the first.** The plan intends this, but the UX implication is heavy: every Cmd-T now produces 9 panes on a 4K screen. That is unambiguously a massive behavior change to the most common action in the app.

---

## Architectural Assessment

### Is this the right decomposition?

Yes, with one nit:

- **`DefaultGridSettings` enum (pure classification + MainActor performer)** — good, mirrors `WelcomeSettings` and is the right unit of colocation.
- **`spawnDefaultGridWhenReady` on AppDelegate + TabManager** — good, reuses `runWhenInitialTerminalReady` pattern.
- **TabManager wiring as an `else if`** — good, keeps welcome / default-grid / single-pane as mutually exclusive branches at the same site.

**Nit:** `DefaultGridSettings.performDefaultGrid` takes a `screenFrame: NSRect`. The screen detection logic (find the right `NSScreen`, handle cross-screen windows, fall back to main) is non-trivial and deserves to live inside the performer, not be the caller's job. Otherwise every caller duplicates the detection logic. Prefer `performDefaultGrid(on: workspace, initialPanel: TerminalPanel)` and let it resolve the screen internally from `workspace` → bonsplit view → window → screen. Open question #1 (ultra-wide) is easier to answer in one place.

### Is this the right structure?

The three-layer structure (settings module + orchestrator + wiring) mirrors an existing working pattern. That's a strong choice — consistency with `WelcomeSettings` lowers cognitive load for the next person reading the code. No objection.

### Alternative framings

Two alternatives worth considering:

1. **Layout templates instead of a classifier.** Instead of "classify monitor → grid," think "workspace has a layout template; default templates are indexed by monitor class." This opens the door to user-defined templates (the 2nd Lattice ticket on roadmap) without refactoring. Cost: more abstraction for MVP, probably not worth it yet.

2. **Do the grid inside `Workspace.init` with a "pending splits" queue that flushes on first surface-ready.** Keeps all workspace construction in one place. Rejected correctly by the plan (screen detection needs a window). Good.

3. **Do it at bonsplit-tree construction time**, not via sequential `newTerminalSplit` calls. If bonsplit has an API for "build this tree shape," use it. The plan assumes sequential splits are the only option — verify this. If bonsplit has a tree-insert API, a single declarative call is cleaner, avoids the "partial grid if one split fails" bailout problem, and sidesteps the visual-evenness concern below.

---

## Is This the Move?

**Mostly yes, with asterisks.**

What the plan gets right:
- Surfaces a real UX friction (manually splitting into a grid every time).
- Reuses an existing pattern, keeps blast radius small.
- Has a clean kill switch (UserDefaults).
- Is revertible.

What's risky:
- **Default-on is a behavior change, not a feature addition.** The plan treats this as low-cost because it's behind a flag — but the flag defaults `true`, which means every existing cmux user wakes up to a new behavior on the next update. The plan has no migration/announcement strategy. The escape hatch exists but is buried in `defaults write`; the average user will not find it.
- **Common failure pattern in projects like this: "great on paper, annoying in practice."** 9 panes on 4K sounds pro-user; in practice it means 9 shells loading, 9 prompts rendering, 9 ports allocated, and 6 of them immediately closed. The welcome quad dodges this because it's once-per-install; the default grid is once-per-new-workspace.
- **Ports/resources:** each terminal panel takes a port ordinal. Workspaces going from 1 pane to 9 means 9x port consumption. The plan does not discuss whether port allocation scales linearly and what the ceiling is.

What I'd do differently:
- **Ship with `defaultEnabled = false`** for one release. Make it discoverable via a settings toggle (which the plan defers). Gather qualitative feedback. Flip default to `true` a release later if reception is good.
- OR: **ship with a smaller default grid (2×2 everywhere)** and let the tier-up to 3×3 / 2×3 land in a follow-up once the basic behavior is validated.

---

## Key Strengths

1. **Mirrors `WelcomeSettings.performQuadLayout` almost exactly.** This is the single strongest move in the plan. The pattern already works, is tested in the field, and handles the surface-ready dance correctly. "Copy the welcome pattern" is load-bearing here, and the plan explicitly anchors to it. (Principle: consistency beats cleverness in a codebase; re-use proven patterns.)
2. **Classifier as a pure function.** `classify(screenFrame:) -> (cols, rows)` is trivially unit-testable without a running app. This is exactly the shape of code that unit tests are good at. (Principle: isolate pure logic from side-effectful orchestration.)
3. **Explicit non-goals.** Multi-monitor, reshuffling, retroactive application, welcome override, saved-layout override — all correctly scoped out. Most plans forget to do this; this one does it well. (Principle: the value of a plan is as much in what it refuses to do as what it does.)
4. **Saved layouts precedence is free.** The plan correctly identifies that the restore path doesn't call `addWorkspace`, so no code is needed. Recognizing "this works by construction" rather than adding belt-and-suspenders code is correct. (Principle: don't write code to reaffirm invariants that already hold.)
5. **Revertibility via UserDefaults.** Clean kill switch, no migration required.
6. **Bailout on split failure is correct.** "Partial grid is acceptable, crash is not" is the right posture for a best-effort layout.

---

## Weaknesses and Gaps

1. **Grid construction algorithm likely produces uneven splits in bonsplit's binary tree.** This is the biggest concrete risk. The plan's Phase 1 does `horizontal split` from the *previous* pane (`panes[i-1]`) repeatedly. In a binary-tree splitter, this typically produces: `[col1 | [col2 | [col3 | col4]]]` — a right-heavy cascade where col1 is 50%, col2 is 25%, col3 is 12.5%, col4 is 12.5%. For a uniform grid you either need (a) a "split the root horizontally N times" API, (b) post-split resize to equalize, or (c) a recursive balanced-split (split root in half, recurse on each half). The plan has not verified which of these bonsplit supports. This is the most likely way the MVP ships visibly wrong.
   - **Downstream effect:** feature ships, user sees uneven columns, files a bug, engineer has to rework the loop or add resize calls. This is avoidable with a 30-minute bonsplit sanity check before coding.

2. **Pixel vs. points ambiguity.** The thresholds are stated in "pixel dimensions" but macOS `NSScreen.frame` returns points. 3840×2160 is the backing pixel count of a 4K display, but the points will be 1920×1080 at 2x or 2560×1440 at 1.5x scale. The plan needs to explicitly state whether thresholds are in points (preferred) or backing pixels (need to multiply by `backingScaleFactor`). As written, ambiguous.
   - **Downstream effect:** wrong threshold classification on the very displays the feature is supposed to shine on.

3. **No discussion of cost per pane.** 9 terminals means 9 shells, 9 ports, 9 `ghostty_surface_s`, 9 initial surface-ready notifications, 9 working-directory resolutions. The plan does not estimate latency impact of spawning a workspace with grid vs. without, nor memory. On a fresh Cmd-T this should feel instant; 9 panes may not.
   - **Downstream effect:** perceived slowdown on workspace creation, especially on slower machines / with heavy shell init.

4. **No discussion of what happens to focus during grid spawn.** The plan says `focus: false` for splits, and "initial top-left retains focus at the end." But `newTerminalSplit` with `focus: false` may still trigger surface activation during creation. If the user is typing during grid spawn (unlikely but possible on slow machines), keystrokes could race the focus model.
   - **Downstream effect:** rare but real keystroke loss / wrong-pane input edge case.

5. **`spawnDefaultGridWhenReady` timing couples to welcome.** The plan's `else if` gates default-grid on `autoWelcomeIfNeeded && select && isEnabled`, but does not gate on `WelcomeSettings.shownKey == true`. The condition order in `addWorkspace` is: "if welcome needed → welcome; else if grid enabled → grid." This works but creates a hidden coupling: if someone ever introduces a third auto-layout, the `else if` chain gets ugly. Consider refactoring to a single `chooseAutoLayout(...)` function that returns an enum. Not a blocker, but worth noting.

6. **Test strategy is thin.** "Unit test the classifier + extract a `gridSplitOperations` helper and test its shape." The helper isn't actually constructed in the plan (it says "factor the loop into a pure function") — that's the test-critical piece, and if the bonsplit ordering is the failure mode, testing the op sequence doesn't catch it. A smoke test that actually runs against a bonsplit controller and asserts final pane count + approximate sizes would be stronger. The plan acknowledges "no xcodebuild test locally" but that doesn't mean no integration test — it means run them on CI.
   - **Downstream effect:** the test suite won't actually catch the most likely bug.

7. **"All terminals" vs. welcome's mixed content is under-justified.** The plan asserts "parallel work space = uniform terminals" as self-evident. That may be true for power users doing `git status`-across-4-repos, but for product-engineering workflows (code + browser + docs), it's wrong. The plan flags this as open question #4 but treats it as low-stakes; it's actually the "what does this feature mean" question.

8. **No mention of the 3-second timeout in `runWhenInitialTerminalReady`.** If the initial surface isn't ready in 3s, the welcome path logs "Welcome quad: initial terminal not ready after 3.0s" and gives up. The default grid will inherit the same behavior — which means on slow machines / heavy init, the grid silently doesn't spawn. Acceptable, but plan should say so.

9. **No rollback plan if the feature ships and users hate it.** "Flip UserDefaults to false" is a workaround, not a rollback. The rollback is "change `defaultEnabled = true` to `false` in a hotfix release." The plan doesn't say this explicitly, but it's the right escalation path.

10. **No telemetry.** If the feature ships default-on, the team will want to know: how often is the grid actually used vs. immediately closed? A simple "grid spawned, pane count at +30s: N" telemetry point would answer this. Not a blocker for MVP but a gap for measuring success.

---

## Alternatives Considered

### A. Default-off with discoverable toggle
- **Alternative:** ship with `defaultEnabled = false` and add a settings pane toggle (deferred in the plan).
- **Tradeoff:** lower "wow factor" on update, but much lower risk of backlash. Users who want it find it; users who don't never see it. Plan chose default-on presumably for product impact.
- **Recommendation:** strongly consider default-off for one release, flip to default-on after qualitative validation.

### B. Smaller default grid (2×2 everywhere)
- **Alternative:** drop the classifier entirely for MVP; always spawn 2×2.
- **Tradeoff:** feature ships faster, simpler code, much smaller behavior change. Loses the "scales with screen" selling point.
- **Recommendation:** viable MVP shape if the team wants to de-risk.

### C. Mixed content (like welcome)
- **Alternative:** 4-tile default = terminal + browser + markdown + terminal, scaling up by adding more terminals on larger screens.
- **Tradeoff:** more opinionated, harder to get right. Closer to real parallel-work usage for many users. Requires deciding what the markdown/browser defaults are.
- **Recommendation:** worth prototyping; punts cleanly to "open question #4" but may actually be the better default.

### D. User-defined templates (punted)
- **Alternative:** skip defaults entirely; ship a "workspace layout templates" feature with one built-in template.
- **Tradeoff:** much more work, but a cleaner long-term abstraction. MVP correctly defers this.

### E. Classifier by cells-per-pane, not screen-resolution
- **Alternative:** compute `effectiveTerminalCellsPerPane` from font size + screen size, target ≥80 cols × 24 rows per pane, derive grid from that.
- **Tradeoff:** more robust across font sizes and scaling, harder to reason about. Overkill for MVP.
- **Recommendation:** defer, but note in `classify`'s doc-comment that the thresholds are proxies for "cells-per-pane ≥ legible."

---

## Readiness Verdict

**Needs minor revision.**

Specifically, three things change the verdict to "ready":

1. **Decide and document: default-on or default-off?** Either is defensible, but the plan should explicitly state the call with rationale. If default-on, add telemetry. If default-off, add settings-pane toggle to MVP scope.
2. **Clarify points vs. pixels in the threshold table.** Make it unambiguous. Confirm the frame API being used returns the expected unit.
3. **Verify the bonsplit grid construction produces even splits.** Either (a) confirm the loop-based approach works via a 30-minute prototype, (b) identify the bonsplit API that gives balanced splits, or (c) add a "post-split resize" step. Update the plan's algorithm section with findings.

Everything else is either correctly scoped to a follow-up (settings UI, multi-monitor, ultra-wide), acceptable as-is (bailout on split failure, 3s timeout inheritance), or resolvable during code review.

---

## Questions for the Plan Author

1. **Default-on vs. default-off:** what's the rationale for shipping with `defaultEnabled = true`? Have you considered the UX impact on existing users who open a new workspace every day and have muscle memory for 1-pane? Would you consider default-off for one release?

2. **Pixel vs. point semantics of the thresholds:** does `3840 × 2160` in your table refer to backing pixels (retina) or logical points (`NSScreen.frame`)? Which unit does your `screenFrame: NSRect` parameter carry? This matters a lot for 4K-at-2x displays.

3. **Grid evenness:** have you verified that repeated `newTerminalSplit(orientation: .horizontal, insertFirst: false)` calls against a right-walking chain produce equal-width columns in bonsplit? If not, is there a tree-building API or a post-split resize step we need?

4. **Mixed content vs. all-terminal:** why all terminals? Most parallel-work setups have 1-2 terminals + a browser + notes. Is the all-terminal bet coming from observed usage, or is it a simplification?

5. **Why `screenFrame` is a caller parameter:** would it be cleaner for `performDefaultGrid` to resolve the screen from the workspace's window internally? Having the caller pass a `NSRect` feels like it leaks detection logic.

6. **Port allocation ceiling:** each pane consumes a port ordinal. On a workspace spawning 9 panes, does port consumption scale linearly? Is there a soft or hard ceiling we should worry about?

7. **Ultra-wide special-casing (open q #1):** the plan defers this. What's the plan to collect data? Will the initial release misclassify 5120×1440 displays, and if so, is that acceptable for MVP?

8. **Focus during grid spawn:** if a user starts typing during the 0.5s dispatch + split cascade, where do the keystrokes land? Do we need to defer focus acceptance until spawn completes, or is the existing surface-ready dance sufficient?

9. **3s surface-ready timeout:** the welcome path gives up silently after 3s. The default grid will inherit this. Is "silently don't spawn the grid" the desired behavior on slow machines, or should we fall back to 1×1 with an explicit log?

10. **Telemetry:** will we instrument "grid spawned" / "panes closed within 30s of creation" to measure whether the default is actually useful? If default-on, I'd strongly advocate for telemetry so we can validate the bet.

11. **Rollback plan:** if the feature ships and generates negative feedback, what's the rollout mitigation? Is it "hotfix release with defaultEnabled = false," or do we have a remote config lever?

12. **Relationship to saved-workspace templates (the follow-up ticket):** will the default grid spawn code get reused as "template = 'default 3x3'" in the follow-up, or is this code throwaway once templates land? Affects how much effort to put into making this generalizable.

13. **Interaction with `autoWelcomeIfNeeded=false` paths:** `openIntegrationInstallSurface` and similar callers explicitly pass `autoWelcomeIfNeeded: false`. The plan's gate is `autoWelcomeIfNeeded && select && isEnabled`, so those sites correctly skip the grid. Confirm this is intended — we don't want the integration-install surface spawning a grid.

14. **Test scope:** is "unit-test the classifier + unit-test the op list" sufficient, or should we add a CI integration test that actually instantiates a workspace, runs the grid, and asserts `panels.count == expected`? The latter catches the bonsplit-ordering class of bug; the former does not.

15. **Settings-pane toggle timing:** the plan defers this. If default-on, users without access to `defaults write` have no opt-out for a release. Is that acceptable, or should the toggle be in-scope for MVP?

16. **Ultra-portrait (open q #6):** the plan defaults to "fixed table, don't auto-rotate." On a 1440×2560 portrait display, 2×3 is wrong (6 panes of 480×855 — tall and skinny). Should we auto-rotate portrait orientations, or is this acceptable because portrait is rare?

17. **Docs escape hatch (one-liner in `docs/`):** which doc page? The config/defaults section of the main docs, or somewhere in `web/app/docs/`? Worth specifying so the doc update doesn't get lost.

---

## Additional notes / things a sharp eye would catch

- The plan's **Total splits** math is correct: `cols*rows - 1`. Good that it's spelled out.
- The plan **does not mention thread/actor discipline** for the grid performer. `WelcomeSettings.performQuadLayout` is `@MainActor`; `DefaultGridSettings.performDefaultGrid` should be too. The sketch has `@MainActor` on the performer, good.
- The plan **does not discuss restart behavior**: if a workspace was created with a 3×3 grid, closed, and re-opened via session restore, it should restore the exact layout (saved-always-wins path, which the plan confirms). This is correct but worth explicitly stating: once spawned, the grid is just a regular saved-layout workspace and behaves identically to a hand-built one.
- **File count discipline:** 4 files touched (`cmuxApp.swift`, `TabManager.swift`, `AppDelegate.swift`, new test file). Reasonable. `~200 LoC app + ~80 LoC tests` feels about right; I'd budget 300 LoC app because the screen-detection + cross-screen logic usually runs longer than expected.
- **Principle alignment with c11mux philosophy (from CLAUDE.md):** "c11mux is host and primitive, not configurator." The default grid is *within* c11mux's boundary — it's manipulating surfaces c11mux owns. No philosophical conflict. Good.
- **No AGENTS.md symlink concern** since no new project directory is being created. N/A.

---

## Relevant file paths referenced

- Plan: `/Users/atin/Projects/Stage11/code/cmux/.lattice/plans/task_01KPHHQ6T4K09KE9YF20KPT8VS.md`
- Welcome pattern (mirror target): `/Users/atin/Projects/Stage11/code/cmux/Sources/cmuxApp.swift:3758`
- AppDelegate welcome orchestrator: `/Users/atin/Projects/Stage11/code/cmux/Sources/AppDelegate.swift:5982`
- `runWhenInitialTerminalReady` (surface-ready dance): `/Users/atin/Projects/Stage11/code/cmux/Sources/AppDelegate.swift:5991`
- TabManager integration point: `/Users/atin/Projects/Stage11/code/cmux/Sources/TabManager.swift:1170`
- Workspace init (initial panel creation): `/Users/atin/Projects/Stage11/code/cmux/Sources/Workspace.swift:5243`
- `newTerminalSplit` API: `/Users/atin/Projects/Stage11/code/cmux/Sources/Workspace.swift:6965`
- Project agent notes: `/Users/atin/Projects/Stage11/code/cmux/CLAUDE.md`
