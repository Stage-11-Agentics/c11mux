### Executive Summary
The biggest opportunity is to treat this as more than a TextBox port. This can become c11mux’s input-control plane for agent workflows: a native composer that is agent-aware, focus-safe, and extensible to history/templates/automation.

Before implementation starts, the plan should absorb three concrete fixes:
1. Resolve shortcut conflict: this repo already uses `Cmd+Option+T` in `AppDelegate` for close-other-tabs behavior.
2. Fix localization strategy: “English-only now” conflicts with c11mux policy requiring localized user-facing strings (including Japanese).
3. Re-scope drag integration: current `ContentView` drag lifecycle differs from the fork; `performDragOperation` alone is too narrow as a port assumption.

### What’s Really Being Built
Under the surface, this is not “a textbox under terminals.” It is:
- A **native input abstraction layer** above PTY key/text transport.
- A **policy engine for agent-aware routing** (`/`, `@`, `?`, control keys, submit semantics).
- A **focus orchestration surface** between AppKit responder chain, Ghostty focus, and pane/workspace selection.

If done well, it becomes reusable infrastructure for future agent UX (drafting, templates, replay, context-insert, structured sends), not just one feature toggle.

### How It Could Be Better
- Replace title-regex detection as primary signal with c11mux metadata (`terminal_type` from existing detector). Keep regex as fallback only.
- Add a preflight “compatibility gate” phase before Phase 1:
  - shortcut collision audit,
  - drag lifecycle diff audit,
  - focus ownership audit across multi-window routing.
- Avoid strict “copy verbatim” framing for `TextBoxInput.swift`; copy behavior, but adapt architecture seams to current c11mux conventions (shortcut plumbing, drag routing, localization discipline).
- Split monolith early (even lightly):
  - `TextBoxRouting` (pure logic/testable),
  - `TextBoxViewBridge` (NSViewRepresentable/AppKit),
  - `TextBoxSettings` (storage/defaults).
  This reduces long-term integration friction.

### Mutations and Wild Ideas
- **Shared Draft Bus**: optional move/copy draft text between panes/workspaces (useful in agent handoffs).
- **Agent-aware composer modes**: shell mode vs agent mode with different submit/routing defaults.
- **Prompt snippets/recents**: lightweight history scoped per workspace/surface.
- **Structured send blocks**: send fenced blocks/files with previewed shell escaping.
- **Composable input accessories**: TextBox is module 1; module 2 could be “command recipe chips” or “context insertors” backed by workspace metadata.

### What It Unlocks
- Faster AI-agent workflows (multi-line composition without terminal-editing friction).
- More reliable routing behavior for agent CLIs without brittle keyboard gymnastics.
- A foundation for higher-level automation UX that can remain local/native and low-latency.
- Better separation between “text authoring UX” and “terminal execution transport,” enabling future features without touching core terminal code each time.

### Sequencing and Compounding
Recommended sequence adjustment:
1. **Phase 0 (new): Integration Preflight**
   - Resolve shortcut decision (`Cmd+Option+T` conflict).
   - Lock localization plan to policy-compliant output.
   - Diff current vs fork drag lifecycle and define exact insertion points.
2. **Phase 1: Core primitive port behind flag**
   - Port routing + input view + settings with feature disabled by default.
3. **Phase 2: Single-workspace/single-active-pane wiring**
   - Ship narrower scope first to validate focus/latency.
4. **Phase 3: Global/all-tab behavior + shortcut customization**
   - Add `.all` scope and full toggle behavior after baseline stability.
5. **Phase 4: Drag-drop integration hardening**
   - Implement full lifecycle-safe routing with explicit browser/textbox/terminal priority tests.
6. **Phase 5: Agent-awareness upgrade**
   - Metadata-first detection path.
7. **Phase 6: UX extensions (optional)**
   - Recents/snippets/draft persistence follow-up.

This sequence compounds learning: first validate core input/focus correctness, then widen scope.

### The Flywheel
A practical flywheel exists:
- Better routing/detection -> fewer failed sends and focus surprises.
- Better reliability -> higher adoption by agent-heavy users.
- Higher adoption -> more observable edge cases (timing/apps/layouts).
- Better insights -> tuned defaults and stronger routing rules.

You can accelerate this by adding lightweight debug counters around submit path, focus transitions, and routing branches during rollout.

### Concrete Suggestions
1. Add a **Phase 0 preflight** and make it a hard gate before code copy.
2. Change open-question #4 resolution now: localization must ship policy-compliant (EN+JA), not English-only.
3. Resolve shortcut ownership now:
   - either keep existing `Cmd+Option+T` behavior and choose another default,
   - or migrate close-other-tabs to configured shortcut action, then allocate TextBox shortcut cleanly.
4. Add explicit acceptance criterion: “TextBox toggle targets the correct workspace/window under multi-window focus contexts.”
5. Add explicit acceptance criterion: “No regressions in existing browser drag/drop lifecycle callbacks.”
6. Use metadata-first agent detection (`terminal_type`) with title regex fallback.
7. Add a minimal architecture seam now (routing engine extracted) to prevent future 1-file lock-in.
8. Include a rollback switch (runtime flag) to disable TextBox key routing while keeping UI mount for fast mitigation.
9. Add a “transport correctness” test unit around bracket-paste + delayed return decision logic.
10. Add a short design note for intended evolution (TextBox as extensible composer subsystem), so future work doesn’t regress into ad-hoc patches.

### Questions for the Plan Author
1. Do you want to preserve existing `Cmd+Option+T` close-other-tabs behavior, or intentionally reassign it to TextBox and move close-other-tabs elsewhere?
2. Should agent detection be metadata-first (`terminal_type`) from day one, with title regex only as fallback?
3. Is policy-compliant localization (EN+JA) required in this PR, or are you explicitly changing that project policy first?
4. Do you want rollout to start with active-pane-only toggle before enabling `.all` scope?
5. Should TextBox content remain strictly ephemeral, or do you want a follow-up for draft persistence per surface/workspace?
6. Should TextBox be framed in code as a one-off feature, or as the first module of a reusable input-composer subsystem?
7. For multi-window setups, what is the exact shortcut target rule: event window first, key window fallback, selected workspace fallback?
8. Do you want instrumentation counters (debug-only) for routing/focus/submit paths during initial rollout?
9. Is “copy verbatim” still a hard requirement if adapting to c11mux architecture requires selective refactor while preserving behavior?
10. Would you prefer one PR with internal phases, or two PRs (core primitive + integration/routing hardening) to reduce review risk?
