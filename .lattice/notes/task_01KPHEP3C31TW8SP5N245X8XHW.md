# CMUX-12 — Pane title bar chrome & theming

Plan note for whoever picks this up. Visual consumer of CMUX-11's metadata layer.

## The intent in one line

Render pane titles (from CMUX-11's `PaneMetadataStore`) as a first-class centered strip above the pane, parallel in contract to the surface title bar and themed consistently with it.

## Source of truth

Full implementation plan at `docs/c11mux-pane-title-bar-plan.md` (199 lines, 9 locked decisions, three phases, risks). This note is the pick-up brief.

## Hard dependency

**CMUX-11 Phases 1 and 2 must merge first.** This ticket has no data to read until `PaneMetadataStore` exists and agents can write to it. Don't start this ticket until the companion plan is at least through its socket-RPC phase.

## Locked decisions (don't relitigate)

1. Centered title text, mirroring the surface title bar contract.
2. **Optional chrome** — only renders when `pane.metadata.title` is set. Unnamed panes look unchanged. This differs from surfaces, which render chrome even when unnamed.
3. Expand chevron toggles title-only ↔ title + description, matching surface title bar.
4. Dismissible via right-click → Hide. Dismissal is ephemeral session state (`paneTitleBarUserCollapsed`, reset per restart, matching Tier 1's ephemeral-state decision for surfaces). Underlying metadata untouched.
5. Right-click menu: **Rename…** (inline TextField write-back via `pane.set_metadata`), **Hide title bar**, **Expand/Collapse**. Future items (Clear, Copy) deferred.
6. Theming unified with surface title bars via the in-flight c11mux theming plan's tokens.
7. Dual-title rendering when both pane and active surface are named: pane title on top, surface title directly below. Each strip owns its own collapse/dismiss.
8. Bonsplit stays unopinionated — c11mux SwiftUI layers render chrome above the pane, bonsplit itself is untouched.

## Phases (each one PR)

### Phase 1 — `PaneTitleBarView` (visible strip)

First user-visible milestone. Deliverables:

- New view `Sources/Panels/PaneTitleBarView.swift` mirroring `SurfaceTitleBarView` props: `title`, `description?`, `isExpanded`, `onToggle`.
- Pane host container gets an optional title-bar stack above content. When `pane.metadata.title == nil && activeSurface.metadata.title == nil` → no chrome.
- State plumbing: `paneTitleBarCollapsed` / `paneTitleBarUserCollapsed` ephemeral state keyed by `PaneID`.
- Title resolution via `PaneMetadataStore.value(for: .title, pane: paneId)` with observer on the store's revision counter.
- Typing-latency hot-path review mandatory — `PaneTitleBarView` must be `Equatable` and only re-evaluate when title metadata changes. Per project CLAUDE.md: any SwiftUI view added to the pane host is hot-path risk. Match `TabItemView` `.equatable()` pattern in `ContentView.swift`.

### Phase 2 — Context menu + inline rename

- Right-click menu with Rename / Hide / Expand-Collapse.
- Rename flow: strip flips into an inline `TextField` populated with current title, writes via `pane.set_metadata` on Return, cancels on Escape or click-away.
- First-class operator UX without dropping to CLI.

### Phase 3 — Theming token unification

- Consume theme tokens from whatever the theming plan establishes (CMUX-9 territory).
- Phase 1 ships with ad-hoc parity to surface title bars; Phase 3 migrates to formal tokens when they land.
- Don't block on theming plan settling — Phase 1 can stand alone.

## Risks (from the plan doc — carry them forward)

- **Typing latency.** Any SwiftUI view in the pane host is hot-path risk. Mitigation: strict hot-path review in Phase 1; equatable view; read-only title state captured at render time, not in a body closure.
- **Chrome proliferation.** Multi-surface panes stack pane title + surface titles + tabs. Mitigation: decisions 2 (optional) and 4 (dismissible) let operators trim to taste.
- **Theming plan churn.** Phase 3 depends on the theming plan's final token shape. Mitigation: ship Phase 1 with ad-hoc parity; migrate in Phase 3.

## Localization

All new strings via `String(localized: "key.name", defaultValue: "…")`. Keys needed: `pane_title_bar.menu.rename`, `pane_title_bar.menu.hide`, `pane_title_bar.menu.expand`, `pane_title_bar.menu.collapse`, `pane_title_bar.rename.placeholder`. English + Japanese translations in `Resources/Localizable.xcstrings`.

## Tests

- `cmuxTests/PaneTitleBarViewTests.swift` — view renders under set title; hides under nil title; expand/collapse transitions.
- `cmuxTests/PaneTitleBarRenameTests.swift` — rename flow writes through to `PaneMetadataStore`; Escape cancels; empty commit clears.
- No `xcodebuild test` locally (per project policy); CI-only.
- Manual validation: `./scripts/reload.sh --tag pane-title-bar`, set a title via CLI, observe chrome; right-click → Rename.

## Size estimate

3 PRs. Phase 1 ~250 LoC; Phase 2 ~200 LoC; Phase 3 ~80 LoC (mostly token plumbing) + localization.

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Confirmed plan doc is detailed. Pick-up note pins the hard dependency on CMUX-11, the hot-path risk, localization keys, and phase-to-PR mapping.
