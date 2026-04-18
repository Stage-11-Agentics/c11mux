# Adversarial Review Synthesis — c11mux TextBox Input Port

- **Plan ID:** c11mux-textbox-port-plan
- **Synthesis of:** `adversarial-claude.md`, `adversarial-codex.md`, `adversarial-gemini.md`
- **Timestamp:** 2026-04-18 12:55
- **Posture:** Consolidated adversarial view. Unsoftened by design.

---

## Executive Summary

All three models converge on the same diagnosis: **the plan reads as a confident mechanical port but treats several load-bearing facts as resolved when they are demonstrably false in current c11mux `main`.** The most prominent example — the `Cmd+Option+T` shortcut collision — is flagged independently by every model with specific file/line evidence, and one model notes that the fork's own source code contains an inline warning about this exact collision that the plan missed.

The deeper pattern across reviews: the plan is anchored to **fork-delta framing** (what changed in the fork branch) rather than **c11mux-contract framing** (what current c11mux actually looks like). Multiple "verbatim copy" and "low risk" claims collapse when the target files are diffed against current `main`. The combination of stale diffs, underspecified integration in high-churn areas (drag routing, focus, responder chain), nondeterministic core mechanics (200ms delayed synthetic Return), brittle heuristics (title-regex app detection), and an explicit localization-policy violation produces a plan that three independent adversaries grade as **not execution-safe as written**.

Cost estimate from the reviews: the plan reads as ~2 days of work but all models predict 4-6 days to execute correctly, with a high probability of post-ship fixes. If implemented literally, at least two phases will stall mid-stream and need replanning.

---

## 1. Consensus Risks (Flagged by Multiple Models)

Numbered in rough priority order. Each item includes which models flagged it.

1. **`Cmd+Option+T` is NOT free — direct collision with existing "Close Other Tabs in Pane"** *(Claude, Codex)*
   - Claude: `AppDelegate.swift:9498` binds `Cmd+Option+T` to `closeOtherTabsInFocusedPaneWithConfirmation()`.
   - Codex: Confirmed via `Sources/cmuxApp.swift:627-631`, `Sources/AppDelegate.swift:9496-9511`, and guarded by `cmuxTests/AppDelegateShortcutRoutingTests.swift:1415`.
   - The fork's own source comment (`KeyboardShortcutSettings.swift:265`) explicitly warns: *"Default: Cmd+Opt+T (upstream cmux PR uses Cmd+Opt+B to avoid conflict with close-other-tabs)"* — the plan missed this warning inside the very file it intends to copy verbatim.
   - Plan's claim "verified not currently used" / "collision resolved" is factually false.

2. **"Verbatim copy" / "low risk" claims do not survive a current-tree diff** *(Claude, Codex, Gemini)*
   - Claude: Fork's `TerminalPanelView.swift` is 114 lines; current c11mux is 56 lines. Shapes differ — fork uses `paneId: PaneID`, pulls `GhosttyConfig.load()` inline, reads `GhosttyApp.shared.defaultBackgroundColor`.
   - Codex: Current c11mux `TerminalPanelView` has no `paneId` parameter. Current `GhosttyApp` has no `defaultForegroundColor` symbol.
   - Gemini: Frames as the "Drop-In Fallacy" — a 1,200-line file bridging SwiftUI/AppKit/custom key routing/event interception does not drop cleanly into a diverged tree.
   - Consensus: the port is not a copy-paste; it is a real integration refactor the plan has not scoped.

3. **Drag routing is under-specified — it is three entry points, not one** *(Claude, Codex)*
   - Claude: c11mux has `draggingEntered`, `draggingUpdated`, `performDragOperation` routed via `updateDragTarget` + `activeDragWebView` state. Fork also modified `updateDragTarget` to return `.copy` for TextBox hits; plan only mentions `performDragOperation`.
   - Codex: Fork's patch depends on `prepareForDragOperation`/`concludeDragOperation` state hooks that do not exist in current c11mux overlay (`Sources/ContentView.swift:607-685`).
   - Without the `updateDragTarget` change, users get a drop-rejected cursor over a valid drop target.

4. **200ms delayed synthetic Return is a fundamentally nondeterministic hack** *(Claude, Gemini)*
   - Gemini: Timing-based synthesis is "fundamentally nondeterministic"; will fail under CPU load, SSH round-trips, busy agents. When it fails the Return is swallowed, orphaned, or appended incorrectly — user sees hung prompts or desynced state.
   - Claude: 200ms is "empirically the minimum" for zsh/Claude CLI but unverified for SSH, `codex`, `ipython`, `docker exec`, tmux-in-ghostty, slow machines, or remote sessions.
   - Neither cancellation (double-submit in <200ms) nor pane-close / workspace-switch interactions during the delay window are specified.
   - Both models recommend: make the delay configurable OR replace with a deterministic prompt-readiness check.

5. **Typing-latency pass criterion is missing** *(Claude, Codex)*
   - Claude: CLAUDE.md explicitly names this a hot path; plan handwaves "verify with debug log." No numeric threshold (p50/p95 keystroke→paint), no baseline, no measurement method.
   - Codex: Asks what objective threshold is being enforced beyond "manual log eyeballing."
   - Adding `@Published` properties that churn on every keystroke, plus `NSTextView.draw(_:)` called on each edit, plus responder-chain hooks, are all suspect without measurement.

6. **AI-agent title-regex detection is brittle** *(Codex, Gemini)*
   - Pattern `Claude Code|^[✱✳⠂] |Codex` silently breaks when Anthropic or OpenAI changes a bullet character or title format.
   - No fallback behavior specified for false-positive or false-negative cases.
   - Ironic given this feature's primary marketing is "for AI-agent workflows."

7. **Localization policy violation is not handwave-able** *(Claude, Codex)*
   - CLAUDE.md / AGENTS.md (`AGENTS.md:145`): "All user-facing strings must be localized... Keys go in `Resources/Localizable.xcstrings` with translations for all supported languages (currently English and Japanese)."
   - Plan recommends English-only (~18 keys) as "option 1" without treating it as a policy exception.
   - Both models ask: either commit to localization or explicitly document the exception in the PR; do not silently skip.

8. **Focus / responder chain in SwiftUI + AppKit + Bonsplit is not additive** *(Claude, Gemini)*
   - Gemini: `firstResponder is InputTextView` is unreliable. AppKit focus is asynchronous and complex; workspace/tab switches will produce focus trapping or lost keystrokes.
   - Claude: Every focus-stealing code path in c11mux needs an `if firstResponder is InputTextView { return }` guard. Plan names two (§4.8); there are likely more.
   - Weak ref to `InputTextView` from `TerminalPanel` is suspect when the SwiftUI host tears down (tab inactive).

9. **Scope / PR size is larger than the plan admits** *(Claude, Gemini)*
   - Claude: 1,246-line Swift file + 18 xcstrings + 4 pbxproj edits + 8 integration hooks across 7 files = not digestible by cmux review standards.
   - Gemini: Classifies as a "god object" bridging multiple layers; should be refactored to c11mux architecture before merging, not ported as-is.
   - Plan's own mitigation ("split if too big") is buried as a conditional rather than the recommendation.

10. **Integration labeled "pure addition" is actually mutative in high-churn files** *(Claude, Codex, Gemini)*
    - Claude: `ContentView.swift` has drifted from the fork baseline significantly.
    - Codex: `Workspace.swift:7757-7857` focus pipeline is not self-contained.
    - Gemini: Adding `@Published` properties to `TerminalPanel` can trigger widespread SwiftUI re-invalidation.

---

## 2. Unique Concerns (Single-Model Risks Worth Investigating)

### Claude-only
11. **Multi-window semantics of `toggleTextBoxMode(.all)`** — Does "all" mean one workspace, one window, or all windows? Fork code iterates `panels.values` for a single workspace; behavior across windows is unspecified.
12. **Collision with c11mux's in-flight tier-1 persistence work** (`docs/c11mux-tier1-persistence-plan.md`) — both plans touch per-panel state (`isTextBoxActive`, `textBoxContent`); uncoordinated, they will collide.
13. **Upstream-fork provenance** — This is a fork by one developer (alumican) with 135 unmerged commits. Was it ever offered to manaflow-ai/cmux? If rejected, why are we adopting it?
14. **Session restore / bracket-paste marker interaction** — Replaying a partial paste in scrollback snapshots could leave orphaned `\x1b[200~` / `\x1b[201~` markers.
15. **Shell-integration heuristic breakage** — Wrapping every command in bracket-paste markers may change what c11mux's tab-dirty logic (`TerminalPanel.swift:49`) sees.
16. **Discoverability** — Setting checkbox + undocumented hotkey = weak discovery. No command-palette entry, no first-run tip, no Help-menu link.
17. **Dual-mode editor surface** — Two input modes in one terminal (line editor + TextBox) is a historical UX trap; every session will contain at least one "wrong mode" moment.
18. **Return-as-submit vs. Return-as-newline muscle memory** — `\`-continuation in bash/zsh will cause premature submits; `Shift+Return = send` is the web-chat convention.
19. **Existing `send` primitives duplication** — c11mux already has `cmux send` via socket/AppleScript/CLI. TextBox submission uses a bespoke bracket-paste+delay that other paths don't use. Which one is canonical?
20. **Scroll-preserve triple-race** — TextBox grows while terminal prints while user is mid-scroll. `handleLiveScroll` / `synchronizeScrollView` interactions unexamined.
21. **Rollback path** — If a user enables TextBox, hits a bug, and cannot disable it, what is the recovery? No safe-mode flag or hidden pref documented.
22. **Deprecation / sunset policy** — If <5% opt-in after 3 months, is this removed? Or kept as dead weight indefinitely?
23. **Full-screen / stage-manager / hidden-dock interactions** — Unexamined.
24. **Phased commits don't correspond to reviewable validation points** — Phase 1 compiles but does nothing; Phase 4 shows UI but nothing toggles. Reviewer cannot run the feature mid-stream.

### Codex-only
25. **Missing automation for integration regressions** — Copied tests are unit-level; no drag/focus/shortcut-dispatch integration test plan.
26. **Keyboard-layout matrix (Dvorak)** — c11mux has Dvorak-specific tests around shortcut dispatch; the plan has no compatibility matrix.
27. **Submission semantics ambiguity** — Fork's submit path trims leading/trailing newlines (`TextBoxInput.swift:689`). Is this intentional product behavior or incidental? Plan doesn't say.
28. **Rollout guardrails beyond "default off"** — No kill switch, no telemetry, no fast rollback branch strategy.
29. **Ghostty focus flows are race-sensitive** — `GhosttyTerminalView.swift:7591-7818` is stateful and race-sensitive; declared "low risk" without evidence.
30. **Plan-vs.-code inconsistency** — Plan picks `Cmd+Option+T` but copied tests (`TextBoxInputTests.swift:53-58`) assert default key `b`. Either the plan or the tests is wrong at merge time.

### Gemini-only
31. **Accessibility / VoiceOver** — Custom `NSTextView` subclass intercepting `keyDown` with custom `draw(_:)` often destroys VoiceOver navigation. Gemini treats this as a merge blocker.
32. **Memory / retain-cycle profile** — `weak var inputTextView: InputTextView?` from a SwiftUI `ObservableObject` to an AppKit view is a red flag; no profiling plan for toggle-100-times-under-splits.
33. **Split-pane thrashing** — `Cmd+Option+T` with `.all` scope in a 6-pane workspace = 6 simultaneous `NSTextView` instantiations + 6 layout animations. Performance unexamined.
34. **Layout overflow on small panes** — TextBox auto-grows 2→8 lines; what happens when the pane is only 10 lines tall? Push, overlap, or crash?
35. **Undo/redo stack bridging** — Custom `NSTextView` with intercepted events interacts with AppKit undo manager AND c11mux's own undo surfaces (tab-close, layout).
36. **Recursive `NSView` walker (`findTextBox(in:windowPoint:)`)** — Gemini specifically calls out the recursion on every drag event as both a correctness and performance hazard in deep Bonsplit trees.
37. **`@Published` churn triggers layout passes** — Adding properties to `TerminalPanel` may cause SwiftUI to invalidate broad view subtrees; unmeasured.

---

## 3. Assumption Audit (Merged & Deduplicated)

Consolidated from all three audits. Severity: **H** = plan collapses or changes significantly if wrong; **M** = significant rework; **L** = cosmetic.

| # | Assumption | Severity | Status | Evidence |
|---|------------|----------|--------|----------|
| A1 | `Cmd+Option+T` is unbound in c11mux | H | **FALSE** | Bound at `AppDelegate.swift:9498` / `cmuxApp.swift:627-631`; guarded by `AppDelegateShortcutRoutingTests.swift:1415`; fork's own source comment warns about it |
| A2 | `TextBoxInput.swift` can be copied verbatim | H | Partially false | Depends on `focusTerminalView`, `sendKey`, `sendSyntheticKey`, `forwardKeyEvent`, `scrollbarOffset`, `isScrolledUp`, `scrollToRow` — none exist in c11mux yet (§4.8 creates them) |
| A3 | `TerminalPanelView.swift` integration is +74/-19 from current c11mux | H | False | Current c11mux is 56 lines vs fork's 114; no `paneId` parameter; no `defaultForegroundColor` on `GhosttyApp` |
| A4 | `Workspace.toggleTextBoxMode` is self-contained | H | Unknown | `Workspace.swift` is ~9,919 lines with async focus restore, tmux snapshots, dismiss flashes; "self-contained" is hope, not verification |
| A5 | Drag routing needs only one entry-point change | H | False | Requires `updateDragTarget` + all three of `draggingEntered`/`draggingUpdated`/`performDragOperation`; fork also relies on `prepareForDragOperation`/`concludeDragOperation` hooks absent in c11mux |
| A6 | 200ms Return delay is reliable | H | Unverified | Probably OK for zsh + Claude CLI local; unverified for SSH, M-series, `codex`, `ipython`, `docker exec`, tmux-in-ghostty, slow machines, heavy CPU load |
| A7 | Feature is meaningful for "AI-agent workflows" | H | Undefended | `cmux send` already provides socket-based text injection; true target is humans typing to agents, not agents themselves. Hypothesis, not premise |
| A8 | "Default off" neutralizes scope/maintenance risk | M | False | 1,246 LOC + 18 xcstrings + 4 pbxproj edits + 7-file integration is not "free" when disabled |
| A9 | 8-phase / 8-commit structure is digestible for review | M | False | Plan's own fallback (split 3+5) is clearly the better choice; split should be default, not conditional |
| A10 | Bracket-paste + synthetic Return preserves input semantics | M | False (implicitly) | Fork trims leading/trailing newlines on send; this is a behavior choice, not transparent |
| A11 | Copied `TextBoxInputTests.swift` is ready to use | M | Inconsistent | Copied tests default to key `b`; plan chose `t`. Also unclear whether tests are unit (offline) or integration (need window) for CI policy |
| A12 | Title-regex AI-agent detection is durable | M | Brittle | Silently breaks on any upstream CLI prompt/bullet change |
| A13 | `firstResponder is InputTextView` is a reliable focus check | M | Weak | AppKit focus is async; workspace/tab transitions + SwiftUI teardown will produce false negatives |
| A14 | Adding `@Published` properties to `TerminalPanel` is risk-free | M | Suspect | Causes broad SwiftUI invalidation; no typing-latency evidence |
| A15 | English-only localization is acceptable | H | Policy violation | AGENTS.md:145 requires EN+JA for all user-facing strings |
| A16 | UserDefaults key namespace is conflict-free | L | Plausible | No evidence provided but no collisions surfaced |
| A17 | Xcode project-file edit is safe | L | True | §4.11 confirmed |
| A18 | Ghostty `scroll_to_row` support is verified | L | True | Confirmed in §4.8 |

**Invisible / unstated assumptions** (not in the plan at all):
- `InputTextView.draw(_:)` placeholder rendering does not regress typing latency.
- Weak-ref to `InputTextView` from `TerminalPanel` survives SwiftUI view teardown on tab-inactive.
- `TextBoxInputTests.swift` can run without an AppKit window (CI policy).
- VoiceOver / accessibility works after custom `keyDown` interception.
- Bracket-paste markers don't corrupt session-restore / scrollback snapshot replay.
- `Cmd+Z` in TextBox doesn't leak into c11mux's own undo surfaces through the responder chain.
- `cmux send` and TextBox-submit are intentionally different (or one should adopt the other's semantics).
- `.all` scope means "current workspace" and not "all windows" (or vice versa).
- Title-regex false-positive / false-negative behavior is defined.
- The feature has a removal/deprecation criterion.

---

## 4. The Uncomfortable Truths (Recurring Hard Messages)

The messages that appear across multiple reviews, deduplicated and numbered:

1. **"Verified" and "resolved" are used for facts that are not verified and not resolved.** The `Cmd+Option+T` claim is the canary; if this specific verification was this thin, other "low risk" and "additive" claims deserve the same skepticism. *(Claude, Codex, Gemini all flag this pattern.)*

2. **The plan is framed around fork deltas, not c11mux contracts.** Line-count claims, "verbatim" claims, and integration-point enumerations read correctly against the fork's internal baseline but not against current c11mux `main`. *(Claude, Codex.)*

3. **"Mostly additive" / "pure addition" is misleading for focus, drag, and responder code.** These systems in AppKit/SwiftUI are non-local; small hooks have large side effects, especially in a tree with Bonsplit, portal layers, and multi-window support. *(All three models.)*

4. **The core mechanism (bracket-paste + timed synthetic Return) is a brittle hack.** Nondeterministic by construction; will fail under load, over SSH, under busy agents. *(Claude, Gemini.)*

5. **The "cheap because we're just porting" argument is a vibe, not accounting.** 1,246 lines of unfamiliar monolithic Swift, eight integration points, and an undefined validation bar is not cheap. A minimal 200-line reimplementation could plausibly deliver 80% of the value with 10% of the maintenance. *(Claude, Gemini.)*

6. **The AI-agent-workflow justification is an undefended premise.** The plan treats it as a reason rather than a hypothesis; it does not show what agent flow this unblocks that `cmux send` cannot. *(Claude, Codex indirectly.)*

7. **Shipping English-only contradicts an explicit CLAUDE.md / AGENTS.md policy.** "Velocity" is not listed as an exception; either commit to the policy or relax it deliberately. *(Claude, Codex.)*

8. **Phase structure is optimized for bisect, not for review.** No mid-stream commit produces a working, reviewable end-to-end feature; reviewers cannot validate individual phases. *(Claude.)*

9. **"Default off" is a maintenance illusion.** Nobody will remove 1,246 lines because the feature is "free" when disabled. That is how codebases accumulate 15-20% dead weight. *(Claude.)*

10. **Manual validation optimism is unusually strong here.** 14 test categories handled as a manual matrix, no automated integration tests for drag/focus/shortcut-dispatch, no latency pass criterion. Manual QA cannot reliably reproduce race conditions under split-pane + CPU-load + SSH combinations. *(Codex, Gemini.)*

---

## 5. Consolidated Hard Questions for the Plan Author

Deduplicated and grouped. Numbered sequentially for easy reference in the response. "Unknown" annotation indicates questions where the current plan provides no answer.

### A. Shortcut Ownership & Collision
1. Why does the plan claim `Cmd+Option+T` is unused when both `cmuxApp.swift:627-631` and `AppDelegate.swift:9496-9511` bind it, and a test explicitly guards that behavior?
2. Do we keep `Cmd+Option+T` for "Close Other Tabs in Pane" or reassign it? If reassigning, what is the migration UX and rollout communication?
3. Should TextBox default to `Cmd+Option+B` (the upstream choice) to avoid conflict entirely? Or an unbound-by-default shortcut (`Cmd+Option+I`, `Cmd+Option+K`) to force explicit opt-in?
4. Did you grep for `StoredShortcut(key:` across all of `Sources/` (not just `KeyboardShortcutSettings`) to surface other hardcoded shortcuts the audit may have missed? *(No evidence of this in the plan.)*
5. Why does Phase 1 "copy tests" when the copied tests default to key `b` while the plan chooses `t`? Which wins at merge time?

### B. Integration Reality vs. Fork-Delta Framing
6. Did you diff `TerminalPanelView.swift`, `Workspace.swift`, `ContentView.swift`, and `GhosttyTerminalView.swift` against current c11mux `main`, or against the fork's internal delta? If the latter, the §4 line counts and "low risk" labels are unreliable.
7. How will you adapt the fork's `TerminalPanelView` integration given that current c11mux has no `paneId` parameter and `GhosttyApp` has no `defaultForegroundColor`?
8. What is the actual shape of the drag-routing change? The fork modifies `updateDragTarget` (to return `.copy` and show the `+` badge) in addition to `performDragOperation`; the plan mentions only the latter. Where is the full three-method change documented?
9. How does `Workspace.toggleTextBoxMode(.all)` interact with the workspace's async focus-restore, tmux snapshot machinery, and notification dismiss flashes at `Workspace.swift:7757-7857`? What evidence backs "self-contained"?
10. What is the semantics of `.all` scope — current workspace, current window, or all windows? Fork code iterates one workspace's `panels`; multi-window behavior is undefined.

### C. Core Mechanism Soundness
11. How does the system recover if the 200ms delayed `Return` fires before the shell/agent is ready? Is there any fallback (retry, detection of echo, user-visible indicator)?
12. Should the 200ms delay be configurable (per-pane / per-app / user-default), or replaced with a deterministic prompt-readiness check?
13. What happens when the user double-submits within 200ms, closes the pane, or switches workspaces while the delayed Return is pending? Is there cancellation / invalidation?
14. Does `Return = send` / `Shift+Return = newline` match user expectation in bash/zsh line-continuation (`\`) contexts, or will it cause systematic premature submits?
15. Should submission preserve exact input bytes (including leading/trailing newlines), or is the fork's trim behavior intentional product choice?

### D. Validation, Latency, Rollout
16. What is the pass criterion for "no typing-latency regression" — numeric threshold (p50/p95 keystroke-to-paint), measurement method, baseline, and comparison data?
17. What automated test guards the existing close-other-tabs shortcut behavior during this port?
18. What automated test guards drag-target precedence across web / TextBox / terminal in the current overlay architecture?
19. Are the copied 360 lines of `TextBoxInputTests.swift` unit (pure, offline) or integration (need AppKit window)? Will they run in c11mux CI per the no-local-tests policy?
20. What is the rollback plan if focus/latency/shortcut regressions appear post-merge, beyond "default off"? Kill switch? Safe-mode flag? Hidden pref?
21. What telemetry / event probe will detect first-user-impact issues (e.g., "Cmd+Opt+T no longer closes tabs")?

### E. Architecture & Integration Depth
22. What is the memory / retain-cycle profile of toggling TextBox on/off 100 times in a 6-pane split workspace? Has the `weak var inputTextView: InputTextView?` pattern been profiled for leaks during SwiftUI teardown?
23. How does the custom `InputTextView` behave with VoiceOver enabled? *(If "we don't know," is this a merge blocker?)*
24. Why is drag routing using a recursive `NSView` walker (`findTextBox(in:windowPoint:)`) on `ContentView` rather than localized drop targets on the `TextBoxInputContainer`? What is the performance cost on every drag event in deeply nested Bonsplit trees?
25. What happens to pane layout when TextBox auto-grows to 8 lines in a 10-line-tall pane? Push, overlap, or constraint failure?
26. How does `Cmd+Z` in `InputTextView` interact with c11mux's own undo surfaces (tab-close, layout) through the responder chain?
27. Are there other focus-stealing code paths in c11mux besides the two §4.8 identifies that need `if firstResponder is InputTextView { return }` guards?
28. Does the TextBox integrate with full-screen / stage-manager / hidden-dock modes? *(Unexamined.)*

### F. Scope, Strategy, Coordination
29. Why port 1,246 lines verbatim instead of reimplementing the 20% that matters (multi-line send with bracket-paste)? Show the hours comparison for port-vs.-rewrite.
30. Was this feature ever offered upstream to `manaflow-ai/cmux`? If rejected, why are we adopting it? If never offered, did the fork author say why? *(Unknown.)*
31. Who owns ongoing maintenance of `TextBoxInput.swift` when c11mux refactors `TerminalSurface`, `GhosttyNSView`, or Bonsplit? That person should sign off on the port.
32. Why 8 commits in one PR instead of the explicitly-acknowledged better split (Phases 1-3 scaffolding + Phases 4-8 integration)? Defend not splitting.
33. Is there a collision with c11mux's in-flight tier-1 persistence work (`docs/c11mux-tier1-persistence-plan.md`)? Both plans touch per-panel state — coordinate now or fight later.
34. Are you willing to ship a plan that violates `AGENTS.md:145` localization policy, or will the plan update now to include Japanese translations for all ~18 new keys?

### G. Product, Hypothesis, Lifecycle
35. Is the feature actually "for AI-agent workflows," or for humans typing to agents in the terminal? They are different targets with different designs — pick one and defend it.
36. What specific agent flow does this unblock that `cmux send` (socket / AppleScript / CLI) does not already handle? Show the gap.
37. How is the feature discovered? A settings checkbox + undocumented hotkey is weak; is there a command-palette entry, first-run tip, or Help-menu link?
38. What happens on session restore when a user had unsubmitted TextBox content? Lost, preserved, or deferred? Make the call; do not silently defer.
39. What is the owner-approved fallback when `Claude Code|^[✱✳⠂] |Codex` title regex fails (false positive or false negative)?
40. If opt-in is <5% after 3 months, what is the deprecation plan? Or do we keep 1,246 lines indefinitely?
41. What is the budget for this port in person-days? Plan reads as ~2 days; adversarial estimate is 4-6 days plus post-ship fixes. Align expectations before starting.

---

## 6. Recommended Pre-Start Actions (Cross-Model Consensus)

Drawn from the intersection of all three reviews. Things to fix **before** the worktree is spun up:

1. **Fix the `Cmd+Option+T` collision.** Decide between reassigning TextBox (to `Cmd+Option+B` or unbound) or migrating "Close Other Tabs." Update plan text and copied tests consistently.
2. **Add a Phase 0 re-diff pass.** Diff all 7 integration files (`TerminalPanelView`, `Workspace`, `ContentView`, `GhosttyTerminalView`, `TerminalPanel`, `KeyboardShortcutSettings`, `CmuxSettingsView`) against current c11mux `main` and rewrite §4 line counts and risk labels.
3. **Rewrite §4.9 (drag routing)** to include the `updateDragTarget` / `draggingEntered` / `draggingUpdated` changes, not just `performDragOperation`.
4. **Split the PR up-front** into scaffolding (Phases 1-3) + integration (Phases 4-8). Do not leave it as a conditional fallback.
5. **Commit to localization** (EN + JA) at ship time, or explicitly document the `AGENTS.md:145` exception in the PR description.
6. **Define a typing-latency pass criterion** (specific numbers, measurement method, baseline) and bake it into Phase 8.
7. **Coordinate with tier-1 persistence work** on per-panel state (`isTextBoxActive`, `textBoxContent`) before either plan is committed.
8. **Reframe the 200ms delay** — either make it configurable OR replace with a deterministic readiness signal. Document the double-submit / pane-close / workspace-switch behavior.
9. **Decide port-as-is vs. refactor-on-port.** 1,246 lines in one file is a deliberate choice; splitting now is cheap, splitting in 2027 is expensive.
10. **State the validation hypothesis explicitly.** Who is this for, what does success look like, what would trigger removal?

---

## 7. Final Word

The three models independently converge on the same verdict: **the plan is structured but not execution-safe as written.** The Cmd+Option+T collision is the canary — if that specific "verified" claim is wrong (and the fork's own source tried to warn us), then every other "verified" / "low risk" / "pure addition" claim deserves the same re-examination. The plan's confidence outpaces its verification.

Fixed properly — Phase 0 re-diff, split PR, correct drag-routing scope, shortcut collision resolved, latency criterion defined, localization decided, persistence coordinated — this becomes a reasonable 3-4 day effort with a known scope. Shipped as written, it is a 2-day plan that becomes a 6-day slog with post-ship fixes and a trust hit when first-user muscle memory breaks on Cmd+Option+T.

The uncomfortable message all three reviewers deliver, in different words: **the cost of doing this port correctly is higher than the plan says, and the benefit (especially for the claimed AI-agent-workflow audience, against an already-capable `cmux send` primitive) has not been defended.**
