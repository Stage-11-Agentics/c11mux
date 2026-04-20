# CMUX-21: CMUX-9 M1: Theme engine foundation + surface adoption (bundled M1a+M1b)

Bundled M1a (engine/parser/default theme; no call-sites) + M1b (surface-by-surface adoption, snapshot-gated) from docs/c11mux-theming-plan.md v2.1 §10.

Parent: CMUX-9 (anchor for full theme-engine delivery).
Scope decision: one complete-story PR rather than two smaller PRs, per operator call 2026-04-19.
Branch: cmux-9-m1-theme-foundation (worktree at ~/Projects/Stage11/code/cmux-worktrees/cmux-9-m1).

Deliverables:
- Sources/Theme/ (C11muxTheme, ThemedValueAST, ThemedValueEvaluator, TomlSubsetParser, ThemeContext, ThemeRoleRegistry, ThemeManager, WorkspaceFrame stub per §7.3).
- Resources/c11mux-themes/stage11.toml (Appendix A.1).
- Chrome surfaces refactored to read via ThemeManager: SurfaceTitleBarView, BrowserPanelView, MarkdownPanelView, Workspace.bonsplitAppearance, ContentView (TabItemView + customTitlebar), WorkspaceContentView.
- Tests: round-trip golden, resolution fixtures, TomlSubsetParserFuzzTests (corpus at cmuxTests/Fixtures/toml-fuzz/), ThemeResolverBenchmarks (p95<10ms/10k, per-lookup <1µs amortized), resolved-snapshot artifact diff, cycle/invalid-value/unknown-modifier, 24-dim sidebar snapshot, titlebar snapshot (4 dim), browser-chrome snapshot (6 dim).

Hard constraints (CLAUDE.md + plan locks):
- §12 #7: hand-written TOML subset parser, zero deps (realistic 400-600 lines per §6.1).
- Typing-latency paths untouched: TabItemView Equatable contract preserved (pre-computed let params, no @EnvironmentObject/@ObservedObject inside view).
- Per-bundle-ID @AppStorage isolation (§12 #14): theme keys route through UserDefaults(suiteName: Bundle.main.bundleIdentifier).
- Per-surface migration flag per §10 M1b: @AppStorage(theme.m1b.<surface>.migrated, default: false).
- Rollback surfaces per §8.1: CMUX_DISABLE_THEME_ENGINE env, theme.engine.disabledRuntime AppStorage, theme.workspaceFrame.enabled AppStorage.
- Runtime contract §6.4.a: parse-time cycle detection; invalid-hex=load-time error; out-of-range modifier args clamp+warn; unknown modifier=error; sRGB-only resolution; cache key = full ThemeContext hash.
- Localization: all user-facing strings via String(localized: key, defaultValue:).
- No xcodebuild test locally: build-only verification; test runs deferred to CI.

Implementation agent: clear codex (headless background).
Review: operator-in-the-loop, no formal gate per §12 #11.
