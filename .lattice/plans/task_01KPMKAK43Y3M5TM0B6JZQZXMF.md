# CMUX-35: CMUX-9 M3+M4: User themes + hot reload + Settings UI + CLI (full operator-facing completion)

Bundled M3 + M4 from docs/c11mux-theming-plan.md v2.1 §10.

Parent: CMUX-9.
Scope decision: bundle M3 (user themes + hot reload) with M4 (Settings UI + CLI) into one operator-facing completion ticket, per operator call 2026-04-20. M5 (stretch) intentionally not ticketed; re-justify only if pursued.

Delivers the full public-facing theming story on top of M2: users can author, install, live-reload, preview in Settings, and drive themes via CLI.

=== M3 — User themes + hot reload ===

Deliverable: Users drop .toml in ~/Library/Application Support/c11mux/themes/ and they load. Stage 11 (default) + Phosphor built-ins ship. Editing a theme file hot-reloads ≤1s. 'cmux ui themes validate' available for offline debugging.

New files:
- Sources/Theme/ThemeDirectoryWatcher.swift — FSEvents watcher, polling fallback (2s), debounce 250ms, handles vim/VSCode atomic-rename patterns.
- Sources/Theme/ThemeCanonicalizer.swift — sorted keys + consistent whitespace formatter.
- Resources/c11mux-themes/phosphor.toml — second built-in (subtle matrix/CRT-phosphor) validating theme switching + aesthetic range (§12 #15).
- Resources/c11mux-themes/README.md — bundled on first-run dir creation.

Modified files:
- ThemeManager.swift — enumerate built-ins + user themes; user-wins shadowing; atomic swap with last-known-good retention on parse failure + sticky OSLog warning.
- cmuxApp.swift — first-launch user-themes-dir + README creation.

Hot-reload contract:
1. FSEvents fires → 250ms debounce.
2. Candidate read → parse → validate → ResolvedThemeSnapshot computed off-main.
3. Main-actor atomic swap — single published-ref replacement.
4. Parse failure → retain last-known-good + OSLog warning + Settings picker warning indicator (see M4).
5. Editor-save patterns handled by debounce + candidate-parse; incomplete intermediates fail parse and retain last-known-good.

M3 tests:
- ThemeDirectoryWatcherTests (via ThemeManager.pathsOverride seam).
- ThemeShadowingTests (user wins; revert on delete, including delete-while-active).
- ThemeMalformedLoadTests (warning, no crash, no swap).
- ThemeAtomicSwapTests (vim-style temp-file+rename, no intermediate-invalid publish).
- ThemeCanonicalizerTests (round-trip semantic equivalence).
- Additive-schema fallback test (missing [chrome.titleBar] → stage11 fallback + diagnostic).

=== M4 — Settings UI + CLI ===

Deliverable: Theme picker + live preview in Settings. Full 'cmux ui themes' + 'cmux workspace-color' CLI including diff and inherit for operator ergonomics.

v2 scope clarification: NO CLI/commands/ or Sources/Settings/ directory restructures — new code lands inline in CLI/cmux.swift (634KB) and Sources/cmuxApp.swift. Refactor is a separate ticket only if size becomes an issue post-M4.

New files (minimal):
- Sources/Theme/AppearanceThemeSection.swift — Settings picker + preview canvas (inline SwiftUI).
- Sources/Theme/ThemePreviewCanvas.swift — miniature c11mux diagram.
- Sources/Theme/ThemeSocketMethods.swift — socket handlers for theme.* + workspace.set_custom_color.

Modified files:
- CLI/cmux.swift — 'ui themes' family: list, get, set <name>, clear, reload, path, dump --json, validate, diff <a> <b>, inherit <parent> --as <new>. 'workspace-color' family: set --workspace <ref> <hex>, clear, get, list-palette. (Note: 'validate' is shared with M3's offline-debug need — lands once.)
- Sources/cmuxApp.swift (~line 4806) — new 'Appearance' settings section above 'Workspace Colors'.
- Sources/ContentView.swift — context-menu Workspace Color submenu tooltip for organic theme discovery.
- docs/socket-api-reference.md — document new socket methods.

Workspace reference grammar (for 'cmux workspace-color --workspace <ref>'):
- <index> — 1-based sidebar index.
- <uuid> — workspace UUID.
- @current / @focused — active / currently-focused.

Dump JSON schema locked per plan §10 M4: identity, source_path, context, roles (expression/resolved/inherited_from), warnings.

M4 tests:
- tests_v2/test_theme_cli.py — full CRUD over CLI.
- tests_v2/test_workspace_color_cli.py — set + read via workspace.list + snapshot; all workspace-ref forms.
- tests_v2/test_theme_validate_cli.py — good/warning/error fixtures + exit codes (lands with M3 need).
- AppearanceSettingsTests — picker change flips ThemeManager.active.
- ThemeDumpJsonSchemaTests — dump --json conforms; inherited_from matches fallback.

=== Shared constraints (M3 + M4) ===

- Socket focus policy: 'cmux ui themes set' MUST NOT steal focus. Handler off-main; main only for no-alloc state update. Audit explicit in PR.
- All user-facing strings via String(localized: key, defaultValue:).
- Per-bundle-ID @AppStorage isolation preserved (§12 #14).
- No xcodebuild test locally; CI only.
- CLI purely additive; Settings section gated behind settings.appearance.themeSectionEnabled AppStorage if needed.

=== Shipping order within the bundle ===

Recommended internal sequencing (single PR still ok; PR body calls out phases):
1. M3 watcher + phosphor + loader (user-visible hot reload working).
2. M4 CLI family landing atop M3 loader.
3. M4 Settings section + preview.

Partial-ship protocol: if Settings UI stalls, M3 hot-reload + M4 CLI is still a complete operator story; Settings UI can defer to follow-up if needed.
