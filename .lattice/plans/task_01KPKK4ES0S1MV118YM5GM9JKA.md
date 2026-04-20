# CMUX-31: Eliminate splitButtons geometry drift bug class (dynamic measurement + test + minimal-mode)

## Consolidation note

This plan replaces three cancelled follow-ups to CMUX-22:

- **CMUX-27** (minimal-mode hover-overlay variant)
- **CMUX-28** (regression-guard test for splitButtons row vs constant)
- **CMUX-29** (Option B PreferenceKey spike)

They merge naturally because the PreferenceKey-driven dynamic measurement (the lead mechanism, née CMUX-29) inherently subsumes the other two. With one measured width driving both the backdrop frame and `trailingTabContentInset`, the minimal-mode hover overlay no longer can shadow tab close-X targets (CMUX-27 dissolves), and the regression test shifts from a fragile "measured ≤ hardcoded" drift check to a strong "measured == applied" invariant (CMUX-28 becomes structural rather than maintenance-driven). This consolidation was authorized by Atin on 2026-04-19.

## 1. Background and bug class

CMUX-22 was iteration #3 of a recurring hand-maintained-geometry drift bug. The same anti-pattern produced this exact bug class three times:

| # | Commit | Symptom | Fix |
|---|--------|---------|-----|
| 1 | `427a7fc` (#74) | Trailing toolbar overhung tabs (initial 3-button row) | Introduced `splitButtonsBackdropWidth = 114pt` reservation |
| 2 | `ee7c0fd` (#1)  | Markdown + NewTab buttons added; row grew 90pt → 175pt; constant not bumped | (latent until reported as CMUX-22) |
| 3 | CMUX-22         | Close-X on rightmost tab intercepted by leftmost-protruding 61pt of buttons row | Bump `114 → 184pt` |

The Trident review pack (`/tmp/c11mux-cmux22/notes/trident-review-CMUX-22-pack-20260419-1452/`) reaches consensus across nine agents (claude/codex/gemini × standard/critical/evolutionary): the diff itself is correct as a tactical patch, but **shipping iteration #3 without an enforcement mechanism makes iteration #4 a near-certainty**. Codex called it "another copy of the layout contract that will rot." Gemini called it "fundamentally broken." Claude called it "the right answer to the wrong question."

The structural cause: `splitButtonsBackdropWidth` is a hand-maintained number that must shadow the intrinsic width of the `splitButtons` HStack. It feeds two co-dependent SwiftUI seams (the opaque backdrop `ZStack.frame` at TabBarView.swift:496, and the scroll-content trailing inset at TabBarView.swift:405 via `trailingTabContentInset` at L194-L204). Adding any button forces the constant to be hand-bumped or the bug returns.

This plan replaces that hand-maintenance with executable measurement.

## 2. Approach — Plan A: PreferenceKey dynamic measurement (lead)

### Existence proof

`TabBarView` already uses a `PreferenceKey` on this exact hot path: `SelectedTabFramePreferenceKey` at TabBarView.swift:50 / 539 / 596 publishes the selected-tab frame back to the view body and is observed via `.onPreferenceChange`. Adding a second PreferenceKey for `splitButtons` width is incremental, not novel — the typing-latency footprint is already paid for in the TabBarView body. This significantly de-risks Plan A vs the abstract "PreferenceKey on a hot path" risk articulated in the CMUX-22 plan.

### Implementation sketch (file: `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift`)

Add a private PreferenceKey near L50, alongside the existing `SelectedTabFramePreferenceKey`:

```swift
private struct SplitButtonsWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
```

Add a `@State` seed inside `struct TabBarView` (near the existing `@State` declarations at L280-L287). Seed value initialized to the Plan-B-derived width (see §3) so first-render geometry is correct without any `splitButtonsBackdropWidth` constant remaining:

```swift
// Seeded from the static derivation in TabBarMetricsActionStrip so the first
// render is geometry-correct before the GeometryReader publishes the actual
// width. Updated by SplitButtonsWidthKey thereafter.
@State private var splitButtonsWidth: CGFloat = TabBarMetricsActionStrip.estimatedRowWidth
```

Replace `trailingTabContentInset` (currently at L322-L327) so it reads the measured width instead of the constant:

```swift
private var trailingTabContentInset: CGFloat {
    showSplitButtons ? (isMinimalMode ? 0 : splitButtonsWidth) : 0
}
```

Inside the trailing `.overlay` ZStack at L478-L506, replace `.frame(width: TabBarStyling.splitButtonsBackdropWidth)` (L496) with `.frame(width: splitButtonsWidth)`, and attach the GeometryReader to `splitButtons`:

```swift
.overlay(alignment: .trailing) {
    if showSplitButtons {
        let shouldShow = !isMinimalMode || isHoveringTabBar
        let backdropColor = Color(nsColor: Self.buttonBackdropColor(...))
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                LinearGradient(...).frame(width: 24)
                Rectangle().fill(backdropColor)
            }
            .frame(width: splitButtonsWidth)            // was: .splitButtonsBackdropWidth

            splitButtons
                .saturation(tabBarSaturation)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: SplitButtonsWidthKey.self,
                            value: geo.size.width
                        )
                    }
                )
        }
        .padding(.bottom, 1)
        .opacity(shouldShow ? 1 : 0)
        .allowsHitTesting(shouldShow)
        .animation(.easeInOut(duration: 0.14), value: shouldShow)
    }
}
```

Subscribe at the existing top-level `.onPreferenceChange` site (next to `SelectedTabFramePreferenceKey` at L539) — same pattern, one extra modifier:

```swift
.onPreferenceChange(SplitButtonsWidthKey.self) { newWidth in
    let clamped = max(newWidth, 1)
    if abs(clamped - splitButtonsWidth) >= 0.5 {
        splitButtonsWidth = clamped
    }
}
```

The 0.5pt diff guard prevents micro-thrash from sub-pixel layout settling on retina vs scaled displays. Without it, every layout pass would write to `@State` and re-publish, which is exactly the ripple risk the CMUX-22 plan flagged.

### Single source of truth (the key invariant)

After this change, `splitButtonsWidth` is the *only* number describing the toolbar's horizontal occupancy. The backdrop frame, the scroll-content trailing inset, and (transitively, in minimal mode) the hover-true hit-test region all read the same `@State`. There is no longer any way for the backdrop and the inset to disagree, because both seams read the same source. This kills the bug class: the next time a button is added, `splitButtons.body` grows, `GeometryReader` measures the new width, both seams update together, and no constant needs maintenance.

### First-render transient (avoiding a one-frame overlap flash)

SwiftUI's measurement loop publishes the GeometryReader value *after* the first body render, so frame 0 uses the seed value. Two things make this safe:

1. **The seed equals the static derivation in §3** (`buttonSize × buttonCount + spacing + separator + padding`), so frame 0 is already geometry-correct for the current button set. The seed only goes stale if a button is added — at which point the very next layout pass corrects it via the PreferenceKey.

2. **No fallback to the old 184pt constant.** That constant is *deleted* in the same change (see §8). Keeping it as a "safety seed" would re-introduce the drift contract we are removing.

The seed is computed from the same private `TabBarMetricsActionStrip` value used in Plan B, so adding a button updates the seed and the dynamic measurement together.

### Files and line numbers to change (Plan A)

- `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift`
  - Add `SplitButtonsWidthKey` PreferenceKey near L50.
  - Add `@State private var splitButtonsWidth` near L280-L287.
  - Replace `trailingTabContentInset` body at L322-L327 to read `splitButtonsWidth`.
  - Replace `.frame(width: TabBarStyling.splitButtonsBackdropWidth)` at L496 with `splitButtonsWidth`.
  - Attach `GeometryReader { ... .preference(key: ...) }` `.background` modifier on `splitButtons` at L498-L499.
  - Add `.onPreferenceChange(SplitButtonsWidthKey.self) { ... }` near the existing one at L539.
  - Update `TabBarStyling.trailingTabContentInset(...)` (L194-L204) to take a `measuredWidth: CGFloat` param, OR remove it entirely and inline (decision in §10).
  - Delete `static let splitButtonsBackdropWidth: CGFloat = 184` at L169 (the CMUX-22 bumped value).

- `vendor/bonsplit/Sources/Bonsplit/Internal/Styling/TabBarMetrics.swift`
  - Add the new `TabBarMetricsActionStrip` private/internal struct (the static derivation, see §3).
  - Remove the `TabBarMetrics.splitButtonsBackdropWidth` alias if CMUX-22 added one (per the CMUX-22 plan's L8 mention; verify presence at implementation time and delete if present).

- `vendor/bonsplit/Tests/BonsplitTests/BonsplitTests.swift`
  - Update `testMinimalModeDoesNotReserveHiddenSplitButtonStrip` (L209-L225) to reference the new measurement seam, since `TabBarStyling.splitButtonsBackdropWidth` no longer exists. Replace the constant comparison with a derivation against `TabBarMetricsActionStrip.estimatedRowWidth`.
  - Add the new regression test (see §6).

## 3. Approach — Plan B fallback: executable static metrics

Use only if Plan A's latency validation (§7) shows measurable typing-latency regression. Codex's "executable metrics" framing from the evolutionary synthesis. Zero SwiftUI state churn; still structural; still kills the drift class — just less elegantly than Plan A.

```swift
// in TabBarMetrics.swift (or as a private value type inside TabBarView.swift)
struct TabBarMetricsActionStrip {
    static let buttonSize: CGFloat = 22                  // matches SplitToolbarButton.frame
    static let buttonSpacing: CGFloat = 2                // matches HStack(spacing: 2)
    static let separatorRule: CGFloat = 1                // matches splitButtonsGroupSeparator
    static let separatorPadding: CGFloat = 8 * 2         // .padding(.horizontal, 8) on both sides
    static let outerLeadingPadding: CGFloat = 6
    static let outerTrailingPadding: CGFloat = 8
    static let backdropGradientWidth: CGFloat = 24       // matches the LinearGradient frame
    static let buttonCount: Int = 6                      // 6 SplitToolbarButtons
    static let separatorCount: Int = 1                   // 1 group separator

    /// Derived width that mirrors what `splitButtons.body` actually renders.
    /// Used as both the runtime backdrop/inset width (Plan B) and the
    /// `splitButtonsWidth` @State seed (Plan A).
    static var estimatedRowWidth: CGFloat {
        let buttons = CGFloat(buttonCount) * buttonSize
        // gaps = (buttonCount + separatorCount) - 1 inter-element spacings.
        // For 6 buttons + 1 separator = 7 children, 6 gaps.
        let gaps = CGFloat(buttonCount + separatorCount - 1) * buttonSpacing
        let separator = CGFloat(separatorCount) * (separatorRule + separatorPadding)
        let outer = outerLeadingPadding + outerTrailingPadding
        return buttons + gaps + separator + outer + backdropGradientWidth
    }
}
```

Under Plan B, `splitButtonsWidth` is replaced by `TabBarMetricsActionStrip.estimatedRowWidth` (a static `var`). The backdrop frame and trailing inset both read it. The `@State` and PreferenceKey are removed. Adding a button bumps `buttonCount` from 6 to 7 and the geometry follows automatically — no SwiftUI ripple, no measurement loop.

The CMUX-28 regression test (§6) still works under Plan B but the invariant shifts:

- **Plan A:** "measured `splitButtons.fittingSize.width` == value flowing through `SplitButtonsWidthKey`"
- **Plan B:** "measured `splitButtons.fittingSize.width` == `TabBarMetricsActionStrip.estimatedRowWidth`"

Both invariants are observable runtime behavior (no source-shape assertion), both fail loudly when a button is added without updating the structure, both meet the project test policy.

## 4. Minimal-mode coverage (CMUX-27 subsumption)

CMUX-27 (cancelled by this plan) flagged that in minimal mode `trailingTabContentInset` returns 0 (TabBarView.swift:196-203 — preserves the no-dead-space invariant when buttons are hidden) but the overlay becomes hit-testable on `isHoveringTabBar` (TabBarView.swift:480, `let shouldShow = !isMinimalMode || isHoveringTabBar`). With the CMUX-22 184pt bump, the hover-true overlay window is now 70pt wider than before, so a user hovering near the rightmost tab to click its close-X has a wider region where the overlay can intercept clicks meant for the tab below. Codex elevated this to Important; Gemini elevated it to a Blocker.

### How Plan A subsumes CMUX-27

In minimal mode, the visible overlay is hit-testable only when `isHoveringTabBar == true`. With Plan A, the overlay backdrop and the buttons are sized to *exactly* the same measured width. The leftmost ~61pt of "buttons protruding past the backdrop" geometry that caused the standard-mode CMUX-22 bug **does not exist anymore in either mode** — the backdrop is the buttons row's bounding box, by construction.

In minimal mode, the question becomes: when `isHoveringTabBar` flips true, does the buttons row appear over a region where the user might be trying to click a tab's close-X? The answer is unchanged from today's behavior — and that behavior is the design intent. Minimal mode trades the no-dead-space invariant for hover-revealed buttons; once the hover is true, the user has chosen to interact with the toolbar region. The CMUX-27 concern was specifically about *unexpectedly wide overlap* (the 70pt extra introduced by the 184pt bump). Plan A returns the overlay width to exactly `splitButtons` intrinsic, which is what the user sees and expects.

### What Plan A does *not* change

The minimal-mode `trailingTabContentInset == 0` rule remains. We are not reserving any inset on hover-true (that would re-introduce the dead-space-when-hidden problem that the comment at TabBarView.swift:200-203 calls out as already-fixed scar tissue). The hover-true overlay is sized correctly to the buttons; that's the entire fix.

### Decision point for Atin (flag before implementation)

If after Plan A lands, operators report close-X clicks on the rightmost tab being intercepted in *minimal mode while hovering*, the next step would be to make the overlay's `.allowsHitTesting` more selective (CMUX-27's option (b)): only the actual button rectangles are hit-testable, not the gradient/backdrop region. This is a downstream tightening, not part of this plan. Surface and decide after observing whether Plan A alone is sufficient.

## 5. Regression test (CMUX-28 subsumption)

Add to `vendor/bonsplit/Tests/BonsplitTests/BonsplitTests.swift`. Renders `splitButtons` in `NSHostingView` and asserts the rendered intrinsic width matches the value applied as the backdrop/inset width. Behavioral, not source-shape. Same `NSHostingView` harness pattern as `testDoubleClickingEmptyTrailingTabBarSpaceRequestsNewTerminalTab` at L676-L719.

### Test seam: extract `SplitButtonsRow` (decision)

`splitButtons` is currently `private` (TabBarView.swift:783). Two options:

- **(a)** Bump `splitButtons` from `private` to `internal`. One-line change. Test imports `@testable import Bonsplit` (already used at L2 of BonsplitTests.swift) and instantiates `TabBarView(...)`, then reaches into `splitButtons` via a small `internal` accessor.
- **(b)** Extract the HStack body (TabBarView.swift:783-841) into a `struct SplitButtonsRow: View` taking the same `controller`, `pane`, `appearance`, `tabBarSaturation` inputs.

**Decision: (b), extract `SplitButtonsRow`.** Reasons:

1. The test wants to render *only* the row, not the entire TabBarView (which requires `BonsplitController`, `SplitViewController`, `PaneState`, etc.). Hosting the full TabBarView for the test is the existing harness pattern (L684) but it measures *the whole tab bar*, not the toolbar row's intrinsic width. The CMUX-28 invariant is specifically about the row's intrinsic width vs the applied seam width.
2. Extracting `SplitButtonsRow` is mechanical (move L783-L841 into a new `struct SplitButtonsRow: View`, pass the four inputs through the initializer, replace the `private var splitButtons` with `SplitButtonsRow(...)`).
3. It opens the door to the `TrailingAccessory` slot extraction (CMUX-30) without forcing it in this plan.
4. It keeps the test independent of the rest of the TabBarView and avoids accidentally measuring `containerGeo`-driven width artifacts.

### The test (≤20 lines of body)

```swift
@MainActor
func testSplitButtonsRowMeasuredWidthMatchesAppliedBackdropWidth() {
    let appearance = BonsplitConfiguration.Appearance(showSplitButtons: true)
    let configuration = BonsplitConfiguration(appearance: appearance)
    let controller = BonsplitController(configuration: configuration)
    let pane = controller.internalController.rootNode.allPanes.first!

    let row = SplitButtonsRow(
        controller: controller,
        pane: pane,
        appearance: appearance,
        tabBarSaturation: 1.0
    )
    let host = NSHostingView(rootView: row)
    host.layoutSubtreeIfNeeded()
    let measured = host.fittingSize.width

    // Plan A: assert the @State-published width tracks fittingSize.
    // Plan B: assert TabBarMetricsActionStrip.estimatedRowWidth tracks fittingSize.
    XCTAssertEqual(
        measured,
        TabBarMetricsActionStrip.estimatedRowWidth,
        accuracy: 1.0,
        "splitButtons row intrinsic width drifted from the structural derivation; " +
        "add the new button to TabBarMetricsActionStrip.buttonCount or the action-strip declaration."
    )
}
```

Both Plan A and Plan B pass this test (Plan A's `@State` is seeded from `estimatedRowWidth`; Plan B uses it directly). Under Plan A, an additional integration assertion can verify the PreferenceKey publishes the same value — but the structural test above is the load-bearing one and is what the CMUX-28 ticket asked for.

### Test policy compliance

This satisfies c11mux/CLAUDE.md "Test quality policy":

- **Observable runtime behavior** — measures `NSHostingView.fittingSize.width` after `layoutSubtreeIfNeeded()`. Real layout, real intrinsic.
- **Not source-shape** — does not count buttons in the HStack textually, does not assert on AST fragments, does not read source files.
- **Has a runtime seam** — `SplitButtonsRow` extraction provides the harness; the test exercises it through that seam.

### Two-commit policy compliance

Per c11mux/CLAUDE.md "Regression test commit policy": land the test in commit (1) against the *current* main (where `splitButtons.body` and `TabBarMetricsActionStrip.estimatedRowWidth` are out of sync because `TabBarMetricsActionStrip` doesn't exist yet — actually, the test cannot exist before the type does, so commit (1) is the test + the type derived to *intentionally wrong* values (e.g., buttonCount = 5) so the test fails; commit (2) corrects the derivation and ships Plan A's PreferenceKey wiring). Alternatively, simulate iteration #4 by setting `buttonCount = 7` in commit (1) (asserting against a 7-button row when only 6 exist) and then setting it to 6 in commit (2). Either approach demonstrates the test catches the bug class.

## 6. Validation strategy for the latency concern

The CMUX-22 plan rejected Plan A on latency-ripple grounds. We need to *prove* before committing.

### Pre-implementation: existence proof (already done)

`SelectedTabFramePreferenceKey` at TabBarView.swift:50 is already on this exact hot path with a per-tab GeometryReader (L593-L601, fires on every tab frame change including during typing-driven tab-title updates). Adding a second PreferenceKey on a single non-ForEach view (`splitButtons`) is incremental at most — likely cheaper than the existing one.

### During implementation: tripwire (Codex evolutionary #5 / Trident Critical #10)

Add a `#if DEBUG` `dlog` line that fires *once per session* when the measured `splitButtons` width differs from the seed by more than 1pt:

```swift
#if DEBUG
@State private var didLogWidthDrift = false
// ... inside .onPreferenceChange:
if !didLogWidthDrift, abs(newWidth - TabBarMetricsActionStrip.estimatedRowWidth) > 1 {
    dlog("tab.splitButtonsWidth.drift seed=\(TabBarMetricsActionStrip.estimatedRowWidth) measured=\(newWidth)")
    didLogWidthDrift = true
}
#endif
```

This is the "tripwire" surfaced in the Trident Evolutionary synthesis (#5 of Best Concrete Suggestions). It costs nothing in release builds, costs one comparison + one boolean check per layout in DEBUG, and surfaces drift the moment a button is added or icon size changes — exactly the moment a future agent would otherwise silently re-introduce iteration #5.

### Empirical validation (manual, with operator)

Two A/B comparisons on a heavy-typing workload (terminal pane with `yes` running, or pasting a multi-line string into Codex):

1. **DEV build with tag `cmux-31-baseline`** built off main with no PreferenceKey wiring. Capture `/tmp/cmux-debug-cmux-31-baseline.log` events for 60 seconds of heavy typing.
2. **DEV build with tag `cmux-31-prefkey`** with Plan A wiring. Capture the same log over the same workload.

Compare `tab.select` / `tab.dragState` / generic re-render entry counts. If Plan A wiring introduces measurable additional log churn during typing (e.g., `splitButtonsWidth.drift` fires more than once, or the existing tab events show ripple), fall back to Plan B.

### Microbenchmark (optional, low priority)

Plan A's worst-case is one `@State` write per layout pass on `TabBarView`. The 0.5pt diff guard (§2) makes this a no-op in steady state. If desired, instrument `body` re-evals via the `TabItemView` `.equatable()` pattern at `Sources/ContentView.swift` (the c11mux-side view that c11mux/CLAUDE.md explicitly calls out as a typing-latency-sensitive seam). But the existence proof + tripwire + manual A/B should be sufficient unless something is anomalous.

### Failure criterion

Plan A is rejected if any of:

- Empirical A/B shows measurable additional log entries on `TabItemView` or `TerminalSurface.forceRefresh` paths during typing that don't appear in baseline.
- The tripwire fires more than once per session (would indicate ongoing re-measurement, not a stable converged width).
- Manual heavy-typing feel test (Atin's call) reveals lag.

Fall back to Plan B in that case. Plan B has zero measurement loop, so it is risk-free on the latency front. The regression test still works under Plan B (§3, last paragraph).

## 7. Constant removal

By the end of this work:

- **`TabBarStyling.splitButtonsBackdropWidth`** at TabBarView.swift:169 — **deleted**. No longer referenced anywhere.
- **`TabBarMetrics.splitButtonsBackdropWidth`** alias (added by CMUX-22 per the CMUX-22 plan; verify presence at implementation time on the `cmux-22-tab-x-fix` branch before this work begins) — **deleted**. The compatibility alias has no compatibility to preserve once both read sites are gone.
- **`TabBarStyling.trailingTabContentInset(...)` at L194-L204** — either takes a `measuredWidth: CGFloat` parameter, OR is deleted entirely and the inline version at TabBarView.swift:322-327 owns the policy. Decision in §10.

The "fallback seed value" the CMUX-31 ticket description mentions becomes `TabBarMetricsActionStrip.estimatedRowWidth` — derived, not a magic number. If we ever need to delete *that* too (because the action set becomes truly dynamic), a future change can switch to a measurement-only path with a pre-published preference value (Loop A / Loop B in the Trident evolutionary synthesis).

## 8. Test file: existing test that touches the constant

`vendor/bonsplit/Tests/BonsplitTests/BonsplitTests.swift:209-225` (`testMinimalModeDoesNotReserveHiddenSplitButtonStrip`) currently asserts:

```swift
XCTAssertEqual(
    TabBarStyling.trailingTabContentInset(showSplitButtons: true, isMinimalMode: false),
    TabBarStyling.splitButtonsBackdropWidth,
    ...
)
```

After this work, the static `TabBarStyling.trailingTabContentInset(...)` no longer makes sense in isolation (it becomes a member function reading `splitButtonsWidth`, or is deleted). Update or rewrite this test to assert the same minimal-mode invariant (zero inset when `isMinimalMode == true`, non-zero when false) using the new seam. The test's name and intent stay; the implementation updates.

## 9. Commit and ship plan

Per c11mux/CLAUDE.md submodule safety: bonsplit commits land on `bonsplit/main` *first*, then the parent c11mux pointer bumps. Do not commit the parent pointer bump until `git -C vendor/bonsplit merge-base --is-ancestor HEAD origin/main` returns 0.

### Sequencing prerequisite

This plan assumes CMUX-22 (the 114→184 bump) has landed on `bonsplit/main`. As of this plan's writing, the CMUX-22 work lives on `cmux-22-tab-x-fix` branches in both repos (parent `ec033f95`, bonsplit `86155d1`) but is **not yet merged to main**. Verify CMUX-22 is on `bonsplit/main` before starting; if not, surface to Atin to land CMUX-22 first. (Mechanically, CMUX-31 *could* skip CMUX-22 entirely — Plan A removes the constant — but the review history, observability, and rollback story is cleaner if iterations land in order.)

### Bonsplit-side commits

1. **Test infrastructure commit** — extract `splitButtons` HStack body into `struct SplitButtonsRow: View` (no behavior change, all read sites still call into it). Update `TabBarView.body` to use `SplitButtonsRow(...)`. Run unit tests via CI (per CLAUDE.md "Never run tests locally").

2. **Failing regression test commit** — add `TabBarMetricsActionStrip` with `buttonCount` deliberately wrong (e.g., 7 or 5) and add the regression test from §6. CI goes red. This is the c11mux/CLAUDE.md "Regression test commit policy" two-commit pattern.

3. **Plan A fix commit** — add `SplitButtonsWidthKey`, `@State splitButtonsWidth`, GeometryReader background on `splitButtons`, `.onPreferenceChange` subscription, change all `.frame(width: TabBarStyling.splitButtonsBackdropWidth)` and `trailingTabContentInset` read sites to read `splitButtonsWidth`. Set `TabBarMetricsActionStrip.buttonCount = 6` (correct value). Delete `TabBarStyling.splitButtonsBackdropWidth` and any `TabBarMetrics.splitButtonsBackdropWidth` alias. Update `testMinimalModeDoesNotReserveHiddenSplitButtonStrip` to use the new seam. CI goes green. Add the `#if DEBUG` width-drift tripwire from §6.

4. **CHANGELOG commit** — add `[Unreleased]` → "Changed" entry to `vendor/bonsplit/CHANGELOG.md`: "Replaced `splitButtonsBackdropWidth` constant with PreferenceKey-driven measurement (CMUX-31; supersedes CMUX-22's tactical 114→184 bump)."

5. Push bonsplit `main`. Verify `git -C vendor/bonsplit merge-base --is-ancestor HEAD origin/main`.

### Parent-side commits

6. **Submodule pointer bump** — `git add vendor/bonsplit && git commit -m "CMUX-31: bump bonsplit pointer for splitButtons dynamic measurement"`. Push.

### Verification

7. **DEV tagged build per c11mux/CLAUDE.md** —

   ```bash
   ./scripts/reload.sh --tag cmux-31-prefkey
   ```

   Manual operator verification: open a 5+ tab pane in a 354pt-wide split (the original CMUX-22 reproduction from `pane:7` of workspace:3 documented in the CMUX-22 plan). Click close-X on the rightmost tab in both standard mode and minimal mode (with hover-true). Assertions pass: close fires; new-tab does not.

   Compare `/tmp/cmux-debug-cmux-31-prefkey.log` against a `cmux-31-baseline` built from `main` for a 60-second heavy-typing run. No measurable additional ripple per §6 acceptance.

### If Plan B fallback path

Replace step 3 with: add `TabBarMetricsActionStrip.estimatedRowWidth` as a static `var`, change all read sites to read it directly, no `@State`, no PreferenceKey, no GeometryReader, no `onPreferenceChange`. Steps 1, 2, 4-7 unchanged. Test in §6 still works (compares `fittingSize` to `estimatedRowWidth`).

## 10. Open questions and decision points

1. **Plan A vs Plan B.** Gated on the latency validation in §6. Default to Plan A based on the existence proof (`SelectedTabFramePreferenceKey` already on the path). Fall back to Plan B if validation surfaces measurable ripple. **Owner: implementer + Atin sign-off after the empirical A/B.**

2. **Minimal-mode UX invariant on hover-true.** Plan A returns the overlay to exactly the buttons row's width, which is *narrower* than today's 184pt-bumped overlay. CMUX-27's concern was the 70pt of extra hit-testable area; Plan A removes that. If operators still report close-X interception in minimal-mode-while-hovering, the next step is selective `.allowsHitTesting` on the actual button frames (CMUX-27 option b). **Owner: Atin to decide whether this is a follow-up the moment Plan A lands, or wait for an operator report.**

3. **Test seam — `SplitButtonsRow` extract vs `internal` bump.** Plan picks the extract for the four reasons in §6. **No further decision needed unless a reviewer pushes back.**

4. **First-render seed value.** Picked `TabBarMetricsActionStrip.estimatedRowWidth` over `TabBarStyling.splitButtonsBackdropWidth` (which is being deleted) and over `0` (which would cause a one-frame backdrop collapse). **No further decision needed.**

5. **Where does `TabBarMetricsActionStrip` live?** Two options: (i) `vendor/bonsplit/Sources/Bonsplit/Internal/Styling/TabBarMetrics.swift` as a sibling enum, public for test access via `@testable`. (ii) Private struct inside `TabBarView.swift`. Recommend (i) for testability and proximity to sibling sizing constants — also satisfies Trident Critical Nit #3 (move the constant to `TabBarMetrics.swift`). **Decision: (i).**

6. **Should `TabBarStyling.trailingTabContentInset(...)` survive as a static function?** Once it needs to read instance state (`splitButtonsWidth`), it is no longer pure. Options: (a) take `measuredWidth: CGFloat` as a parameter (stays pure, callsite passes in `splitButtonsWidth`); (b) delete the static function and inline the computation at TabBarView.swift:322-327. Recommend (a) — keeps the existing test seam (`testMinimalModeDoesNotReserveHiddenSplitButtonStrip`) viable and keeps the policy decision in `TabBarStyling` where its sibling layout policies live. **Decision: (a).**

## 11. Out of scope

- **CMUX-30 (TrailingAccessory slot extraction).** Strategic move to factor c11mux-specific buttons (terminal/browser/markdown) out of bonsplit into a `TrailingAccessory` slot exposed by bonsplit. Being planned in parallel under a separate ticket. CMUX-31 is the **tactical durable answer** (kills the bug class). CMUX-30 is the **strategic architectural answer** (changes who owns the buttons). They compose: once CMUX-31 ships, CMUX-30 inherits the dynamic-measurement primitive and applies it to whatever buttons consumers inject. Doing CMUX-31 first proves the measurement model on the existing bonsplit-owned action strip; doing CMUX-30 second externalizes the buttons without re-litigating the measurement question.

- **The "Toolbar Genome" / declarative action list** (Codex evolutionary #6 / Gemini evolutionary #2 / Claude evolutionary #6). Converting the 6 hand-rolled `SplitToolbarButton` calls into a `[ToolbarActionSpec]` array. Natural follow-on to CMUX-30 once the slot exists. Not in this plan.

- **Responsive-collapse / chrome-budget primitive** (Codex evolutionary #5 / Codex's "Chrome Budget Ledger"). When pane width drops below threshold, low-priority buttons collapse behind a `+` menu. Future architectural work; depends on the data-driven action list. Not in this plan.

- **Agent-driven action injection** (Gemini evolutionary wildest mutation #3). Future thesis-aligned work. Not in this plan.

- **Hit-test heatmap / region log** (Claude/Codex evolutionary #5/#10). DEBUG-only diagnostic that would have made CMUX-22 visible-at-a-glance. Useful generic infrastructure; orthogonal to this plan; the §6 tripwire is a minimal version of it scoped to this one width.

## 12. Firewall and do-nots

- **Plan only at this stage.** No implementation work in this plan agent's session. Implementation is a separate ticket execution.
- **Do not run tests locally.** Per c11mux/CLAUDE.md "Testing policy". All test runs go through CI / GitHub Actions / VM.
- **Do not run `reload.sh` from the plan agent.** No DEV builds during planning.
- **Submodule safety rule** — bonsplit commits push to `origin/main` first, then parent pointer bump. Verify with `git -C vendor/bonsplit merge-base --is-ancestor HEAD origin/main`. Per c11mux/CLAUDE.md "Submodule safety". Never commit on detached HEAD.
- **Do not skip the regression-test-first commit pattern.** The CMUX-28 invariant *must* be demonstrated as a real catch via the two-commit pattern (failing test → fix → test passes). Per c11mux/CLAUDE.md "Regression test commit policy".
- **Localization policy doesn't apply** — no user-facing strings change.
- **Typing-latency rule** — `TabItemView` and `TerminalSurface.forceRefresh` are explicitly listed as latency-sensitive. The validation strategy in §6 is the contract for not regressing them.

---

## Reset 2026-04-19 by cmux-drift-consolidate-1
