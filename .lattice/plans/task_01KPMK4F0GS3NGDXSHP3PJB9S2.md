# CMUX-34: CMUX-9 M4: Settings UI + cmux ui themes CLI

M4 from docs/c11mux-theming-plan.md v2.1 §10.

Parent: CMUX-9.
Deliverable: Theme picker with live preview in Settings. Full cmux ui themes + cmux workspace-color CLI. 'cmux ui themes diff' and 'cmux ui themes inherit' for operator ergonomics.

v2 scope clarification: M4 does NOT introduce CLI/commands/ or Sources/Settings/ directory restructures — new code lands inline in existing CLI/cmux.swift (634KB) and Sources/cmuxApp.swift. Refactor is deferred to a separate ticket if size becomes an issue post-M4.

New files (minimal):
- Sources/Theme/AppearanceThemeSection.swift — Settings picker + preview canvas (inline SwiftUI view).
- Sources/Theme/ThemePreviewCanvas.swift — miniature c11mux diagram.
- Sources/Theme/ThemeSocketMethods.swift — socket handlers for theme.* + workspace.set_custom_color.

Modified files:
- CLI/cmux.swift — 'ui themes' subcommand family: list, get, set <name>, clear, reload, path, dump --json, validate, diff <a> <b>, inherit <parent> --as <new>. 'workspace-color' family: set --workspace <ref> <hex>, clear, get, list-palette.
- Sources/cmuxApp.swift (~line 4806) — new 'Appearance' settings section above 'Workspace Colors'.
- Sources/ContentView.swift — context-menu Workspace Color submenu tooltip for organic theme discovery.
- docs/socket-api-reference.md — document new socket methods.

Workspace reference grammar (for 'cmux workspace-color --workspace <ref>'):
- <index> — 1-based sidebar index.
- <uuid> — workspace UUID.
- @current / @focused — active / currently-focused (may differ during handoff).

Dump JSON schema locked per plan §10 M4 (identity, source_path, context, roles with expression/resolved/inherited_from, warnings).

Tests:
- tests_v2/test_theme_cli.py — full CRUD over CLI.
- tests_v2/test_workspace_color_cli.py — set + read via workspace.list + snapshot file; all workspace-ref forms.
- AppearanceSettingsTests — picker change flips ThemeManager.active.
- ThemeDumpJsonSchemaTests — dump --json output conforms; inherited_from annotations match fallback.

Hard constraints:
- Socket focus policy: 'cmux ui themes set' must NOT steal focus. Handler off-main; main only for theme application (no-alloc state update). Audit explicit in PR.
- All user-facing strings localized.
- CLI purely additive; Settings section gated behind settings.appearance.themeSectionEnabled AppStorage if needed.
