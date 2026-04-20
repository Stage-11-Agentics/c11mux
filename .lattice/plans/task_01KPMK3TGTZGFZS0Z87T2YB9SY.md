# CMUX-33: CMUX-9 M3: User themes + hot reload + phosphor

M3 from docs/c11mux-theming-plan.md v2.1 §10.

Parent: CMUX-9.
Deliverable: Users drop .toml in ~/Library/Application Support/c11mux/themes/ and they load. Stage 11 (default) + Phosphor built-ins ship. Editing a theme file hot-reloads ≤1s. 'cmux ui themes validate' available for offline debugging (pulled forward from M4 per Trident evolutionary review).

New files:
- Sources/Theme/ThemeDirectoryWatcher.swift — FSEvents watcher, polling fallback (2s), debounce 250ms, handles vim/VSCode atomic-rename patterns.
- Sources/Theme/ThemeCanonicalizer.swift — sorted keys + consistent whitespace formatter.
- Resources/c11mux-themes/phosphor.toml — second built-in (subtle matrix/CRT-phosphor) validating theme switching + aesthetic range (§12 #15).
- Resources/c11mux-themes/README.md — bundled on first-run dir creation.
- CLI: cmux ui themes validate <path-or-name> — error-collecting loader, exit 0 clean / 1 warning / 2 error.

Modified files:
- ThemeManager.swift — enumerate built-ins + user themes; name shadowing (user wins); atomic swap with last-known-good retention on parse failure + sticky OSLog warning.
- cmuxApp.swift — first-launch user-themes-dir + README creation.

Hot-reload contract:
1. FSEvents fires → 250ms debounce.
2. Candidate read → parse → validate → ResolvedThemeSnapshot computed off-main.
3. Main-actor atomic swap — single published-ref replacement triggering per-section publishers.
4. Parse failure → retain last-known-good; OSLog + M4 Settings picker warning indicator.
5. Editor save patterns handled by debounce + candidate-parse; incomplete intermediates fail parse and retain last-known-good.

Tests:
- ThemeDirectoryWatcherTests — use ThemeManager.pathsOverride seam.
- ThemeShadowingTests — user wins; revert on delete, including delete-while-active.
- ThemeMalformedLoadTests — warning, no crash, no swap.
- ThemeAtomicSwapTests — vim-style temp-file+rename; no intermediate-invalid state published.
- ThemeCanonicalizerTests — round-trip semantic equivalence.
- Additive-schema fallback test — missing [chrome.titleBar] falls back to stage11 + diagnostic.
- tests_v2/test_theme_validate_cli.py — good/warning/error fixtures + exit codes.

Risks mitigated: FSEvents latency (polling fallback), missing-variable references (additive fallback §6.5), file-deleted-while-active (last-known-good), directory edge cases (no-user-themes + warning).

Rollback: built-ins always load regardless of user-theme state.
