# CMUX-28: Bonsplit: regression-guard test for splitButtons row vs splitButtonsBackdropWidth

Trident critical 3/3 consensus, hammered hardest by Codex+Gemini: CMUX-22 is iteration #3 of the same hand-maintained-geometry drift bug (`427a7fc` sized for 3 buttons → `ee7c0fd` grew to 6 → CMUX-22). Iteration #4 is near-certain without an enforcement test.

The plan literally wrote the 4-line test body and chose not to add it (test policy + need to expose private `splitButtons`). This ticket is for adding it.

Suggested approach: render `splitButtons` in NSHostingView and assert `fittingSize.width <= TabBarMetrics.splitButtonsBackdropWidth + 1.0`. Requires either (a) extracting `splitButtons` HStack body into an internal `SplitButtonsRow` struct, or (b) bumping `splitButtons` from `private` to `internal`. Existing harness pattern at vendor/bonsplit/Tests/BonsplitTests/BonsplitTests.swift:684 (NSHostingView + TabBarView).

Per c11mux/CLAUDE.md test policy: must verify observable runtime behavior (the rendered intrinsic width), NOT source-shape (counting buttons in the HStack textually). The `fittingSize.width` measurement passes that bar.
