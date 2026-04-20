# Adversarial Plan Review — cmux-15-default-grid

- **PLAN_ID:** cmux-15-default-grid
- **MODEL:** Claude
- **Timestamp:** 20260418-2026
- **Plan under review:** `/Users/atin/Projects/Stage11/code/cmux/.lattice/plans/task_01KPHHQ6T4K09KE9YF20KPT8VS.md`

---

## Executive Summary

This plan is a competent, well-grounded sketch, but it is **shipping a default-on UX change for every new workspace on every install**, and the depth of analysis is not commensurate with the blast radius. The single biggest concern is the decision to ship `cmuxDefaultGridEnabled = true` with **no in-app settings UI and no data** on whether 4–9 panes is actually what users want on workspace creation. Second biggest: the grid construction algorithm as written produces a **geometrically non-uniform grid** on a binary-split tree, not the clean `cols × rows` the classification table implies. Third: the interaction with the Welcome quad is described as "mutually exclusive" but the plan's own gating logic (`shownKey == true`) means the grid will fire on the *second* new workspace a brand-new user ever creates — the one right after they close the Welcome quad — which is likely the most disorienting moment possible to hit them with a 9-pane explosion.

The plan reads as if the hard question is "what are the pixel thresholds" when the actually hard questions are "should this default to true?", "does this break existing users' muscle memory?", and "how do we undo this once it ships?". There is no telemetry, no staged rollout, no A/B, and no user-facing kill switch — just `defaults write` for power users who already know the key name.

Recommend: **do not ship with default `true` on MVP.** Either default `false` with a settings toggle that lets opt-in users pick their grid, or ship behind an explicit first-run prompt. Also: fix the grid geometry analysis before writing code, resolve the welcome-interaction sequencing, and add at least one observability hook.

---

## How Plans Like This Fail

Plans that change the default layout/shape of a primary user surface tend to fail in the following ways. Each is applicable here.

1. **"Designers' default" drift.** The author picks thresholds that feel right on their own monitor and ship them. Three months in, reports trickle in: "my 27" external always opens as 2×3, I always collapse 4 of them, please stop." The plan doesn't have a mechanism for discovering this drift short of complaint volume. → **This plan has no telemetry, no opt-in measurement, no beta cohort.**
2. **Hidden-cost-of-default.** The default appears "free" to the implementer because the opt-out exists. But every non-power user now pays the cognitive tax of closing 3–8 panes they didn't ask for, forever. The opt-out (`defaults write com.cmux.app cmuxDefaultGridEnabled -bool false`) is invisible to anyone who doesn't read release notes. → **Explicitly acknowledged in plan as "follow-up work (not scope-critical)." It is scope-critical.**
3. **Algorithm doesn't match intuition.** The classification table implies a uniform grid, but binary-tree splits + the specific loop order in the plan produce a non-uniform result. First user who grids on 4K and notices the 3×3 is lopsided will file a bug, and the fix is not small. → **See "Challenged Decisions" below.**
4. **Resource spike on startup.** Launching 9 Ghostty surfaces concurrently on workspace creation has very different perf characteristics from launching 1. The plan doesn't measure, bound, or stage this. `TabItemView` is explicitly called out as typing-latency-sensitive in `CLAUDE.md`; pane creation storms touch adjacent code paths (inheritance font seeding, `rememberTerminalConfigInheritanceSource`, bonsplit notifyGeometryChange firing 8 times in sequence). → **The plan waves at `focus: false` and calls it done.**
5. **Bad interaction with features that assume "one initial pane."** Tier 1 persistence, remote-terminal startup commands, shell-integration CWD inheritance, session snapshot restoration — each of these was designed around a 1-pane initial workspace. 9 panes fanned out in a sync loop is a different regime. → **The plan asserts "Implicit precedence: saved always wins. No new code needed" without auditing every caller of `addWorkspace`.**
6. **"We'll add the UI later."** Power-user opt-out via `defaults write` plus a "UI is follow-up" promise is a well-known pattern for "the UI never ships." The follow-up dies because the feature is working, the squeaky users learned the defaults command, and the silent majority learned to live with it. → **This is the plan's explicit rollout strategy.**
7. **Monitor heterogeneity is underestimated.** The three-bucket classification assumes a world of MacBook / QHD / 4K. In practice: ultra-wides (5120×1440, 3440×1440), portrait-rotated externals (1440×2560), non-Retina cheap externals (1920×1080 at 24"), Sidecar iPads, DisplayPort daisy-chained mixed resolutions. The plan acknowledges ultra-wide as an "open question" but has no plan for the long tail. → **The tail is the entire problem.**

---

## Assumption Audit

### Load-bearing (plan collapses without these holding)

| Assumption | Stated? | Likely to hold? |
|---|---|---|
| "Users want a grid of terminals on every new workspace" | Implicit | **Unknown.** No evidence in plan. Founder preference is not user preference. |
| "Welcome-quad firing once, then grid firing for every subsequent workspace, is the correct first-run sequence" | Implicit via gating logic | **Probably wrong.** A new user sees quad (TL terminal + browser + markdown + terminal-with-claude). Next workspace: 9 terminals. This is whiplash. |
| "`window.screen?.frame` gives the correct screen at dispatch time" | Stated | **Fragile.** Workspace creation flows via `addWorkspace` → model update → SwiftUI update → window attach. Timing is not obvious; the plan acknowledges this is why dispatch is deferred, but doesn't specify what "at dispatch time" actually resolves to or how long it waits. |
| "The initial terminal panel's surface readiness is the right signal for 'now it's safe to spawn 8 more'" | Implicit via mirroring `sendWelcomeWhenReady` | **Partially.** Welcome quad spawns 3 additional panes (browser, markdown, terminal). A 3×3 grid spawns 8. The readiness dance wasn't designed for this fan-out. |
| "`newTerminalSplit` can be called 8 times synchronously on the main actor without UI thrash, layout jitter, or focus bugs" | Implicit | **Unverified.** Each call mutates `bonsplitController`, fires `notifyGeometryChange`, mutates `panels`, triggers Combine publishers. The last in-flight 'split.created' dlog will be 8 deep. No test proves this doesn't break. |
| "Partial grid on failure is acceptable UX" | Stated | **Debatable.** A lopsided 5-out-of-9 grid is arguably worse than 1 pane. The plan says "bail silently" but doesn't specify rollback. |
| "All panes inheriting the same CWD from the source pane is the right behavior" | Implicit | **Probably yes** for single-repo workflows. **Probably wrong** for users opening a new workspace specifically because they want to switch context — they now get 9 panes all in the previous workspace's directory. |
| "Users will discover `defaults write cmuxDefaultGridEnabled -bool false`" | Implicit | **Almost certainly false.** Release-note-readers only. |
| "Unit-testing `classify` and `gridSplitOperations` gives meaningful coverage" | Stated | **Low-value.** The risky behavior is async, async-ready-gated, multi-split state mutation — none of which the proposed tests cover. |

### Cosmetic (nice-to-have, don't break the plan)

- Ultra-wide special-casing ("defer; log as an open question") — actually more than cosmetic; see below.
- "Estimated diff size: ~200 LoC app + ~80 LoC tests" — estimates in plans are vibes; don't anchor on them.

### Invisible / Unstated assumptions

- **That `NSScreen.screens.max(by: intersectionArea)` is well-defined when `NSScreen.screens` is empty.** Closures in `max(by:)` on empty arrays return nil — handled by optional chaining, but the plan doesn't actually write the code.
- **That the existing Welcome quad is the "proven welcome pattern" worth mirroring.** Is it? Has it been A/B'd? Does it have telemetry? It's the *precedent*, not the *validated pattern*.
- **That first-run Welcome detection (`shownKey`) is the only first-run state that matters.** Ignores: users who migrate from another machine, users who reset preferences, users who `defaults delete com.cmux.app`.
- **That grid-spawn is "free" relative to battery / laptop unplugged / low-memory scenarios.** 9 zsh processes + 9 Ghostty surfaces on a maxed-out M1 Air on battery is not free.
- **That `autoWelcomeIfNeeded && select` is the correct gate.** This excludes socket-driven and CLI-driven workspace creation — but socket/CLI callers often pass `select: true` from `cmux new-tab` specifically because they *want* a workspace the user will interact with. Do those get the grid? The plan doesn't say.

---

## Blind Spots

1. **No mention of `cmux new-tab` / socket-driven workspace creation.** There are multiple callers of `addWorkspace`. The plan names exactly one (Welcome). What about CLI tab creation from a shell? What about `cmux open <dir>`? What about session restore from snapshot? What about drag-a-file-onto-the-app? Every single `addWorkspace` caller inherits this behavior change.
2. **No mention of workspaces created with explicit `workingDirectory` / `initialTerminalCommand`.** A user who runs `cmux open ~/project` expects to land in that project — do they want 9 panes all in ~/project? A user who runs `cmux exec 'npm test'` definitely doesn't want 8 extra panes.
3. **Remote workspaces.** `remoteTerminalStartupCommand()` exists specifically to inject a startup command for remote-terminal sessions. Each of 9 panes will run that startup command 9 times. The plan does not acknowledge that remote terminals exist. This will produce 9 parallel SSH connections on workspace creation.
4. **No telemetry plan.** `TelemetrySettings.enabledForCurrentLaunch` is already plumbed. A single counter ("grid fired, cols/rows/screen class") would give actionable ship data. Zero words on this in the plan.
5. **No accessibility consideration.** VoiceOver users, reduced-motion users, users with screen-reader-driven terminal workflows. 9 focusable panes at startup is a navigation cost they didn't opt into.
6. **No "what if user has zero-motion preference" or "what if user has a tiny default font size / display scale."** `width × height` classification ignores effective work area post-scale. A 4K display at 200% UI scale has the visual real estate of a 2K, yet classifies as 4K.
7. **No undo / "collapse back to one pane" affordance.** You can close 8 tabs manually. That's not an undo. That's labor.
8. **No mention of `TabItemView` equatability invariants.** The CLAUDE.md explicitly calls out typing-latency-sensitive paths. Creating 9 tabs in sync rapid-fire is adjacent to that hot path. Has anyone verified this doesn't regress typing latency during workspace creation?
9. **No mention of window-resize-after-creation behavior.** A user opens a grid on 4K (3×3), then drags the window to their laptop screen. The 3×3 is now unusable. The plan says "no reshuffling" but doesn't say what *does* happen visually — presumably bonsplit's existing resize logic, which wasn't designed for 9-pane grids.
10. **No discussion of animation / visual churn during fan-out.** 8 split operations in rapid sequence. Does the user see 8 frames of "pane split animation"? One chunky jank? The plan doesn't say.
11. **No mention of window chrome / toolbar / sidebar occupying horizontal space.** `screen.frame` is the full screen. Workspace content gets screen minus chrome minus sidebar minus safe areas. Classification on raw pixels over-classifies.
12. **No plan for what happens when `performDefaultGrid` is called but the workspace was already closed by the user.** 3-second timeout window in `runWhenInitialTerminalReady`. User closes the workspace before it fires. Plan doesn't say.
13. **No mention of the CLI `cmux` having any interaction with this.** Should `cmux new-tab --grid=2x2` be a thing? The plan treats CLI as out-of-scope, but this is the feature most-obviously-belongs-in-CLI.
14. **No Lattice integration.** This is cmux, which is heavily agent-coordinated. Are agent-spawned workspaces (via Lattice display/panel creation) affected? Are they supposed to be?

---

## Challenged Decisions

### 1. Default `cmuxDefaultGridEnabled = true`

**Counterargument:** A layout default this opinionated should be opt-in. The Welcome quad is defensible as a one-time first-run experience. An always-on grid default is a persistent behavior change.

**Likely retort:** "If it's off by default, no one finds it." True. But the right answer is in-product discovery (settings pane, command palette, contextual nudge), not a default-on that 80% of users never asked for.

**Recommendation:** Default `false`. Add a **settings pane toggle** in MVP (not follow-up). On first-run-after-upgrade, surface a one-shot toast or command-palette hint: "Try the default pane grid — auto-splits new workspaces to fit your monitor."

### 2. `shownKey == true` gating

**Counterargument:** This causes the grid to fire on the *second* workspace a brand-new user creates. The first workspace is the Welcome quad (4 mixed panes). The second is 9 terminals. That's two radically different experiences back-to-back on day one.

**Recommendation:** Either grid doesn't fire in the "first 24 hours after welcome" window, or the welcome quad is replaced by the grid (not coexistent).

### 3. Pixel-based classification

**Counterargument:** The plan rejects inches "because macOS doesn't expose physical diagonal reliably." True but misleading. `NSScreen.visibleFrame` (not `.frame`) and `NSScreen.backingScaleFactor` + effective pixel-density-at-default-font give a much better signal for "how much usable work area does this screen have." The plan uses raw pixel dimensions which conflate 4K-at-200%-scale with 4K-at-100%-scale — very different user realities.

**Recommendation:** Use effective work area at default font size, not raw pixels. At minimum, use `visibleFrame` not `frame`.

### 4. Binary-split algorithm

**Counterargument (this is the most technical critique):** The proposed algorithm does not produce the grid the classification table advertises.

Phase 1 (columns): `for i in 1..<cols: splitPane(from: panes[i-1], .horizontal)`. This creates a right-biased split chain:
- After i=1: `[P0 | P1]` — each 50% wide. OK.
- After i=2: `[P0 | P1 | P2]`? **No.** Bonsplit is a binary tree. Splitting P1 horizontally gives `[P0 | [P1 | P2]]` where the P1/P2 sub-split takes 50% and is then split again into 25% each. P0 is 50% wide, P1 and P2 are 25% each. **The 3×3 is not 1/3, 1/3, 1/3 — it's 1/2, 1/4, 1/4.**

Phase 2 (rows per column): same issue. The top pane in each column is 1/2 height; the lower two are 1/4 each.

**This is likely not what the author intended.** To get uniform thirds you need to either:
- (a) split each existing column proportionally (split the middle group, not the leaf),
- (b) use a radix/balanced construction where you split in half first, then split each half.

Neither is described. The plan asserts correctness via "Total splits: (cols-1) + cols*(rows-1)" — the count is right, but **count-of-splits does not equal geometric uniformity**.

**Recommendation:** Write the algorithm against a real `BonsplitController` first and print the resulting geometry. Do not merge until visual output matches the table. Or: explicitly document that the grid is non-uniform and show a mockup of what it actually looks like.

### 5. Factoring `gridSplitOperations` as a pure function

**Counterargument:** You can test that the operation list has the right shape, but the shape is the easy part. The hard part is what bonsplit actually does with that sequence. A pure-function test that passes while the real split produces a non-uniform grid is worse than no test — it provides false confidence.

**Recommendation:** Either test against a real (headless) BonsplitController, or don't unit-test this and do integration tests only.

### 6. "No new code needed" for saved-layout precedence

**Counterargument:** "Saved layouts don't go through addWorkspace" is a claim, not a proof. Audit every caller. Session-snapshot restoration, drag-and-drop tab detachment, window-restore-after-quit-relaunch — verify each path.

### 7. Putting `DefaultGridSettings` in `cmuxApp.swift`

**Counterargument:** `cmuxApp.swift` is already a grab-bag. This is the kind of decision that's always "fine right now, regret in a year." A `Sources/Settings/DefaultGridSettings.swift` (or `Sources/Workspace/DefaultGrid.swift`) is the durable location. The plan puts it next to `WelcomeSettings` because `WelcomeSettings` is there — but `WelcomeSettings` being there is itself a smell worth fixing, not a pattern worth extending.

### 8. 3-second timeout for surface readiness

**Inherited from `runWhenInitialTerminalReady`**, not introduced by this plan — but the plan inherits the assumption. On a cold-start with 9 pending surfaces and startup commands, is 3 seconds enough? The welcome case has 1 + 2 + 1 = 4 surfaces. A 3×3 has 9. No data.

---

## Hindsight Preview

Two years from now, looking back at this feature, the likely "we should have known" moments:

1. **"We should have shipped off-by-default with a prompt, not on-by-default with a hidden flag."** The opt-out-via-`defaults-write` will be the #1 support-forum response for 18 months. Eventually someone adds the settings UI, but by then the behavior is entrenched and changing the default would be a bigger disruption than the original ship.
2. **"We should have measured what fraction of users keep all 9 panes open five minutes later."** Without telemetry, there's no feedback loop. The feature will be judged by loud complaints and silent churn — both lossy.
3. **"We should have designed for the long tail of monitors, not the median one."** The 3-bucket classification will be revised to 6 buckets, then to a per-display-inch database, then to "user picks a grid shape in settings, screen class is only the default hint." Every iteration is a migration.
4. **"We should have made this a user-defined template, not a system-decided layout."** The natural endpoint is `workspace templates` (the Welcome quad is a template, the default grid is a template). Building a one-off rule for "default grid" is building the wrong abstraction. If workspace templates are a future feature (they should be), this should be implemented as one of them.
5. **"We never figured out what 'grid' meant for non-terminal panes."** The plan says "all terminals." First Lattice/agent workflow will want a mixed template (display + panel + terminal). Now you have two code paths: Welcome-quad-style mixed, and DefaultGrid-style uniform. These should have been one abstraction.

### Early warning signs this plan has no mechanism to detect

- Users closing panes immediately after workspace creation (no telemetry).
- Users disabling the flag (no telemetry; also no in-app UI to disable, so only power users can).
- Regressions in typing latency during workspace creation (no benchmark).
- Remote-terminal users hitting 9x SSH connections (no log, no counter, no bound).
- Screen-misclassification on edge-case displays (no feedback loop).
- Users reporting "cmux opens weird-sized panes" without knowing why (no visible indication that "grid mode" is what did it).

---

## Reality Stress Test

Three realistic disruptions, hit simultaneously:

### Disruption A: The welcome quad is revised between now and ship.
The current plan mirrors Welcome's ready pattern. If someone else changes Welcome (e.g., to add a 5th pane, or restructure it as a template system), this code drifts from its template. The `sendWelcomeWhenReady` mirror is a **literal copy-paste pattern**, not a shared abstraction. Classic duplication-rot setup.

### Disruption B: A user files a bug: "opening a new tab on my 4K spawns 9 panes, I hate it, the defaults write command didn't help."
Turns out they set `defaults write com.cmux.app cmuxDefaultGridEnabled -bool false` but their bundle ID is actually something else (staging build, tagged build, custom build, helper bundle). The defaults-write advice is bundle-ID-specific and the plan doesn't document this. Support burden: high.

### Disruption C: macOS ships a sequoia-point-release that changes how `NSScreen.screens` reports ultra-wides.
(Hypothetical, but macOS display APIs change often.) The classification now misfires on 5120×1440. Plan punted ultra-wide as "open question" — open questions ship as bugs.

**Combined:** Welcome team refactors Welcome and the grid code falls behind. Bug reports trickle in about the grid from 4K and ultra-wide users. The defaults flag is discovered to be bundle-ID-scoped. There's no telemetry to estimate how bad it is. The fix requires a code change + release + Sparkle update. Weeks, not hours.

---

## The Uncomfortable Truths

- **This is a feature nobody explicitly asked for.** It's being designed because the author thinks users want it. That might be true. But the plan presents no user-facing evidence (interviews, session recordings, support tickets, Zulip complaints saying "I always split into 9 panes manually"). The implicit rationale is "parallel work is cmux's whole thing, so obviously more panes on creation is better." That is a reasonable hypothesis. It is not a validated one.
- **"The grid default only fires from the `addWorkspace` path" is a statement of hope, not a contract.** `addWorkspace` is called from many places. Claiming a behavior change is scoped by virtue of being attached to one function is only true if the function has one caller. It doesn't.
- **The plan's test strategy is weak and the author knows it.** "No xcodebuild test locally" is honest about the constraint, but the fallback (pure-function tests of classification + operation-shape) covers the cheap parts and leaves the expensive parts — async readiness, fan-out side effects, focus preservation, CWD inheritance at N=9, remote-terminal startup fan-out — untested. Manual `reload.sh --tag` is not a test plan.
- **The "follow-up work" list is where the real UX work lives.** Settings pane toggle, in-product discoverability, telemetry, multi-monitor, workspace-scoped override, pane-mix templates — those are "not scope-critical." They are the entire user experience.
- **This feature hides a bigger question: what is a workspace?** Today a workspace is "a bonsplit tree rooted in one initial terminal." This plan reframes it as "a layout template parameterized by monitor class." That is a much bigger conceptual change, worth naming. If you're going to go there, go deliberately — design workspace templates as a first-class feature, with the default grid as one instance.
- **Defaulting `true` is a forcing function to ship, and defaulting `false` is a forcing function to do the discovery work.** Choosing `true` is choosing "we won't do the discovery work, and we'll learn from complaints." That is a choice. It should be an acknowledged one.

---

## Hard Questions for the Plan Author

1. **What user evidence drove the choice to default this to `true`?** If the answer is "it feels right" or "cmux is about parallel work," that is not user evidence. Flag as we-don't-know.
2. **What does the 3×3 grid actually look like after 8 binary splits in the proposed loop order?** Draw the bonsplit tree. Show the geometry. If it's 1/2, 1/4, 1/4 instead of 1/3, 1/3, 1/3, is that acceptable? If not, what's the corrected algorithm?
3. **What happens when `addWorkspace` is called from the socket/CLI path with `select: true` — does the grid fire?** If yes: is that intended? If no: how is it gated, given `autoWelcomeIfNeeded && select` currently matches?
4. **What happens when the source pane has `remoteTerminalStartupCommand` set and the grid spawns 8 new terminals?** Do all 9 run the startup command? Is that 9 SSH connections? 9 auth prompts? Is there a bound?
5. **What is the expected time from "workspace created" to "grid fully rendered with all 9 surfaces ready" on a typical machine?** No number is given. Measure before ship.
6. **What does a user see during fan-out?** 8 sequential split animations? One atomic layout? Something flickery? Is there a design target here?
7. **What is the telemetry plan?** Specifically: how do you measure "did the user keep the grid panes or close them within 30 seconds?" Flag as we-don't-know.
8. **What is the rollback plan if default-on ships and produces a support spike?** Sparkle-push a new build with default-off? Server-side kill switch? The plan doesn't say. Flag as we-don't-know.
9. **Why isn't this a workspace-template system?** If the answer is "too big for MVP," why is default-on-for-everyone the MVP instead of opt-in-with-one-template?
10. **What interaction is intended with session-snapshot restoration specifically?** If a user had a grid, closed the workspace, reopened from snapshot — does restoration replay the grid, or restore the literal saved tree? Plan asserts "saved wins" but doesn't prove it for this new code path.
11. **Ultra-wide monitors: not an "open question," a shipping question.** 5120×1440 and 3440×1440 are common. What does the MVP do for them? "Deferred" is not an answer when you're shipping default-on.
12. **Does the grid fire on `cmux new-tab` CLI invocations?** The CLI is the agent-control surface. If the grid fires there, every agent-spawned workspace gets 9 panes. Is that intended?
13. **How is this tested under load?** If a user has 20 tabs already and creates a new workspace that tries to fan-out to 9 panes — is the machine OK? No benchmark in plan.
14. **What happens if `newTerminalSplit` returns nil on the 3rd of 8 splits?** Plan says "bail silently, partial grid acceptable." Show the resulting geometry. Is the user supposed to understand what they're looking at?
15. **Why is `DefaultGridSettings` inside `cmuxApp.swift`?** Is this durable placement, or inherited-from-Welcome by default?
16. **What's the opt-out UX for a non-power user?** `defaults write` is not an answer for 90% of users. The plan says UI is "follow-up." Is "ship default-on with no UI opt-out" a decision you'd defend in a room? Flag as we-don't-know-we-said-yes-anyway.
17. **Who is the single user you're picturing when you imagine this feature shipping?** Describe them. What's their monitor? Their workflow? Do they run Lattice? Do they have existing muscle memory around new-workspace? If you can't name three of them, you're building a default for yourself.
18. **What is the success metric?** What number, six months post-ship, would tell you this feature was right? Flag as we-don't-know if there isn't one.
19. **Did you consider shipping this as a command palette action — `⌘⇧G: Grid This Workspace` — instead of as a default?** On-demand gridding has all the upside and almost none of the downside. Why is default-on the chosen shape?
20. **What does the settings pane toggle look like?** Just an on/off, or does it let the user pick their grid (1×1, 2×2, 2×3, 3×3, custom)? If the latter, the whole classification logic collapses into a user preference and the monitor-class detection becomes a "suggested default" rather than the acting rule. That's a much better feature. Why isn't *that* the MVP?
