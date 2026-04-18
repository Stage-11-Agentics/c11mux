# Standard Review Synthesis — c11mux-textbox-port-plan

**Reviewers synthesized:** Claude Opus 4.7, Codex (standard)
**Missing:** Gemini (API capacity failure — not available for this round)
**Plan under review:** `docs/c11mux-textbox-port-plan.md`
**Date:** 2026-04-18

> **Gap Notice:** The third Standard review slot (Gemini) failed due to API capacity and is absent from this synthesis. Findings below draw from two independent perspectives; a tie-breaker / additional perspective on architectural questions (especially drag lifecycle depth and theming seam) is not available. Treat anything labeled "unique insight" as a single-model observation that has not been independently confirmed.

---

## Executive Summary

Both reviewers agree: the port is the right move, the decomposition is sound, and the feature is worth the weekend-sized integration cost. Both also agree the plan is **not execution-ready as written** — it contains at least one hard factual error (the `Cmd+Option+T` shortcut collision), several underspecified integration touchpoints, and one localization-policy conflict. None of the defects require rethinking the architecture; all are factual corrections, scope expansions, or additive touchpoints.

The consolidated verdict across both reviewers is **Needs minor-to-moderate revision, then ready to execute.** Revisions cluster around four axes:

1. **Shortcut ownership** (`Cmd+Option+T` is taken; recommend `Cmd+Option+B`).
2. **Drag lifecycle scope** (not just `performDragOperation`).
3. **Test-file reconciliation** (fork's tests are internally inconsistent; cannot be copied verbatim).
4. **Localization compliance** (plan says EN-only; policy and fork both already have JA).

Claude's review is notably deeper on agent-detection architecture and surface-metadata integration; Codex's review is sharper on the theme-seam question and c11mux's tagged-build policy. Neither reviewer flagged a show-stopper that invalidates the overall port strategy.

---

## 1. Where the Models Agree (Highest Confidence Findings)

These findings are surfaced by both reviewers independently and should be treated as high-confidence corrections.

1. **`Cmd+Option+T` is already bound in c11mux.** Both reviewers cite `Sources/AppDelegate.swift:9498` (close other tabs in focused pane). The plan's §4.5 / §7 claim that this chord is free is factually wrong. Both reviewers converge on the same recommendation: **use `Cmd+Option+B`** — the fork author's own source comment calls it out as the upstream-safe fallback, and it requires no migration of the existing close-other-tabs binding.

2. **Fork's test file is internally inconsistent and cannot be "copied with minimal edits."** Both reviewers caught the same two contradictions:
   - `TextBoxInputSettings.defaultEnabled = true` in fork source, but test asserts `false`.
   - Fork default shortcut key is `"t"`, but test asserts `"b"`.
   - The plan's §4.1 ("copy tests; update `@testable import`") therefore lands broken assertions in c11mux. Tests must be reconciled against whichever shortcut decision we lock in.

3. **Drag-routing touchpoints are undercounted in §4.9.** Both reviewers flag that the plan mentions only `performDragOperation` and the `findTextBox()` helper, but the fork also modifies:
   - `prepareForDragOperation` (accept drops over TextBox even when no terminal/webview is under cursor; Claude's specific point).
   - `draggingUpdated` (green "+" badge feedback; Claude's specific point).
   - `concludeDragOperation` / prepared-webview state (Codex's specific point).
   - Both converge on: expand Phase 6 to cover the full drag lifecycle, not just the terminal fallback branch.

4. **Localization strategy conflicts with both fork reality and c11mux policy.** The plan's §4.10 claims the fork is English-only; it isn't — the fork already ships Japanese translations for all TextBox strings. c11mux's CLAUDE.md also requires EN+JA for all user-facing strings. Both reviewers recommend: **port the fork's existing JA translations in the same PR.** Zero incremental cost, policy-aligned.

5. **Opt-in default (defaultEnabled = false) is the right call.** Both reviewers endorse flipping the fork's `defaultEnabled = true` to `false` for c11mux.

6. **Not porting `SUFeedURL` / fork release scaffolding is correct.** Both reviewers commend the "what we do NOT port" rejection list as the single most important discipline-preserving artifact in the plan.

7. **Phased commit structure is reviewable.** Both reviewers endorse the 8-phase split as the right granularity for this size of PR.

8. **The overall port-vs-reimplement decision is correct.** Both reviewers independently judge porting verbatim as cheaper than reimplementing, and explicitly endorse shipping it this way for the initial landing.

9. **Focus-interaction risk is non-trivial.** Both reviewers flag Workspace.swift focus logic as a real risk surface, with Codex pushing the risk level up from Low to Medium until validated.

---

## 2. Where the Models Diverge (Disagreement as Signal)

The reviewers disagree on a few specific points — these are where additional thought is warranted.

1. **Title-sync as a blocker vs. not mentioned.**
   - **Claude:** Treats the missing `Workspace.updatePanelTitle → terminalPanel.updateTitle(trimmed)` call as a **blocking functional regression** — without it, the agent-detection feature (Rules 3–5) silently never fires, so the port ships a visibly-working-but-broken feature.
   - **Codex:** Does not mention this touchpoint at all.
   - **Signal:** Claude's claim is specific enough to be verifiable. If true, this is the plan's second-most-important correction after the shortcut collision. The absence in Codex's review is likely a coverage gap rather than a disagreement, but it warrants confirming against source before locking in.

2. **Agent detection: port as-is vs. wire to AgentDetector.**
   - **Claude:** Strongly argues the fork's title-regex detector is weaker than c11mux's existing process-based `AgentDetector` writing to `SurfaceMetadataStore`. Recommends a ~10-line change to read `terminal_type` metadata first, fall back to title regex. Frames this as an architectural improvement, not just porting.
   - **Codex:** Does not raise this at all.
   - **Signal:** Claude is pulling from c11mux-specific knowledge (M2 metadata layer, AgentDetector) that Codex may not have deeply surveyed. The recommendation is low-cost and architecturally cleaner — worth surfacing to the plan author as a decision point even if the answer is "defer."

3. **Theme / foreground-color source.**
   - **Codex:** Flags a medium-severity gap: fork's `TerminalPanelView` references `GhosttyApp.shared.defaultForegroundColor`, which does not exist in current c11mux. Recommends explicitly choosing a source (`GhosttyConfig.foregroundColor` or a new runtime accessor) before Phase 4.
   - **Claude:** Does not raise this at all.
   - **Signal:** This is a Codex-only finding and, if accurate, is a concrete symbol-not-found compile error waiting to happen. Should be verified and, if confirmed, added to the plan as a Phase-4 decision point.

4. **Tagged-build policy compliance.**
   - **Codex:** Flags that the plan's generic `xcodebuild … build` language doesn't match c11mux's tagged-reload policy (CLAUDE.md mandates `./scripts/reload.sh --tag <slug>` or tagged derivedDataPath for any local run).
   - **Claude:** Does not raise this.
   - **Signal:** Codex is correct per CLAUDE.md. Low stakes (it's a working-process note, not a design flaw), but should be folded into Phase 8 validation language.

5. **File organization (keep 1246-line file vs. split).**
   - **Claude:** Explicitly recommends leaving it as one file for the initial port, with a follow-up ticket to split.
   - **Codex:** Raises a related question (Q11: slim down giant inline test-plan comments during port for maintainability?) but doesn't take a position on whole-file splitting.
   - **Signal:** Not a real disagreement — both reviewers are comfortable with "leave it big, refactor later." Worth confirming in plan as an explicit deferral.

6. **Focus-guard site count.**
   - **Claude:** Suggests the plan's "two focus guards" may be low; names additional c11mux-specific paths (`scheduleAutomaticFirstResponderApply`, `reassertTerminalSurfaceFocus`) that may need guards and recommends a grep pass.
   - **Codex:** Raises focus risk generically (Workspace.swift orchestration) but doesn't enumerate specific paths.
   - **Signal:** Claude's finding is more actionable. Add an explicit "grep all `makeFirstResponder(surfaceView)` call sites" step to Phase 3.

7. **Rollback / typing-latency regression plan.**
   - **Claude:** Raises a specific concern that a latency regression affecting TextBox-*disabled* users needs a concrete rollback plan. Recommends measuring typing latency with TextBox globally disabled as a committed baseline.
   - **Codex:** Does not raise rollback at all.
   - **Signal:** Claude is leaning on CLAUDE.md's typing-latency-sensitive-paths section. This is a reasonable but not critical add.

---

## 3. Unique Insights (Single-Model Observations)

### From Claude Only

1. **Missing title-sync touchpoint in `Workspace.updatePanelTitle`.** Without this line, `TerminalPanel.title` stays at default `"Terminal"` and the title-regex agent detection never matches. Framed as a blocking functional regression. (See divergence #1.)

2. **c11mux has a stronger agent detector (`AgentDetector` + `SurfaceMetadataStore`) that the plan ignores.** Recommends wiring TextBox's `detectedApp` check to read `terminal_type` metadata first, title regex as fallback. (See divergence #2.)

3. **`TextBoxInputContainer` identity under bonsplit churn.** Concern that conditional sibling-container mounting in the VStack could race with rapid `Cmd+Opt+T` toggles during bonsplit drag; the `panel.inputTextView` weak ref could churn. Plan's §4.4 mentions focus races generically but doesn't call out this specific sibling-identity concern.

4. **`TerminalPanelView` signature drift.** c11mux's `TerminalPanelView` does not take a `paneId: PaneID` parameter; fork's does. Non-blocking for the port, but means during Phase 4 the diff cannot be taken wholesale — only the TextBox-relevant slice.

5. **Settings UI placement underspecified.** cmuxApp.swift is 6197 lines. "Append a SettingsSectionHeader" doesn't say *where* — Input tab? Keyboard Shortcuts? Advanced? Plan should name the target.

6. **`TextBoxToggleTarget.default` vs. `.all` semantics are redundant as specified.** If `.default` always resolves to `.all`, the variable is dead weight. Recommend promoting scope to a user-configurable setting stored in UserDefaults.

7. **M2 surface-metadata integration opportunities.** Per-surface `isTextBoxActive`, draft-text persistence, sidebar metadata — all deferrable, but file the follow-up tickets at port time rather than post-ship.

8. **Two-commit regression-test pattern does not apply here.** Plan should explicitly note that since the tests validate a ported feature (not a c11mux bug fix), the red-then-green commit split doesn't apply. Otherwise a future reviewer will ask.

9. **Upstream-contribution intent affects commit hygiene and file organization.** Worth explicit call: is there a plan to upstream into `manaflow-ai/cmux` after it bakes?

10. **CI implications.** Phase 8 says "push and let build-only PR CI run." c11mux's CI is now build-only (`f65024da`). Do the `TextBoxInputTests.swift` run anywhere on CI/VM, or are they local-only?

### From Codex Only

1. **Theme / foreground-color source is unspecified for current c11mux.** Fork references `GhosttyApp.shared.defaultForegroundColor` which c11mux doesn't expose. Needs an explicit chosen source before Phase 4. (See divergence #3.)

2. **Tagged-build policy compliance.** Plan's generic `xcodebuild` language needs to be rewritten against c11mux's `./scripts/reload.sh --tag <slug>` convention. (See divergence #4.)

3. **"Enable Mode = On" activation semantics.** When the user flips the master toggle on, should *all existing* panels immediately show the TextBox, or only new / focused panels? Plan doesn't say. (Q9 in Codex's list.)

4. **Trimming newlines on submit — intentional product behavior?** Should leading/trailing blank lines be preserved, or is trimming deliberate? (Q8 in Codex's list.)

5. **Browser / markdown focus behavior for the shortcut.** Should the TextBox toggle chord work when a browser or markdown surface is focused, and if so, what's the expected focus behavior? (Q6 in Codex's list.)

6. **Pre-port PR idea.** Codex raises the option of landing a small preparatory PR that only resolves shortcut ownership and tests baseline before the feature code arrives. (Q12 in Codex's list.) Not a strong recommendation, but a real option.

7. **Shortcut migration specificity.** If the project *does* choose to keep `Cmd+Option+T` for TextBox, where exactly is the new close-other-tabs binding specified? Plan doesn't address the migration path. (Q2 in Codex's list.)

---

## 4. Consolidated Questions for the Plan Author

Deduplicated across both reviews, ordered by priority (blockers first):

### Blocker / Decision-Lock Questions

1. **Shortcut default: use `Cmd+Option+B`, or rebind `Cmd+Option+T`'s current owner?** `Cmd+Option+T` is currently bound to "close other tabs in focused pane" in c11mux (both menu wiring and AppDelegate). The fork author's own source comment acknowledges `Cmd+Option+B` as the upstream-safe fallback. **Both reviewers recommend `Cmd+Option+B` — zero migration cost.** If instead you want to keep `Cmd+Option+T` for TextBox, where is the migration for close-other-tabs specified?

2. **Test-file reconciliation strategy?** Fork's `TextBoxInputTests.swift` has two contradictions against fork source itself (`defaultEnabled` false-vs-true; default key `"b"` vs. `"t"`). "Copy verbatim + update `@testable import`" will land broken assertions. Port tests selectively and update expectations to whichever shortcut/default you lock in.

3. **Drag lifecycle scope: `performDragOperation` only, or full lifecycle?** The fork modifies `prepareForDragOperation`, `draggingUpdated`, and `concludeDragOperation` in addition to `performDragOperation`. Which of these are in-scope for the port? (Both reviewers recommend: full lifecycle.)

4. **Localization: port fork's existing Japanese translations, or explicitly take a policy exception?** Plan says EN-only; fork already has JA; CLAUDE.md policy requires EN+JA for user-facing strings. **Both reviewers recommend: port JA translations in the same PR.**

5. **Title-sync in `Workspace.updatePanelTitle` — confirm this touchpoint is added?** Without `terminalPanel.updateTitle(trimmed)`, the fork's agent-detection (Claude/Codex title regex) silently never fires, shipping a broken agent-integration feature. Claude's review flags this as a blocking functional regression. Please confirm against source and add to §4.4 if confirmed.

### Architectural / Integration Questions

6. **Agent detection: port title-regex as-is, wire to c11mux's `AgentDetector` / `SurfaceMetadataStore`, or both?** c11mux has a stronger process-based detector writing `terminal_type` metadata. A ~10-line change would have TextBox consult metadata first and fall back to title regex. Stronger for detached/renamed-tab scenarios.

7. **Theme foreground-color source for TextBox styling?** Fork references `GhosttyApp.shared.defaultForegroundColor`, which current c11mux doesn't expose. Should we use `GhosttyConfig.foregroundColor`, add a new runtime accessor, or something else? Needs explicit decision before Phase 4.

8. **Focus-guard site count.** Plan says two guards (`ensureFocus`, `applyFirstResponderIfNeeded`). c11mux also has `scheduleAutomaticFirstResponderApply` and `reassertTerminalSurfaceFocus` in the focus-restore chain. Should every `makeFirstResponder(surfaceView)` call site get a TextBox guard? Recommend a grep pass during Phase 3.

9. **Toggle scope: keep hardcoded `.all`, expose as user setting, or change default to `.active`?** `.default` currently resolves to `.all`. Multi-agent workflows may want per-pane scope. Recommend: global UserDefaults setting, default `.all`, add to Settings rows.

10. **Shortcut behavior across surface types.** Should the TextBox toggle chord work when browser or markdown surfaces are focused, and if so, what's the expected focus behavior?

11. **"Enable Mode = On" activation semantics.** When the master toggle flips on, do existing panels show TextBox immediately, or only new/focused panels?

12. **Settings UI placement.** cmuxApp.swift is 6197 lines — which settings tab/section does the TextBox block go into (Input? Keyboard Shortcuts? Advanced?)?

### Product / Policy Questions

13. **Submitted-text newline behavior.** Preserve leading/trailing blank lines, or is trimming deliberate?

14. **Per-surface persistence scope.** Should `isTextBoxActive` and draft text survive app restarts via `SurfaceMetadataStore`, or stay in-memory? (Defer OK, but file the follow-up at port time.)

15. **IME coverage for validation.** Japanese only in Phase 8, or Chinese and Korean too? (Recommend JA for initial port, CJK follow-up.)

16. **Rollback plan if a typing-latency regression ships.** Opt-in default makes TextBox-enabled rollback trivial, but what about regressions affecting TextBox-disabled users? Recommend committing a typing-latency baseline with TextBox disabled as a reference.

### Execution / Hygiene Questions

17. **M-numbering and branch name.** Is this M9? Confirm convention (`m9-textbox-input` vs. `M9-textbox-input` vs. `feature/m9-textbox-input`).

18. **One PR or split into scaffolding + integration?** 8 commits in one PR is borderline but reviewable. Claude's recommendation: one PR (splitting creates awkward intermediate states). Codex's option: a small pre-port PR that only resolves shortcut ownership + tests baseline.

19. **Build commands in Phase 8 need to use tagged reloads.** Rewrite against c11mux's `./scripts/reload.sh --tag <slug>` convention rather than generic `xcodebuild`.

20. **Changelog / docs / screencasts.** Fork has `docs/assets/textbox-*.{gif,mp4,png}`. Port them only if we ship a user-facing changelog/release note announcing the feature.

21. **Two-commit regression-test pattern.** Since these tests validate a ported feature (not a c11mux bug fix), the red-then-green commit split doesn't apply — please state that explicitly in §4.1 to avoid reviewer confusion.

22. **CI coverage for `TextBoxInputTests.swift`.** c11mux's PR CI is build-only (`f65024da`). Where do the new unit tests run — CI, VM, or local-only?

23. **Inline test-plan comments in `TextBoxInput.swift`.** Retain the giant inline test-plan comments verbatim, or slim them for c11mux maintainability?

24. **File organization follow-up.** Keep as one 1246-line file for the initial port (both reviewers OK with this), but file a follow-up ticket to split into `Sources/TextBoxInput/` once the feature has bedded in?

25. **Upstream-contribution intent.** Plan to upstream into `manaflow-ai/cmux` after it bakes in c11mux? Affects commit hygiene (cherry-pickability) and file organization.

---

## 5. Overall Readiness Verdict (Synthesized)

**Verdict: Needs minor-to-moderate revision, then ready to execute.**

Both reviewers converge on "directionally right, execution details need a revision pass." Claude's framing: "factual corrections and one additive touchpoint, not a rethink." Codex's framing: "needs revision before implementation, ready once shortcut / drag / tests / localization are resolved." Same destination, slightly different phrasing.

### Minimum Revisions Before Phase 1 (consolidated from both reviewers)

1. Resolve shortcut ownership. **Recommended: switch default to `Cmd+Option+B`.** Update §4.5, §7 risk register, and §8 Q1 accordingly.
2. Expand §4.9 drag-routing scope to cover `prepareForDragOperation`, `draggingUpdated`, and `concludeDragOperation` — not just `performDragOperation`.
3. Reconcile test-file strategy in §4.1: selective port with assertions updated against c11mux's chosen defaults, not verbatim copy.
4. Flip §4.10 localization plan: port fork's existing Japanese translations alongside English.
5. Add the `Workspace.updatePanelTitle → terminalPanel.updateTitle(trimmed)` touchpoint (verify against source first; add to §4.4 or new §4.4b if confirmed).
6. Specify the theme foreground-color source for TextBox styling (Codex's point; verify fork reference to `GhosttyApp.shared.defaultForegroundColor` and document the c11mux-side replacement).
7. Rewrite Phase 8 build commands to use c11mux's tagged-reload convention (`./scripts/reload.sh --tag <slug>`).

### Strongly Recommended (but not strict blockers)

8. Add a decision point on wiring TextBox agent detection through c11mux's `AgentDetector` / `SurfaceMetadataStore` (recommend: minimal wiring, title regex as fallback).
9. Enumerate settings UI placement target (specific tab/section in cmuxApp.swift).
10. Enumerate all `makeFirstResponder(surfaceView)` call sites and add focus guards where needed.
11. Make an explicit call on toggle scope (recommend: global UserDefaults setting, default `.all`).
12. File M2-metadata follow-up tickets at port time (persistence, sidebar indication).

### Execution Estimate

Once revisions are in, both reviewers judge this as a senior-engineer-weekend-sized piece of work: long afternoon for Phases 1–5, half-day for Phases 6–8 including validation. The 8-phase commit structure keeps the PR reviewable. Worktree isolation (`../cmux-m9-textbox`) is the correct working mode for the integration.

### Gap Acknowledgment

The Gemini review was not available for this round. A third perspective might have surfaced additional architectural concerns (particularly around bonsplit interaction, portal-layer mounting, or broader focus-routing implications) that neither Claude nor Codex emphasized. The two surviving reviews are convergent on the high-priority corrections, but absent a tiebreaker, reviewers downstream of this synthesis should treat the single-model "unique insights" (Section 3) as provisional until verified against source.
