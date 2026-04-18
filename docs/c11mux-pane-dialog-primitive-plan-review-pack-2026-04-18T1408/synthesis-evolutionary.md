# Evolutionary Review Synthesis — c11mux Pane Dialog Primitive

**Plan**: `c11mux-pane-dialog-primitive-plan` (Draft v1, 2026-04-18)
**Review pack**: `2026-04-18T1408`
**Reviewers synthesized**: Claude (Opus), Codex
**Reviewer gap noted**: Gemini Evolutionary did not run — capacity failure. Synthesis proceeds with two models. Where consensus appears between two reviewers, treat it as strong rather than unanimous; a third perspective was not available to triangulate.

---

## Executive Summary

Both reviewers converge on a single thesis: **the plan is framed as a nicer close-confirm dialog, but the asset being built is c11mux's first pane-scoped interaction substrate.** The close-confirm use case is real and worth shipping, but the primitive's name, enum shape, ownership model, and socket-addressability are one-way doors. Each reviewer, independently, urges the plan author to widen the contract *before* Phase 1 — cost now is ~30–100 LOC of scaffolding; cost after three consumers special-case modal behavior is a multi-day refactor.

Claude's review emphasizes ambition: rename the primitive (`PaneInteraction` over `PaneDialog`), separate modality from focus-capture as orthogonal properties, make the presenter socket-addressable from day one so agents can trigger pane-scoped prompts, and treat this as the **agent consent substrate** for Stage 11 — a category-jump differentiator from every other multiplexer.

Codex's review emphasizes rigor: audit *all* close-confirm entry points (the plan misses `Workspace.confirmClosePanel(for:)`), relocate state ownership from the `Panel` protocol to a workspace-scoped runtime, treat browser-panel portal layering as first-class risk (not low-risk), add stale-intent re-resolution at async completion time, and centralize focus suppression behind one semantic gate rather than grepping every `makeFirstResponder` site.

The two reviews are highly compatible — Claude zooms out, Codex zooms in. Combined, they argue for: (1) a wider enum shape with modal/non-modal distinction, (2) workspace-scoped ownership via a `PaneDialogRuntime`/`PaneInteractionRuntime`, (3) complete close-path coverage including the `Workspace` path, (4) a socket command stub in v1, (5) a stale-topology re-resolution contract, and (6) a canary `.textInput` (rename) consumer immediately after to prove genericity.

The biggest risk both flag: shipping the primitive so narrowly-named and narrowly-scoped that the next three consumers each negotiate their own protocol, and the "flywheel" of pane-local UI language never spins up.

---

## 1. Consensus Direction (Evolution Paths Both Models Identified)

1. **Generalize from "dialog" to "interaction substrate."** Both reviewers independently argue the primitive is really a local modality runtime / pane-interaction substrate, not a close-dialog component. Claude: rename to `PaneInteraction`, widen enum to include banner/toast/progress/form. Codex: define `PaneDialogRequest`/`PaneDialogResult` contract + queue/cancellation semantics before wiring callers.

2. **Text-input / rename is the canary second consumer.** Both explicitly recommend rename-tab / rename-workspace as the immediate next migration to prove genericity. Claude frames it as a 1-commit canary PR; Codex frames it as Phase E of a re-sequenced plan. Same idea.

3. **Non-confirm consumers are where the primitive earns its name.** Both identify at least one non-confirm mutation as essential: Claude names banner/toast/progress/agent-consent; Codex names undo cards, permission prompts, and long-running progress cards. Convergent list.

4. **Socket/agent-facing addressability is a major latent unlock.** Claude makes it a first-class recommendation (ship `cmux pane confirm` in v1). Codex lists it as Mutation 5 ("Coordination protocol — socket-level prompt request/response channel with audit trails"). Both see the same opportunity; Claude weights it more heavily.

5. **The `Panel`-protocol ownership model is wrong.** Claude doesn't flag it directly but hints via "make the presenter public and document as API." Codex states it explicitly: relocate state to workspace-scoped runtime keyed by `panelId`, let panel types opt into rendering rather than storage. This avoids churn across all `Panel` conformers (markdown, future types) and is a cleaner architectural seam.

6. **NSAlert fallback should not be permanent.** Claude: "Getting out of the NSAlert business entirely is the right long-term move." Codex: "Keep NSAlert fallback only for truly unanchorable cases, but [commit to replacement]." Same direction.

7. **Focus-suppression policy needs to be a single gate, not grep.** Claude proposes a `PresenterCoordinator`. Codex proposes a `isPanelDialogBlockingInput(panelId)` semantic gate. Same solution, different names.

8. **Portal z-order is a real risk, not a hypothetical.** Both reviewers flag this; Codex upgrades browser-panel layering from "low risk" (plan's label) to "first-class risk" because browser content is also portal-hosted.

9. **Accessibility IDs must be a v1 contract.** Claude: stable accessibility-identified root for snapshot testing + UI tests. Codex: `PaneDialog.Root`/`PaneDialog.Confirm`/`PaneDialog.Cancel` IDs from day one.

---

## 2. Best Concrete Suggestions (Most Actionable Ideas Across Both)

Ordered roughly by leverage-per-effort:

1. **Rename the primitive now, before Phase 1.** `PaneInteraction` (Claude's recommendation) or similar. One-way door; find-and-replace today costs nothing, rename after two consumers is a multi-day audit. (Claude §Suggestion 1)

2. **Widen the enum shape now, implement only `.confirm` in v1.** Reserve `.textInput`, `.choice`, `.banner`, `.toast`, `.progress`, `.form` as exhaustiveness placeholders. Add three disambiguator properties: `capturesFocus`, `blocksInput`, `allowsConcurrent`. ~30 LOC of enum boilerplate; prevents a v2 rewrite. (Claude §Suggestion 2, §3)

3. **Expand the in-scope close-path migration.** Include `Workspace.confirmClosePanel(for:)` — otherwise the plan ships user-visible inconsistency between `Cmd+W`/explicit-tab-close and runtime-close paths. Codex's most important concrete catch; the plan as drafted misses this entry point. (Codex §1, Phase B)

4. **Move dialog state off the `Panel` protocol to a workspace-scoped runtime.** `PaneDialogRuntime`/`PaneInteractionRuntime` owns `present(panelId:request) -> Task<Result, Never>`, per-panel FIFO queue, `cancelAll(panelId:)`, `cancelAll(workspaceId:)`, and stale-anchor detection. Panel types opt into rendering, not storage. Avoids protocol churn across all conformers including markdown. (Codex §2, §Concrete Suggestions 1)

5. **Add stale-intent re-resolution at completion time.** Any async handler that captured `workspace` or `willCloseWindow` at prompt creation must re-resolve by ID at decision time — topology can have changed while the card was up. Concrete bug risk if not addressed. (Codex §4, §Concrete 5)

6. **Centralize focus suppression behind one semantic gate.** `isPanelDialogBlockingInput(panelId)` (Codex) or a `PresenterCoordinator` subscription (Claude). Replaces the "grep every `makeFirstResponder` site" pattern, which is brittle per-PR forever. (Codex §5, Claude §Suggestion + Q14)

7. **Ship one socket command (`cmux pane confirm`) in v1.** ~80 LOC + one Python socket test in `tests_v2/`. Opens a new agent-coordination surface. Exits 0 on accept, 1 on cancel. Must follow existing socket focus policy (no app-activation / window-raising). (Claude §Suggestion 3, §2)

8. **Return `ConfirmResolution` enum, not `Bool`.** `.accepted`/`.cancelled`/`.dismissed`/`.superseded`. Consumers treat the last three identically today; distinguishing them later doesn't require an API break. Concrete v1 decision with compounding returns. (Claude §6)

9. **Ship tab-chrome pending-dialog badge in this PR.** When `presenter.current != nil` AND the panel is not visible, reuse the existing `hasUnreadNotification` ring mechanism on `TabItemView` to surface that a prompt is queued. Without this, FIFO queuing is a footgun — users miss prompts on backgrounded panes. ~20 LOC. (Claude §Suggestion 5)

10. **Lock in accessibility identifier contract now.** `PaneDialog.Root`, `PaneDialog.Confirm`, `PaneDialog.Cancel`. Stabilizes UI tests and future automation, enables snapshot testing. Trivial in v1; retrofit is not. (Codex §Concrete 7, Claude §It Unlocks 8)

11. **Widen presenter API to address-by-id, not just "current."** `resolve(_ id: UUID, result:)` + `dismissAll()`. Trivial now; eliminates a class of bugs when two stacked banners arrive. (Claude §4)

12. **Factor `PaneInteractionOverlay` as a dispatcher with per-case subviews from v1.** `switch interaction { case .confirm: ConfirmCardView(...); case .textInput: TextInputCardView(...); ... }`. Only `ConfirmCardView` ships in v1, but the dispatch shape prevents a monolithic overlay from bloating the moment the second case lands. (Claude §Suggestion 10)

13. **Publish a short consumer guide.** `docs/pane-interaction-guide.md` (~200 lines) with the enum-case checklist: "(1) add enum case, (2) add overlay subview, (3) add test hook, (4) add localization prefix." First follow-up consumer produces the doc as a PR artifact. Compounds by the third consumer. (Claude §Suggestion 4, §Suggestion 12)

14. **Establish localization prefix convention.** `dialog.pane.confirm.*`, `dialog.pane.text-input.*`, `dialog.pane.banner.*`. Two keys today, but discipline now prevents ten flat keys later. (Claude §Compound §Phase 6)

15. **End-to-end close-panel-kills-dialog test.** Not just a unit test on the presenter: an integration test where a pending dialog's parent workspace closes and the continuation resolves cleanly (no leaks, no hangs). The footgun that wedges apps. (Claude §Suggestion 6)

---

## 3. Wildest Mutations (Most Creative / Ambitious)

Ordered roughly by imagination-per-risk. Most are Claude's — Codex's mutations tend toward pragmatic leverage; Claude's reach further.

1. **The primitive becomes the agent-consent substrate.** (Claude Mutation 1) Agent in pane A wants to run `rm -rf foo/`; its hook calls `cmux confirm --panel $CMUX_PANEL_ID --title "Run dangerous command?" --destructive`. c11mux shows the card on pane A *only*; pane B keeps typing untouched. This turns c11mux from "a multiplexer you run agents in" into "the coordination substrate every agent routes consent through." Category jump; nothing else can do this because nothing else understands pane identity.

2. **Cross-agent coordination channel.** (Claude Mutation 2) Once agents can trigger pane-scoped prompts on their own panes, they can trigger them on *other* panes too. Claude-A asks Codex-B's human: "Hand off or continue?" via `cmux ask --panel $CODEX_B_PANEL --options "Hand off,Continue"`. Dangerous without ACLs — gate cross-workspace by default; require explicit opt-in; add provenance display and (source-agent, target-panel) throttles.

3. **The primitive replaces confirm-then-close with undo-after-close.** (Claude Mutation 5) Gmail-style: close immediately, show 5-second "Tab closed — Undo" toast on the pane's replacement content. The dialog primitive becomes the toast host. Modern design has moved past pre-action dialogs; the primitive should be shaped so this pivot is a consumer-level change, not a rewrite. Codex echoes this as Mutation 2 (undo/recovery cards for destructive operations).

4. **Multiplexer-native prompt shell.** (Claude Mutation 6) Push far enough and every pane has a structured interactive region *separate* from the terminal buffer — a permanent "interaction strip" where agents and the app compose UI. Starts to converge with the M9 textbox port; the two will eventually merge into a unified pane-UI language.

5. **Pane-scoped notification center merger.** (Claude Mutation 4) `TerminalNotificationStore` already exists for OSC-52 notifications (ring/badge). Let them surface as inline interactive cards: toast for "Tests passed ✓", banner for "Disk full — claude cannot write", interactive for "Build failed — View log?". Merge point between notification store and dialog presenter → one publisher, one queue, one overlay mount site. This is where naming matters most.

6. **Inline form runner (multi-field wizard).** (Claude Mutation 3) `.form(FormContent)` with N fields, validation, multi-step. Sudden new consumers: workspace creation wizard, "send to agent" composer, per-pane env-var overrides, one-off token-paste prompts. Going straight to `.form` with N=1 as degenerate costs 50 LOC more than `.textInput` and removes the rewrite risk.

7. **Cross-pane dialog chaining.** (Claude Wild Idea 1) "Confirm delete on pane A, then pane B, then pane C" — batch workflows with per-item confirmation without N separate window modals. Presenter's per-panel FIFO + async continuations already support this; just expose it.

8. **Dialogs render in `cmux tree`.** (Claude Wild Idea 2) Agent automation reads `cmux tree` output and sees that pane X has a pending prompt. Full-loop autonomy: Claude-A sees Codex-B's prompt, answers it for Codex-B. Controversial but fits Stage 11's direction. Presupposes provenance + ACL model from Mutation 2.

9. **Dialog macros / replay.** (Claude Wild Idea 3) Record an interaction sequence, replay against a different set of panes. "Approve this command pattern across all 5 panes" → one dialog broadcasts the decision to all matching queued dialogs.

10. **Long-running operation cards.** (Codex Mutation 4) Small progress/cancel cards for browser import, session actions, git fetches — avoid global blocking, keep operation context local. Less ambitious than the others but high-probability-of-adoption.

---

## 4. Flywheel Opportunities (Self-Reinforcing Loops)

Both reviewers identify flywheels; Claude names five explicitly, Codex names one six-step loop. Combined, the distinct loops are:

### Loop A — Primitive adoption compounding (Claude Loop 1)
Each new consumer reduces the friction for the next. Close-confirm (1) → rename (2) → banner (3) → marginal cost of the 4th approaches zero. **Accelerator**: first follow-up consumer produces the "consumer guide" doc as a PR artifact, so the third consumer gets the checklist free.

### Loop B — Agent substrate (Claude Loop 2) — highest leverage
If the socket API ships in v1:
1. Stage 11 agents use pane-dialog for consent/handshakes.
2. Users see it work and ask for more.
3. Agents ship new hooks that use it.
4. More agents adopt c11mux as the coordination surface.
5. c11mux's agent-forward positioning hardens into moat.

Claude flags this as the single highest-leverage loop in the plan and warns it's also the one most easily killed by deferring the socket API. **Protect it by shipping the stub in v1.**

### Loop C — Pane-scoped UI language (Claude Loop 3)
As the primitive grows, panes accumulate per-pane visual language (cards, banners, progress, notifications, agent chips, consent gates). The pane becomes a *richer UI surface* — a visual differentiation from every other multiplexer (which all treat panes as bags of cells). Visual moat. **Accelerator**: commission a "pane UI language" internal design doc once 2–3 non-modal affordances exist; external contributors inherit the reference.

### Loop D — Trust-through-contextual-prompts (Codex's six-step loop)
1. Better contextual prompts reduce accidental destructive actions.
2. Reduced mistakes increase trust in in-pane prompts.
3. Higher trust lets c11mux replace more app-modal interactions.
4. More prompt traffic yields better telemetry (cancel/confirm rates, confusion points).
5. Telemetry improves copy/defaults/placement.
6. Better outcomes reinforce trust and adoption.

**Accelerator (Codex)**: instrument prompt type, anchor panel type, latency-to-decision, and cancellation reasons; tune defaults quarterly.

### Loop E — Dialog telemetry (Claude Loop 4 — latent)
Every presented dialog is a datapoint. "Users cancel close-confirm 30% of the time — drop the confirm?" "Median 4s response to agent consent — add snooze?" ~40 LOC + opt-in toggle + Stage 11 privacy defaults. Overlaps with Loop D's step 4 — Claude and Codex independently identified the same telemetry-feeds-evolution loop.

### Loop F — Screenshot-test corpus (Claude Loop 5 — latent)
Every dialog case ships with a gold-master PNG snapshot. Over time c11mux accumulates a visual regression corpus. Future SwiftUI / macOS releases that break styling are caught immediately. No other multiplexer has this. Fold into Phase 8; one snapshot per case.

### What kills the flywheels (Claude, synthesis)
- Naming the primitive too narrowly → each new consumer is a different module.
- Scoping out the socket command → agent substrate never spins up (kills Loop B entirely).
- Keeping NSAlert fallback permanent → always two paths, flywheel halved.
- Not publishing the queue → no pane-level "pending prompt" badge → users miss queued prompts on backgrounded panes → users turn off the whole feature (kills Loop D at step 2).

---

## 5. Strategic Questions for the Plan Author

Deduplicated, numbered, ordered by decision urgency (most-blocking first). Where both reviewers asked the same or overlapping question, the consolidated form appears once with attribution.

### Architecture & Scope

1. **Naming (one-way door).** Will you commit to a name before Phase 1 that invites the second, third, and fourth consumers — `PaneInteraction`, `PanePrompt`, or keeping `PaneDialog`? What family does this primitive belong to? *(Claude Q1)*

2. **State ownership.** Should dialog state live on panel objects (current plan), or in a workspace-level runtime keyed by `panelId` (e.g., `PaneDialogRuntime`)? The latter avoids protocol churn across all `Panel` conformers (markdown, future types) and cleans up cancellation/stale-resolution semantics. *(Codex Q2)*

3. **Complete close-path coverage.** Do you want this primitive to own **all** tab/panel close confirmations — including `Workspace.confirmClosePanel(for:)` which the plan currently misses — or intentionally split across PRs? The latter leaves user-visible inconsistency between `Cmd+W` and runtime-close paths. *(Codex Q1)*

4. **Enum shape and modality axis.** Do you agree the enum should distinguish modal vs. non-modal cases from v1 (via `capturesFocus`/`blocksInput`/`allowsConcurrent` properties), even if v1 only implements `.confirm`? This is the single highest-leverage API-shape decision and it shapes the focus-guard design in §4.7 of the plan. *(Claude Q3)*

5. **Stale-topology contract.** For async non-modal flows, what is the required behavior when the target topology changes before the user responds (panel moved, closed, workspace detached)? Need to re-resolve by ID at completion time and recompute `willCloseWindow`, etc. *(Codex Q4)*

6. **Overlay host strategy.** What is the canonical overlay host for portal-backed views — SwiftUI ZStack in the panel container (current plan) or AppKit mount inside `GhosttySurfaceScrollView` — so z-order bugs are impossible by construction for *both* terminal and browser panels? Decide before Phase 3. *(Codex Q3)*

### Socket / Agent Surface

7. **Socket addressability in v1.** Is it acceptable to ship one socket command (`cmux pane confirm`) in this PR — ~80 LOC + one Python socket test — or defer to a follow-up? Strong recommendation: include it. If deferred, is there a named follow-up ticket? *(Claude Q2)*

8. **Agent-consent positioning.** Is Stage 11 interested in this primitive becoming the agent-consent substrate (Mutation 1), or is that better hosted elsewhere (Lattice, a separate daemon)? The answer shapes how much provenance/ACL/throttling infrastructure to build into v1. *(Claude Q4)*

### Consumer Strategy

9. **Rename canary timing.** Land rename-tab / rename-workspace as a 1-commit canary PR immediately after this lands (Claude's recommendation), or as a nebulous future follow-up (current plan §8 Q1)? *(Claude Q6, echoes plan §8 Q1)*

10. **First non-confirm consumer.** Which non-confirm mutation has highest business value right after the `.textInput` canary: rename, undo, permission prompt, or progress card? *(Codex Q6)*

11. **Single-PR `.textInput`?** Alternatively, do you want to include one `.textInput` consumer (rename) in *this* PR to validate generality immediately, or keep strict confirm-only scope with rename in a follow-up? *(Codex Q5)*

12. **Bulk-close long-term path.** Should bulk close (`Cmd+Shift+W` multi-select, "close other tabs in pane") remain NSAlert long-term, or do you want a future workspace-scoped/window-level dialog primitive for that class? If migrating, when and into what surface? *(Codex Q8, Claude Q5)*

### Persistence, Notifications, Quality

13. **Persistence contract.** For cases most likely to hit a restart mid-interaction (rename, form, agent-consent), should the presenter persist pending interactions or always drop them? This affects the enum shape (add `survivesRestart: Bool`?) and coordinates with the tier-1 persistence plan. *(Claude Q7)*

14. **Notification-center unification.** `TerminalNotificationStore` already exists. Is the direction to eventually merge it into `PaneInteractionPresenter` (one queue, one mount, unified publisher), or keep them separate? If merge, when? *(Claude Q8)*

15. **Tab-pending badge in this PR.** Should the "panel has pending interaction" tab-chrome badge ship with this PR (~20 LOC, reuses `hasUnreadNotification` ring), or leave it for a follow-up? Strong recommendation: include — without it, FIFO queuing is a footgun. *(Claude Q9)*

16. **Per-case overlay dispatch (v1).** Factor the overlay as a dispatcher with per-case subviews from v1, even though only `.confirm` ships? Trivial now; essential when the second case lands. *(Claude Q11)*

17. **Focus-guard strategy.** "Grep every `makeFirstResponder` site" (current plan Phase 5) works once but is brittle per-PR forever. Is a `PresenterCoordinator`/`isPanelDialogBlockingInput(panelId)` semantic gate worth the additional scaffolding? *(Claude Q14, Codex §5)*

18. **Primitive consumer guide.** Will you publish `docs/pane-interaction-guide.md` alongside this PR? ~200 lines; pays off by the third consumer. *(Claude Q12)*

19. **Telemetry opt-in.** Is there interest in emitting opt-in, local-only telemetry for dialog interactions (cancel/confirm rates, latency-to-decision, cancellation reasons) to inform future evolution? Aligns with Loops D and E. If yes, Phase 2 adds a publisher hook. *(Claude Q13, Codex Q7)*

20. **Brand alignment.** Plan §8 Q3–Q4 flag visual design as a guess. Will you coordinate with `company/brand/visual-aesthetic.md` before Phase 3, or treat v1's palette as provisional and revisit after launch? *(Claude Q15, echoes plan §8 Q3–Q4)*

21. **Module numbering vs. dependency order.** Given the dependency analysis (pane-dialog → rename canary → textbox adopts for error/confirm surfaces), should this land *before* m9 (textbox) on the calendar? If yes, the "m10" numbering conflicts with intent — reconsider m8a or keep parallel but sync on the shared primitive. *(Claude Q10, echoes plan §8 Q6)*

---

## 6. Closing Observation

Both reviewers close with the same essential advice, phrased differently:

- **Claude**: "Ship it. But name it and shape it so that six months from now nobody has to write a 'pane interaction primitive plan' because they're building on the one already here."
- **Codex**: "Panel-scoped prompts create a strong flywheel... to accelerate it: instrument prompt type, anchor panel type, latency to decision, and cancellation reasons, then tune defaults quarterly."

The underlying thesis — **modality is a property of a pane, not a window, and that matters for N-agent workflows** — is correct, currently under-communicated in the plan, and is the real deliverable of this PR. The close-confirm UI is the first visible manifestation; the substrate is the asset. Name it, claim it, build on it.

**Gemini gap**: A third perspective would have been useful on two points in particular — (a) whether the `.form(N-field)` vs. `.textInput(1-field)` expansion is worth the v1 cost, and (b) whether the socket command stub should include provenance/ACL primitives from day one or accept them as a known v2 addition. Both Claude and Codex lean same direction on these, but the third voice is missing.
