# M10 Pane-Interaction Primitive — Manual Validation

Runbook for validating the M10 feature before a merge decision. Assume the
tagged Debug app is running:

```bash
./scripts/reload.sh --tag m10-pane-interaction
```

Tagged socket: `/tmp/c11mux-debug-m10-pane-interaction.sock`
Tagged log: `/tmp/c11mux-debug-m10-pane-interaction.log`

## Matrix

| # | Path | Expected | Status |
|---|------|----------|--------|
| 1 | Tab ✕ with running child | Overlay card on that pane only; other panes stay interactive | |
| 2 | Cmd+W on tab with running child | Same card; Enter accepts; Esc / Cancel dismisses | |
| 3 | Cmd+W on workspace (last surface) with running child | Card on workspace's focused panel | |
| 4 | Ghostty child-exit with `needs_confirm` (Ctrl+D in shell) | Card appears exactly once (dedupe token prevents double-fire) | |
| 5 | Right-click tab → Rename Tab… | TextInput card; field preselected; Enter applies; Esc cancels | |
| 6 | Right-click workspace → Rename Workspace… | TextInput card anchored on focused panel | |
| 7 | Right-click workspace → Color → Custom… | TextInput card; invalid hex shows inline error; card stays open | |
| 8 | `cmux-dev pane-confirm --panel <uuid> --title X --destructive` | Card appears on that panel; exit 0 on accept, 2 on cancel | |
| 9 | 2×2 split; close on one pane | Overlay on that pane only; other three remain interactive | |
| 10 | IME (Kotoeri Hiragana) in rename card | Composition underline works; Enter commits without cancelling card | |
| 11 | VoiceOver on card | Announces as modal; Tab cycles buttons | |
| 12 | `CMUX_PANE_DIALOG_DISABLED=1` relaunch; repeat 1 | Falls back to NSAlert | |

## Typing-latency baseline

- `forceRefresh()` / `hitTest()` / `TabItemView` body have no M10 additions.
- Spot-check: run an intensive typing stream in a terminal while no card is
  active; compare subjective latency to a non-tagged Debug build. No regression
  expected since the overlay is only mounted on demand.

## Telemetry (DEBUG only)

`tail -f "$(cat /tmp/cmux-last-debug-log-path)"` should show:

- `pane.interaction.present panel=<5> source=<local|socket> kind=<confirm|textInput>`
- `pane.interaction.resolve panel=<5> result=<confirmed|cancelled|dismissed|submitted>`
- `focus.suppressed surface=<5> reason=<…>` while card is visible on a terminal

## Known follow-ups (not M10 blockers)

- Workspace custom-color visibility is subtle in the sidebar — logged in
  `TODO.md` under UI/UX Improvements.
- Dedicated `CloseTabPaneOverlayUITests` / `RenameTabPaneOverlayUITests`
  files need Xcode to wire into the cmuxUITests target; extending existing
  detectors covers the overlay path in the interim (see Phase 8 commit).
