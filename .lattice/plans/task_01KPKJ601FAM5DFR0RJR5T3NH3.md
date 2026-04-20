# CMUX-27: Bonsplit minimal-mode hover-overlay variant of CMUX-22

Trident review (codex critical Important #1, gemini critical Blocker #2) confirmed CMUX-22's hit-test bug class is also reachable in **minimal mode**, separately from the standard-mode variant fixed by the 184pt bump.

In minimal mode `TabBarStyling.trailingTabContentInset` returns 0 (vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift:196) but the split-button overlay (TabBarView.swift:480) becomes hit-testable on `isHoveringTabBar` (driven by NSTrackingArea on the tab-bar background). When a user moves the mouse to click the rightmost tab's close-X, the hover triggers the overlay and the now-184pt-wide button cluster intercepts the click.

Three options sketched in the synthesis:
- (a) Reserve trailing inset on hover-true in minimal mode (changes the no-dead-space invariant)
- (b) Make overlay's allowsHitTesting more selective (only over the actual button rects)
- (c) Resolve via Option B PreferenceKey-driven measurement (covered by separate ticket)

Pick after deciding minimal-mode UX intent. Linked from CMUX-22.
