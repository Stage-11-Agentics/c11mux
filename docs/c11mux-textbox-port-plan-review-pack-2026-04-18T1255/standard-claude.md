# Standard Plan Review — c11mux-textbox-port-plan (Claude)

**Reviewer model:** Claude Opus 4.7
**Plan:** `docs/c11mux-textbox-port-plan.md`
**Date:** 2026-04-18

---

## Executive Summary

The plan is directionally right and the overall shape — "selective forward-port, not a merge; one 1246-line file verbatim + small additive hooks in 7 sites" — is the correct framing. The feature is genuinely useful for agent workflows, the fork is clean enough to cherry-pick, and porting is clearly cheaper than reimplementing. I would say yes, do it.

That said, the plan has **one hard-blocking factual error** that would waste an afternoon if it slipped into execution, **one quiet functional regression** that would ship a broken feature, and **one architectural question** that's worth surfacing before Phase 1. These are all cheap to fix now.

1. **`Cmd+Opt+T` is already bound in c11mux.** The plan claims (§4.5, §7 risk register) that this shortcut is not currently used. It is — `Sources/AppDelegate.swift:9498` binds `Cmd+Opt+T` to "close other tabs in focused pane" (and, contextually, "close settings window" when the settings window is key). The fork's own source code comment at `KeyboardShortcutSettings.swift:265` even says: *"Default: Cmd+Opt+T (upstream cmux PR uses Cmd+Opt+B to avoid conflict with close-other-tabs)."* The fork author already hit this and knew about it. The plan missed the comment.
2. **`Workspace.updatePanelTitle` is a required second touchpoint and it's missing from the plan.** The fork adds a single critical line inside `updatePanelTitle` that calls `terminalPanel.updateTitle(trimmed)` so the TextBox's Claude Code / Codex title-regex detection actually has a title to match against. c11mux's current `updatePanelTitle` does not sync into `TerminalPanel.title`, and no other code path in c11mux updates `TerminalPanel.title` either. Without this line, the AI-agent-specific behavior (Rules 3–5: `/`, `@`, `?` forwarding) silently never fires — the feature appears to work but the agent-integration part of it is dead. The plan says §4.4 adds "one method, `toggleTextBoxMode(_:)`" — it should add two things in Workspace.swift.
3. **c11mux already has a stronger agent detector (`AgentDetector`) that the plan ignores.** c11mux's `AgentDetector` reads foreground processes via `ps -t <ttys>` and writes authoritative `terminal_type` into M2 metadata with explicit precedence (declare/osc/explicit > heuristic). The fork's approach is a regex over the terminal tab title — much weaker, breaks when the user renames a tab, breaks in detached sessions, etc. The plan ports the title-regex detector verbatim. It should at least *consider* wiring TextBox's "is this Claude / Codex?" check to read c11mux's `terminal_type` metadata instead. (Title-regex can stay as a fallback.)

Beyond these, there are several smaller issues and questions (below). Overall verdict: **Needs minor revision, then ready to execute.** The revisions are factual corrections and one additive touchpoint, not a rethink.

---

## The Plan's Intent vs. Its Execution

The underlying intent is well captured: port a meaningful feature for agent workflows without absorbing the fork's branding/release scaffolding. The plan reads like an engineer who actually sat down with both trees — the "what we do NOT port" table (§5) is exactly the kind of explicit rejection list that prevents scope creep during execution, and the phase split is sensible ("drop code in → wire up → validate" is the canonical order).

Where execution drifts from intent:

- **The plan underspecifies the integration surface.** It names 7 fork-touched files in §4 but undercounts the actual touchpoints within them. ContentView is called out as touching `performDragOperation` and a helper (§4.9), but the fork also modifies `prepareForDragOperation` and `draggingUpdated` for the green "+" badge feedback (fork lines 693–699 and 783–790). Workspace is called out as touching `toggleTextBoxMode` only, but also needs the title-sync line. These are small changes, but "the full list" should be in the plan, not discovered during Phase 5.
- **The plan claims the fork is English-only on localization (§4.10); it isn't.** The fork's `Localizable.xcstrings` already ships Japanese translations for all 9 TextBox strings. Recommendation should flip from "ship English-only" to "copy the existing JA translations along with the EN" — zero incremental cost, and c11mux doesn't regress its i18n bar. (See Q4 below.)
- **The plan says `§4.1`: "Copy tests; update `@testable import`."** The tests as they exist in the fork assert `shortcut.key == "b"` at line 54 of `TextBoxInputTests.swift`, but the fork's actual default shortcut key is `"t"` (per `KeyboardShortcutSettings.swift:267`). **The fork's own tests are broken right now.** Copying verbatim lands broken tests in c11mux. Decide on final shortcut (see §Weaknesses), then update the test assertion to match.

---

## Architectural Assessment

The decomposition is good. Single file + additive hooks is the right structure for a feature of this shape — it keeps the blast radius small and makes the eventual upstream-merge scenario (if alumican/cmux-tb ever lands in manaflow-ai/cmux) cleanly reversible.

### Things the plan gets architecturally right

- **Opt-in default (flipping `defaultEnabled` to `false`).** c11mux has its own personality and its own users; shipping a new UI-layer feature default-on would surprise everyone. The plan's instinct here is correct.
- **Not porting `SUFeedURL`.** This is the kind of subtle thing that would otherwise silently hijack the update channel. Good catch.
- **Portal-mounted search overlay preservation (§4.3 review point).** Flagging this up front is exactly right — CLAUDE.md calls out the search-overlay layering contract as a landmine, and the plan anticipates it.
- **Scroll-position restore via `scroll_to_row` (§4.8).** Preserving scroll offset when the TextBox resize triggers SIGWINCH is a genuinely subtle bit of correctness. The plan correctly identifies this as a dependency and confirms the binding exists in c11mux's ghostty submodule.

### Things that deserve more architectural attention

- **Agent detection duplication (see point 3 above).** c11mux has a canonical agent-detection layer. Porting a second, weaker one creates two sources of truth for "is this a Claude Code pane?" that will drift. The minimal fix: keep TextBox's detection code for now, but have it *consult* `SurfaceMetadataStore.shared.get(surfaceId: …).terminal_type` before falling back to title regex. This is a ~10-line change and puts c11mux's TextBox on better footing than the fork's.
- **`TerminalPanel.inputTextView` is a weak reference held at the model layer.** The plan's §4.2 proposes `weak var inputTextView: InputTextView?` on the model. This couples the SwiftUI model to an AppKit view — not inherently wrong, but it creates an ordering dependency: the panel's `inputTextView` is only populated when `TextBoxInputContainer` is mounted, which only happens when `showTextBox == true`. Any code path that does `panel.inputTextView?.window?.makeFirstResponder(...)` before the container has mounted will silently no-op. The fork's `toggleTextBoxMode` handles this by wrapping in `DispatchQueue.main.async`, which works but is fragile. Worth at least a note in the plan that this weak-ref pattern is understood and deliberate.
- **TextBoxInputContainer identity under bonsplit churn.** c11mux's `TerminalPanelView` carefully uses `.id(panel.id)` on `GhosttyTerminalView` to keep identity stable across bonsplit updates. The plan's proposed VStack wrapping puts `TextBoxInputContainer` as a sibling of `GhosttyTerminalView`. The TextBoxInputContainer is conditionally present (`if showTextBox`), which means every toggle mounts/unmounts it. Test this against rapid `Cmd+Opt+T` toggles during a bonsplit drag — there's a plausible failure mode where the panel's `inputTextView` weak ref churns and `toggleTextBoxMode` races with mount/unmount. The plan's §4.4 review point mentions focus races generally, but this specific sibling-container-identity concern is worth calling out.

### Alternative framing worth one paragraph's consideration

The plan treats this as a straight source port. An alternative framing: "Port the idea, not the file." The fork's `TextBoxInput.swift` is a 1246-line behemoth bundling settings, routing, SwiftUI container, AppKit bridge, and custom NSTextView subclass. c11mux's code style tends toward smaller, more composable files. A future maintainer (human or agent) will find "one 1246-line file" much harder to evolve than "seven 150–200-line files in `Sources/TextBoxInput/`." I think the plan's choice (verbatim port) is still right for the *initial* landing — it's faster, makes upstream merges easier if we ever want them, and avoids gratuitous churn. But §9 acceptance criteria should include a follow-up ticket to split the file once the feature has bedded in. Otherwise it becomes a 1246-line permanent tax on whoever next touches it.

---

## Is This the Move?

Yes, with the caveats above. Reasons it's the right bet:

- **Real user value for agent workflows.** Multi-line prompt editing in-terminal is genuinely awful. The use case is solid and not hypothetical.
- **Scope is bounded.** A 1246-line additive file + ~250 lines of hooks across 7 files is a weekend-sized PR for a senior engineer. The risk register is accurate: medium risk on ContentView drag routing, low risk everywhere else.
- **The fork has done the hard R&D.** The 200ms delay before the synthetic Return, the IME-safe update pattern, the bracket-paste mechanism, the focus-guard locations — these are all bugs-that-already-happened-to-someone-else. Porting captures that institutional memory for free.
- **Opt-in default means low downside.** Worst case, users don't turn it on and the only cost is 1246 lines of dead code and a slightly bigger binary. That's acceptable.

Reasons it could still go wrong (beyond the three issues above):

- **Drag routing in c11mux is non-trivial.** c11mux uses a `DragOverlayRoutingPolicy` helper plus state-tracking across `draggingEntered/Updated/Exited/prepareForDragOperation/performDragOperation`. The fork's diff against upstream cmux mirrors all of this, but c11mux's version has evolved independently (M7 sidebar work, browser/terminal coordination). The plan flags this as "highest collision risk" but understates it — this is where real work happens.
- **Typing latency drift.** The plan correctly notes that the TextBox hooks don't touch `forceRefresh()`, `hitTest()`, or `TabItemView`. But adding a VStack sibling to `GhosttyTerminalView` does add SwiftUI invalidation paths. I'd want the debug log compared pre/post with TextBox *unmounted* (baseline), TextBox *mounted-but-empty*, and TextBox *mounted-and-focused-while-typing-in-terminal*. Not a high concern but worth explicitly measuring per phase 8.
- **cmuxApp.swift is massive (6197 lines).** The plan says "append-only addition to the settings panel." In practice, appending to a 6000-line file without reading the surrounding settings structure leads to misplaced sections. Phase 2 should budget 30 minutes for reading the settings section layout, not just "append."

---

## Key Strengths

1. **Explicit rejection list (§5).** The "what we do NOT port" table is unusually good. It's the single most important artifact in this plan because it defines the port's discipline. Every port of a forked feature I've watched go sideways did so because *something* from the fork's branding/release infrastructure leaked in silently. This plan preempts it.

2. **Phased execution with build checks between phases.** The 8-phase structure (scaffold → model → terminal → view → wiring → drag → i18n → validate) is the right granularity. Each phase is one logical commit, which matches the two-commit regression-test policy in CLAUDE.md and keeps PR review digestible.

3. **Risk register names specific mitigations, not platitudes.** §7 items like "Verified present in c11mux's submodule at `src/input/Binding.zig:427`" are the right kind of risk-register entries — they cite evidence. (Offset by the *incorrect* "`Cmd+Option+T` collision: Resolved" entry, which is the single biggest failure mode of this plan.)

4. **Worktree isolation.** Doing this work in `../cmux-m9-textbox` via `git worktree` rather than branching the main checkout is exactly right — the user has other agents in-flight and the feature touches enough hot files that interleaving would be painful.

5. **Default-off and opt-in via Settings.** Correct instinct. Users discover it on their terms.

---

## Weaknesses and Gaps

### 1. The shortcut-collision claim is factually wrong
Already covered in the Executive Summary. This is the plan's highest-priority correction. Decision needed:
- Use `Cmd+Opt+B` (the fork author's explicit fallback per their code comment; matches fork test assertions out of the box), OR
- Use `Cmd+Opt+T` and rebind c11mux's "close other tabs" to something else first, OR
- Use some third shortcut (e.g. `Cmd+Ctrl+T`).

Recommend `Cmd+Opt+B`. It's what the fork author intended for the upstream PR, it's what the tests already assert, and "close other tabs in pane" is a muscle-memory shortcut that c11mux users may already rely on.

Be aware `Cmd+Shift+B` is already used in c11mux? Check: `KeyboardShortcutSettings.swift:123` shows `Cmd+B` (no modifiers) is bound to `toggleSidebar`. `Cmd+Opt+B` is distinct and appears unused. Worth double-checking during execution before locking in.

### 2. The title-sync touchpoint is missing
Already covered. Add to §4.4 explicitly: *"Additionally, inside `updatePanelTitle`, call `terminalPanel.updateTitle(trimmed)` when `didMutate && panels[panelId] is TerminalPanel`. Without this, `TerminalPanel.title` stays at its default value `"Terminal"` and TextBox agent detection never fires."*

### 3. Fork test file inconsistency not flagged
Already covered. Plan §4.1 should say: *"Copy; update `@testable import` to c11mux's target name; update the default-shortcut assertion to match our chosen default (see Q1 below)."*

### 4. Drag-routing touchpoints undercounted
Plan §4.9 mentions only `performDragOperation` and `findTextBox()`. Fork also modifies:
- `prepareForDragOperation` — to accept drops over TextBox even when no terminal/webview is under cursor.
- `draggingUpdated` — to return `.copy` for the green "+" badge feedback over the TextBox.
- `concludeDragOperation` behavior is preserved (OK).

The `prepareForDragOperation` change is the most subtle: c11mux's current `prepareForDragOperation` returns `true` only if a webview *or* terminal is under the cursor. If the user drops a file while hovering over a TextBox that sits below a terminal but outside the terminal's bounds, the drop will be rejected at the `prepare` stage and `performDragOperation` won't get a chance to route. Missing this change would make the drag feature appear not to work, but only when the drop happens in the narrow padding zone.

### 5. Focus-guard site count may be low
Plan §4.8 says "Two focus guards." The fork adds guards in two places — `ensureFocus` and `applyFirstResponderIfNeeded`. c11mux has those same two paths (verified). But c11mux also has `scheduleAutomaticFirstResponderApply` and `reassertTerminalSurfaceFocus` in the focus-restore chain. Worth grep'ing every call path that ultimately calls `window.makeFirstResponder(surfaceView)` and checking whether each needs the TextBox guard. If the count ends up being three or four, add them.

### 6. The `TerminalPanelView` call-signature drift
c11mux's `TerminalPanelView` does not take a `paneId: PaneID` parameter; the fork's version does (because the fork uses it for bonsplit-aware portal priority). **This is a non-issue for the port** — you don't need paneId for TextBox functionality — but it means `TerminalPanelView` in fork vs c11mux have diverged beyond the TextBox changes. During Phase 4, take only the TextBox-relevant diff, not the full file-diff. The plan should flag this.

### 7. Settings UI placement underspecified
§4.7 says "append" a `SettingsSectionHeader("TextBox Input")` section. c11mux's cmuxApp is 6197 lines of settings views. Plan should name the target: is this in the Input Settings tab? The Keyboard Shortcuts tab? The Advanced tab? The fork appends inside an existing pane structure — the specific placement matters for the settings navigation to feel coherent.

### 8. `TextBoxToggleTarget.default` semantics vs §8 Q3
§4.6 passes `workspace.toggleTextBoxMode(.default)` in AppDelegate. `.default` resolves to `.all` per `TextBoxBehavior.toggleScope`. But §8 Q3 asks "keep `.all` or switch to `.active`?" as if this were a decision in the plan, then recommends keeping `.all`. If we keep `.all`, the `.default` variable is just a redundant alias. If we ever want per-pane toggle scope (sensible for multi-agent workflows where different panes run different agents), we need more plumbing than "flip the `toggleScope` constant." Worth making a call on whether scope should be per-workspace (stored in workspace state), global (stored in UserDefaults), or hardcoded. Recommend: global UserDefaults setting, default `.all`, add to the four settings rows in §2.

### 9. No explicit handling of c11mux's M2 surface metadata
c11mux has a rich `SurfaceMetadataStore` (per CLAUDE.md / memory index on c11mux module-branch patterns). TextBox's feature could benefit from:
- Persisting `isTextBoxActive` per surface across app restarts (currently lost).
- Persisting `textBoxContent` (draft text) per surface. §8 Q5 raises this as an open question; recommend deferring but file the ticket at port-time, don't wait to discover the need post-ship.
- Surfacing "TextBox is active on this pane" as sidebar metadata (minor, but fits the M7 title-bar / sidebar-metadata story).

None of this is a blocker for the initial port. The plan should just note these as follow-ups rather than leave them implicit.

### 10. No test for the regression-policy two-commit pattern
CLAUDE.md has a regression-test commit policy: failing test first commit, fix second commit. The plan's Phase 1 commits both the test file *and* the source file, which means the test never sees the "red" state. This isn't wrong per se — the tests are ports, not regression tests for c11mux bugs — but the plan should explicitly say the two-commit rule doesn't apply here because the tests are validating the ported feature, not guarding against a bug fix.

---

## Alternatives Considered

### A. Port vs. reimplement
Plan chose port. Reimplementation would mean writing a ~1246-line feature from scratch with c11mux-idiomatic patterns, integrating AgentDetector, splitting into composable files, etc. **Port is better** for the initial ship: the R&D cost (discovering the 200ms Return delay, IME-safe updates, focus-guard locations) is already sunk in the fork. Reimplementing would pay all that cost again. Defer reimplementation to a future refactor ticket.

### B. Upstream the feature to manaflow-ai/cmux first, then merge upstream
Would mean contributing TextBox to the upstream cmux (not the c11mux fork), then pulling in the upstream commit via c11mux's normal Ghostty-style submodule/update flow. **Port is better here too** — c11mux diverges from upstream cmux in ways that mean round-tripping through an upstream PR would create more merge pain, not less.

### C. Keep TextBox as a separate module/target rather than integrating
Would mean shipping TextBox as an optional module with a plugin-style hook. **Port is better** because the integration surface (drag routing, focus guards, keyboard shortcuts) is already deeply coupled to c11mux internals — a plugin boundary would either leak those internals or duplicate them.

### D. Wrap TextBoxInput into a Panel (vs. inline-below-terminal)
Would mean giving TextBox its own Panel type (`.textbox`) and letting bonsplit manage it as a splittable pane. **Plan's choice (inline below terminal) is better** — the TextBox is conceptually tied to exactly one terminal surface (it submits text to it). Giving it its own pane breaks the 1:1 relationship and creates questions like "what terminal does this TextBox send to?" that the inline approach eliminates for free.

### E. Ship without agent-integration, just the basic TextBox
Would mean stripping Rules 3–5 (the `/`, `@`, `?` forwarding). **Keeping agent integration is better** — the whole user-value story of this feature is that it helps agent workflows. Without that, it's just "a text box" and the feature is much less compelling. But: fixing the title-sync bug (Weakness #2) is required for this rationale to hold.

---

## Readiness Verdict

**Needs minor revision, then ready to execute.**

Minimum revisions before Phase 1:
1. Correct the `Cmd+Opt+T` collision claim in §4.5, §7, and §8 Q1. Propose `Cmd+Opt+B` as the default.
2. Add the `Workspace.updatePanelTitle` title-sync touchpoint to §4.4 (or a new §4.4b).
3. Flag the fork test-file inconsistency in §4.1 and commit to updating the assertion.
4. Add `prepareForDragOperation` and `draggingUpdated` to §4.9.
5. Correct §4.10 — fork ships Japanese translations; carry them forward.
6. Add a decision point on whether to wire TextBox agent detection through c11mux's `AgentDetector` / `SurfaceMetadataStore` (recommend: minimal wiring, title regex as fallback).

None of these require rethinking the architecture. They're all factual corrections and one additive touchpoint.

Once the revisions are in, the plan is executable by a senior engineer in a single worktree session (probably a long afternoon for Phases 1–5, another half-day for Phases 6–8 including validation). The 8-phase commit structure keeps the PR reviewable.

---

## Questions for the Plan Author

1. **Shortcut default: `Cmd+Opt+B` or rebind `Cmd+Opt+T`?** `Cmd+Opt+T` is currently bound to "close other tabs in focused pane" in c11mux. The fork author's source-code comment already acknowledges `Cmd+Opt+B` as the upstream-friendly fallback. Which do you want? (Recommend: `Cmd+Opt+B`, zero rebinding cost.)

2. **Agent detection: port title-regex, wire to AgentDetector, or both?** The fork detects Claude Code / Codex via terminal-title regex. c11mux has a stronger process-based `AgentDetector` writing to `SurfaceMetadataStore`. Recommend wiring TextBox's `detectedApp` check to read `SurfaceMetadataStore.terminal_type` first, falling back to the fork's title regex. ~10-line change, significantly more reliable in detached/renamed scenarios.

3. **Should `TerminalPanel.title` be synced at all, or should TextBox just read from `SurfaceMetadataStore`?** If we go with the AgentDetector wiring (Q2), the `updatePanelTitle` title-sync becomes less critical — but still useful for any future `TerminalPanel.title` consumer. Recommend sync it anyway; cheap and orthogonal.

4. **Japanese translations: port fork's, translate fresh, or ship EN-only?** Fork already has JA translations; plan incorrectly claims otherwise. Recommend: port fork's JA translations along with EN. Zero cost.

5. **Settings UI placement: which settings tab/section does the TextBox block go into?** cmuxApp is 6197 lines; "append" is underspecified. Name the target (Input? Keyboard Shortcuts? A new Advanced subsection?).

6. **Persistence: draft text and `isTextBoxActive` per-surface?** §8 Q5 defers. Fine to defer but file the follow-up ticket at port time. Concretely: should TextBox's per-surface state land in `SurfaceMetadataStore` or stay in-memory?

7. **Toggle scope: keep hardcoded `.all`, or expose as a user-setting?** §8 Q3 keeps `.all`. I'd push for "global setting, default `.all`" so power users with multi-agent workflows can scope to active pane without touching source.

8. **File organization: leave as one 1246-line file, or split at port-time?** Recommend: leave as one file for the initial port (faster, cleaner diff, easier to grep for `[TextBox]` markers). File a follow-up ticket to split into `Sources/TextBoxInput/` once the feature has bedded in.

9. **M-numbering: is this M9?** §8 Q8 asks. The user's memory mentions M1–M8 branches. Presumably yes — but confirm the branch name convention (`m9-textbox-input` vs `M9-textbox-input` vs `feature/m9-textbox-input`).

10. **One PR or split into scaffolding + integration PRs?** §8 Q7 asks. 8 commits in one PR is borderline — reviewable but dense. Recommend: one PR. Splitting into two creates awkward intermediate states (Phase 1–3 landed but TextBox not reachable from UI) that invite "partially ported" to linger.

11. **CI implications?** c11mux's PR CI is build-only per the recent `f65024da` commit. Phase 8 says "push and let build-only PR CI run." Is there an existing unit-test gate that would run `TextBoxInputTests.swift`, or are we shipping the tests to run only locally / on the VM? (Per c11mux CLAUDE.md's testing policy, tests run on CI/VM, not locally.)

12. **Docs: do we want a changelog entry and/or a README blurb?** The fork provides `docs/assets/textbox-*.{gif,mp4,png}` screencasts. §8 Q6 asks whether to port these. My recommendation: port the screencasts into c11mux's docs *only if* we ship a user-facing changelog/release note announcing the feature. If we keep it undocumented-for-now (so the opt-in feels more like a power-user surprise), skip the assets.

13. **Feature-flag vs. settings-only gating?** Plan ships it as settings-only (opt-in via Settings pane). Any desire to additionally gate it behind a debug/feature flag for a first rollout period, so we can tell adopters "this is experimental, expect rough edges"? Probably not needed — the settings toggle is already explicit — but worth one line in the plan to say "no, settings toggle is sufficient."

14. **Phase 8 validation matrix includes IME testing with Japanese input. Do we want to add a Chinese and Korean IME pass?** The fork's test checklist includes all three (T3.1–T3.3). c11mux's current test user base is primarily EN/JA. Recommend: Japanese for the initial port, Chinese/Korean as a follow-up checkbox.

15. **What's the rollback plan if a regression ships?** The plan doesn't say. Given the opt-in default, rollback is trivially "users flip the setting off." But if a typing-latency regression slips through and affects TextBox-*disabled* users, we need a sharper rollback story. Recommend: Phase 8 validation explicitly measures typing latency with TextBox globally disabled, and we commit that baseline as an expected-latency reference for future agents.

16. **Upstream contribution intent?** Is there a plan to upstream this into `manaflow-ai/cmux` after it bakes in c11mux? That would affect commit hygiene (do we want the commits cherry-pickable back upstream?) and file organization (splitting the 1246-line file would make upstreaming harder). Probably no, given c11mux is diverging, but worth an explicit call.
