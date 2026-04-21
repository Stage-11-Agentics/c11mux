# C11-6: App chrome UI scale for sidebar and tab text

## Problem

C11 has configurable Ghostty terminal font sizing, but the C11-owned chrome does not have a user-facing UI scale. The immediate dogfooding pain is readability in two places:

- the workspace sidebar card text, especially workspace names and metadata rows
- the top surface tab strip text for individual tabs

These are separate from terminal cell font size. Operators can already tune Ghostty internals, but C11 chrome remains mostly fixed-size and scattered.

## Primary goal

Add an app chrome UI scale setting focused first on the C11 chrome that operators scan constantly: workspace sidebar cards and the top surface tab strip. The result should let an operator make C11 chrome text larger without changing Ghostty terminal font size.

## Scope

In scope for the first implementation slice:

- A persisted C11 App Chrome UI Scale setting in Settings.
- Semantic typography tokens or an equivalent central resolver for C11 chrome text.
- Sidebar workspace card text: title, notification subtitle, agent chip row, metadata/status rows, log/progress labels, branch/directory/PR/port rows, unread/shortcut accessory text where practical.
- Top surface tab strip title text for individual tabs.
- Surface title bar text if it can share the same token cleanly without expanding the PR too much.
- Runtime update without relaunch.

Out of scope for v1:

- Ghostty terminal cells, prompts, scrollback, cursor, and terminal zoom behavior.
- Web page content inside browser surfaces.
- Markdown document content sizing unless the chrome around markdown needs small companion changes.
- A fully comprehensive sweep of every app popover/debug/settings string.

## Bonsplit notes

The top tab strip is Bonsplit-owned UI, but c11 already configures Bonsplit appearance from `Workspace.swift`. Bonsplit exposes `BonsplitConfiguration.Appearance.tabTitleFontSize`, and `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabItemView.swift` renders tab titles from that value.

Prefer the conservative path first: route the C11 UI scale into the existing Bonsplit appearance knob from c11-owned code. Only modify vendored Bonsplit if larger tab text requires paired public knobs for tab height, icon/accessory sizing, min/max width, or hit target geometry. If Bonsplit changes become necessary and are not c11-specific, flag them as upstream candidates.

## Design direction

Use presets rather than a freeform slider for v1:

- Compact: about 0.90x
- Default: 1.00x
- Large: about 1.12x
- Extra Large: about 1.25x

Use semantic tokens rather than raw multiplication at every call site. Candidate tokens:

- `sidebarWorkspaceTitle`
- `sidebarWorkspaceDetail`
- `sidebarWorkspaceMetadata`
- `sidebarWorkspaceAccessory`
- `surfaceTabTitle`
- `surfaceTitleBarTitle`
- `surfaceTitleBarAccessory`

The scale should adjust related layout only where necessary. Bigger fonts should not clip, overlap close buttons, break shortcut hint pills, or make Bonsplit tab dragging harder.

## Acceptance criteria

- Settings includes a localized App Chrome UI Scale control.
- The setting persists and updates live.
- Sidebar workspace card text scales visibly while preserving hierarchy from C11-5.
- Bonsplit surface tab titles scale visibly through the existing appearance path when possible.
- Ghostty terminal font size remains unchanged.
- The selected scale does not cause obvious clipping/overlap in sidebar cards or tab-strip tabs at Compact, Default, Large, and Extra Large.
- User-facing strings are localized in `Resources/Localizable.xcstrings`.
- Tests cover scale resolution/persistence and any pure token math. Do not add source-text grep tests.
- Validation includes a tagged build and visual check of sidebar cards plus surface tab strip.

## Implementation notes

Start with a narrow foundation PR. Add the setting and token resolver, wire sidebar cards, then wire `BonsplitConfiguration.Appearance.tabTitleFontSize` from the same resolver. Reassess only after that whether Bonsplit needs additional public sizing knobs.

