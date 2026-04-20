# CMUX-10 — Flash the sidebar tab selector, not just the pane — themable flash colors

Plan note for whoever picks this up. Task-level fidelity.

## The intent in one line

`cmux trigger-flash --surface <ref>` should flash the sidebar tab for that surface's workspace, not only the pane content — so an attention signal lands even when the surface is off-screen.

## Problem statement

Today, flashing fires inside the pane via `GhosttyFlashOverlayView` mounted on `GhosttySurfaceScrollView`. When the target surface is in an unfocused workspace (or inside a non-selected tab group), the flash paints pixels nobody's looking at. "Look here" becomes invisible — defeating the primitive.

## Where the work lives

### Current flash path

- Protocol: `Panel.triggerFlash()` at `Sources/Panels/Panel.swift:92`.
- Conformers: `TerminalPanel.triggerFlash()` at `Sources/Panels/TerminalPanel.swift:230`, `BrowserPanel.triggerFlash()` at `Sources/Panels/BrowserPanel.swift:2854`, `MarkdownPanel.triggerFlash()` at `Sources/Panels/MarkdownPanel.swift:134`.
- Workspace fan-out: `triggerFocusFlash(panelId:)` at `Sources/Workspace.swift:8275`, `triggerNotificationFocusFlash(panelId:requiresSplit:shouldFocus:)` at `Sources/Workspace.swift:8279`.
- Flash rendering lives on the AppKit side: `GhosttyFlashOverlayView` at `Sources/GhosttyTerminalView.swift:6180` (+ `flashOverlayView`/`flashLayer` fields on `GhosttySurfaceScrollView` at 6237–6238). `FlashStyle` enum at 6219.
- Socket command dispatch: keyboard shortcut + command palette entry `palette.triggerFlash` at `Sources/ContentView.swift:4875-4876`, `5152-5154`, `5775`.

### Sidebar tab selector

The sidebar tab views (the row representing a workspace in the sidebar) are in `Sources/ContentView.swift` — grep for `SidebarTab` / `WorkspaceTabItem` to locate the row component. Needs a second flash-capable overlay; model the API after `GhosttyFlashOverlayView` so the visual idiom is consistent.

## Sequence of changes

1. **Add a flash surface to the sidebar tab row.** Either a small `CAShapeLayer` overlay on the row's NSView backing, or a SwiftUI modifier whose opacity is driven by a published state on `Workspace`. Prefer the layer approach for parity with the pane flash — the animation curve needs to match.
2. **Extend `Workspace.triggerNotificationFocusFlash`** (or add a sibling method) so it fires both the pane flash and the sidebar tab flash. The call is already workspace-scoped; pass through a flag for "also flash the sidebar tab" default-true, false for debug flash palette entry.
3. **Themable color token.** Add `flash.color` (and optionally `flash.sidebarColor` if they diverge) to the theme schema under construction in `docs/c11mux-theming-plan.md`. Default color is whatever the current flash paints. When the theming engine lands (CMUX-9 territory), the flash reads from `C11muxTheme.flash.color`.
4. **Socket/CLI plumbing.** `cmux trigger-flash --surface <ref>` already exists — confirm the dispatch path reaches `Workspace.triggerNotificationFocusFlash`. No CLI surface changes needed if the sidebar flash fires automatically on the same path.
5. **Respect the user toggle.** `settings.notifications.paneFlash` at `Sources/cmuxApp.swift:4498-4505` disables the pane flash. The sidebar tab flash should respect the same toggle — don't add a second knob for v1.

## Non-goals

- Do not flash the Ghostty terminal content itself (cell rendering is Ghostty's; the flash is chrome).
- Do not flash the macOS window frame / traffic lights.
- Do not add a separate sidebar-only toggle — ride on `paneFlash`.

## Relationship to the theming epic

This ticket should be `related_to` the theming epic (CMUX-9) once that ticket settles. Depends on the theme engine foundation if flash color becomes a theme token; the sidebar flash behavior can land independently with a hardcoded color and get retrofitted.

## Tests

- `cmuxTests/SidebarFlashTests.swift` — trigger a flash on a workspace; assert the sidebar row's flash state toggles and returns to resting state within the expected duration.
- `tests_v2/test_trigger_flash_sidebar.py` (new) — from outside the app, `cmux trigger-flash --surface <ref>` on a surface whose workspace is not currently selected, assert the socket returns success (visual assertion is manual for v1).
- Manual validation: `./scripts/reload.sh --tag sidebar-flash`; create two workspaces; switch to workspace A; from a pane in A, `cmux trigger-flash --surface <B's surface>`; observe B's sidebar tab flash.

## Size estimate

~120 LoC app + ~80 LoC tests. Single PR. Larger if the theming token work is bundled — split that into a follow-up if CMUX-9 hasn't settled yet.

## Open questions

- [ ] Flash color sibling: single `flash.color` or `flash.pane` + `flash.sidebar` pair? Atin's call once the theming plan settles.
- [ ] Default color: keep current tone, or drop in an early sketch of the `$workspaceColor` derivation from the theming plan?
- [ ] Animation curve: match pane flash exactly, or do a slightly gentler sidebar pulse to avoid dueling pulses?

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Added concrete file:line anchors for the existing flash surface, a sequenced change list, test plan, and positioned the ticket relative to the theming epic.
