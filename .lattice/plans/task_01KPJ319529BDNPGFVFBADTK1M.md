# CMUX-20: CMUX-15 follow-up: retina scale, remote guard, latency, diagnostic

## Summary

Follow-up fixes for CMUX-15 (PR #24, already merged). Trident plan review surfaced four straightforward bugs worth shipping as a single follow-up PR, plus three product decisions the author has explicitly accepted as-is (documented below so future agents don't re-litigate).

## Parent ticket

CMUX-15 — "Default pane grid sized to monitor class (3x3 / 2x3 / 2x2)"
Merged PR: https://github.com/Stage-11-Agentics/c11mux/pull/24

## Fixes to ship

### 1. Pixels-vs-points in `DefaultGridSettings.classify()` [CRITICAL]

`NSScreen.frame` returns **logical points**, not physical pixels. On a Retina 32" 4K running a typical HiDPI mode ("Looks like 2560"), `frame.width` = 2560, which misclassifies as QHD → 2×3 grid. Almost no real user currently gets 3×3.

**Fix:** scale the frame by `backingScaleFactor` before classification. In `Sources/cmuxApp.swift`, `DefaultGridSettings.resolvedScreenFrame(for:)` returns the raw `screen.frame` today — scale it:

```swift
static func resolvedScreenFrame(for window: NSWindow?) -> NSRect {
    let screen: NSScreen? = window?.screen
        ?? (window.flatMap(bestScreen(for:)))
        ?? NSScreen.main
    guard let screen else { return .zero }
    let scale = screen.backingScaleFactor
    return NSRect(
        x: 0, y: 0,
        width: screen.frame.width * scale,
        height: screen.frame.height * scale
    )
}
```

**Tests:** add `testClassifyRetina27ScaledProducesTwoByThree` and `testClassifyRetina32ScaledProducesThreeByThree` with a synthetic scaled-up NSRect.

### 2. Remote workspace 9x SSH fan-out [MEDIUM]

`performDefaultGrid` does not gate on remote workspaces. `Workspace.newTerminalSplit` pulls in `remoteTerminalStartupCommand()` per pane — a 9-pane grid on a remote workspace means 9 SSH sessions established at workspace creation.

**Fix:** early-return in `Sources/cmuxApp.swift`, inside `performDefaultGrid`:

```swift
guard !workspace.isRemoteWorkspace else { return }
```

**Why before the split loop:** cheaper than skipping each split and cleaner semantics.

### 3. Drop 0.5s `asyncAfter` on the default-on path [MEDIUM]

Both `AppDelegate.spawnDefaultGridWhenReady` and `TabManager.spawnDefaultGridWhenReady` copy-pasted a `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5)` wrapper from the welcome quad code. Welcome runs once per lifetime; grid runs on **every** new workspace. A perceptible half-second layout lag per Cmd-T is the wrong tradeoff.

**Fix:** remove the `.asyncAfter(deadline: .now() + 0.5)` wrapper in both locations. Call `performGrid(terminalPanel)` or `performDefaultGrid(...)` directly once surface readiness is signalled.

### 4. Silent partial-failure diagnostic [LOW]

`performDefaultGrid` early-returns on split failure with zero signal. Makes field reports ("grid is wrong on X setup") un-debuggable.

**Fix:** wrap the two `return`s inside the `for op in ops` loop with a DEBUG log:

```swift
#if DEBUG
dlog("grid.split.failed col=\(op.column) dir=\(op.direction)")
#endif
return
```

Follow `vendor/bonsplit/Sources/Bonsplit/Public/DebugEventLog.swift` `dlog` convention.

## Decisions documented (NOT fixing)

These trident findings were reviewed and explicitly accepted. Future agents should not re-litigate without new evidence.

### 5A. 3×3 grid produces 50% / 25% / 25% widths, not 1/3 / 1/3 / 1/3 — ACCEPTED

Binary-tree splits from the previous column's tail halve that column each time. Result: `[50, 25, 25]` on a 3-column axis, not `[33, 33, 33]`. Trident flagged as "not really a grid."

**Decision:** accept the skew. The asymmetry is tolerable for the MVP; fixing it requires either a bonsplit ratio API or a post-pass via `BonsplitController.setDividerPosition`, both out of scope. Revisit if users complain.

### 6A. Welcome-to-grid whiplash — ACCEPTED

Day-one UX: 1st workspace ever = 4-pane welcome quad (mixed surfaces). 2nd workspace ever = 4–9 pane all-terminal grid. Visible jump; different content mix.

**Decision:** ship as-is. The grid pattern establishes itself quickly; advanced users (the target audience) will prefer it.

### 7A. Default-on for all existing users — ACCEPTED

Every user's next Cmd-T becomes a grid without opt-in. Trident called this out across all three adversarial reviews.

**Decision:** ship as-is. `defaults write com.cmux.app cmuxDefaultGridEnabled -bool false` is the escape hatch. A Settings-pane toggle is a reasonable follow-up ticket but not a blocker.

## Scope

- Single follow-up PR for fixes 1–4.
- Items 5A, 6A, 7A: no code change. Decisions captured here so they're not re-raised.
- Tests accompany fix 1 (retina scaling). Fixes 2–4 are small enough that pure-function regression tests aren't warranted; DEBUG log assertions are inappropriate. Rely on CI unit tests + manual tag-build verification.

## Non-goals

- Geometry fix for the 50/25/25 bug (5A accepted).
- Settings-pane UI toggle (future ticket).
- Telemetry instrumentation (future ticket).
- Multi-monitor support (CMUX-16).

## Branch + worktree

Worktree: `/tmp/cmux-15-followup/` (or similar)
Branch: `cmux-15-followup` off `main`
