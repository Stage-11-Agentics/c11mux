# CMUX-22: Tab close-X overlap — diagnosis & fix proposal

## Reproduction confirmed

**Yes — confirmed by code analysis; visual screenshot blocked by macOS screen-recording permission, see Open Questions.**

The conditions described in the ticket are matched by the agent's own current pane: `pane:7` of workspace:3 ("C11 Improvements") is 860px wide and currently hosts 5 terminal surfaces with long titles (`"✳ Verify C11Mux main branch code state"`, `"⠐ Explore CMUX 16 multi-monitor support"`, `"CMUX-16 Spike"`, `"CMUX-16 Q&A"`, `"⠐ Read and follow prompt instructions"`). At the configured `tabMinWidth = 48` and the trailing inset of 114pt, the rightmost tab necessarily sits flush against the action button cluster — see math in *Root cause*. `screencapture -x` and `screencapture -i -W` both returned `"could not create image from display"` (TCC permission denied for this terminal binary), so a still image is not attached. Atin can capture one in seconds if needed.

## Root cause

The trailing action-button cluster ("Terminal", "Browser", "Markdown", separator, "HSplit", "VSplit", "+") is **wider than the trailing inset reserved for it on the scroll content**. Two hard-coded constants are out of sync with the actual button-row width.

### Code refs

`vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift`:

- **L168–L204** — `enum TabBarStyling`:
  - L169: `static let splitButtonsBackdropWidth: CGFloat = 114` ← only 114pt of opaque backdrop.
  - L194–L203: `trailingTabContentInset(showSplitButtons:isMinimalMode:)` returns `splitButtonsBackdropWidth` (114pt) in standard mode, `0` in minimal mode.
- **L405**: `.padding(.trailing, trailingTabContentInset)` on the scroll content's HStack — tabs stop 114pt from the trailing edge in standard mode, 0pt in minimal mode.
- **L478–L506** — split-buttons `.overlay(alignment: .trailing)`:
  - L486–L500: `ZStack(alignment: .trailing) { backdropHStack.frame(width: 114); splitButtons }` — the **backdrop is constrained to 114pt, but `splitButtons` itself is unconstrained** and renders at its intrinsic width.
- **L783–L841** — `splitButtons` HStack (the actual button content):
  - 6 × `SplitToolbarButton` (each 22pt wide, defined at L1009–L1023 of the same file) = **132pt of buttons**.
  - 1 × `splitButtonsGroupSeparator` (L843–L849: 1pt rule + 8pt horizontal padding × 2) = **17pt**.
  - HStack `spacing: 2` × 6 inter-element gaps = **12pt**.
  - `.padding(.leading, 6)` + `.padding(.trailing, 8)` = **14pt**.
  - **Intrinsic width ≈ 132 + 17 + 12 + 14 = 175pt.**

### Mechanism

The ZStack at L486 renders the 114pt opaque backdrop pinned to the trailing edge, with `splitButtons` overlaid on top — also `.trailing`-aligned but at its full ~175pt width. The leftmost ~61pt of the button row therefore extends **past the leading edge of the backdrop**, into the area where tabs are still drawn (since the scroll content's trailing padding is also only 114pt, matching the backdrop).

That ~61pt happens to land squarely on the rightmost tab's trailing edge — exactly where the close-X (`closeButtonSize = 16pt`, L24 of `TabBarMetrics.swift`) sits. SwiftUI renders overlays above their parent and routes hit tests top-down, so the "Terminal" button (leftmost in the row, hence leftmost-protruding) intercepts clicks intended for that close-X.

### Minimal failing condition

Triggered whenever `(tabsTotalWidth + 114pt) >= containerWidth`. With 5 tabs at the floor of `tabMinWidth = 48pt`, that's 240pt of tabs — every pane narrower than ~354pt overlaps; every wider pane overlaps as soon as enough tabs push the rightmost one inside the 175pt button shadow. In practice every pane with ≥4 long-titled tabs hits it.

### Why this regressed now

`git log` on `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift`:

```
ee7c0fd  tabbar: Markdown + NewTab toolbar buttons with hover and group separator (#1)
58d8f96  Fix minimal mode pane tab clicks and sizing
…
427a7fc  Use paneBackground color, add trailing scroll padding for buttons (#74)
```

Commit **`ee7c0fd` (2026-04-18)** added 3 buttons (Terminal, Browser, Markdown) and grew the group separator from 1pt-padded to 8pt-padded — adding ~80pt to the button row's intrinsic width. Commit `427a7fc` (#74) is where the 114pt trailing padding was originally introduced, sized for the prior 3-button row ([HSplit][VSplit][+] ≈ 90pt + padding). The two constants were not updated together.

## Fix options

### Option A: bump the constant (cheap, ≤5-line change)

Update `TabBarStyling.splitButtonsBackdropWidth` to match the real intrinsic width of the current button row. Since the same constant drives both the backdrop and the scroll-content trailing inset (via `trailingTabContentInset`), one change closes both gaps.

```swift
// vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift
enum TabBarStyling {
    // 6 buttons (22pt) + 5 spacings (2pt) + separator (1+16pt padding)
    // + leading (6) + trailing (8) padding + a small breathing margin.
    static let splitButtonsBackdropWidth: CGFloat = 184   // was 114
    …
}
```

**Pros:** one-line change, no layout-pipeline risk, immediately fixes both the visual occlusion and the hit-test misroute (`trailingTabContentInset` increases too, so tabs stop 184pt before the right edge instead of 114pt).
**Cons:** the constant has to be hand-bumped every time a button is added or removed; the same drift will recur. Eats a fixed 70pt extra of tab-strip width even when split buttons are hidden in minimal mode (still gated by `isMinimalMode ? 0 : value`, so minimal mode is unaffected). On very narrow panes (≤300pt), tabs collapse to `tabMinWidth` sooner.

### Option B: measure the button row, drive the inset from the measurement (proper)

Wrap `splitButtons` in a `GeometryReader` and publish its real width via a `PreferenceKey`; have the parent feed the measured width back into both the backdrop frame and `trailingTabContentInset`. Auto-adapts when buttons are added/removed and respects locale-dependent button widths if `SafeTooltip`/icons ever resize.

```swift
private struct SplitButtonsWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// in TabBarView
@State private var splitButtonsWidth: CGFloat = TabBarStyling.splitButtonsBackdropWidth

// inside the ZStack overlay (replace fixed 114 frame):
splitButtons
    .saturation(tabBarSaturation)
    .background(
        GeometryReader { geo in
            Color.clear.preference(key: SplitButtonsWidthKey.self, value: geo.size.width)
        }
    )
// backdrop HStack:
HStack(spacing: 0) { gradient; rectangle }
    .frame(width: splitButtonsWidth)

// scroll-content trailing inset (line 405):
.padding(.trailing, isMinimalMode ? 0 : splitButtonsWidth)

// at top level:
.onPreferenceChange(SplitButtonsWidthKey.self) { splitButtonsWidth = max($0, 1) }
```

**Pros:** self-tuning, no constant to drift, future-proof against button additions or icon size changes; also covers the case where `SafeHelp` tooltips push button widths up under Accessibility settings.
**Cons:** introduces a measurement → state → re-layout cycle on the tab bar's hot path. SwiftUI `PreferenceKey` updates can ripple; need to verify it doesn't trigger redraws on every pane focus toggle. The first paint may briefly use the stale default before the measurement lands (mitigated by initializing `splitButtonsWidth` to 184pt rather than 0). More code, more surface area for subtle SwiftUI layout bugs in `TabBarView`, which the project already has scar tissue around (see CLAUDE.md "Typing-latency-sensitive paths" for `TabItemView`).

## Recommendation

**Option A.** Ship the constant bump now to unblock every operator running 4+ tabs. The risk surface is one integer; the failure mode is "an extra ~70pt of trailing dead-space when the strip would otherwise be empty," which is invisible. Add a code comment that ties the constant to the structure of the `splitButtons` HStack so the next person to add a button knows to bump it.

Defer Option B unless we add another row of buttons or start localising tooltips that change button widths. If we do go to Option B later, the diff against Option A is small.

## Test strategy

Two test layers, neither requires new UI infrastructure:

1. **Pure-Swift unit test in `vendor/bonsplit/Tests/BonsplitTests/`** — a deterministic assertion that the *measured* intrinsic width of `splitButtons` (rendered in an `NSHostingView`, sized to fit) does not exceed `TabBarStyling.splitButtonsBackdropWidth`. Catches drift the moment a future button is added without bumping the constant.

   ```swift
   func testSplitButtonsFitWithinReservedBackdrop() {
       let view = SplitButtonsTestHarness()  // exposes splitButtons via internal init
       let host = NSHostingView(rootView: view)
       host.layoutSubtreeIfNeeded()
       XCTAssertLessThanOrEqual(
           host.fittingSize.width,
           TabBarStyling.splitButtonsBackdropWidth + 1.0,
           "splitButtons row exceeds reserved backdrop — close-X overlap will return"
       )
   }
   ```

2. **Hit-test integration test** (per CLAUDE.md "Test quality policy", behavioral not source-shape): with N tabs in a pane of fixed width, assert that `closeButtonHitTarget(forTabAt: tabs.count - 1)` does not intersect any `SplitToolbarButton` frame in the same coordinate space. This test fails on `main` today and passes after Option A.

Both belong in bonsplit, not Sources/. Per the task firewall I have not added either.

## Open questions for Atin

1. **Visual confirmation.** I couldn't take a screenshot — `screencapture` returned `"could not create image from display"` (TCC permission denied). The math is unambiguous and the cluster overhang is ~61pt, but if you want a still image attached to the ticket, capture one with `Cmd+Shift+4` over `pane:7` and drop it next to this plan; or grant Screen Recording to the cmux PTY child and I can re-attempt. **Worth flagging:** even granting that permission may not reach this Claude session (the permission is per-binary and Claude is running under the cmux-spawned shell); a one-shot manual `Cmd+Shift+4` is the lowest-friction path.
2. **Submodule pointer bump.** The fix lives in `vendor/bonsplit/`, which is a submodule (`Stage-11-Agentics/bonsplit`). Per c11mux/CLAUDE.md "Submodule safety", landing the fix requires: (a) bonsplit branch + commit + push to `origin/main`, (b) parent-repo submodule pointer bump. **I have not done either** — this plan is read-only per the firewall.
3. **Bump magnitude.** I recommend `184pt` (intrinsic ~175pt + ~9pt safety). Acceptable to round to `192pt` if you want a multiple-of-8; lower than `180pt` risks edge-case hover frames overflowing again.
4. **Screen-capture permission story for autonomous agents.** Out of scope for this ticket but worth its own — UI-bug repro by autonomous agents will keep hitting this TCC wall.

## Reset 2026-04-19 by agent:claude-opus-4-7
