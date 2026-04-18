### Executive Summary
The biggest opportunity is to treat this as a **panel-scoped interaction substrate**, not a one-off close-confirm dialog. If you evolve it correctly, you get a reusable “in-pane decision layer” for confirmations, text input, undo, agent approvals, and lightweight progress prompts without app-modal focus theft.

The current draft is strong on UX intent, but it underestimates three structural realities in c11mux today: (1) close confirmations are split across both `TabManager` and `Workspace` paths, (2) portal-hosted surfaces make SwiftUI overlay placement fragile for both terminal and browser panels, and (3) async/non-modal flows need stale-intent guards (workspace/panel may change before user responds).

### What's Really Being Built
You are building a **local modality runtime** for pane-level interactions:
- Addressing: map a prompt to a concrete panel identity.
- Arbitration: queue/resolve/cancel multiple prompt intents per panel.
- Focus governance: temporarily override panel input routing while preserving other panes/windows.
- Lifecycle semantics: what happens when target panel detaches, closes, or loses selection.

That runtime is more strategic than the close dialog itself. It is effectively a new UI primitive for c11mux’s multi-pane/multi-agent model.

### How It Could Be Better
1. Cover all close-confirm entry points in one design pass.
`Cmd+W`/explicit tab close currently routes through `Workspace.confirmClosePanel(for:)` (sheet/modal path), while runtime close uses `TabManager.closeRuntimeSurfaceWithConfirmation`. If only `TabManager` paths are migrated, user-visible behavior remains inconsistent for the most common close flow.

2. Avoid forcing `dialogPresenter` onto the `Panel` protocol as the primary state owner.
`Panel` has more conformers than terminal/browser (e.g. markdown). Adding a stored-property requirement increases churn and can create accidental compile gaps. A better shape is workspace-owned state keyed by `panelId` (or a `PanelDialogCoordinator`) so panel types opt into rendering, not storage.

3. Treat browser layering as a first-class risk, not a low-risk case.
Browser content is also portal-hosted in key paths. Mounting the dialog only in `BrowserPanelView` can produce the same z-order failure mode called out for terminal search overlays.

4. Add stale-intent protection for async resolution.
With non-modal dialogs, by confirmation time the target workspace/panel/window topology may have changed. Any code that captures `workspace` object or `willCloseWindow` at prompt creation should re-resolve by IDs at completion time.

5. Centralize focus suppression policy.
“Grep every `makeFirstResponder`” is brittle. Introduce one semantic gate (`isPanelDialogBlockingInput(panelId)`) and route focus restoration helpers through it.

### Mutations and Wild Ideas
Ranked by expected leverage (impact x probability x reuse):

1. **Prompt Primitive -> Rename Primitive (text input variant)**
Immediate next mutation. Same anchoring/focus rules, high user value, little conceptual overhead.

2. **Prompt Primitive -> Undo/Recovery cards**
Destructive operations (close/move/detach) can produce pane-local undo affordances. This compounds trust and reduces “are you sure?” pressure.

3. **Prompt Primitive -> Agent permission prompts**
Pane-local approve/deny for actions like “send command to terminal”, “open URL externally”, “apply patch”. Fits c11mux’s multi-agent workflow directly.

4. **Prompt Primitive -> Long-running operation cards**
Small progress/cancel cards (e.g., browser import, session actions) that avoid global blocking and keep operation context local.

5. **Prompt Primitive -> Coordination protocol**
Expose a socket-level prompt request/response channel so automation can initiate and resolve pane-local prompts with audit trails.

### What It Unlocks
- A uniform UX contract for all panel-scoped decisions.
- Reduced app/window focus stealing (aligned with socket focus policy).
- Better multi-pane safety: fewer wrong-pane confirmations.
- Higher-confidence automation hooks (test/agent-friendly explicit prompt IDs and outcomes).
- A reusable foundation for richer inputs without reopening focus/layering architecture every time.

### Sequencing and Compounding
Recommended order (different from current plan) to maximize learning and minimize rework:

1. **Phase A: Contract + Host Topology**
Define `PaneDialogRequest`, `PaneDialogResult`, queue semantics, cancellation semantics, and host rendering layer strategy (SwiftUI vs portal/window overlay) before wiring callers.

2. **Phase B: Migrate `Workspace.confirmClosePanel(for:)` first**
This validates explicit user close flows (`Cmd+W`, tab close) where the pain is most visible.

3. **Phase C: Migrate `TabManager.closeRuntimeSurfaceWithConfirmation`**
Unify runtime-initiated close with the same primitive.

4. **Phase D: Migrate workspace-close confirmation path**
Handle `closeWorkspaceIfRunningProcess` with stale-topology-safe re-resolution at completion.

5. **Phase E: Introduce `.textInput` consumer (rename tab/workspace)**
Proves the primitive is truly generic and prevents overfitting to confirm-only.

6. **Phase F: Add one non-confirm consumer (undo or permission prompt)**
This is the compounding step that converts “feature” into “platform.”

### The Flywheel
Panel-scoped prompts create a strong flywheel:
1. Better contextual prompts reduce accidental destructive actions.
2. Reduced mistakes increase user trust in in-pane prompts.
3. Higher trust allows replacing more app-modal interactions.
4. More prompt traffic yields better telemetry (cancel/confirm rates, confusion points).
5. Telemetry improves copy/defaults/placement.
6. Better outcomes reinforce trust and adoption.

To accelerate it: instrument prompt type, anchor panel type, latency to decision, and cancellation reasons (where available), then tune defaults quarterly.

### Concrete Suggestions
1. Add a single `PaneDialogRuntime` object at workspace scope with:
- `present(panelId:request) -> Task<Result, Never>`
- per-panel FIFO queue
- `cancelAll(panelId:)` and `cancelAll(workspaceId:)`
- stale-anchor detection before resolve

2. Replace closure-based completion with request/result IDs internally. Keep closures only at adapter boundaries.

3. Expand in-scope migration list to include `Workspace.confirmClosePanel(for:)`; otherwise the feature will feel partial.

4. Decide and document one rendering host strategy for portal-backed content before Phase 3 coding.

5. In async completion handlers, re-resolve workspace/panel by ID and recompute `willCloseWindow` at decision time.

6. Keep NSAlert fallback only for truly unanchorable cases, but ensure fallback path does not violate socket focus policy for non-user-initiated flows.

7. Add an accessibility identifier contract now (`PaneDialog.Root`, `PaneDialog.Confirm`, `PaneDialog.Cancel`) so UI tests and future automation remain stable.

8. Plan one short “consumer pack” follow-up PR (rename + one non-confirm card) to lock in primitive legitimacy.

### Questions for the Plan Author
1. Do you want this primitive to own **all** tab/panel close confirmations (including `Workspace.confirmClosePanel(for:)`) in this effort, or intentionally split across PRs?
2. Should dialog state live on panel objects, or in a workspace-level runtime keyed by panel ID?
3. What is the canonical overlay host for portal-backed views (terminal and browser) so z-order bugs are impossible by construction?
4. For async non-modal flows, what is the required behavior when target topology changes before user response (panel moved/closed/workspace detached)?
5. Do you want to include one `.textInput` consumer in this PR to validate generality, or keep strict confirm-only scope?
6. Which non-confirm mutation has highest business value right after this: rename, undo, permission prompt, or progress card?
7. What telemetry (if any) is acceptable for prompt interactions in this release?
8. Should bulk-close remain NSAlert long-term, or do you want a future “workspace-scoped” dialog primitive for that class of operation?
