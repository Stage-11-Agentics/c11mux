# C11-30: Close-workspace confirmation: workspace-scoped black overlay (not the pane-scoped card)

The pane-interaction confirmation overlay (built for close-pane) is currently doing double duty for close-workspace, and the result undersells how destructive a workspace close is. Build the workspace-scoped equivalent: a black scrim over the entire workspace area with a centered confirm/cancel card, so the disruption is unmistakable.

CONTEXT
- Closing a workspace tears down all panels, the remote connection, browser tracking, git probes, and any running agents (TabManager.swift:2246-2269). When it's the last workspace it also closes the window. This is the most destructive routine action in c11.
- We already shipped a pane-interaction confirmation system (Sources/Panels/PaneInteractionOverlayHost.swift) for close-pane. That overlay is panel-anchored, modal-within-the-pane, and reads visually as a small card. It was the right move for close-pane.
- We then routed close-workspace through the same overlay (TabManager.swift:2557-2573 -> Workspace.presentConfirmClose at Workspace.swift:9897-9922). Same small card, same visual weight as close-pane. Wrong scale for the action.
- A legacy NSAlert fallback still exists at TabManager.swift:2576-2582 for when the feature flag is off or no panel resolves. Should also be retired once the new workspace overlay covers all trigger sites.

PROPOSAL
Build a workspace-scoped sibling of the existing pane-interaction overlay:
- Black scrim covering the workspace area (sidebar stays visible — keeps spatial context, makes 'this workspace' feel scoped). Use BrandColors.black at ~0.85 opacity.
- Centered confirm/cancel card. Reuse strings dialog.closeWorkspace.title ('Close workspace?') and dialog.closeWorkspace.message ('This will close the workspace and all of its panes.'). Any new strings via String(localized:) + translator pass for ja/uk/ko/zh-Hans/zh-Hant/ru.
- Mount in the AppKit portal layer so it sits above terminals + WebView surfaces (same constraint that forced the find overlay into GhosttySurfaceScrollView per CLAUDE.md).
- Keystroke trap so keys do not reach terminals underneath (reuse the find overlay's beginFindEscapeSuppression() pattern).
- Esc cancels, Return confirms.
- Fade in 120-180ms.

TRIGGER SITES TO REWIRE (all six currently route through closeCurrentWorkspaceWithConfirmation / closeWorkspaceWithConfirmation)
- Cmd+Shift+W -- AppDelegate.swift:10074
- File menu 'Close Workspace' -- c11App.swift:811
- Command palette palette.closeWorkspace -- ContentView.swift:5904
- Sidebar X button -- ContentView.swift:11280
- Sidebar middle-click -- ContentView.swift:11545
- Sidebar right-click context menu -- c11App.swift:1372

OUT OF SCOPE
- Close-pane overlay stays as-is. It is correctly scoped today.
- Window close (AppDelegate.confirmCloseMainWindow at AppDelegate.swift:5094-5113) still uses raw NSAlert and is equally destructive — file a follow-up ticket if we want the same treatment, but do not bundle.

ACCEPTANCE
- All six workspace-close trigger sites present the full-workspace black overlay, not the pane-anchored card and not an NSAlert.
- Esc / explicit Cancel dismisses without teardown; Confirm proceeds with the existing teardown sequence.
- Keystrokes do not reach terminals underneath while the overlay is up.
- Sidebar remains visible and interactive-during-display is fine (clicking another workspace dismisses + reroutes is a reasonable extension; not required).
- Legacy NSAlert path at TabManager.swift:2576-2582 and the confirmClose handler injection at TabManager.swift:2413 are removed.
- Translator pass run for any new localized strings.
- PR includes a screenshot or short clip of the blacked-out workspace.

NOT UPSTREAM-ELIGIBLE
This is fixing our own over-application of the pane-interaction overlay. The pane-interaction system is c11-only; no cmux equivalent to upstream against.
