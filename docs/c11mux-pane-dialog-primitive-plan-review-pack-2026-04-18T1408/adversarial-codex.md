# Adversarial Review
PLAN_ID: c11mux-pane-dialog-primitive-plan
MODEL: Codex

## Executive Summary
Concern level is high. The plan’s biggest problem is that it targets the wrong seam for tab-close confirmations: it assumes the tab/surface close flow is primarily `TabManager.confirmClose`, but a major real path is `Workspace.confirmClosePanel` via Bonsplit delegate callbacks. That means the plan can ship “pane dialogs” and still leave common close flows on `NSAlert`, or regress behavior while thinking it is complete (`docs/c11mux-pane-dialog-primitive-plan.md:24`, `:41-43`, `Sources/Workspace.swift:8931-8958`, `:9321-9394`, `Sources/TabManager.swift:2423-2460`).

## How Plans Like This Fail
1. [Factual Error] Refactor looks comprehensive on paper but misses the active runtime seam.
The plan scopes two triggers (`closeRuntimeSurfaceWithConfirmation`, `closeWorkspaceIfRunningProcess`) and frames current behavior as `TabManager.confirmClose` (`docs/c11mux-pane-dialog-primitive-plan.md:24`, `:41-43`). But close confirmation for explicit tab closes is currently in `Workspace.confirmClosePanel` (sheet/modal) called from `splitTabBar(_:shouldCloseTab:inPane:)` (`Sources/Workspace.swift:8931-8958`, `:9321-9394`).

2. [Factual Error] “No portal hazard” call for browser is incorrect.
The plan marks browser overlay risk as low/no portal hazard (`docs/c11mux-pane-dialog-primitive-plan.md:256-258`). Browser code explicitly documents portal layering hazards and mounts search overlay in AppKit portal specifically to avoid being hidden by portal-hosted `WKWebView` (`Sources/Panels/BrowserPanelView.swift:445-456`, `:1120-1145`).

3. [Design Weakness] Assumes local modal behavior without rethinking global shortcut routing.
Current app-level shortcut handler has explicit close-confirmation special-case for NSPanel alerts, including Cmd+D destructive accept (`Sources/AppDelegate.swift:9018-9050`). Pane-local SwiftUI overlay bypasses that mechanism unless reworked.

## Assumption Audit
1. [Factual Error] Assumption: only TerminalPanel and BrowserPanel need presenter conformance.
Plan says protocol addition is satisfied by TerminalPanel and BrowserPanel (`docs/c11mux-pane-dialog-primitive-plan.md:133`, `:223-227`). But `MarkdownPanel` also conforms to `Panel` (`Sources/Panels/MarkdownPanel.swift:20-23`).

2. [Factual Error] Assumption: protocol/type visibility will compile as shown.
Plan adds `dialogPresenter: PaneDialogPresenter` to a `public protocol Panel` (`docs/c11mux-pane-dialog-primitive-plan.md:210-214`, `Sources/Panels/Panel.swift:65-67`) while declaring presenter as non-public in snippet (`docs/c11mux-pane-dialog-primitive-plan.md:102-107`). That is an access-control mismatch unless adjusted.

3. [Design Weakness] Assumption: panel-anchored dialog remains usable for non-selected workspace closes.
Sidebar row close calls can target non-selected workspaces (`Sources/ContentView.swift:10900`, `:11138`). Non-selected workspace views are non-hit-testable (`Sources/ContentView.swift:2075`). Plan anchors workspace-close dialog to `workspace.focusedPanelId` (`docs/c11mux-pane-dialog-primitive-plan.md:332-359`) but does not define a visibility/interaction fallback.

4. [Design Weakness] Assumption: keyboard suppression is solved by terminal-only focus guard.
Plan only calls out guarding terminal focus-restoration (`docs/c11mux-pane-dialog-primitive-plan.md:376-385`), but browser focus code actively reassigns first responder to `WKWebView` (`Sources/Panels/BrowserPanelView.swift:6220-6263`).

## Blind Spots
1. [Factual Error] Missing explicit migration of `Workspace.confirmClosePanel` path.
If this is not migrated or rerouted, the “replace NSAlert” goal is incomplete for explicit tab close operations (`Sources/Workspace.swift:8931-8958`, `:9321-9394`).

2. [Factual Error] Missing Cmd+D parity plan.
Plan keyboard contract lists Return/Escape/Tab (`docs/c11mux-pane-dialog-primitive-plan.md:46`, `:529`), but existing behavior and tests depend on Cmd+D accepting destructive close for workspace/window path (`Sources/AppDelegate.swift:9036-9049`, `cmuxUITests/CloseWorkspaceCmdDUITests.swift:10-27`).

3. [Design Weakness] UI test impact is under-scoped.
Plan only names one existing test file for overlay detector work (`docs/c11mux-pane-dialog-primitive-plan.md:476-481`) while acceptance requires several suites still pass (`docs/c11mux-pane-dialog-primitive-plan.md:532`). Existing helper methods are dialog/alert-centric (e.g. cancel click path) and likely need broader updates (`cmuxUITests/CloseWorkspaceConfirmDialogUITests.swift:48-63`).

4. [Design Weakness] Focus-guard implementation detail is missing.
Plan suggests `if terminalPanel.dialogPresenter.current != nil { return }` inside Ghostty focus code (`docs/c11mux-pane-dialog-primitive-plan.md:381`), but those methods currently do not have a `terminalPanel` reference in scope (`Sources/GhosttyTerminalView.swift:6125-6160`, `:7739-7818`).

## Challenged Decisions
1. [Design Weakness] New localization keys for Close/Cancel are unnecessary and risky.
Plan introduces `dialog.pane.confirm.close` and `.cancel` (`docs/c11mux-pane-dialog-primitive-plan.md:390-399`). Existing `dialog.closeTab.close`/`.cancel` already exist and are broadly translated (`Resources/Localizable.xcstrings:29376`, `:29489`). Reuse would reduce churn and avoid locale regression.

2. [Design Weakness] Forcing `dialogPresenter` into `Panel` protocol may be over-coupling.
This pushes modal concerns into every panel type (including markdown) instead of using a narrower capability/protocol or panel-type-specific presenter map.

3. [Design Weakness] Async flip lacks explicit unit-test adaptation strategy.
Plan changes close paths to Task/async (`docs/c11mux-pane-dialog-primitive-plan.md:314-326`, `:347-360`) but does not call out updates for unit tests that currently assume immediate effects (`cmuxTests/TabManagerUnitTests.swift:259-281`).

## Hindsight Preview
1. “We solved the visible demo path, not the real close path.”
This will be the postmortem if `Workspace.confirmClosePanel` remains untouched.

2. “We under-modeled focus ownership.”
Terminal and browser both have active first-responder reassertion machinery; pane-modal UX needs explicit integration points in both stacks, not only a terminal grep pass.

3. “We created i18n debt by adding duplicate keys.”
New primitive-level Close/Cancel keys are likely to drift from existing dialog terminology and translation coverage.

Early warning signs:
- Any close action still shows NSAlert after merge.
- Cmd+D stops confirming close in workspace-close flow.
- Browser pane dialog appears under web content or loses keyboard control.

## Reality Stress Test
Most likely 3 disruptions:
1. User closes a non-selected workspace from sidebar while another workspace is active.
2. Browser panel is portal-hosted and steals/reclaims first responder.
3. CI runs existing close-dialog tests expecting NSAlert/Cmd+D behavior.

Combined outcome:
- Dialog appears in a non-interactive layer or not visibly actionable.
- Keyboard routes to web/terminal surface, not dialog.
- Test failures surface late, after architecture is already spread across TabManager + panel views.

## The Uncomfortable Truths
1. [Factual Error] The plan currently describes a cleaner architecture than the one that exists; it omits a core existing close-confirmation implementation in `Workspace`.
2. [Design Weakness] “Pane-local modal” sounds scoped, but it crosses TabManager, Workspace/Bonsplit delegate, AppDelegate shortcut policy, terminal focus, browser portal layering, and UI tests.
3. [Design Weakness] Risk ratings are optimistic in the wrong places (browser layering, non-selected workspace interaction, keyboard parity).

## Hard Questions for the Plan Author
1. Are you intentionally leaving `Workspace.confirmClosePanel` (`Sources/Workspace.swift:8931-8958`) on NSAlert, and if so, which user-triggered close paths remain NSAlert by design?
2. How will pane dialogs behave for non-selected workspace close actions from sidebar rows (`Sources/ContentView.swift:10900`, `:11138`) when non-selected workspaces are non-hit-testable (`:2075`)?
3. What is the explicit Cmd+D contract after migration, and where is the replacement for current NSPanel-specific shortcut forwarding (`Sources/AppDelegate.swift:9036-9049`)?
4. Why does the plan classify browser as low/no portal hazard despite explicit portal layering warnings in `BrowserPanelView` (`:445-456`)?
5. If `Panel` gets `dialogPresenter`, what is the intended behavior for `MarkdownPanel` (`Sources/Panels/MarkdownPanel.swift:20-23`)?
6. What is the concrete plumbing to let Ghostty focus code check dialog state when those methods currently lack direct panel references (`Sources/GhosttyTerminalView.swift:6125-6160`, `:7739-7818`)?
7. Why introduce new Close/Cancel localization keys instead of reusing existing translated keys (`Resources/Localizable.xcstrings:29376`, `:29489`)?
8. Which unit tests are expected to change for async close semantics, and where is that work called out in phases?
9. What is the explicit fallback policy when panel-anchored dialog cannot be surfaced interactively (hidden workspace, retired workspace, non-owned pane host)?
10. Do you want one primitive for both “panel close” and “workspace close,” or should workspace close use a different affordance because the destructive scope is larger than one panel?
