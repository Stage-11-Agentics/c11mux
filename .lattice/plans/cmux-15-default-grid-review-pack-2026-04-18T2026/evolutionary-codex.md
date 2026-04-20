### Executive Summary
The biggest opportunity is to evolve “default grid” from a one-time hardcoded split heuristic into a reusable workspace boot system: monitor-aware, intent-aware, and eventually self-tuning. Right now it creates pane geometry; with small architectural shifts, it can become c11mux’s layout intelligence layer.

### What's Really Being Built
Under the surface, this is not just 2x2/2x3/3x3 splitting. It is the first automatic workspace composition primitive:
- Trigger point: new workspace creation lifecycle.
- Environment sensing: display/frame classification.
- Deterministic execution: pure split schedule (`gridSplitOperations`) applied against Bonsplit.

That combination is the seed of a generalized “workspace initializer” engine.

Note: the referenced task plan file (`task_01KPHHQ6T4K09KE9YF20KPT8VS.md`) was not present in the repo snapshot, so this review is based on the current default-grid implementation and tests in the referenced code files.

### How It Could Be Better
1. Promote from hardcoded rules to declarative layout profiles.
2. Decouple “when to apply” from “what to apply” and “how to execute.”
3. Shift classification from static pixel breakpoints to effective usable area (window frame, safe regions, sidebar/topbar occupancy).
4. Add idempotency and explicit completion states (success/partial/fallback), instead of silent truncation.
5. Introduce per-workspace and per-display override seams rather than a single global on/off toggle.

### Mutations and Wild Ideas
- **Layout DNA:** store a compact “layout genome” in workspace metadata; children workspaces inherit and mutate it.
- **Intent-first bootstrap:** `cmux new --intent review|ship|triage` chooses topology + surface mix (terminal/browser/markdown), not just pane count.
- **Adaptive defaults:** detect repeated manual reshaping after spawn and suggest “make this your default for this monitor class.”
- **Team profile packs:** checked-in layout presets per repo/team, selected automatically by cwd.
- **Progressive reveal grid:** spawn minimal layout first, then opportunistically add panes as surfaces become ready to reduce cold-start friction.

### What It Unlocks
- Reliable workspace reproducibility without full session restore.
- Faster time-to-first-productive-pane on new tabs/workspaces.
- A clean bridge to future declarative manifests (`workspace.template`, `layout.apply`).
- Observable operator intent signals (which defaults are kept/modified/deleted) that can drive iterative improvements.

### Sequencing and Compounding
1. **Stabilize execution contract now:** return/apply status, log partial builds, add tests for readiness race + monitor resolution.
2. **Extract layout plan model:** represent split plans as data, keep current 2x2/2x3/3x3 as first three built-ins.
3. **Add profile selection layer:** map monitor class + optional user preference to a plan id.
4. **Add operator control surface:** settings + CLI for choosing per-class defaults and one-off overrides.
5. **Add adaptation loop:** observe post-spawn manual edits and suggest persistent profile updates.

This order compounds because each phase reuses the previous phase’s artifacts (status signals, plan model, profile registry, behavior data).

### The Flywheel
- Better default profile fit -> less manual rearrangement.
- Less rearrangement -> higher trust in auto-layout.
- Higher trust -> more default-grid usage.
- More usage -> richer telemetry about mismatches and preferred mutations.
- Richer telemetry -> better profile evolution.

A small change to accelerate it: capture a lightweight “first 60s layout delta” metric after spawn (how much the user re-splits/moves).

### Concrete Suggestions
1. Introduce `WorkspaceLayoutPlan` (data model), with an executor that consumes plan steps.
2. Keep `DefaultGridSettings.classify` but make it return a `profileId` (`grid.2x2`, `grid.2x3`, `grid.3x3`) rather than raw tuple.
3. Add execution result type: `applied`, `partial(failedStepIndex)`, `skipped(reason)` and emit to debug log + optional status metadata.
4. Unify `TabManager.spawnDefaultGridWhenReady` and `AppDelegate.spawnDefaultGridWhenReady` behind one readiness/apply path to avoid drift.
5. Add per-display override storage keyed by display characteristics, not only global `cmuxDefaultGridEnabled`.
6. Add future-safe CLI seams now: `cmux layout list`, `cmux layout apply <profile>`, `cmux workspace new --layout <profile>`.
7. Extend tests beyond pure helpers to include integration-level behavior: readiness timing, screen resolution choice, and partial-build determinism.

### Questions for the Plan Author
1. Is the target behavior “every new workspace gets a default layout” or only specific creation paths/intents?
2. Should layout classification be based on screen pixels, window points, or effective usable content area?
3. Do you want non-terminal surfaces in default profiles (browser/markdown), or keep this strictly terminal-only for v1?
4. Should operators be able to set different defaults per monitor class and per repository?
5. What is the desired UX when a split step fails: silent partial grid, retry, or explicit operator-visible notice?
6. Should default-grid application be recorded in workspace metadata for later replay/inspection?
7. Do you want a declarative layout API/CLI in this ticket scope, or should this ticket stay heuristic-only and seed a follow-up?
8. What signal defines success for CMUX-15: reduced setup time, reduced manual pane edits, or higher workspace creation throughput?
