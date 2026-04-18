# TP-c11mux-textbox-port-plan-Synthesis-Evolutionary-20260418-1255

**Synthesis of:** Claude (Opus 4.7), Codex, Gemini evolutionary reviews
**Plan:** `docs/c11mux-textbox-port-plan.md`
**Mode:** Evolutionary — what this *becomes*, not whether it ships.

---

## Executive Summary

All three reviewers converge on one core insight: **the plan undersells what is actually being built.** Framed as a utility port of a sibling fork's TextBox feature, the work is in reality the introduction of c11mux's first **input intercept layer** — a native, observable, policy-aware composition surface that sits between user intent and the PTY byte stream. Every reviewer independently named this seam ("Input Intercept Layer", "Composition Surface", "native input abstraction layer") and every reviewer concluded the same strategic consequence: the name, scope, and architecture decisions locked in during this port shape a 12-month roadmap of agent-aware features (attachments, templates, broadcast, pre-flight inspection, multimodal, cross-pane context).

Three shared, concrete course-corrections recur across all reviewers and should be treated as preflight blockers:

1. **Replace title-regex agent detection with c11mux's native `AgentDetector` / `SurfaceMetadataStore`** (unanimous across Claude, Codex, Gemini). The fork's regex on `panel.title` is the single most fragile piece in the design and is exactly what c11mux can beat natively at near-zero cost.
2. **Re-evaluate the hardcoded 200ms paste/Return delay** (unanimous). It is a latency-dependent heuristic that will silently truncate submissions on SSH, slow PTYs, and battery-saver modes. Make it configurable; ideally handshake with agents via socket.
3. **Fix the localization strategy before merge** (Claude + Codex). "English-only" contradicts c11mux's 18-locale policy; Codex calls this a hard gate, Claude offers three concrete options (translate now, block non-English, feature-flag).

A fourth shared thread runs through the wild ideas: every reviewer independently identified **attachments / multimodal composition** (images, file contents, `NSTextAttachment`s) as the highest-ceiling mutation — and all three noted that designing the `InputTextView` to accept attachments *now*, even if unused, is the difference between a 30-line follow-up and a 6-month rearchitecture.

The single largest irreversible decision is **naming**. Claude is most emphatic (`TextBoxInput` → `ComposeSurface`), Codex frames it as "first module of a reusable input-composer subsystem," Gemini calls it a "Command Palette / Prompt Bar." Once `UserDefaults` keys ship, renaming costs user state migrations forever.

---

## 1. Consensus Direction — Evolution Paths All Three Models Identified

1. **This is an Input Intercept Layer, not a text box.** Claude's "Layer 2: input intercept seam," Codex's "native input abstraction layer above PTY key/text transport," and Gemini's "Input Intercept Layer" are the same claim in three voices. c11mux transitions from dumb PTY pipe to smart proxy with composition semantics.

2. **Agent detection must be metadata-first, not regex-first.** All three reviewers reject title-regex (`Claude Code|^[✱✳⠂]`) as the primary signal. All three point to c11mux's existing socket telemetry / `AgentDetector` / `terminal_type` metadata as the correct source. Claude calls it "the single highest-leverage evolutionary improvement available in the port."

3. **The 200ms paste delay is a fragility, not a solution.** All three flag it. All three propose the same escalation ladder: (a) make it configurable, (b) add diagnostics/telemetry, (c) replace with a structured agent socket handshake for opt-in agents, with bracket-paste as legacy fallback.

4. **Design for attachments / multimodal from day one.** Claude's M4/M7, Codex's "composable input accessories / structured send blocks," and Gemini's "Multimodal Preparation / Context-Aware Drop Zone" all land on the same point: the `NSTextView` subclass should not foreclose `NSTextAttachment` support. This is the cheapest way to preserve a high-ceiling mutation path.

5. **Frame this as the first module of a subsystem, not a one-off feature.** Claude wants explicit namespacing (`CS1`, `M9: Compose`), Codex wants "a reusable input-composer subsystem," Gemini wants a "unified floating Command Palette." The architectural shift is identical: treat this as infrastructure, name it as infrastructure, sequence follow-ups against it.

6. **Phase the work behind a preflight gate.** Claude proposes a "Phase 0: Rename decision." Codex proposes a "Phase 0: Integration Preflight." Gemini implicitly does the same by reordering into "Abstract → Harden → Rich Context." Consensus: do not start copying code until naming, shortcut conflicts, drag lifecycle diffs, and localization policy are resolved.

7. **Split the monolith early.** Claude (rules-as-data struct), Codex (`TextBoxRouting` / `TextBoxViewBridge` / `TextBoxSettings` separation), and Gemini (decouple per-pane coupling) all want the one-file fork structure broken apart before it ossifies.

8. **Ship with fewer settings, not more.** Claude explicitly argues for 2 settings instead of 4; Codex's "narrower scope first" and Gemini's silence on the settings sprawl align. Consensus lean: trim surface area, add back only on user request.

---

## 2. Best Concrete Suggestions — Most Actionable Ideas Across All Three

Ranked by leverage × reversibility × consensus.

1. **Replace `TextBoxAppDetection` (title regex) with `AgentDetector` / `SurfaceMetadataStore` during the port.** All three reviewers. ~50 LOC delete, net-negative line count, unambiguous upgrade, unlocks every future agent-aware feature cleanly. (Claude §1 / Codex §6 / Gemini §2)

2. **Rename before first commit.** `TextBoxInput` → `ComposeSurface` (Claude's recommendation, echoed structurally by Codex and Gemini). File, class prefixes, `UserDefaults` keys (`textbox.*` → `compose.*`), settings section, shortcut action, `[TextBox]` tags. ~30 minutes now; requires user-state migration forever after ship. (Claude §4)

3. **Add an explicit Phase 0 preflight gate** covering: rename decision, shortcut collision audit (`Cmd+Option+T` already used by `AppDelegate` for close-other-tabs per Codex), drag lifecycle diff, localization strategy, focus ownership audit. Hard gate before code copy. (Codex §1, Claude's "Phase 0")

4. **Fix missing `GhosttyApp.defaultForegroundColor`.** The fork reads this property; c11mux's `GhosttyApp` does not have it. Missing from the plan's §4.3 and §4.8. Without this the integration does not compile. Add it in Phase 3 alongside the existing `defaultBackgroundColor` path. (Claude §1 — unique catch but mechanically load-bearing)

5. **Fix the fork's broken test before porting.** `TextBoxInputTests.swift:54` asserts `shortcut.key == "b"` but the actual binding returns `"t"`. Decide and fix before copying; do not inherit a failing test into Phase 8 under time pressure. (Claude §2)

6. **Make the 200ms delay configurable as `returnDelayMs` / `pasteDelay`** with a recommended default. Emit a `dlog` on every submission with timing metadata for post-ship diagnosis. (All three reviewers; Gemini §1, Claude §2)

7. **Design `InputTextView` to accept `NSTextAttachment` from day one**, even if current behavior only extracts paths. Prevents a future rewrite when multimodal lands. (Gemini §2, Claude M4/M7)

8. **Add structured submission telemetry** via `dlog("compose.submit length=… lines=… surface=… agent=…")`. ~20 LOC. Unlocks cost estimation, session replay, usage analytics, and 200ms-delay fragility diagnosis. (Claude §7, Codex §8 debug counters)

9. **Localize at port time, not after.** EN + JA required by c11mux policy; other 16 locales can be batch-drafted by LLM. Feature-flag off in non-English locales if translation lags. Do not ship 17 stubs. (Claude §6, Codex §2)

10. **Ship with 2 settings, not 4.** `enabled` + `sendOnReturn`. Make `escapeBehavior` a function of agent detection; ship `shortcutBehavior` as `.toggleFocus` only. Add back on user request. (Claude §5)

11. **Split into two PRs.** PR1: scaffolding (phases 1–3, low-risk, reviewable in isolation). PR2: integration (ContentView, drag routing, focus guards, concentrated risk). The plan's §7 already suggests this; reviewers endorse strongly. (Claude §12, Codex §10)

12. **Add a runtime rollback switch** that disables TextBox key routing while keeping the UI mounted. Fast mitigation path during rollout. (Codex §8)

13. **Add behavioral acceptance criteria** beyond unit tests: "TextBox toggle targets the correct workspace/window under multi-window focus" and "No regressions in existing browser drag/drop lifecycle callbacks." (Codex §4, §5)

14. **Add a transport-correctness test** around bracket-paste + delayed-Return decision logic. (Codex §9)

15. **Declare the architectural intent in a doc comment** at the top of the renamed file: "This file hosts c11mux's composition surface — the seam between user intent and the PTY byte stream." Future readers understand what the file is *for*, not just what it does. (Claude §8, Codex §10)

---

## 3. Wildest Mutations — Most Creative / Ambitious Ideas

Roughly ordered from cheapest working version to most ambitious. All three reviewers independently generated variations on several of these.

1. **Cross-pane broadcast submission.** Submit from one composition surface, route the same text to every terminal in the workspace (or a marked subset). ~40 LOC on top of the plan. Obvious follow-up to the fork's `.all` toggle scope. Enormous leverage for agent fleet operation. (Claude M1, Codex "Shared Draft Bus")

2. **"Undo send" cooling window.** Extend the 200ms delay to a configurable 500–1000ms window where Escape aborts submission. Makes the surface safer than in-terminal editing for destructive commands. One check before `asyncAfter` fires. (Claude M2)

3. **Context pins.** Persistent block of context pinned at the top of the composition surface, invisible to the shell between submits but prepended on send. Solves context-forgetting in agent workflows. (Claude M3)

4. **Context-aware drop zone / image + attachment support.** Drag-drop a PNG → c11mux writes to `/tmp`, associates the attachment with the next submission. For vision-capable agents, forward image content via socket. Dropping a file while an agent is active wraps content in `<file>` tags or parses via local agent. (Claude M4, Gemini "Context-Aware Drop Zone")

5. **Structured prompt templates / snippets / recents.** Named, parameterized templates stored per-surface: `/template reviewer` expands to a full prompt. Lives in `SurfaceMetadataStore`. Workspace-scoped history. (Claude M5, Codex "Prompt snippets/recents")

6. **Pre-flight command inspection / "Are you sure?" intercepts.** Scan text for destructive patterns (`rm -rf /`, `curl | sudo bash`) and require confirmation before the PTY ever sees them. Only possible because we now own the intercept seam. (Claude M6, Gemini "Pre-Flight Inspection")

7. **Agent socket handshake (`agent.submit_prompt` / `agent.accept_prompt`).** Structured JSON payload bypasses bracket-paste entirely for opt-in agents. Eliminates the 200ms fragility, unlocks multimodal and cost preview. (All three reviewers converge on this; Gemini §4 drafts the command name)

8. **Composition-surface-as-canvas.** `NSTextView` holds `NSTextAttachment`s → inline widgets: collapsed diffs, image thumbnails, model selectors, cost previews, visual token counters. Terminal stays a character grid; composition surface becomes a rich canvas. The "multimodal chat client that happens to have a shell" endgame. (Claude M7, Gemini "Multimodal Preparation" / "Rich CLI UI Controls")

9. **Reverse channel: terminal output → composition surface.** Command fails → c11mux recognizes the failure (already scans output) → populates the surface with a fix suggestion. Goes from "you type and we send" to "we converse." (Claude M8, Gemini "Reverse Routing")

10. **Composition surface for the browser pane.** Same surface reused for URL bar, form fill, search. Turns the feature from terminal-only into c11mux's generalized input substrate. Highest leverage per incremental effort. (Claude M9 — unique to Claude)

11. **Local-first interceptor.** On-device LLM or grammar engine inside the composition surface for autocompletion, syntax correction, natural-language-to-shell expansion *before* bytes hit the PTY. (Gemini "Local-First Interceptor" — unique to Gemini)

12. **Agent-aware composer modes.** Shell mode vs agent mode with different submit and routing defaults, switched by detected context. (Codex — unique framing)

13. **Shared draft bus.** Move or copy draft text between panes and workspaces during agent handoffs. (Codex — unique)

14. **Feature-flag tied to welcome experience.** Make "Enable Composition Surface" an explicit opt-in checkbox in c11mux's onboarding flow (the 2x2 quad welcome sequence from recent commit `3ee342e0`), rather than a buried settings toggle. Free marketing of a differentiating feature. (Claude §9 — unique concrete surface)

---

## 4. Flywheel Opportunities — Self-Reinforcing Loops

Claude identifies two flywheels and argues only one is truly defensible. Codex and Gemini each describe one. The synthesis:

1. **Flywheel A: UX-driven agent adoption (Gemini, Codex, Claude-identified-but-deprioritized).** Better multiline composition → c11mux becomes de facto environment for CLI agents (Claude Code, Aider, Codex) → agent tool authors integrate more deeply → structured interactions unlock further features → more users. Real, but **not unique to c11mux** — Warp has executed on this loop for years. A "me too" flywheel.

2. **Flywheel B: Composition surface → proprietary data → differentiation (Claude, emphasized as the larger prize).** Owning the composition surface means c11mux sees data the PTY cannot: (a) what was about to be sent, (b) what the user edited away before sending, (c) which agent context the submission targeted, (d) how long composition took. Nobody else has this data. Compounding features — session replay, prompt libraries, cost estimation, cross-agent context migration — require the surface and are therefore defensible. **Unique to c11mux.**

3. **Flywheel C: Reliability → adoption → edge cases → tuned defaults (Codex's operational flywheel).** Better routing and detection → fewer failed sends and focus surprises → higher adoption by agent-heavy users → more observable edge cases (timing, apps, layouts) → better insights → tuned defaults and stronger routing rules. Accelerated by adding lightweight debug counters around submit path, focus transitions, and routing branches during rollout.

**Synthesis recommendation:** The plan as written spins Flywheel A by default. Two small moves flip it toward the more defensible Flywheel B: (i) log structured submission events from day one (Claude §7), (ii) name and surface the abstraction as "Composition" in code, settings, and changelog (Claude §4, §8). Codex's debug-counter instrumentation (§8) simultaneously spins Flywheel C and primes the data lake that feeds Flywheel B.

---

## 5. Strategic Questions for the Plan Author (Deduplicated, Numbered)

Merged from Claude's 13 questions, Codex's 10 questions, and Gemini's 5 questions. Ordered by reversibility cost (most irreversible first).

1. **Naming — rename to `ComposeSurface` (or similar) before first commit, or ship as `TextBoxInput`?** This is the most irreversible decision in the port because `UserDefaults` keys persist across upgrades. Does the plan commit to the rename, or to a later migration strategy? (Claude Q1, Q6; Codex Q6)

2. **Agent detection strategy — metadata-first (`terminal_type` / `AgentDetector`) with title-regex fallback, or title-regex primary?** Unanimous reviewer recommendation: metadata-first. Does the plan adopt this from day one? (Claude Q2, Codex Q2, Gemini Q3)

3. **Missing `GhosttyApp.defaultForegroundColor` — add during port (Phase 3) or defer?** The fork assumes it; c11mux does not have it. Without this, integration does not compile. What is the resolution path? (Claude Q3)

4. **Localization — EN-only now, EN+JA at port time, or feature-flagged off for non-English locales until translated?** c11mux policy requires localized user-facing strings. Which option ships? (Claude Q5, Codex Q3)

5. **Shortcut ownership — `Cmd+Option+T` conflicts with existing `AppDelegate` close-other-tabs behavior.** Preserve existing and choose another default, or reassign and migrate close-other-tabs? (Codex Q1; Claude notes fork's own test/binding mismatch on `t` vs `b`)

6. **Settings count — ship all four fork settings, or start with `enabled` + `sendOnReturn` only?** The smaller surface is cheaper now and extensible later; the wider surface locks in decisions and 18-locale translations. (Claude Q4)

7. **Architectural coupling — per-pane `TextBoxInputContainer` vs. a single workspace-level floating composition palette that targets the active surface?** Gemini argues strongly for the global overlay (memory, hierarchy depth, drag-routing simplification). What are the tradeoffs in the per-pane approach? (Gemini Q5, Claude §M9 adjacent)

8. **Module framing — one-off feature, or first module of a reusable composer subsystem with its own namespace (CS1, CS2, … or M9: Compose, M9.1: Broadcast, M9.2: Attachments)?** (Claude Q9, Codex Q6)

9. **PR split — single PR with internal phases, or two PRs (scaffolding + integration)?** Reviewers strongly recommend two. What is the plan's position? (Claude Q12, Codex Q10)

10. **Rollout scope — active-pane-only toggle first, then widen to `.all`, or full scope from day one?** Narrower validates focus/latency correctness before expanding. (Codex Q4)

11. **Rollback switch — include a runtime flag to disable key routing while keeping UI mounted, for fast mitigation?** (Codex Q8)

12. **Multi-window shortcut target rule — event window first, key window fallback, selected workspace fallback? Explicit acceptance criterion required.** (Codex Q7)

13. **Submission robustness — is the 200ms delayed `Return` resilient enough for SSH / high-latency contexts? Configurable, or replaced with dynamic check / agent socket handshake?** (All three reviewers; Gemini Q1)

14. **Multimodal future-proofing — does the copied `InputTextView` foreclose later `NSTextAttachment` support, or is the subclass designed to accept attachments from day one?** (Gemini Q2, Claude M4/M7)

15. **Drag & drop — is file-path drag-drop essential for the initial port, or deferred to a follow-up PR to reduce `ContentView.swift` collision risk?** Gemini argues for deferral; Codex demands an explicit drag-lifecycle diff audit. (Gemini Q4, Codex §5)

16. **Cross-pane broadcast — is `.all` scope the follow-up PR after port lands (M9.1: Broadcast), or deferred indefinitely?** If indefinite, consider collapsing `.all` into `.active` for v1 to reduce surface area. (Claude Q7)

17. **Structured submission socket API — should c11mux define `agent.submit_prompt` / `agent.accept_prompt` to bypass bracket-paste for opt-in agents?** Worth a plan note even if deferred. Prerequisite for multimodal and cost preview. (Claude Q8, Gemini §4)

18. **Draft persistence — is TextBox content strictly ephemeral, or is there a follow-up for draft persistence per surface/workspace?** (Codex Q5)

19. **Telemetry baseline — will Phase 1 include submission event logging (`dlog` or equivalent)?** If not, when? Every day without this log is a day of missing diagnostic data and usage analytics. (Claude Q10, Codex Q8)

20. **Browser pane reuse — has anyone evaluated whether c11mux's browser pane would benefit from the same composition surface (URL bar, form fill, search)?** If yes, abstraction should accommodate non-terminal targets from day one. (Claude Q11)

21. **"Copy verbatim" hard requirement — if adapting to c11mux architecture requires selective refactor (splitting the monolith, changing detection source, renaming) while preserving behavior, is that acceptable, or is verbatim copy a non-negotiable constraint?** (Codex Q9)

22. **"Off by default" duration — what is the criterion for flipping the default to on? Usage-based, time-based, or user-requested?** Without a criterion, opt-in features stay opt-in forever, which kills Flywheel B. (Claude Q13)
