### Executive Summary
The direction is correct, but this draft is not ready to execute yet. The plan targets the right UX problem (contextual close confirmation) and proposes a reasonable primitive, but it misses a critical integration seam in the existing codepath, introduces async state hazards that are not fully modeled, and has at least one likely compile-time gap.

Most important issue: the plan is framed around replacing `TabManager.confirmClose`, but the common tab-close confirmation path for `Cmd+W`/tab close button currently runs through `Workspace.splitTabBar(...shouldCloseTab...) -> confirmClosePanel(for:)` in `Workspace.swift` (around lines ~9370 and ~8931), not through `TabManager.confirmClose`. If this plan is executed as written, the app will ship mixed behavior: some closes use pane dialogs, while common close flows still show NSAlert sheets.

### The Plan's Intent vs. Its Execution
The intent is clear: replace window-centered close confirmation with panel-local confirmation so users always know what they are confirming.

Where execution drifts:
- The document says the current close-confirmation flow is `TabManager.confirmClose` for tab/surface closes. In current code, that is not the full picture.
- Runtime Ghostty callback closes do use `TabManager.closeRuntimeSurfaceWithConfirmation`, but regular panel tab closes pass through Bonsplit delegate gating in `Workspace` (`confirmClosePanel(for:)`), which still constructs NSAlert.
- The plan's acceptance criteria promise "closing a tab with a running process" gets a pane card. As scoped, that is not guaranteed.

Net: the plan solves a subset of close flows, but claims full tab/surface coverage.

### Architectural Assessment
Good architectural choices:
- A per-panel presenter with FIFO queue is the right locality model.
- Keeping NSAlert fallback for truly anchorless flows (bulk close) is pragmatic.
- Reserving API shape for future `textInput` is a sensible forward-compatibility move.

Structural problems to resolve:
- `Panel` protocol expansion is incomplete. The plan adds `dialogPresenter` to `Panel` and only names `TerminalPanel` and `BrowserPanel`, but `MarkdownPanel` also conforms to `Panel`. As written, this likely fails to compile or forces accidental design decisions.
- Layering is unresolved at architecture time. The plan acknowledges terminal portal z-order risk and proposes fallback "if smoke test fails." That fallback (mounting in portal/AppKit layer) is a material architecture change, not a minor contingency.
- Async conversion changes invariants but the plan still treats close flows like synchronous decision points.

### Is This the Move?
Yes, but only after reframing the integration boundary.

The strongest path is:
1. Unify the close-confirmation decision point across both primary routes: `Workspace.confirmClosePanel(for:)` and the `TabManager` workspace-close path.
2. Define deterministic behavior for non-visible anchors (e.g., closing a non-selected workspace).
3. Add explicit async revalidation rules at confirmation-time.

Without those, this becomes a partial UX fix with regressions risk in focus, state, and tests.

### Key Strengths
- Scope discipline is strong: clear in-scope/out-of-scope list.
- The queueing model is thoughtful and addresses multi-trigger edge cases.
- Risk register identifies real hazards (portal layering, focus stealing, async shift).
- Integration breakdown by file and phase is practical and reviewable.

### Weaknesses and Gaps
Critical:
- Wrong primary seam: common close confirmation path in `Workspace.confirmClosePanel(for:)` is not in scope.
- Non-selected workspace close can produce an invisible pane dialog (anchor exists, but user cannot see/interact without switching context).
- `closeWorkspaceIfRunningProcess` async path snapshots `willCloseWindow` before await; window/workspace count can change while dialog is open.
- `Panel` protocol requirement likely breaks `MarkdownPanel` conformance.

High:
- `closeRuntimeSurfaceWithConfirmation` sample refactor drops existing notification cleanup (`notificationStore.clearNotifications(...)`).
- Focus suppression plan is not comprehensive enough for current `GhosttyTerminalView` focus machinery (`ensureFocus`, `applyFirstResponderIfNeeded`, mouse-driven responder acquisition, search focus restoration).
- Test impact is understated: existing unit tests around runtime close confirmation assume near-synchronous behavior and will need updates.
- UI-test plan references overlay detection but does not define required accessibility identifiers in the architecture section.

Medium:
- New localization keys (`dialog.pane.confirm.close/cancel`) duplicate existing `dialog.closeTab.close/cancel` and create avoidable translation debt.
- Keyboard API choice in plan (`.onKeyPress`) should align with existing `backport.onKeyPress` compatibility pattern.
- "Manual smoke via TestSupport/debug menu" is cited, but no explicit hook is planned.

### Alternatives Considered
1. Integrate at workspace delegate seam first
Alternative: replace/route `Workspace.confirmClosePanel(for:)` to the pane dialog primitive, then route runtime close through the same primitive.
Why better: covers the dominant user-facing close route and removes split-brain behavior.

2. Use a workspace-owned dialog coordinator instead of adding `dialogPresenter` to `Panel`
Alternative: `Workspace` owns `[panelId: PaneDialogPresenter]` (or a lightweight coordinator keyed by panel ID).
Why better: avoids expanding `Panel` protocol for panel types that may never host dialogs (e.g., markdown).

3. Explicit fallback policy for non-visible anchors
Alternative: if target workspace/panel is not visible, either select/focus it before presenting or use sheet fallback.
Why better: avoids invisible modal state.

4. Revalidate state at acceptance time
Alternative: on confirmation completion, recompute `tabs.count`, workspace existence, panel mapping, and intent viability before applying close.
Why better: closes async race conditions introduced by non-modal dialogs.

### Readiness Verdict
Needs revision before implementation.

Minimum changes to reach "ready":
- Expand scope to include (or explicitly exclude with rationale) `Workspace.confirmClosePanel(for:)` and reconcile acceptance criteria accordingly.
- Define behavior for non-selected/non-visible workspace anchors.
- Add acceptance-time revalidation rules for async close paths (especially workspace/window close decision).
- Resolve `Panel` protocol impact on all conformers (including `MarkdownPanel`) or choose a different ownership model.
- Update test plan to include existing unit-test adaptations and required accessibility identifiers.
- Preserve current side effects (notification clearing) in refactor snippets.

### Questions for the Plan Author
1. Is the feature meant to replace confirmation for `Cmd+W`/tab close button paths, or only Ghostty runtime close callbacks?
2. If yes to #1, why is `Workspace.confirmClosePanel(for:)` not an explicit integration point?
3. For closing a non-selected workspace that needs confirmation, should we auto-select it, present a sheet fallback, or allow an off-screen pane dialog?
4. Should close outcomes be based on state at prompt time or state at confirmation time when async delays are possible?
5. If `tabs.count` changes while a workspace-close dialog is open, what is the expected behavior?
6. How should stale dialogs resolve if workspace/panel disappears before user action (always cancel, silent drop, or fallback)?
7. Do we actually want `dialogPresenter` as a `Panel` protocol requirement, including `MarkdownPanel`, or should presenter ownership be external?
8. Should markdown panels ever host this dialog for workspace-close confirmations when markdown is focused?
9. Do we want to reuse existing localization keys (`dialog.closeTab.close/cancel`) instead of adding `dialog.pane.confirm.*`?
10. Which accessibility identifiers will be guaranteed on overlay root/title/buttons for robust UI tests?
11. Should keyboard handling use `backport.onKeyPress` to match existing compatibility strategy?
12. How do we guarantee z-order over portal-hosted terminal content: commit to one layering architecture now, or add a spike phase before implementation?
13. Is duplicate close-trigger dedupe needed (beyond FIFO) to prevent queue spam from repeated shortcuts?
14. Should fallback NSAlert keep `NSApp.activate(ignoringOtherApps:)`, or do we need to avoid focus-stealing behavior where possible?
15. Where will we add deterministic test seams for presenter-driven confirmations in existing `TabManagerUnitTests` and workspace close tests?
