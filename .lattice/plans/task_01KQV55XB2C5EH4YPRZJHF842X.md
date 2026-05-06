# C11-26: Per-surface 30 fps redraw cap

Follow-up to C11-25 (deferred at plan time per operator scope decision 2026-05-04).

The C11-25 ticket called for "no surface can exceed 30 fps redraw, regardless of producer." That criterion was deferred to this ticket because it requires either:
- A libghostty patch (`manaflow/ghostty` submodule) to expose a per-surface frame-rate cap accessor, OR
- A Swift-side throttling wrapper around the surface's `setNeedsDisplay` calls, which reaches into the typing-latency hot path and needs its own design pass.

Either approach needs a dedicated typing-latency review (CLAUDE.md typing-latency-sensitive paths section) before landing.

C11-25 already partially addresses the underlying motivation:
- Non-focused workspaces: libghostty occlusion (`ghostty_surface_set_occlusion(false)`) caps redraws at <2 Hz regardless of producer.
- The remaining case is "spammy producer in a focused surface flooding the renderer."

Recommended approach for design: see C11-25's plan note §2 row "4" and risk callout 5.1 for the prior analysis.

Acceptance criteria (carried forward from C11-25):
- No single surface exceeds 30 fps redraw rate, even with a CPU-pinning producer (e.g. `top -l 0 -s 0`, awk-per-cell radar) running in a focused state.
- Typing-latency hot paths (`WindowTerminalHostView.hitTest`, `TabItemView`, `TerminalSurface.forceRefresh`) preserve their current behavior; no regression.
