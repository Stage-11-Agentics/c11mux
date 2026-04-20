# Synthesis — Standard/Analytical Reviews of CMUX-25 Plan

**Plan under review:** `/Users/atin/Projects/Stage11/code/cmux/.lattice/plans/task_01KPHHQZA4XZTQD4BQCGQYC7FR.md`
**Reviewers synthesized:** Claude Opus 4.7 · Codex · Gemini
**Date:** 2026-04-19
**Note on Gemini:** The Gemini review is shorter because the model hit an API quota mid-review. Treat it as a complete-but-brief third opinion — its signal is still load-bearing in the aggregation.

---

## Executive Summary

All three reviewers agree on the architecture: Hybrid C (process-scoped pane/workspace registries, per-window `WorkspaceFrame`) is the correct north star. None proposes rethinking. The locked primitive hierarchy (`Window → Sidebar → Workspace → WorkspaceFrame → Pane → Surface → Tab`), the rejection of a bonsplit-spanning-windows model, the rejection of super-workspace-as-label, the deferral of hotplug and hibernation to CMUX-26, and the decision to keep bonsplit's single-tree-per-frame contract unchanged — all three models endorse these calls unambiguously.

They diverge on **readiness**, and the disagreement maps cleanly to how aggressively each reviewer probed Phase 2:

1. **Gemini:** "Ready to execute." (Minor schema gaps can be resolved mid-Phase-2.)
2. **Claude Opus:** "Ready to execute, with three sharpening asks." (Phase 2 sub-ordering, feature-flag semantics, session-schema field enumeration — all as Phase 2 kickoff prerequisites, not blockers to the plan itself.)
3. **Codex:** "Needs revision before execution." (Phase 2 is under-scaffolded; the old-to-new object mapping is imprecise; pane single-home vs multi-home is unresolved; window-close orphan rule is missing; socket focus defaults need explicit policy.)

The disagreement is itself the signal: **Phase 2 is the load-bearing wall of this plan, and the plan's current description of Phase 2 is under-specified relative to the work it encodes.** Two of three reviewers (Claude and Codex) independently arrive at the same concerns — estimate too tight, sub-ordering absent, rollback story missing, session-schema spec vague. Codex pushes these into "blocker to start," Claude into "sharpen before Phase 2 kickoff," Gemini into "resolve mid-phase." The substantive finding is identical; only the severity threshold differs.

The consolidated recommendation: **the architecture is locked; Phase 2 needs a pre-kickoff revision pass** covering (a) sub-ordering into revertible sub-PRs, (b) an explicit old-to-new object mapping, (c) pane-home decisions with implications for `workspace.spread all_on_each`, (d) session schema v2 with migration and rollback, (e) feature-flag semantics disambiguated, (f) socket focus policy, (g) realistic estimates. Phase 1 can ship as-is (modulo a small acceptance-criteria tightening). Phases 3–6 inherit from Phase 2's quality.

---

## 1. Where the Models Agree (Highest-Confidence Findings)

### 1.1 Architecture is correct — do not reopen it

All three reviewers endorse Hybrid C (process-scoped pane registry + per-window `WorkspaceFrame`) as the right decomposition.

- **Claude:** "This is the right decomposition. Three reasons: respects bonsplit's contract; matches the existing code gradient; makes pane migration a pointer operation, not a lifecycle event."
- **Codex:** "The central decomposition is right: keep Bonsplit as one tree per rendered frame, and move shared state out from under window-local managers."
- **Gemini:** "Option C (Hybrid) is the only architecture that genuinely models the problem domain."

Unanimous rejection of Option A (one bonsplit tree spanning windows — would break bonsplit's encapsulation) and Option B (super-workspace label — doesn't deliver the Emacs-frames property).

### 1.2 The v1/v2 split is correct — defer hotplug and hibernation to CMUX-26

All three endorse deferring runtime display hotplug, affinity memory, and hibernation to v2.

- **Claude:** "Runtime hotplug is genuinely hard... Deferring it to CMUX-26 with a depends-on link, and telling v2 to 're-survey operator behavior before starting,' is mature planning."
- **Codex:** "Runtime display changes, reconnect affinity, and optional hibernation are system-integration work with unpleasant testability. Keeping v1 manual lets the team validate the core model first."
- **Gemini:** "Pushing hotplug/hibernation to CMUX-26 is the strongest decision in the plan."

### 1.3 Bonsplit contract preservation is correct

All three models call out that keeping bonsplit as "one tree per `WorkspaceFrame`" is the right boundary.

### 1.4 Per-window (not global) focused pane is correct

Claude and Codex both explicitly endorse per-window focus. Claude: "matches platform convention." Codex: "a global focused pane would make multi-window c11mux feel remote-controlled rather than native." (Gemini implicitly endorses; does not challenge.)

### 1.5 Cross-window drag-drop at v1 is correctly scoped

All three endorse shipping cross-window drag-drop at v1, riding on `.ownProcess` pasteboard visibility, with a CLI-only fallback if AppKit misbehaves.

### 1.6 Socket API rename (`workspace.move_to_window` → `workspace.move_frame_to_window`) is correct

All three endorse renaming now with a deprecation shim, not deferring. Claude: "ships a correctness-fiction in the public API, which agents will write automation against and then have to migrate." Codex: "windows do not own workspaces. Keeping the old name as the canonical API would encode the old architecture in the public surface." Gemini: "the 1-release shim is mature and respects existing automation scripts."

### 1.7 Phase 2 estimate (2 weeks) is optimistic — all three reviewers flag this

This is the strongest multi-reviewer signal in the pack.

- **Claude:** "For a team of 1 engineer, this is a 3–4 week job with standard care; 2 weeks only works if (a) the engineer is already deeply familiar with `TabManager`, `Workspace`, and `SessionPersistence`, and (b) nothing unexpected surfaces."
- **Codex:** "Two weeks is not credible for one owner given the current coupling. Three to four weeks is more realistic, possibly more if schema rollback and CI fixtures are built properly."
- **Gemini:** "A 2-week estimate for Phase 2... is highly optimistic. This is the 'draw the rest of the owl' phase."

Both Claude and Codex independently propose splitting Phase 2 into 4–6 revertible sub-PRs. Overlap in the proposed ordering is substantial:
- First: mechanical rename and registry shells (no ownership moves).
- Next: extract `WorkspaceRegistry`, then `PaneRegistry` (or equivalent), then `WorkspaceFrame`.
- Finally: session schema migration and socket rename.

### 1.8 Session-persistence schema needs more concrete specification at Phase 2

All three reviewers flag that the schema spec is too abstract.

- **Claude:** "Enumerate every field added to `SessionWindowSnapshot` and `AppSessionSnapshot` at Phase 2, including any CMUX-26 forward-compat seams."
- **Codex:** "The plan says 'schema version bump; add migration', but it does not define the v2 shape with enough precision." (Includes a concrete four-level split: workspace / surface / frame / window.)
- **Gemini:** "The exact serialization structure isn't fully defined. The schema will likely need an intermediate mapping structure to reliably deserialize."

### 1.9 CMUX-26 forward-compat seams must be explicit at Phase 2

Both Claude and Codex flag a tension: CMUX-26 says its schema is "already set up in CMUX-25 Phase 2," but CMUX-25 Phase 2 only explicitly commits to `sidebarMode`. The display-affinity (`lastKnownDisplayID`) field is not called out by name. Either commit to the field now or state that CMUX-26 owns its own schema bump.

### 1.10 `hibernatedFrames` leftover in Phase 2 schema is a bug in the plan text

Codex catches this directly (citing `task_01KPHHQZA4XZTQD4BQCGQYC7FR.md:153`): hibernation was explicitly removed from v1, yet `hibernatedFrames` still appears in the Phase 2 schema sketch. Either fix the text or restore hibernation scope.

---

## 2. Where the Models Diverge (The Disagreement Is Signal)

### 2.1 Readiness verdict

The single biggest divergence.

| Reviewer | Verdict |
|---|---|
| Gemini | Ready to execute. Minor schema gaps can be resolved in Phase 2. |
| Claude Opus | Ready to execute, with three sharpening asks as Phase 2 kickoff prerequisites. |
| Codex | Needs revision before execution. Plan should not start Phase 2 as written. |

**Interpretation:** The substantive concerns are nearly identical across Claude and Codex. Gemini's "ready" verdict is likely shaped by the quota-truncated review — it flags the 2-week Phase 2 estimate as a risk but doesn't deep-dive into sub-ordering, rollback, pane-home decisions, or window-close rules. If Gemini had more output tokens, it would probably converge closer to Claude's position.

**Synthesized reading:** Treat this as "architecture locked; Phase 2 description needs sharpening before the first sub-PR opens." Codex's "revise" and Claude's "sharpen" are operationally the same bar; they differ only in label.

### 2.2 `workspace.spread all_on_each` (clone/mirror mode)

- **Codex:** Explicitly questions whether `all_on_each` even makes sense under single-homed panes. "If panes own AppKit views, MTL layers, or Ghostty views, multi-homing is not a small extension; AppKit views/layers are normally single-parent objects. If v1 is single-homed, remove or defer `all_on_each`. If multi-homed is a required future seam, Phase 2 needs a representation for frame references, view attachment, and focus semantics across multiple renderings of the same surface."
- **Claude:** Doesn't flag `all_on_each` directly, but asks Question 14 about multi-viewport semantics ("Can two `WorkspaceFrame`s of the same workspace in different windows render *different* bonsplit layouts?").
- **Gemini:** Doesn't address.

**Codex's point is substantively stronger and should carry the day.** The pane-home question is binary and blocks clean registry design. Either drop/defer `all_on_each`, or design multi-homing explicitly at Phase 2.

### 2.3 What happens when a window closes and its frame contains panes hosted nowhere else?

- **Codex:** Raises this as a required-before-start invariant. "The plan says closing a window destroys its frames, never its panes, and that remaining-only-on-that-window panes either migrate to another frame or hibernate. But v1 explicitly has no hibernation." Proposes: choose a destination window, create a frame in another window, prompt user, or block close.
- **Claude:** Touches it obliquely via Question 16 (the empty-window "choose a workspace" state) but doesn't flag the orphan-pane scenario as an invariant.
- **Gemini:** Doesn't address.

**Codex's finding is uniquely valuable and underspecified in the plan.** Without a defined behavior, registry invariants and persistence shape are both underdetermined.

### 2.4 Socket focus policy for new commands

- **Codex:** Raises this explicitly as a Phase 2/3 design input, citing `Sources/TerminalController.swift:3784` and `Sources/AppDelegate.swift:4085–4092`. Argues for a single internal move/spread service that takes a focus policy object.
- **Claude and Gemini:** Don't address.

**Unique Codex insight; high-signal.** The repo's existing socket focus policy (documented in cmux's `CLAUDE.md`) mandates that non-focus-intent commands preserve user focus — any new command (`pane.move`, `workspace.spread`, `window.create --display`, split-to-new-window) must specify its focus default before it ships.

### 2.5 Phase 2 as a smoke test for multi-frame machinery

- **Claude:** Argues Phase 2 should land with *one* developer-accessible path to spawn a second `WorkspaceFrame` on an existing workspace (even behind a debug flag), to prove the pointer-swap actually works before Phase 3 starts relying on it.
- **Codex and Gemini:** Don't propose this.

**Unique Claude insight; worth adopting.** Otherwise Phase 3 may become "Phase 2.5 (fix latent registry bugs) + Phase 3 (actually add UX)," blowing the 1-week Phase 3 estimate.

### 2.6 Feature-flag retirement criteria

- **Claude:** The flag has "two different meanings in different phases" — an internal refactor-soak flag (Phase 2) and a user-visible-behavior flag (Phase 3+). Proposes either one UX-gated flag or splitting into two named flags (`CMUX_MULTI_FRAME_REGISTRY` / `CMUX_MULTI_FRAME_UX`).
- **Codex:** Independently catches the same contradiction: "The ticket says all six phases land behind `CMUX_MULTI_FRAME_V1=1`, and also says the flag retires after Phase 3 soaks on main for a release cycle. That is ambiguous. If Phase 4–6 are still in flight, retiring the flag after Phase 3 either exposes later work unguarded or means 'flag' refers only to the Phase 2/3 internal model."
- **Gemini:** Doesn't address.

**High-confidence multi-reviewer finding.** Fix the flag semantics before kickoff.

### 2.7 Parallelism claim for Phases 3–6

- **Claude:** Sharpens the dependency graph: `1 → 2 → {3, 4} → 5`, plus `{3, 6}`. Phase 5 depends on Phase 3's `pane.move` primitive; Phase 6 depends on Phase 3's display resolver path and Phase 1. "Phases 3 and 4 are truly parallel post-Phase-2. Phase 5 depends on both. Phase 6 depends on Phase 3 but not Phase 4."
- **Codex:** Same concern, framed as a shared-primitive issue: "Phase 5 and Phase 6 should either depend on Phase 3's internal pane placement/move service or explicitly share a lower-level `PanePlacementService` created in Phase 2. `workspace.spread`, `pane.move`, and split-to-new-window are three entry points into the same operation... If these are implemented independently in parallel, they will drift."
- **Gemini:** Doesn't address.

**Both reviewers arrive at the same solution in different terms:** either tighten the dependency graph, or elevate a shared placement primitive into Phase 2 so 5/6 can actually parallelize with 3.

---

## 3. Unique Insights per Reviewer

### 3.1 Claude Opus — unique findings

- **Phase 2 needs a smoke test for the multi-frame machinery before main.** (See 2.5.)
- **`WorkspaceFrame`'s multi-viewport identity should be documented explicitly.** The primitive's novel property is "viewport identity" (window 3's view of workspace `agents`), not just "container for bonsplit tree."
- **Rollback story is absent.** `TabManager` → `WindowScope` rename can't be flag-gated (types can't be renamed behind a flag), and session-schema bump isn't flag-gated. Flag-off doesn't actually roll back to pre-Phase-2. Either commit to `git revert` as painful-but-documented, land Phase 2 as independently revertible sub-PRs, or use a long-running branch for QA before merging.
- **Forward-compat schema downgrade question.** If a user rolls back from post-Phase-2 to pre-Phase-2, does session state survive (graceful downgrade) or is it discarded (schema mismatch)? Plan should state intent.
- **Keybinding conflict audit.** `Cmd+Shift+Ctrl+<Arrow>` (Phase 3) and `Cmd+Opt+Shift+<Arrow>` (Phase 6) should be audited against Ghostty defaults and common TUI shortcuts (cc, codex, vim, emacs-in-terminal).
- **`CMUX_TAB_ID` incidental finding is unresolved.** Either ticket it or absorb into Phase 2.
- **Dogfooding plan.** Who runs with `CMUX_MULTI_FRAME_V1=1` during Phases 3–6 development, on what rig (single-monitor dev laptops won't exercise the feature)?
- **Retirement criteria need to be calendar-objective, not subjective.** "Soaks one release cycle" could be a week or a quarter. Propose: "shim removed in the release tagged at least 30 days after Phase 2's merge commit lands on main."

### 3.2 Codex — unique findings

- **Old-to-new object mapping is imprecise and load-bearing.** The plan says panes hold PTY/Ghostty/MTL lifecycle, but today those objects live on `Panel` (which is a `Surface`-level concept). Without an explicit mapping, implementers may place lifecycle on the wrong primitive. Codex proposes:
  - Current `Workspace` → process-scoped workspace metadata + zero-or-more `WorkspaceFrame`s.
  - Current `Workspace.panels` → process-scoped `Surface` objects.
  - Current bonsplit `PaneID` → frame-local layout leaves (or process-scoped pane records that own ordered surface IDs).
  - Current bonsplit `TabID` → UI/layout identifier for a surface within a pane.
- **Pane single-home vs multi-home is a binary decision that must be made before Phase 2 starts.** (See 2.2.)
- **Window-close orphan-pane rule must be specified.** (See 2.3.)
- **Socket focus policy per command.** (See 2.4.)
- **Reconciliation at boundaries.** Even with "reconciliation model: zero" as the goal, edge cases exist: window-local selection pointing at deleted workspaces; frames referencing removed pane IDs; pane metadata for panes removed by close; active focus pointing to a pane no longer hosted in that window; session restore rehydrating workspaces before frames. Plan documents the missing-workspace fallback; same-style fallback should be documented for stale panes and stale frames.
- **`Workspace` is not just "layout plus panels"; it is also a status, metadata, remote, notification, and panel lifecycle hub.** Plan should enumerate which fields remain on `Workspace`, which move to `WorkspaceFrame`, and which move to `Surface`/registry. (Remote workspace state, git probes, metadata/status/log/progress, recently closed browser restore, pane interaction runtime, title bar state, panel subscriptions, terminal inheritance data.)
- **Feature-flag rollback after v2 snapshot has been written.** If the binary launches with `CMUX_MULTI_FRAME_V1=0` after a v2 snapshot was written, what happens? Options: one-way migration with backup, dual read/write during soak, or explicit refusal. Plan must pick one.
- **Staged compatibility architecture alternative.** Introduce a process-scoped registry facade first, backed by the current `TabManager`/`Workspace` structure. Convert call sites to the facade before moving storage. Then move storage behind the facade. Costs indirection; reduces flag-day risk.
- **Cross-window drag-drop minimality claim should be softened.** Under the new model, the hard part is reconciling frame-local pane IDs, target frames, pane/surface registries, and focus/window policy — not pasteboard visibility. Treat drag-drop as a *consumer* of the shared move primitive, not its own path.
- **Concrete code citations anchoring the critique.** Codex repeatedly cites exact file:line references:
  - `Sources/Workspace.swift:4979`, `Sources/Workspace.swift:4983` — current `Workspace` owns both `bonsplitController` and `panels`.
  - `Sources/TabManager.swift:687`, `Sources/TabManager.swift:691` — `TabManager` owns per-window `[Workspace]`.
  - `Sources/SessionPersistence.swift:5`, `:428–444`, `:447`, `:452`, `:471` — persistence store rejects any version other than `currentVersion`; `SessionWorkspaceSnapshot` mixes workspace data and layout; workspaces embedded inside each window.
  - `Sources/TerminalController.swift:3486`, `:3784` — socket resolver + existing v2 focus-allowed pattern.
  - `Sources/AppDelegate.swift:4085`, `:4085–4092`, `:4782` — `moveSurface` and `locateSurface` already traverse windows; `focusWindow: true` current default.
  - `Sources/Workspace.swift:9344`, `:9380` — `handleExternalTabDrop` routes through `AppDelegate.moveBonsplitTab`.
  - `vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:407`, `:428`, `:433` — bonsplit's external drop hooks and `onExternalTabDrop` call path.

### 3.3 Gemini — unique findings

- **Spread distribution's `ceil(N/D)` fill-leftmost rationale: it avoids the elusive "primary display" concept,** which varies wildly between macOS setups. (Claude endorses the same choice but frames it as determinism; Gemini frames it as avoiding macOS variability — complementary justifications.)
- **4-monitor addressing question.** Positional aliases `left`, `center`, `right` don't obviously extend to 4+ monitors. Should there be `center-left`, `center-right`? Or is numeric `index` the answer?
- **Empty window state UI question.** When a window's selected workspace is deleted, does the empty "choose a workspace" state UI already exist, or does it need to be built in Phase 4?

---

## 4. Consolidated Questions for the Plan Author (Deduplicated, Numbered)

### Phase 2 scoping and execution

1. **Phase 2 sub-ordering.** Will Phase 2 be broken into revertible sub-PRs with a documented ordering (e.g., mechanical rename → registry shells → workspace/pane ownership moves → `WorkspaceFrame` introduction → session schema → socket rename)? If not, what is the plan for reviewing and rolling back a single 5,000-line+ PR? (Claude, Codex)

2. **Phase 2 estimate honesty.** Is 2 weeks predicated on a specific engineer already deeply familiar with `TabManager`/`Workspace`/`SessionPersistence`, or is it generic? Would you support widening to 3–4 weeks, or committing to the 2-week estimate with a day-10 tripwire? (Claude, Codex, Gemini)

3. **Phase 2 rollback story.** If Phase 2 lands on main and a P0 regression surfaces three days later, what is the rollback protocol? `git revert`, revertible sub-commits, or a long-running branch QA'd before merge? (Claude)

4. **Phase 2 smoke test.** Does Phase 2 ship with a developer-accessible path to spawn a second `WorkspaceFrame` on an existing workspace (e.g., behind a secondary debug flag), proving the registry handles its design load before Phase 3 relies on it? (Claude)

5. **Phase 2 acceptance criteria.** What test or set of tests, when green, says "Phase 2 is done"? (Registry round-trip, session migration tests, socket rename tests, existing suites green with flag off and on, model invariant checks?) (Claude, Codex)

6. **Phase 2 CI coverage.** What is required before Phase 2 merges — at minimum: snapshot migration tests, flag-off/flag-on launch behavior, single-window regression tests, model invariant tests? (Codex)

### Object model and invariants

7. **Pane single-home vs multi-home.** Is a pane hosted in exactly one `WorkspaceFrame` at a time in v1? If yes, is `workspace.spread all_on_each` deferred, or redefined as a clone/mirror operation? If no, how does Phase 2 represent frame references, view attachment, and focus semantics across multiple renderings? (Codex, partially Claude)

8. **Lifecycle ownership clarification.** Which object owns PTY/Ghostty/MTL lifecycle — `Pane` or `Surface`? The plan text says pane; the current code and locked hierarchy imply surface. (Codex)

9. **Registry shape.** Is there one `PaneRegistry` containing pane records that own ordered surface IDs, with a separate `SurfaceRegistry` for live surface objects? Or is it a single registry? (Codex)

10. **Window-close orphan rule.** When the user closes a window whose frame contains panes that are not hosted anywhere else, and v1 has no hibernation — does the app choose a destination window, create a frame elsewhere, prompt the user, or block close? (Codex)

11. **Empty window state.** Should v1 allow a workspace to be selected in a window when no frame exists yet? If yes, does selecting create an empty frame, rehost an existing frame, or show a "choose/spread panes" state? Does the UI for this empty state already exist, or is it Phase 4 work? (Codex, Gemini)

12. **"No workspace selected" nomenclature.** Is a window with no `WorkspaceFrame` still a `WindowScope`, or does it have a distinct type/state? Worth locking in the nomenclature. (Claude)

13. **`WorkspaceFrame` multi-viewport semantics.** Can two `WorkspaceFrame`s of the same workspace in different windows render *different* bonsplit layouts (window A shows 2x2 grid, window B shows single pane)? If yes, what does "drag pane from frame A to frame B of the same workspace" mean semantically? (Claude)

14. **Old-to-new object mapping.** Enumerate fields that remain on `Workspace` (process-scoped metadata) vs. move to `WorkspaceFrame` (layout, frame-local pane/surface selection) vs. move to `Surface`/registry (PTY, Ghostty, MTL, terminal state). Current `Workspace` hosts remote workspace state, git probes, status/log/progress, recently closed browser restore, pane interaction runtime, title bar state, panel subscriptions, terminal inheritance — which of these migrate? (Codex)

15. **Reconciliation rules at boundaries.** Beyond the documented missing-workspace fallback, what is the fallback for: stale pane IDs in a frame, stale frame references, active focus pointing to a now-not-hosted pane, session restore ordering (workspaces before frames)? (Codex)

### Feature flag and rollback

16. **Feature-flag semantics.** When `CMUX_MULTI_FRAME_V1=1` during Phase 2 (pre-Phase-3), what user-visible behavior differs from flag-off? If nothing, why does Phase 2 need a flag at all, versus flag-default-off-and-no-op-until-Phase-3? Alternatively, should there be two flags (registry vs UX)? (Claude, Codex)

17. **`CMUX_MULTI_FRAME_V1` retirement criterion.** Is it after Phase 3 soaks, after Phase 6 soaks, or after a full release containing all v1 behavior? What is the calendar-objective criterion (days on main, version number)? (Claude, Codex)

18. **Flag rollback with v2 snapshot already written.** If the user flips `CMUX_MULTI_FRAME_V1=0` after a v2 snapshot has been written, what happens? One-way migration with backup, dual read/write during soak, or refusal? (Codex)

19. **Forward-compat downgrade intent.** If a user rolls back from a post-Phase-2 build to a pre-Phase-2 build, does session state survive via graceful downgrade, or is it discarded (schema-version mismatch, start fresh)? (Claude)

### Session persistence schema

20. **Field-by-field Phase 2 schema.** Enumerate every field added to `SessionWindowSnapshot` and `AppSessionSnapshot` at Phase 2, including CMUX-26 forward-compat seams. Specifically: `sidebarMode`, `lastKnownDisplayID`/affinity field (or explicit statement that CMUX-26 owns its own bump), and any hibernation markers. (Claude, Codex)

21. **`hibernatedFrames` in the schema sketch.** The plan text at `task_01KPHHQZA4XZTQD4BQCGQYC7FR.md:153` mentions `hibernatedFrames` despite hibernation being v2-only. Is this leftover text to remove, or intentional? (Codex)

22. **Concrete schema split.** What fields move from `SessionWorkspaceSnapshot` to a new `SessionWorkspaceFrameSnapshot` — layout/bonsplit tree, frame-local pane/surface selection, zoom state? What remains process-scoped — title/custom title/color/pin, cwd/default context, metadata/status/log/progress/git, surface IDs? (Codex, Gemini)

23. **CMUX-26 schema commitment.** CMUX-26 says its schema is "already set up in CMUX-25 Phase 2." Is that an explicit commitment in this plan with named fields, or aspirational — i.e., CMUX-26 needs its own schema bump? (Claude, Codex)

### Phase 1 and CLI surface

24. **Phase 1 scope and acceptance.** Does Phase 1 include `display.list`, `window.create --display`, CLI aliases for display refs, `window.move_to_display`, and display refs appearing in `identify`/`window.list`/`tree` output? Or is `window.move_to_display` deferred? "No behavior change" vs "enables manual window-to-monitor assignment" is in tension. (Codex)

25. **4+ monitor positional aliases.** For a 4-monitor setup, how are the middle displays addressed — purely by numeric index (`display:2`, `display:3`), or with `center-left`/`center-right` aliases? (Gemini)

### Socket policy and UX

26. **Socket focus defaults per new command.** What is the focus default for `pane.move`, `workspace.spread`, `window.create --display`, and split-to-new-window? Should a single internal move/spread service take a focus-policy object, or does each phase decide independently? (Codex)

27. **Socket shim retirement criterion.** "One release cycle" for `workspace.move_to_window` is subjective. Is it a specific day count after Phase 2's merge, a named minor version, or telemetry-gated ("no known internal callers for N days")? (Claude, Codex)

28. **Keybinding conflict audit.** Have `Cmd+Shift+Ctrl+<Arrow>` (Phase 3) and `Cmd+Opt+Shift+<Arrow>` (Phase 6) been audited against Ghostty defaults and common TUI shortcuts (cc, codex, vim, emacs-in-terminal, macOS system)? (Claude)

### Phase 3 / 5 / 6 parallelism and algorithms

29. **Phase 3/4/5/6 dependency graph and ownership.** Which phases can genuinely run in parallel? If the same engineer owns 3 and 4, parallelism is fictional and the estimate should be additive. Should a shared `PanePlacementService` be lifted into Phase 2 so 5 and 6 can parallelize with 3? (Claude, Codex)

30. **Phase 5 `existing_split_per_display` algorithm.** How does the tree get split when it has nested horizontal/vertical splits that don't cleanly match the display count? Is this specced anywhere? Should it ship in v1, or is it too algorithmically ambiguous versus `one_pane_per_display`? (Claude, Codex)

31. **Localization scope.** Do Phases 5 and 6 menu and keyboard entry points include localization work in their 3-day estimates? (Codex)

### Incidental

32. **`CMUX_TAB_ID` fix.** The incidental-findings note flags this as "worth a 1-line fix ticket separately." Is that ticket being created, or should it be absorbed into Phase 2 (cheap while already in the file)? (Claude)

33. **Dogfooding plan.** Who runs with `CMUX_MULTI_FRAME_V1=1` during Phases 3–6 development, on what multi-monitor rig, and for how long before the flag retires? (Claude)

34. **File contention during parallel work.** Who owns compatibility adapters during Phase 2? Who is allowed to touch `TabManager.swift`, `Workspace.swift`, `AppDelegate.swift`, and `TerminalController.swift` if multiple agents work in parallel? (Codex)

---

## 5. Overall Readiness Verdict (Synthesized)

**Architecture: locked and correct.** All three reviewers endorse Hybrid C; none proposes rethinking.

**Phase 1: ready to ship as-is** — with a small tightening to explicit acceptance criteria (`display.list`, `window.create --display`, CLI aliases for display refs, display refs in `identify`/`window.list`/`tree`, and an explicit decision about whether `window.move_to_display` belongs to Phase 1 or a later phase).

**Phase 2: ready to *plan*, not yet ready to *execute*.** The revision pass required before kickoff is substantive but bounded. Specifically, the plan needs:

1. Sub-ordering into 4–6 revertible sub-PRs, each landing green.
2. An explicit old-to-new object mapping for `Workspace`, `WorkspaceFrame`, `Pane`, `Surface`, `Tab` — including which fields of current `Workspace` move where, and which primitive owns PTY/Ghostty/MTL lifecycle.
3. A pane single-home vs multi-home decision, with implications for `workspace.spread all_on_each` (drop, defer, or commit to multi-home representation in Phase 2).
4. A window-close / orphan-pane rule (v1 has no hibernation).
5. A v2 session schema with concrete field-level specs, a forward-compat seam for CMUX-26 (called out by name or explicitly deferred), and a rollback story for when the feature flag is flipped after a v2 snapshot has been written.
6. Feature-flag semantics disambiguated (one UX-gated flag, or two named flags split by role) plus a calendar-objective retirement criterion.
7. Socket focus defaults per new command, aligned with the repo's existing socket focus policy.
8. A sharpened dependency graph for Phases 3/4/5/6 — or a shared `PanePlacementService` lifted into Phase 2 so 5 and 6 can actually parallelize with 3.
9. Revised estimates: Phase 2 at 3–4 weeks (not 2), Phases 5 and 6 at 4–5 days (not 3 each); total v1 envelope ~7–9 weeks rather than ~7.

**Phases 3–6: quality is inherited from Phase 2.** Specific sharpenings per phase are listed above in Section 4 but none is a blocker to the plan's integrity.

**Best path forward:** The plan author spends ~1 day doing a revision pass against the consolidated question list above, with particular focus on Section 4 questions 1, 7, 10, 14, 16, 18, 20, 23, and 26 (the items where Claude and Codex independently converged). The revision does not change the architecture. It makes the plan executable by a second engineer (or a pair of agents) without those engineers having to re-derive invariants from first principles mid-Phase-2.

**Closing synthesis:** All three reviewers respect what this plan refused to do — rewrite bonsplit, ship super-workspaces, build sync-mode sidebar UX at v1, attempt hotplug in v1. That restraint is the plan's strongest artifact and the reason the architecture holds up to three independent standard reviews. The remaining work is on Phase 2's internal structure, not on its direction.
