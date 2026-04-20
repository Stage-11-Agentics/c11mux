# CMUX-32: CMUX-9 M2: Workspace color prevalence + frame + dividers (bundled M2a+M2b+M2c)

Bundled M2a + M2b + M2c from docs/c11mux-theming-plan.md v2.1 §10.

Parent: CMUX-9 (anchor for full theme-engine delivery).
Scope decision: single ticket covering all three M2 sub-slices, per operator call 2026-04-20.
Plan source of truth: docs/c11mux-theming-plan.md v2.1.

M2a — Bonsplit DividerStyle (submodule-only):
- vendor/bonsplit ships DividerStyle struct (§7.1) + ThemedSplitView.dividerThickness override.
- Files: BonsplitConfiguration.swift, SplitContainerView.swift, ThemedSplitView.swift, BonsplitDividerThicknessTests.
- CLAUDE.md submodule safety: branch off bonsplit main, commit, push to Stage-11-Agentics/bonsplit, verify 'git merge-base --is-ancestor HEAD origin/main', bonsplit CI green before M2b.
- Parent repo NOT bumped in M2a.
- Rollback: none (additive, no c11mux callers).

M2b — Parent repo wires divider color + thickness through bonsplit:
- Bump bonsplit submodule pointer to M2a commit (separate commit).
- Workspace.bonsplitAppearance takes ThemeContext; applyGhosttyChrome no-op guard extended to borderHex + dividerStyle.thicknessPt + customColor.
- WorkspaceContentView subscribes to Workspace.customColorDidChange for live divider re-apply.
- Tests: WorkspaceDividerColorPropagationTests; XCUITest live workspace-color change.
- Rollback: CMUX_DISABLE_THEME_ENGINE=1.

M2c — Outer workspace frame + sidebar tint overlay:
- New: Sources/Theme/WorkspaceFrame.swift (fills .idle rendering), ThemeManager+WorkspaceColor.swift.
- WorkspaceContentView gets .overlay(WorkspaceFrame). ContentView sidebar tint overlays chrome.sidebar.tintOverlay.
- Tests: WorkspaceFrameRenderTests, inactive-workspace frame opacity, unfocused-window frame opacity, divider-thickness no-op guard, rounded-corner geometry.
- Risks audited in PR: typing-latency paths, workspace crossfade flicker, portal-hosted terminal z-ordering, minimal-mode persistence.
- Rollback: theme.workspaceFrame.enabled AppStorage kill switch.

Partial-ship protocol: M2a→M2b→M2c sequential; each shippable independently (M2a alone = additive API, M2b alone = live dividers sans frame, full bundle = full workspace-color prevalence).

Hard constraints (CLAUDE.md + plan locks):
- Submodule safety workflow strict (see M2a checklist).
- Typing-latency paths untouched.
- No xcodebuild test locally; tests run in CI.
- All user-facing strings localized.
- Per-bundle-ID @AppStorage isolation (§12 #14).

Branch: TBD (cmux-9-m2-workspace-color suggested).
