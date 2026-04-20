# CMUX-19: Per-surface theme button (right-click menu)

Add a per-surface theme override mechanism. Each surface (terminal, markdown, etc.) can have its own theme that overrides the global Ghostty theme. Accessible via right-click context menu on the surface (not top bar chrome).

Design principles (from discussion 2026-04-18):
- Theme is a SURFACE property, not a pane-slot property. Travels with the surface if moved. Rationale: surfaces are the action; operator on a small screen may have very different work in each surface and wants them visually distinguishable (e.g., prod red, staging yellow, scratch Dracula).
- Default behavior: all surfaces inherit the global Ghostty theme (current behavior).
- Override: right-click → "Theme…" opens a picker. Overriding marks the surface as having a theme override — sticky until cleared.
- UI placement: right-click menu first (discoverable, non-intrusive). Theme button in top bar of every pane is too much chrome for a rarely-touched action.
- Unified entry point across surface types: same context menu item, picker content varies by surface type (terminal → Ghostty themes; markdown → markdown themes — see sibling ticket CMUX-N for markdown themes).

Implementation notes (not prescriptive):
- Ghostty accepts per-surface config; leverage that for terminal surfaces.
- Surface manifest key (e.g. theme_override) stores the selection.
- Clearing the override returns the surface to global-theme inheritance.

Tradeoff named in discussion: unified global palette (calm) vs per-surface identity (circus tent). Opt-in override model preserves both options: calm by default, distinguishable when the operator wants it.
