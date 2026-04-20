# CMUX-1 — Another round of human testing

Chore. Smoke-test the primitives a human operator actually touches. Run on a tagged debug build (`./scripts/reload.sh --tag smoke-<date>`) so it doesn't collide with other running instances.

## When to run

- Before a release cut.
- After any PR that touches bonsplit, window lifecycle, persistence, or socket commands.
- Anytime automated CI passes but the behavior feels off in manual use.

## Walk-through (check each box)

### Surfaces

- [ ] Open a new workspace → lands on a single terminal pane.
- [ ] `cmux new-split --orientation horizontal` and `--orientation vertical` from the pane's terminal produce the expected layout.
- [ ] Focus jumps correctly on split creation (should land on the new surface unless `--focus false`).
- [ ] Typing in a Ghostty surface has no visible latency — press keys in a streaming `yes` loop and confirm no stutter.

### Tabs

- [ ] Drag a tab to reorder within the tab bar.
- [ ] Drag a tab onto another tab → merges into a tab group (bonsplit primitive).
- [ ] Close a tab via ⌘W → confirm no prompt storm if multiple panes are running.
- [ ] Tab title reflects `cmux set-title` calls from inside the pane.

### Workspaces

- [ ] Create a second workspace; switch between them via sidebar.
- [ ] Workspace sidebar tab shows the correct status pill when an agent emits one.
- [ ] Close and reopen the app → all workspaces restore with the right split layout, titles, cwd, and sidebar width.
- [ ] Pin a workspace; confirm it's pinned post-restart.

### Browser surface

- [ ] Open a browser surface (`cmux new-browser https://example.com` or the welcome flow).
- [ ] Navigate, back/forward, reload.
- [ ] Browser pane focus routes keyboard input to the page, not the terminal host.

### Markdown surface

- [ ] Open a markdown surface pointing at a live file.
- [ ] Save the file from an external editor → content reloads in the surface.

### Socket / CLI

- [ ] `cmux tree` renders the current workspace's spatial layout.
- [ ] `cmux set-status --key test --value "hi"` puts a chip in the sidebar; `cmux clear-status --key test` removes it.
- [ ] `cmux set-metadata --key foo --value bar` and `cmux get-metadata --key foo` round-trip.
- [ ] `cmux trigger-flash --surface <ref>` flashes the pane (sidebar flash tracked separately under CMUX-10).

### Sidebar

- [ ] Collapse/expand the sidebar.
- [ ] Resize the sidebar; confirm the width persists across restart.

## What to capture if something breaks

- Debug log path: `cat /tmp/cmux-last-debug-log-path`.
- Screenshots of the surface + sidebar at the moment of failure.
- The exact tagged build version (`./scripts/reload.sh --tag smoke-<date>` preserves this in the app name).
- Whether the regression is in DEBUG only or reproduces on Release (`./scripts/reloadp.sh` — but see the project CLAUDE.md note about not killing running instances when collaborating).

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Expanded one-paragraph stub into a concrete checklist organized by primitive (surfaces, tabs, workspaces, browser, markdown, socket, sidebar) with reproduction-capture guidance.
