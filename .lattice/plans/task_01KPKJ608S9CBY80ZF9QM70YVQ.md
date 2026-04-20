# CMUX-29: Bonsplit: dynamic measurement for splitButtons trailing inset (Option B)

Trident evolutionary 3/3 consensus: replace `TabBarMetrics.splitButtonsBackdropWidth` (a hand-maintained constant) with PreferenceKey-driven dynamic measurement of the actual splitButtons row.

Documented in the CMUX-22 plan (Option B). Rejected for the immediate fix because of perceived layout-pipeline risk (TabBarView is on a typing-latency-sensitive path per c11mux/CLAUDE.md), but the right durable answer.

Sketch:
```swift
private struct SplitButtonsWidthKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

@State private var splitButtonsWidth: CGFloat = TabBarMetrics.splitButtonsBackdropWidth
splitButtons.background(GeometryReader { geo in Color.clear.preference(key: SplitButtonsWidthKey.self, value: geo.size.width) })
backdropHStack.frame(width: splitButtonsWidth)
.padding(.trailing, isMinimalMode ? 0 : splitButtonsWidth)
.onPreferenceChange(SplitButtonsWidthKey.self) { splitButtonsWidth = max($0, 1) }
```

Spike: validate no `onPreferenceChange` ripple on typing-latency-sensitive paths. If clean, also resolves the minimal-mode variant (CMUX-XX) by being the single source of truth.
