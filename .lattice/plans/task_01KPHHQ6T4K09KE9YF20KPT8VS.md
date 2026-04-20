# CMUX-15 — Implementation Plan: Default pane grid sized to monitor class

Status: **draft for trident review**
Author: agent:claude-opus-4-7
Date: 2026-04-18

---

## Goal

When a user opens a new workspace in c11mux, auto-spawn a grid of terminal panes sized to the monitor's pixel class, so the user lands in a parallel-work layout without manual splits.

## Non-goals

- Multi-monitor support (tracked separately).
- Reshuffling panes on window-move-between-displays after creation.
- Retroactively applying a grid to existing workspaces.
- Overriding saved-workspace layouts (those always win).
- Changing the welcome-quad layout for first-run (that's a distinct, curated experience).

## Monitor classification

**Signal:** pixel dimensions of the screen hosting the window at workspace-creation time. macOS exposes this via `window.screen?.frame` (fallback `NSScreen.main?.frame`). Pattern matches existing code at `Sources/GhosttyTerminalView.swift:3022`, `Sources/AppDelegate.swift:2599`, `Sources/ContentView.swift:1788`.

**Why pixel dimensions, not inches:** macOS does not expose physical diagonal reliably across external displays. Pixels are deterministic, already-used throughout cmux, and track the thing the user actually cares about (screen real estate available for panes).

**Thresholds (starting point):**

| Resolution class                              | Grid (cols × rows) | Total panes |
|-----------------------------------------------|--------------------|-------------|
| ≥ 3840 × 2160 (4K, typical 32"+)              | 3 × 3              | 9           |
| ≥ 2560 × 1440 (QHD, typical 27")              | 2 × 3              | 6           |
| < 2560 × 1440 (laptop/small external)          | 2 × 2              | 4           |

These thresholds are tunable constants in one file.

**Edge cases:**
- No screen detectable (detached / headless) → fall back to **1×1** (current behavior). Don't crash.
- Window frame crosses two screens → use the one with greatest intersection area (`NSScreen.screens.max(by: intersectionArea)`).
- Ultra-wide monitors (5120×1440, 3440×1440) → classified by whichever threshold they cross on width. A 5120×1440 would hit ≥ 3840 on width but below on height — propose special-case: use `width` for columns, `height` for rows, independently classified. Defer; log as an open question.

## Integration point

`Sources/Workspace.swift:5241` is where the single initial terminal panel is created today. The grid spawn hooks **after** workspace creation, via the same surface-ready pattern as `WelcomeSettings.performQuadLayout` (`Sources/cmuxApp.swift:3775`). The invocation site parallels `TabManager.addWorkspace` → `sendWelcomeWhenReady` at `Sources/TabManager.swift:1170–1177`.

**Why after-creation, not inside `Workspace.init`:**
- Matches the proven welcome pattern.
- Keeps grid spawn async, waiting for the initial Ghostty surface to be ready before further splits.
- Screen detection needs a window, which isn't attached during `Workspace.init`.

## Mutual exclusion with welcome

Welcome-quad (first run ever, `!UserDefaults.bool(WelcomeSettings.shownKey)`) wins. The default grid fires only when `autoWelcomeIfNeeded && select && shownKey == true` — i.e., subsequent new-workspace creations. Gated by its own toggle (see Settings).

## Saved layouts

`TabManager.restoreSessionSnapshot` → `Workspace.restoreSessionLayout` rebuilds the persisted bonsplit tree. The grid default only fires from the `addWorkspace` path, which is already not used during restore. Implicit precedence: saved always wins. **No new code needed for this.**

## Grid construction algorithm

Binary-tree composition (bonsplit uses binary splits). For a `cols × rows` grid starting from `initialPanel`:

```
// Phase 1: horizontal fan to create `cols` columns
panes = [initialPanel]
for i in 1..<cols:
    right = workspace.newTerminalSplit(from: panes[i-1], orientation: .horizontal, insertFirst: false, focus: false)
    panes.append(right)

// Phase 2: vertical fan to create `rows` per column
for col in panes:
    current = col
    for i in 1..<rows:
        bottom = workspace.newTerminalSplit(from: current, orientation: .vertical, insertFirst: false, focus: false)
        current = bottom
```

**Focus:** `focus: false` for all splits; initial top-left retains focus at the end. If any split fails (returns nil), bail silently and leave whatever layout we already produced — partial grid is acceptable, crash is not.

**Total splits:** `(cols-1) + cols*(rows-1)` = `cols*rows - 1`. For 3×3 that's 8 splits; for 2×3 it's 5; for 2×2 it's 3.

## Pane content

All terminals. Unlike the welcome quad (mixed terminal/browser/markdown), the default grid is "parallel work space" — uniform terminal panes. Each inherits:
- Working directory from the source pane (already handled by `inheritedTerminalConfig`).
- Ghostty config template (already handled).
- No auto-command sent (unlike welcome's `cmux welcome` text).

## Settings surface

**UserDefaults key:** `cmuxDefaultGridEnabled` (bool, default `true`). Follows the pattern of `cmuxWelcomeShown` at `Sources/cmuxApp.swift:3759` and `TelemetrySettings` at 3817.

**Central module:** add `enum DefaultGridSettings` adjacent to `WelcomeSettings`:

```swift
enum DefaultGridSettings {
    static let enabledKey = "cmuxDefaultGridEnabled"
    static let defaultEnabled = true

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: enabledKey) == nil { return defaultEnabled }
        return defaults.bool(forKey: enabledKey)
    }

    static func classify(screenFrame: NSRect) -> (cols: Int, rows: Int) { ... }

    @MainActor
    static func performDefaultGrid(on workspace: Workspace, initialPanel: TerminalPanel, screenFrame: NSRect) { ... }
}
```

**UI:** no settings-pane UI added in MVP. Key is observable via `defaults write com.cmux.app cmuxDefaultGridEnabled -bool false`. Settings-pane toggle is follow-up work (not scope-critical).

## TabManager wiring

Mirror `sendWelcomeCommandWhenReady`:

```swift
// Sources/TabManager.swift, after the welcome check at 1170
else if autoWelcomeIfNeeded && select && DefaultGridSettings.isEnabled() {
    if let appDelegate = AppDelegate.shared {
        appDelegate.spawnDefaultGridWhenReady(to: newWorkspace)
    } else {
        spawnDefaultGridWhenReady(to: newWorkspace)
    }
}
```

`spawnDefaultGridWhenReady` is a close copy of `sendWelcomeWhenReady` — same surface-ready dance — but dispatches to `DefaultGridSettings.performDefaultGrid` with the computed `screenFrame` read at dispatch time (not at workspace creation time, since window isn't attached yet).

## Test strategy

1. **Unit test `DefaultGridSettings.classify`** — pure function, table of `(width, height) → (cols, rows)`. Zero friction. Covers all three thresholds + edge (zero rect).
2. **Unit test grid construction helper** — factor the split-sequence loop into a pure function `gridSplitOperations(cols:rows:) -> [SplitOp]`, test shape without a running app.
3. **No `xcodebuild test` locally** (per project memory `feedback_cmux_never_run_xcodebuild_test`). Unit tests run on CI only.
4. **Manual validation** — run `./scripts/reload.sh --tag default-grid`, open new workspace on primary display, verify grid matches classification.

## Rollout

- Behind the `cmuxDefaultGridEnabled` UserDefaults flag, defaulting `true`.
- Escape hatch documented in `docs/` (add one-liner to the config/defaults section).
- Revertible: flip the key to `false` via `defaults write`.

## Files touched

1. `Sources/cmuxApp.swift` — add `enum DefaultGridSettings` (new section ~50–80 LoC near `WelcomeSettings`).
2. `Sources/TabManager.swift` — add `spawnDefaultGridWhenReady` (mirrors `sendWelcomeWhenReady` ~20–30 LoC) and wire the `else if` branch at `addWorkspace`.
3. `Sources/AppDelegate.swift` — add `spawnDefaultGridWhenReady(to:)` (mirrors `sendWelcomeCommandWhenReady`).
4. `Tests/cmuxTests/DefaultGridSettingsTests.swift` — new unit tests.

**Estimated diff size:** ~200 LoC app + ~80 LoC tests.

## Open questions (for user sign-off before implementation)

1. **Ultra-wide monitors (5120×1440):** special-case, or let the width-only classification push them into the 3-col bucket?
2. **Opt-out UX:** UserDefaults-only for MVP OK, or should the settings pane get a toggle?
3. **First-ever new workspace after welcome has run:** if welcome has run (on first launch), does the *next* new workspace get the default grid? (Default: yes, since welcome.shown == true.)
4. **Pane content:** all terminals OK, or should the grid mix browser/markdown like the welcome layout?
5. **Thresholds:** confirm the pixel breakpoints (3840×2160 and 2560×1440). Alternative: use `NSScreen.frame.width` alone and class on width.
6. **Grid aspect fit:** for ultra-portrait monitors (1440×2560, rare), does 2×3 still apply or should it flip to 3×2? (Default: fixed table, don't auto-rotate.)
7. **Config precedence:** if a future workspace-scoped setting says "single pane" but global default is grid, which wins? (Proposal: workspace-scoped wins. Out of MVP scope.)

## Related tickets

- Multi-monitor support (sibling ticket created in parallel). Link with `related_to` after creation.
