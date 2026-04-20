# CMUX-18: Markdown surface: user-configurable light/dark theme

The markdown surface already has light and dark modes, but theme selection is not user-configurable. The current light mode looks good; the current dark mode does not. Add user-configurable theme selection (starting with light/dark as the minimum set). This is the starting point for a broader markdown theming system that may eventually include GitHub-style, Dracula, Solarized, etc.

Scope (MVP):
- User can toggle between light and dark on any markdown surface
- Setting persists as a surface property (surface manifest key, e.g. markdown_theme)
- Default mode respects system appearance or an app-level default

Out of scope (for now):
- Full theme library beyond light/dark
- Per-document overrides via frontmatter
- Integration with the broader per-surface theme button (see sibling ticket)

Clarifications from discussion (2026-04-18):
- Theme is a surface property (travels with the surface, not tied to pane slot).
- Starting with the existing light/dark primitives rather than building a new theme system from scratch.
