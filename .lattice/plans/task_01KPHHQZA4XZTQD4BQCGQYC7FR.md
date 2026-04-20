# CMUX-16 Spike: Pane-first c11mux (Emacs-frames model)

> **Public charter (v3):** CMUX-25 elevates **panes** to first-class, stable, mobile identities in c11mux. They hold their own IDs, persist across sessions, and can move between frames and windows without lifecycle churn. Multi-frame / multi-window (Emacs-frames) is the first consumer of that primitive; v1.1 unlocks (pane attach, frame mirror, broadcast, workspace.present) follow from the same foundation. The product story is the primitive elevation; "multi-window" is the outward-facing demo.

Written 2026-04-19 against `main @ 520ea766` after survey of `Sources/AppDelegate.swift`, `Sources/TabManager.swift`, `Sources/Workspace.swift`, `Sources/SessionPersistence.swift`, `Sources/TerminalController.swift`, and `vendor/bonsplit/`.

**Revised 2026-04-19: CMUX-16 open questions resolved — see per-section changes and new sub-ticket list below.** Key shifts: (a) no formal cross-display latency target at v1; (b) per-window independent sidebars at v1, but data structures must allow a future sync/primary-sidebar mode; (c) no runtime hibernation — windows stay alive; display affinity tracking + hotplug auto-restore pushed to a v2 follow-up (outside the v1 envelope); (d) spread uses ceil(N/D) fill-leftmost; (e) `workspace.move_to_window` renamed to `workspace.move_frame_to_window` in Phase 2 with a deprecation shim on the old name; (f) super-workspace stays backlog; (g) sidebar-edge configurability is a logged v1.1 wishlist, not in Phase 4.

**Revised 2026-04-19 (second pass): sub-ticket structure consolidated.** Per Atin's redirect, the six proposed sub-tickets (originally 16a–16f) are folded into a **single phased implementation ticket** rather than six separate tickets. The six phase scopes are preserved verbatim inside that ticket's description; the six `CMUX-16a`..`CMUX-16f` labels are retired in favour of phase numbering (Phase 1..6). Two new tickets created: **CMUX-25** (v1 phased implementation) and **CMUX-26** (v2 hotplug follow-up). CMUX-23 and CMUX-24 (the first two split tickets) were created briefly and then cancelled as superseded.

**Revised 2026-04-19-PM (third pass): nine-reviewer pack resolutions applied.** Trident review pack (3 standard + 3 adversarial + 3 evolutionary, plus 3 syntheses) at `.lattice/plans/cmux-25-plan-review-pack-2026-04-19T1511/` triaged with Atin and folded in. Key shifts: (a) **Pane-first c11mux** — the public charter reframes around panes becoming first-class, stable, mobile identities; multi-frame is one consequence. (b) Lifecycle owner clarified — Surface owns the runtime objects (PTY, Ghostty, MTL); Pane is a grouping primitive. Pane-level scrollback is the durable artifact carried across hibernation/migration. (c) `FrameID` becomes a first-class UUID with `{workspace_id, window_id}` as fields — v1 enforces one frame per tuple at the API layer, but the door stays open for v1.1 mirror/present without an identity refactor. (d) `PaneAttachment` ledger lands at Phase 2 as the fact table for pane↔frame relations. (e) Single-home panes for v1 — `workspace.spread all_on_each` cut. (f) Phase 2 estimate honest at 3 weeks with day-10 tripwire; total v1 envelope 7–9 weeks. (g) Phase 2 broken into 4 revertible sub-PRs with documented ordering. (h) Session schema v2 enumerated as a field table with explicit migration framework. (i) `CMUX_MULTI_FRAME_V1` flag is UX-gated only and exposed in Settings; retires ≥30 days after Phase 6 with no open P0s. (j) `SidebarMode.primary`/`.viewport` stubs and `broadcastSelection` no-op deleted from v1; only `.independent` ships. (k) Close-window destroys panes with the window (today's behavior preserved); empty-window state shows a "New Workspace" CTA. (l) Socket focus policy section + multi-host resolver default ("caller's window wins; fall back to MRU") + 4-monitor positional alias rule + cross-window drag-drop acceptance matrix + Phase 1 perf canary + Phase 2 test matrix all enumerated. (m) Stable `pane:` / `frame:` / `workspace:` / `surface:` / `display:` / `window:` ref scheme published as a public contract at Phase 2. (n) Group 3 evolutionary wishlist captured at `docs/cmux-25-v1.1-wishlist.md`. Accessibility is an explicit non-goal at v1. Dogfooding is non-gate; the Settings toggle is the validation surface.

## Primitive hierarchy (locked)

**Window** (NSWindow, macOS-level) **→** has a **Sidebar** (window-local UI, selects what the window hosts) **→** selects a **Workspace** (process-scoped logical container — name, git branch, status pills, owns a set of Panes) **→** rendered in this window via a **WorkspaceFrame** (one bonsplit tree per `FrameID`, leaves reference pane IDs) **→** **Panes** (process-scoped in a `PaneRegistry` — durable identity + layout grouping, carry pane-level scrollback as a promoted aggregate) **→** each pane holds one or more **Surfaces** (process-scoped; PTY, Ghostty surface, MTL layer, and other runtime objects live here — the Surface is the runtime owner).

**Runtime ownership clarification.** PTY, Ghostty controller, and MTL layer live on the **Surface**. The **Pane** groups 1..N surfaces (tabs), carries a stable `pane:<UUID>` identity and the durable pane-local metadata blob, and owns aggregates that outlive any one surface — chiefly **scrollback** (relevant for CMUX-26 hibernation: the pane hibernates as a unit, carrying surface scrollback snapshots with it). Plan text in earlier revisions that said "pane owns PTY/Ghostty/MTL" was incorrect against both the locked hierarchy and the current code shape — amended here.

**FrameID as first-class UUID.** Every `WorkspaceFrame` has a `FrameID: UUID` as its identity; `{workspace_id, window_id}` are carried as **fields** on the frame record, and the API layer enforces a "one frame per `(workspace_id, window_id)` tuple" invariant at v1. This keeps v1 semantics simple (the tuple uniquely maps to a frame) while avoiding an identity refactor through every socket call, session snapshot, and placement event when v1.1 features that relax the invariant land (frame mirror, frame present, future sync mode).

**Pane single-home at v1.** Each Pane is attached to exactly one `WorkspaceFrame` at a time. Moving a pane across frames is unlink-and-link (pane registry untouched; scrollback carried). Multi-homed panes (a pane rendered into two frames simultaneously) are out of v1 scope — they require an offscreen-texture / IOSurface / view-proxy multi-renderer abstraction that would blow Phase 2 past any honest estimate. `workspace.spread all_on_each` is cut from v1 as a consequence (see §Socket API additions); the mode moves to v1.1 when multi-viewer is properly designed.

**Stable ref scheme (public contract at Phase 2).** Named identifiers — `pane:<UUID|short>`, `frame:<UUID|short>`, `workspace:<UUID|short>`, `surface:<UUID|short>`, `display:<display-id|position|index>`, `window:<UUID|short>` — are published as a stable, versioned socket contract at Phase 2. Breaking changes require a new scheme version. This unlocks third-party automation, agent SDK targeting, and NSUserActivity / Spotlight integration down the line. The refs are already in the wild (cmux skill, agent scripts); publishing the contract codifies existing reality rather than opening a new surface.

Tabs are the UI affordance when a pane holds multiple surfaces; a pane with one surface renders no tab bar. Tabs ≠ surfaces strictly — tabs are the rendering, surfaces are the content.

## Decision summary

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| 1 | Workspace model | **Hybrid C:** workspace is a process-scoped logical container; each window holds a `WorkspaceFrame` (= a bonsplit tree) whose leaves reference panes in a shared registry | Keeps bonsplit's single-tree contract intact while letting one workspace's panes span windows. The boundary is the pane registry, not the split tree |
| 2 | Sidebar topology | **Per-window independent sidebars at v1; data shape extensible for a future 'sync' mode** | Per-window independence matches the parallel-agents north star (different workspace per monitor). Phase 4 ships only `.independent`; `broadcastSelection` stubs and `.primary` / `.viewport` enum cases are NOT in v1 (Resolution G1.13) — sync mode is designed and built when it actually ships. Sidebar edge configurability (left/right per window) logged in `docs/cmux-25-v1.1-wishlist.md` |
| 3 | Cross-window drag-drop | **Ship at v1** (extend existing bonsplit gesture) | `.ownProcess` pasteboard visibility already allows intra-process cross-window; `AppDelegate.moveSurface` / `locateSurface` already walk all windows. Fall back to CLI-only if a blocking AppKit issue surfaces late |
| 4 | Focus model | **Per-window focused pane; Cmd+~ does NOT re-focus** | Parallel-agents case: cycling windows should land on the pane you were last using *there*. Matches Xcode/Safari/Finder |
| 5 | Split-into-new-window | **Opt-in** (`cmux new-split --overflow-to-display <ref>` / `--spawn-window`) | Auto-overflow is surprising; we already avoid it in CMUX-15's grid. Optional UI hint when a split would fall below minimum pane width |
| 6 | Session restore / hotplug | **v1: session restore per-display (already ~80% there). No runtime hotplug tracking at v1** — windows stay alive and let macOS migrate them when a display disconnects. Display affinity tracking + auto-reconnect restore is a v2 follow-up ticket outside CMUX-16 | Atin's direction: deliberately scope v1 to "user spawns windows and assigns them to monitors manually." Defer intense system-integration work (hotplug, affinity, hibernation) to a v2 ticket once v1 has soaked |

## 1. Workspace model

The keystone. Three options:

- **A. Workspace-as-top-level, one bonsplit tree spanning NSWindows.** Window edges would become split boundaries inside one tree. Bonsplit today is a single `SplitNode` tree rendered inside one `PaneContainerView`. Treating NSWindow boundaries as tree-internal dividers forces rewriting bonsplit's rendering assumption that each tree owns one SwiftUI view hierarchy. Rejected: bonsplit is a shared primitive across c11mux's split and tab surfaces; widening its contract for this one feature is the wrong trade.
- **B. Workspace-per-window + super-workspace.** Each window keeps its own workspaces; a super-workspace is a metadata grouping. Cheap; abandons the north star — it's just a label, not connection. Moving a pane between "siblings" is still a workspace migration, not a pane migration inside one workspace. Rejected.
- **C. Hybrid (recommended).** Panes become first-class process-scoped objects in a `PaneRegistry`. A `Workspace` owns a set of PaneIDs plus one or more `WorkspaceFrame`s. A `WorkspaceFrame` is what a single NSWindow renders for that workspace — it holds a local `BonsplitController` whose leaves reference PaneIDs. Moving a pane across windows = unlink the leaf in frame A, link it as a leaf in frame B; the Pane object itself (durable identity, pane-local metadata, scrollback) is untouched. Closing a window destroys that window's `WorkspaceFrame`s and the panes attached to those frames (Resolution G2.5-a: today's behavior preserved at v1; parked/headless registry state is explicitly NOT in v1 scope). If a workspace is hosted in another surviving window, that frame continues to hold its own panes — it is the **per-window frame** whose panes die with the window, not the workspace at large. Pane-level scrollback is carried whenever a pane is *moved* between frames; it is not preserved when a pane's frame is destroyed by a window close.

**Cost of C:** every call site that reaches `workspace.panels[panelId]` today routes through the registry. `Workspace.bonsplitController` is replaced by `WorkspaceFrame.bonsplitController`. `TabManager.tabs: [Workspace]` gives way to a process-scoped workspace registry and a window-local projection. The refactor includes introducing a `PaneAttachment` / `PanePlacement` ledger (~50 lines + serialization) — a fact table mapping each pane to the frame it is currently attached to, its leaf path inside that frame, and its ordering hint. The ledger is the single source of truth for "which pane is where"; `tree --by-display`, `pane.move`, `workspace.spread`, placement events, and CMUX-26 hotplug all read/write through it. Rough estimate: **7–9 weeks total for v1** across 6 phases (see Implementation tickets below); Phase 2 is the heaviest at 3 weeks with a day-10 tripwire.

**Why C is worth it:** it gives the Emacs-frames property exactly — multiple viewports onto shared pane state — without asking bonsplit to be something it isn't. The existing `moveWorkspaceToWindow` / `moveSurface` primitives already hint at this: `Workspace.detachSurface(panelId:)` returns a `DetachedSurfaceTransfer`, and `AppDelegate.moveSurface` walks windows to locate surfaces. C is the natural generalisation.

## 2. Sidebar topology

**v1 choice: per-window independent sidebars.** Each window has its own left-edge sidebar showing the full workspace list. Window A can show "Backend" while window B shows "Agents" while window C shows "Browser" — three monitors, three contexts, one c11mux brain. Panes in a single workspace can still span windows via drag / `pane.move` / `workspace.spread`. This is Emacs-frames exactly: multiple viewports, independent selection, shared underlying state.

Split the current `SidebarState`/`SidebarSelectionState`:

- **Process-scoped (shared):** workspace registry (names, status pills, progress bars, git branch, ports), pane registry summaries, notification counts. Lives on `AppDelegate` as an `@MainActor` observable store; no reconciliation needed — single source of truth.
- **Window-local:** sidebar visibility, sidebar width, selected workspace for *this window* (drives which `WorkspaceFrame` the window renders), sidebar scroll position, `sidebarMode` (single-case `.independent` at v1; enum type exists so future minors can extend without a schema break — but no stub cases, see Resolution G1.13 below).

Reconciliation model: zero. The shared store publishes; each window's sidebar subscribes. When the user creates/renames/closes a workspace, every window's sidebar updates automatically via Combine.

### Defer sync/primary mode cleanly — do NOT stub it at v1 (Resolution G1.13)

Atin's direction (second pass): ship independent-per-window at v1 and carry the *data* seams for a future sync mode. Third-pass review convergence from all three reviewers: the half-wired `.primary` / `.viewport` enum cases and the `broadcastSelection` no-op stub are YAGNI-shaped footguns, not seams. They get read by agents, skills, and future developers as "this almost works" and invite incorrect assumptions. **Delete them from v1.** Design sync mode when it ships — not before.

Concrete v1 shape:

- `SidebarMode` enum on `WindowScope` is a single-case enum at v1: `.independent`. Forward compatibility on decode: unknown values deserialize to `.independent` and emit a `dlog` warning once per process. The enum type exists so that a future v1.x minor can add cases without a schema break; the no-op stubs do not.
- **Remove** `broadcastSelection(from:to:)` entirely. Not a stub, not a no-op — no method, no call sites, no tests. It re-enters the codebase when sync mode is actually designed.
- Session persistence (`SessionWindowSnapshot`) serialises `sidebarMode` as a string token. v1 persistence round-trips only `.independent`; any other token on load is coerced to `.independent` with a one-time warning.

**Session persistence / reload:** the per-window selected workspace must round-trip cleanly. On relaunch, each window re-hosts its last-selected workspace from the process-scoped registry. If the workspace is missing (deleted between sessions) or no workspace is selected, the window shows an explicit **"New Workspace" CTA** state (Resolution G2.7) with actions: *New Workspace*, *Open Recent*, *Drag a Workspace Here*. No silent creation, no crash, no silent re-parenting. Covered by the Session schema v2 migration (see §Session schema v2 below).

Sidebar edge configurability (left / right per window, useful on a 3-monitor row where outer sidebars on outer edges would feel natural) is a **v1.1 wishlist item**, not in 16d. Logged in Incidental findings.

Extension: sidebar gets a small badge showing how many windows currently host a frame for this workspace (`⧉ 3`). Click the badge to jump-focus the next window hosting that workspace. v1 can ship without the badge.

## 3. Cross-window drag-drop

AppKit constraints:

- `NSDraggingSession` started in any window **enters other windows of the same process** as a first-class drop target. No special cross-window API needed.
- `NSItemProvider` registered with `.ownProcess` visibility **allows intra-process consumers**, including drop targets in sibling windows. It only blocks *other* processes. `TabTransferData`'s `sourceProcessId` check likewise accepts any drag from this pid.
- `UTType.tabTransfer` and `com.cmux.sidebar-tab-reorder` are declared in `Resources/Info.plist` under `UTExportedTypeDeclarations` (CLAUDE.md pitfall note), so drop targets in every window already register them identically.
- `AppDelegate.moveSurface(panelId:toWorkspace:...)` already walks `mainWindowContexts.values` via `locateSurface`. The drop resolver is cross-window today; the gesture has never been exercised across windows because until now workspaces were window-owned.

**Conclusion: cross-window drag-drop should work at v1 with minimal code change.** Action items in Phase 3's implementation scope:

- Audit `draggedOntoWindow` / `firstResponder` swizzles in `AppDelegate.swift` for accidental window-scoping.
- CLI `pane.move` is always the supported fallback path — if any scenario below routes to CLI, the user flow is still complete.
- If a blocking AppKit issue surfaces (e.g. drop target geometry not updating when the sibling window is offscreen), fall back to CLI-only cross-window move and reinstate drag at v1.1. The architecture doesn't depend on drag being the primary path — it's ergonomic sugar.

**Acceptance matrix (Resolution G1.18).** Each of the following must pass before Phase 3 ships drag-to-migrate; otherwise the failing scenario routes to CLI fallback with a user-visible message.

| # | Scenario | Expected |
|---|----------|----------|
| 1 | Two visible windows, same Space, same display | Drag commits; pane re-attaches in target frame; source frame re-layouts |
| 2 | Two displays, different resolutions/scales | Drag commits; drop-target rect resolves under the correct retinafactor; no render artifact |
| 3 | Target window minimized | Drag routes to CLI fallback or fails fast with "target minimized — use `cmux pane move`" toast |
| 4 | Cross-Space drag | Blocked; prompt "move target window to this Space first" |
| 5 | Fullscreen target | Supported if target exits fullscreen; otherwise blocked with toast |
| 6 | Source window closes mid-drag | Pane stays in source's frame until commit; drag cancels cleanly |
| 7 | Target frame closes post-validation, pre-attach | Operation reverts cleanly; pane stays in source frame; user notified |
| 8 | Mixed-DPI drag (drop between retina and non-retina) | Retinafactor reacquired; no render artifact on either side |
| 9 | `WKWebView` / browser portal pane drag-over | Existing `DragOverlayRoutingPolicy` handles; no routing regression |
| 10 | Mission Control interrupt mid-drag | Drag cancels cleanly; source unchanged |

Each row is a Phase 3 acceptance test. Failures that can't be fixed in-phase downgrade to CLI fallback for that scenario, documented in the CHANGELOG.

## 4. Focus model

Two models:

1. Each window has its own focused pane; Cmd+~ cycles windows without disturbing focus.
2. A single globally focused pane; Cmd+~ moves it.

**Choice: per-window focused pane.** Justifications:

- **Parallel-agents case:** the operator runs 3 agents on 3 monitors. After reading agent 3's output, Cmd+~ should land back on agent 1 ready to type. Single-global-focus would force a second keystroke to refocus the pane the user was already using in window 1.
- **macOS convention:** every native app with multiple windows (Xcode, Safari, Finder, Terminal) maintains per-window focus. Breaking convention needs a strong reason; there isn't one here.
- **The sidebar already follows the window,** because sidebar selection is per-window view state (see §2). No special logic.

Socket API: `cmux identify` reports the caller's window's focused pane, exactly as today. New optional `--all-windows` flag returns focused pane per window for orchestrators who want a cross-window picture (not v1-critical).

### Multi-host resolver policy (Resolution G2.8)

A workspace can now be hosted in multiple windows simultaneously (two frames of the same workspace, one per window). When a socket caller passes only `workspace_ref` and the workspace has more than one hosting frame, the default resolver policy is:

1. **If the caller has a resolvable window context** (from the caller's surface/pane chain or an explicit `window_ref` in the request), the caller's window wins. Matches the principle that a script running in window A shouldn't reach across to window B accidentally.
2. **Otherwise, the most-recently focused frame of the workspace wins.** MRU fallback is tracked by the process-scoped registry (already needed for tab-history anyway).

This policy applies to: `workspace.select`, `surface.focus`, `pane.focus`, `read-screen`, notification-jump, and any other future focus/read-class command. It parallels the existing `v2FocusAllowed` gate at `Sources/TerminalController.swift:3784`.

Explicit overrides:
- `window_ref` in the request forces the specified window.
- `--broadcast` (future flag; not v1) fans out to all hosting frames.
- Commands where strict targeting matters (future `read-screen --strict`) can opt into an `ambiguous_host` error when no `window_ref` is present.

No ambient `ambiguous_host` error at v1 — the MRU fallback is preferred over breaking every script that worked against the single-window world.

## 5. Split-into-new-window

When the minimum pane width would be crossed by a split, two options: auto-overflow to the next display, or opt-in.

**Choice: opt-in.** A sibling-display spawn is a non-local visible action — a window flies in on another monitor. Doing it automatically violates least-surprise. CMUX-15's grid also avoided auto-overflow for the same reason.

Concrete affordances:

- **CLI:** `cmux new-split <dir> --overflow-to-display <ref>` or `--spawn-window` creates a new window (on the given display if passed, or the display positional to the current one) and places the new pane as the sole frame there.
- **Keyboard:** `Cmd+Opt+Shift+<Arrow>` — "split overflow" — mirrors `Cmd+Shift+Ctrl+<Arrow>` from the pane-migration binding. (v1 can ship without a dedicated key; CLI is enough.)
- **UI hint:** when a regular split would leave any resulting pane under a minimum pixel width threshold (say 480px), show a one-time toast "Panes are getting tight — split to display 2?" with a button. Post-v1.

**Keybinding conflict audit (Resolution G1.15) — required at Phase 3 and Phase 6.** Both `Cmd+Shift+Ctrl+<Arrow>` (pane migration, Phase 3) and `Cmd+Opt+Shift+<Arrow>` (split overflow, Phase 6) get audited against: Ghostty default keymap; common TUI shortcuts (cc, codex, vim, emacs-in-terminal, helix); macOS system bindings (Mission Control, Spaces, screen capture). One-paragraph audit note in each phase's ticket scope; collisions documented with mitigation (rebind, ship-anyway, document workaround).

## 6. Session restore / hotplug

**v1 scope (deliberately narrow):** session-restore on relaunch only. No runtime hotplug tracking; no hibernation; no display-affinity memory. Users spawn multiple windows and assign them to monitors manually via `cmux window new --display <ref>` or by dragging the NSWindow. When a monitor disconnects at runtime, macOS auto-migrates windows to a surviving display and c11mux does nothing — both windows remain alive on the remaining desktop, the user picks which to focus, exactly per Atin's laptop-home scenario.

**Persistence (still required for 16b):** extend `SessionWindowSnapshot` with a link back to the workspace it hosts (today it has `tabManager: SessionTabManagerSnapshot` which embeds workspace data). In the new model, window snapshots reference workspace IDs by value; workspace-level data (the shared registry) is in its own top-level `AppSessionSnapshot.workspaces` collection. Each snapshot carries:

- Window frame + display snapshot (as today, already display-aware via `SessionDisplaySnapshot` / `resolvedWindowFrame`).
- `WorkspaceFrame` bonsplit tree for each workspace the window hosts.
- `sidebarMode` per window (see §2 — v1 always `.independent`, but the seam is serialised for forward compat).

**Restore:** `resolvedWindowFrame` already does the right thing — if the display is present, restore there; otherwise area-overlap onto nearest surviving display; otherwise centre on primary. Reuse verbatim. Schema version bump at Phase 2 with a real migration framework (see §Session schema v2 below — not a one-bullet "schema bump").

**Deferred to v2 (tracked as a follow-up ticket outside the CMUX-16 sub-ticket set):** runtime hotplug handling, display-affinity memory, and any hibernation/auto-reconnect behavior. v2 scope sketch when we get there:

- Each window tracks the display it was last on (`NSScreen.cmuxDisplayID`).
- On `didChangeScreenParametersNotification`: when a previously-seen display reappears, offer to move any windows that originated there back to it (auto / prompt / never, per Settings).
- Optional hibernation store for the "3 monitors → 1 monitor" undock case if operator feedback asks for it. Defaults to "no hibernation, let macOS handle migration."
- Merge-two-windows-into-one as a manual command (Atin's far-future wishlist).

This keeps v1 uncontroversial and lets us observe real usage before committing to any hotplug UX.

## Session schema v2

Phase 2 bumps `AppSessionSnapshot.schemaVersion` from 1 to 2. The current loader at `Sources/SessionPersistence.swift:5` and `:466` rejects version mismatch outright; that's replaced with a versioned migrator interface so we can ship v2 without bricking v1 sessions on first launch (Resolution G1.10).

### Field table

| Type | Field | Type | Notes |
|------|-------|------|-------|
| `AppSessionSnapshot` | `schemaVersion` | `Int` | Bumped to `2` |
| `AppSessionSnapshot` | `workspaces` | `[SessionWorkspaceSnapshot]` | NEW. Top-level workspace collection. |
| `AppSessionSnapshot` | `windows` | `[SessionWindowSnapshot]` | Existing collection; embedded workspace data removed (see below). |
| `AppSessionSnapshot` | `surfaces` | `[SessionSurfaceSnapshot]` | NEW (or promoted from inline). Top-level surface collection keyed by surface id. |
| `AppSessionSnapshot` | `paneAttachments` | `[SessionPaneAttachmentSnapshot]` | NEW. Pane↔frame placement ledger (Resolution G2.4). |
| `SessionWorkspaceSnapshot` | `id` | `UUID` | |
| | `name` | `String` | |
| | `customTitle` | `String?` | |
| | `color` | `String?` | |
| | `pinned` | `Bool` | |
| | `cwd` | `String?` | |
| | `defaultContext` | `String?` | |
| | `gitBranch` | `String?` | |
| | `statusPills` | `[StatusPillSnapshot]` | |
| | `surfaceIds` | `[UUID]` | References into `AppSessionSnapshot.surfaces`, not embedded. |
| `SessionWorkspaceFrameSnapshot` | `frameId` | `UUID` | NEW type. First-class FrameID. |
| | `workspaceId` | `UUID` | Tuple field. |
| | `windowId` | `UUID` | Tuple field. |
| | `bonsplitTree` | `BonsplitTreeSnapshot` | The pane-leaf tree for this frame. |
| | `frameLocalFocusedPaneId` | `UUID?` | Per-frame focused pane (per-window focus model). |
| | `zoomState` | `ZoomStateSnapshot?` | |
| `SessionWindowSnapshot` | `windowId` | `UUID` | |
| | `frame` / `display` / `sidebarVisibility` / `sidebarWidth` | (existing fields) | Preserved. |
| | `hostedWorkspaceIds` | `[UUID]` | NEW. Replaces the embedded `SessionTabManagerSnapshot.tabs`. |
| | `selectedWorkspaceId` | `UUID?` | NEW. Replaces `SessionTabManagerSnapshot.selectedTabId`. |
| | `sidebarMode` | `String` | NEW. v1 always `"independent"`; unknown values coerce to `"independent"` with a warning. |
| | `frameIds` | `[UUID]` | The `WorkspaceFrame`s this window owns (1 per hosted workspace at v1). |
| `SessionSurfaceSnapshot` | `id` / `kind` (terminal/browser/markdown) / `customTitle` / `pinned` / `unread` / `cwd` / `listeningPorts` / `metadata` | (typed) | Promoted from existing inline shapes. |
| `SessionPaneAttachmentSnapshot` | `paneId` | `UUID` | NEW type. |
| | `frameId` | `UUID` | Which frame the pane is attached to. |
| | `leafPath` | `[Int]` | Bonsplit leaf coordinates inside the frame. |
| | `orderingHint` | `Int` | Tab order within the pane's enclosing tab group. |

### Migration framework (replaces the previous one-line bullet)

1. **`SnapshotMigrator` protocol** in `Sources/SessionPersistence.swift`. Each migrator declares `from: Int`, `to: Int`, and `migrate(_ data: Data) throws -> Data`. The loader walks the chain from the on-disk version up to the current version.
2. **`V1ToV2Migrator`** synthesises:
    - A top-level `workspaces` array from each window's embedded `SessionTabManagerSnapshot.tabs`.
    - A top-level `surfaces` array from each workspace's embedded surfaces.
    - One `WorkspaceFrame` per (workspace, window) pair with the workspace's existing bonsplit tree adopted as the frame's tree.
    - One `PaneAttachment` per leaf in each frame's bonsplit tree.
    - Window snapshots replace `tabManager` with `hostedWorkspaceIds`, `selectedWorkspaceId`, `sidebarMode = "independent"`, `frameIds`.
3. **Duplicate-workspace merge rule.** If the same workspace appears under multiple windows in v1 (currently only possible via `workspace.move_to_window`), merge by `(id)` first; if only `(name, path)` matches but ids differ, prefer the most recently focused entry and discard duplicates with a `dlog` notice. The duplicate fixture lives in test data and is exercised by the Phase 2 migration test.
4. **One-time backup.** Before writing the v2 snapshot, copy the on-disk v1 snapshot to `<snapshot-path>.v1.bak` once. If the user rolls back to a pre-Phase-2 build, the loader cannot read the v2 snapshot — the user starts with a fresh session. Downgrade is **not supported**; the backup is for forensic recovery only.
5. **Failure mode.** Any migrator throwing aborts session restore and falls back to the empty-state behavior (one window, one default workspace), with a one-time alert summarising the migration failure and pointing at the backup. We do not silently drop user state.

The migrator interface and v1→v2 implementation are in scope of Phase 2 sub-PR 4 (see Phase 2 sub-ordering below).

## Code change sketch (file-by-file)

Severing `TabManager ↔ NSWindow` coupling is spread across ~12 files; nothing is a single-line swap. Groups of changes:

**New types (`Sources/Pane*.swift`, `Sources/WorkspaceFrame.swift`, `Sources/DisplayRegistry.swift`):**
- `PaneRegistry` — process-scoped actor-isolated store: `panes: [UUID: any Pane]`, `panesByWorkspace: [UUID: Set<UUID>]`, add/remove/query APIs. Pane lifecycle (durable identity, pane-local metadata, scrollback aggregate) is owned here. **Surface lifecycle** (PTY spawn/teardown, Ghostty surface create/destroy, MTL layer) lives on the `Surface` type and is reached via the pane's surface list — not from the registry directly.
- `PaneAttachment` ledger (`Sources/PaneAttachment.swift`) — process-scoped fact table mapping each pane id to its current attachment: `{ paneId: UUID, frameId: UUID, leafPath: [Int], orderingHint: Int }`. Single source of truth for "which pane is where." All cross-frame operations (`pane.move`, `workspace.spread`, drag-drop, CMUX-26 hotplug) read and mutate the ledger and emit placement events (see §Socket API additions). v1 invariant: each `paneId` appears in the ledger exactly once (single-home).
- `WorkspaceFrame` — one NSWindow's view of a workspace: identity is `frameId: UUID` with `{ workspaceId, windowId }` as fields; holds a `BonsplitController` and a `paneLeafReferences: [PaneID]` (denormalised from bonsplit tree for fast lookups). Invariant at v1: at most one `WorkspaceFrame` per `(workspaceId, windowId)` pair, enforced at the API layer in `WorkspaceRegistry.attachFrame(...)`.
- `DisplayRegistry` — enumerates current `NSScreen`s with stable refs (`display:<cmuxDisplayID>`), positional aliases (`left`/`center`/`right` from sorted `frame.minX`), and numeric indices. Publishes a `displaysChanged` signal that Phase 1 consumes for CLI enumeration only; runtime hotplug response is deferred to CMUX-26.
- `HibernatedFrameStore` is **deferred to CMUX-26** and is not introduced at v1. Hibernation, parked/headless registry state, and any auto-restore behavior live entirely in the v2 follow-up ticket.

**`Sources/Workspace.swift`:** thin down. `Workspace` keeps `id`, `name`, metadata, git/status/ports — not `panels`, not `bonsplitController`. Rename `owningTabManager` → `workspaceRegistry` reference. `detachSurface` / `attachDetachedSurface` become registry operations mediated through `WorkspaceFrame` removal/insertion.

**`Sources/TabManager.swift`:** rename to `WindowScope` (still `@MainActor`, `ObservableObject`). Drop `tabs: [Workspace]` as a source of truth; replace with `hostedWorkspaces: [UUID]` (IDs only) and `selectedWorkspaceId: UUID?`. All workspace mutations delegate to a new process-scoped `WorkspaceRegistry`. Keep everything about selection, sidebar history, per-window focus tracking — that's legitimately window-local.

**`Sources/AppDelegate.swift`:**
- `mainWindowContexts` keeps MainWindowContext but replaces `tabManager` with `windowScope: WindowScope`.
- Introduce `workspaceRegistry: WorkspaceRegistry` and `paneRegistry: PaneRegistry` as process-level properties.
- Rename `moveWorkspaceToWindow` to `moveWorkspaceFrameToWindow(workspaceId:, windowId:)`. Old `moveWorkspaceToWindow` stays for one release as a thin shim that forwards to the new method and emits `dlog("moveWorkspaceToWindow deprecated; use moveWorkspaceFrameToWindow")` in DEBUG. Public socket method rename lands in the Socket API section below.
- Rewrite `moveSurface` to operate on registry panes + `WorkspaceFrame`s. The cross-window traversal through `mainWindowContexts` stays; the pane lookup is now `paneRegistry.pane(for: paneId)`.
- `DisplayHotplugCoordinator` is **deferred to CMUX-26**. Phase 1 only emits a `displaysChanged` signal from `DisplayRegistry` for CLI enumeration purposes; nothing in v1 listens to that signal at runtime to migrate windows.

**`Sources/cmuxApp.swift`:** `activeTabManager` computed property becomes `activeWindowScope`. Menu bar commands that act on "this window's workspaces" stay window-scoped; commands that act on "all workspaces" (e.g. new cross-window features) read from `workspaceRegistry` directly.

**`Sources/ContentView.swift`:** sidebar view moves from reading `@EnvironmentObject var tabManager: TabManager` to reading `@EnvironmentObject var workspaceRegistry: WorkspaceRegistry` for shared data, plus a local `@ObservedObject windowScope: WindowScope` for selection/width/visibility. `SidebarState` stays per-window (visibility, width). `SidebarSelectionState` stays per-window (tabs/notifications view).

**`Sources/TerminalController.swift`:** V2 socket handlers already accept `window_ref` / `workspace_ref` params and route via `v2ResolveTabManager`. Swap that helper to `v2ResolveWindowScope`. Add new methods (§ Socket API additions below). `moveSurface` handlers untouched in shape, just target new types.

**`Sources/SessionPersistence.swift`:** schema bump to `2`; new top-level `workspaces`, `surfaces`, `paneAttachments`, and the `WorkspaceFrame` records carried inside window snapshots. Migration framework + `V1ToV2Migrator` per §Session schema v2. (`hibernatedFrames` is **not** part of the v2 schema — that field belongs to CMUX-26's eventual snapshot extension and is not touched at Phase 2.)

**`vendor/bonsplit/`:** no public contract change anticipated. Bonsplit still owns one tree per `BonsplitController`; we just create N controllers per workspace (one per frame) instead of one. The cross-window drag surface is handled in cmux code, not bonsplit — bonsplit sees opaque PaneID leaves and trusts the host to resolve them.

**Phase 2 bonsplit pre-check (Resolution G1.4).** Adversarial review flagged "no contract change" as an unverified assumption (assumption A1). Phase 2 sub-PR 1 includes a pre-check pass: confirm that no internal pane-ID uniqueness caches inside `vendor/bonsplit/` break under N controllers per workspace (today bonsplit assumes one controller per workspace tree). If a cache is found that asserts global uniqueness across controllers, Phase 2 either updates the assumption or carries a small bonsplit patch. Tracked as the first acceptance check in sub-PR 1.

**`Sources/Panels/*`:** panel views continue to take a PaneID and render; they gain no awareness of windows. Focus and selection plumbing is unchanged per-window.

## Socket API additions

Signatures follow existing v2 conventions (camel-snake method names, `params` dict, `ok`/`err` result wrappers, `*_ref` string refs next to `*_id` UUIDs).

**`display.list`** — enumerate current displays.

Request: `{}`
Response:
```json
{
  "displays": [
    {
      "id": 4228710654,
      "ref": "display:4228710654",
      "index": 1,
      "position": "left",
      "name": "LG UltraFine",
      "frame":          { "x":    0, "y": 0, "w": 3840, "h": 2160 },
      "visible_frame":  { "x":    0, "y": 0, "w": 3840, "h": 2135 },
      "scale":          2.0,
      "is_primary":     false,
      "windows":        ["window:…", "window:…"]
    }
  ]
}
```
Position is computed from sorted `frame.minX`. **Positional alias rules (Resolution G1.16):**
- `N == 1` → only `"left"` (synonym `"center"`, `"right"` rejected as ambiguous).
- `N == 2` → `"left"` (index 1), `"right"` (index 2). `"center"` rejected.
- `N == 3` → `"left"`, `"center"`, `"right"`.
- `N >= 4` → `position` is `null`; positional aliases (`left`/`center`/`right`) **return `err(code: "ambiguous_position", message: …, data: { "available_displays": […] })`** in resolvers. Only `display:1..display:N` (numeric index) and `display:<cmuxDisplayID>` are valid for ≥4-display rigs.
- Otherwise resolvers reuse the same `ambiguous_position` error code.

**`window.create`** — extend existing with `--display`.

Request: `{ "display_ref": "display:left" | "display:2" | "display:4228710654" | null, "workspace_ref": "workspace:42" | null }`
Response: `{ "window_id": "…", "window_ref": "window:3", "display_ref": "display:4228710654" }`

Missing `display_ref` → current behaviour (macOS picks). Unresolvable `display_ref` → `err(code: "display_not_found", message: …, data: { "available_displays": […] })`.

**`workspace.spread`** — one window per display, distribute panes.

Request: `{ "workspace_ref": "workspace:1", "mode": "one_pane_per_display" | "existing_split_per_display" }`
Response: `{ "window_ids": ["…","…","…"], "frame_assignments": [ { "window_id": "…", "display_ref": "display:left", "pane_refs": ["pane:1"] } ] }`

`one_pane_per_display` round-robins existing panes across new windows. `existing_split_per_display` preserves the current workspace's bonsplit tree but splits it along vertical dividers matched to display count.

**`all_on_each` is cut from v1 (Resolution G2.9, follows from G2.1 single-home).** Multi-homing the same pane onto every display requires an offscreen-texture / IOSurface / view-proxy multi-renderer abstraction that's out of v1 scope. The mode moves to v1.1 when multi-viewer is properly designed; until then, callers requesting `mode: "all_on_each"` get `err(code: "mode_not_supported", message: "all_on_each cut from v1; tracked for v1.1", data: { "available_modes": ["one_pane_per_display", "existing_split_per_display"] })`.

**`pane.move`** — move a pane to another window and/or display.

Request:
```json
{
  "pane_ref":      "pane:17",
  "window_ref":    "window:3" | null,
  "display_ref":   "display:right" | null,
  "split_target":  { "orientation": "horizontal", "insert_first": false } | null,
  "focus":         true
}
```

Either `window_ref` or `display_ref` required; supplying both is valid (target window on that display — create one if none exist). Response: `{ "pane_ref": "pane:17", "window_ref": "window:3", "workspace_ref": "workspace:1" }`. Error codes: `window_not_found`, `display_not_found`, `pane_not_found`, `invalid_target`.

**`window.move_to_display`** — move an existing window to a display.

Request: `{ "window_ref": "window:2", "display_ref": "display:center" }`. Uses macOS `setFrame` onto the resolved `visibleFrame` with centre alignment and clamping (reuses `Self.clampFrame`). Response: `{ "window_ref": "window:2", "display_ref": "display:4228710654", "frame": {...} }`.

**`workspace.move_frame_to_window`** — rename of the existing `workspace.move_to_window` to reflect the 16b primitive shift (windows host workspace *frames*, they don't own the workspace itself).

Request: `{ "workspace_ref": "workspace:1", "window_ref": "window:3" }`. Response: `{ "workspace_ref": "workspace:1", "window_ref": "window:3", "frame_ref": "frame:…" }`.

**Deprecation path:** `workspace.move_to_window` keeps working as a thin shim that forwards to `workspace.move_frame_to_window` and returns the same response shape. The shim logs a deprecation warning once per process to the DEBUG log (`dlog("deprecated: workspace.move_to_window → workspace.move_frame_to_window")`) and surfaces a `deprecation_notice` field in the response: `{ ..., "deprecation_notice": "renamed to workspace.move_frame_to_window" }`. Callers with automation can grep that field to find migration sites. **Shim retirement criterion (Resolution G1.17):** removed in the first release tagged **≥30 days after Phase 2 lands on `main`**. The same calendar-objective gate as the feature flag — no soak-theatre, no "one release cycle" hand-wave. CHANGELOG at Phase 2 documents the rename and the gate; CHANGELOG at the retirement release documents removal.

**Pre-removal consumer audit (Resolution G2.15).** Before the shim-removal PR ships, run a documented grep for `workspace.move_to_window` against: every Stage 11 sibling repo (`code/cmux*`, `code/Lattice/`, `code/lattice-stage-11-plugin/`, `code/internal-tooling/`), the cmux skill (`~/.claude/skills/cmux/`), `claude-in-cmux`, `cmuxterm-hq` CI, and any beta-user repo Atin can name. Results paste into the shim-removal PR description as a checklist. Catches drift; cheap insurance.

**`tree` extensions.** Extend the existing output (whose shape is documented in `vendor/cmuxd/` and `Sources/TerminalController.swift`):

Every pane entry gains:
- `window_ref: "window:1"`
- `display_ref: "display:left"` (derived from the hosting window's `NSScreen.cmuxDisplayID`)

Every window entry gains `display_ref`.

New flag: `--by-display` produces a display → windows → workspaces → panes projection alongside the current window-first projection. Useful for operators asking "what's on my right monitor?".

**`cmux identify` extension.** Current response adds `display_ref` for both `focused` and `caller` based on their hosting window.

### Socket focus policy (Resolution G1.14)

Every new command introduced by CMUX-25 — `pane.move`, `workspace.spread`, `window.create --display`, `window.move_to_display`, `workspace.move_frame_to_window` — defaults to **preserving user focus** unless the caller explicitly opts in by passing `focus: true` in the request. This matches the existing `v2FocusAllowed` pattern at `Sources/TerminalController.swift:3784`.

Rules:
- The data/model mutation always applies (the pane moves, the window opens on the chosen display, etc.).
- Macro-level focus side effects (NSWindow `makeKeyAndOrderFront`, app activation, sidebar selection change in another window, hovered-pane focus) only fire when `focus: true` is set.
- `cmux identify` and `cmux tree` query commands never mutate focus.
- Bare `pane.focus` / `surface.focus` / `workspace.select` / `window.focus` retain explicit-intent semantics: they are the focus commands; they always focus. The preservation rule applies to *non-focus* commands that incidentally touch a window or pane.

This rule is non-negotiable and lands in the v2 socket-handler base class so a new command cannot accidentally activate the app. Tests in `tests_v2/` assert focus-preservation for each new command.

### Stable ref scheme contract (Resolution G2.10)

At Phase 2, the following ref formats are published as a **public, versioned, stable contract**. Breaking changes require a new scheme version. Documented in the cmux skill, the CLI help output, and the socket protocol docs.

| Ref | Format | Notes |
|-----|--------|-------|
| `pane:` | `pane:<UUID>` or `pane:<short-id>` | Stable across session restore. |
| `frame:` | `frame:<UUID>` or `frame:<short-id>` | Stable across session restore. |
| `workspace:` | `workspace:<UUID>` or `workspace:<short-id>` | Stable across session restore. |
| `surface:` | `surface:<UUID>` or `surface:<short-id>` | Stable across session restore. |
| `display:` | `display:<cmuxDisplayID>` or `display:<index>` or `display:left|center|right` (per N-rules above) | Display IDs are macOS-stable across reboots for built-in displays; positional aliases resolve at call time. |
| `window:` | `window:<UUID>` or `window:<short-id>` | Stable for the session; not preserved across relaunch (windows are recreated). |

Versioning discipline:
- The scheme version (`v1`) is reported by `cmux api version`.
- A breaking change to any format bumps the version and the old format keeps resolving with a `deprecation_notice` for one calendar-defined window (same gate as the feature flag).
- New ref types (e.g. `attachment:`, `placement:`) can be added in a minor version without bumping the scheme.

This codifies what's already in the wild (the cmux skill documents `pane:`, `workspace:`, `surface:`; agent scripts use them) and gives third-party automation a stable target to write against.

## Implementation tickets (revised 2026-04-19 — consolidated into a single phased ticket per Atin)

Per Atin's redirect, the six originally-proposed sub-tickets are consolidated into **one phased implementation ticket** (CMUX-25). Phase scopes are preserved verbatim inside that ticket's description; phase numbering replaces the original 16a–16f labels. A separate v2 backlog ticket (CMUX-26) tracks the deferred hotplug work. CMUX-23 and CMUX-24 were created briefly under the original split-ticket plan and were cancelled as superseded.

**CMUX-25 — Pane-first c11mux: Emacs-frames implementation (phased).** `subtask_of CMUX-16`. Status: backlog. Six phases; execute Phase 1 → Phase 2 → (Phases 3–6 in parallel after 2 lands). Total v1 envelope: **7–9 weeks** (Resolution G1.6).

### Feature flag `CMUX_MULTI_FRAME_V1` (Resolution G1.11, G1.12, G2.12)

- **UX-gated only.** Phase 2's registry refactor ships unconditionally — the flag never gates the refactor. The flag gates only the visible multi-frame UX (Phase 3+ behaviors: cross-window drag, `pane.move`, `workspace.spread`, split-overflow, multi-frame session restore).
- **Settings-toggle exposure.** The flag is exposed as a user-visible setting in c11mux Settings (default OFF for v1, ON for nightly). Power users opt in; everyone else stays on the single-frame UX. This replaces a formal dogfooding cohort — adoption is the validation.
- **Retirement criterion.** The flag is removed in the first release tagged **≥30 days after Phase 6 lands on `main`** AND with no open P0 regressions filed against multi-frame in that window. Calendar-objective; no soak-theatre.
- **Two-flag split considered, rejected.** A separate registry-vs-UX flag was on the table; the single UX-gated flag is simpler and aligns with the more common pattern in the cmux codebase.

### Phase 1 — Display registry + CLI surface (~1 week)

Deliverables: `DisplayRegistry`, `display:` ref scheme, `display.list` socket, `display_ref` on `identify` and `tree` outputs.

**Scope clarification (Resolution G1.7).** Phase 1 has no cross-window behavior change. The new commands unlock manual display assignment only (`cmux window new --display <ref>`, `cmux window move-to-display`); they do not change how single-window c11mux behaves. The earlier "no behavior change" wording was in tension with this — corrected here.

**Phase 1 perf canary baseline (Resolution G1.19).** Capture, with no target threshold, baseline numbers for: keystroke→onscreen latency (typing in a focused terminal); `cmux tree` response time at 3 windows × 30 panes; `cmux identify` response time; frame creation latency (new window with empty workspace); sidebar update coalescing under a status/log/progress burst. Re-run the canary at the end of every subsequent phase. A regression of >20% on any metric triggers an investigation issue but does not block the phase from landing.

### Phase 2 — Pane-first registry refactor (~3 weeks, day-10 tripwire) (Resolution G1.5, G1.8)

The heaviest phase. Delivers the registry refactor that all later phases depend on. Honest estimate: **3 weeks**, with a day-10 tripwire — at the day-10 review, if sub-PRs 1+2 are not landed, the phase splits into two sub-phases (the second slips estimates accordingly).

**Sub-PR ordering (each sub-PR lands green on CI with the flag off and on):**

1. **Introduce `WorkspaceRegistry` + `PaneRegistry` shells (facade pattern, no ownership moves).** Existing structures remain authoritative; the registries forward to them. Bonsplit pre-check (Resolution G1.4) lands here. No user-visible change.
2. **Move panel/surface lifecycle behind the facade.** `Workspace.panels`, `Workspace.bonsplitController` are routed through the registries. UI behavior unchanged.
3. **Introduce `WorkspaceFrame` wrapping `BonsplitController`.** Still one frame per workspace at this sub-PR (the multi-frame invariant relaxes in Phase 3); `FrameID` becomes a real UUID with `{workspaceId, windowId}` as fields. `PaneAttachment` ledger lands here.
4. **Rename `TabManager` → `WindowScope`; session schema v2 migration; socket rename + deprecation shim for `workspace.move_to_window`.** Test matrix below applies.

**Phase 2 acceptance test matrix (Resolution G1.20):**
- Snapshot migration v1→v2 with a duplicate-workspace fixture (covers the merge rule from §Session schema v2).
- Flag-off launch behavior: full single-window regression suite, including session restore and cross-tab drag-drop.
- Model invariant tests: `WorkspaceRegistry`/`PaneRegistry`/`PaneAttachment` consistency under add/remove/move; assert no stale frame references.
- Socket rename tests: both `workspace.move_to_window` and `workspace.move_frame_to_window` resolve to the same outcome; deprecation notice appears on the old name.
- Concurrent `pane.move` same-pane idempotency test (stub at Phase 2; real cross-window test at Phase 3).

### Phase 3 — Cross-window pane migration (~1 week)

Drag-drop matrix (see §3 Cross-window drag-drop above) + `pane.move` socket + `Cmd+Shift+Ctrl+<Arrow>` keybinding. **Keybinding audit (Resolution G1.15)** lands here.

### Phase 4 — Per-window independent sidebar (~1 week)

`SidebarMode` enum carrying only `.independent`; session persistence round-trips per-window selection. Sync-mode `.primary`/`.viewport` cases and `broadcastSelection` no-op are NOT introduced (Resolution G1.13).

### Phase 5 — `workspace.spread` (~4–5 days) (Resolution G1.6)

`workspace.spread` command with `ceil(N/D)` fill-leftmost distribution; menu + keyboard entry. `mode: "all_on_each"` returns `mode_not_supported` (cut from v1).

### Phase 6 — Split-into-new-window opt-in (~4–5 days) (Resolution G1.6)

`--overflow-to-display` / `--spawn-window` flags; `Cmd+Opt+Shift+<Arrow>`. **Keybinding audit (Resolution G1.15)** repeats here for the new combo.

---

**CMUX-26 — Multi-window c11mux v2: display hotplug + affinity + auto-reconnect.** `subtask_of CMUX-16`, `depends_on CMUX-25`. Status: backlog. Priority: low. Runtime `didChangeScreenParameters` response, per-window last-known-display tracking, optional hibernation store, auto-restore on reconnect. Parked/headless registry state (the `⎇ N parked` sidebar affordance) — if it ever ships — also lives here, not in v1. Default behavior TBD once v1 has soaked and operator feedback tells us what's needed.

**Logged as v1.1 wishlist (full inventory at `docs/cmux-25-v1.1-wishlist.md`):** sidebar edge configurability (per-window left/right placement), sidebar sync mode / primary-sidebar UI (the data structures support it; the UX still needs design), merge-two-windows-into-one command, accessibility pass for multi-frame surfaces (Resolution G2.13: explicit non-goal at v1, revisit v1.1), `SidebarMode.primary` → `.director` rename decision (Resolution G2.14, deferred to when sync mode is actually designed), and the 20 reviewer-suggested unlocks.

## Incidental findings

- `TabManager` is 5,283 lines — more growth would be hostile to diff review. Phase 2 is a natural moment to split: `WindowScope` stays lean; workspace lifecycle moves to `WorkspaceRegistry`; tab history stays with the window.
- The `CMUX_TAB_ID` memory note (workspace UUID ≠ tab UUID) is still on main. While reading session restore I saw no new code around it. Not in spike scope; worth a 1-line fix ticket separately.
- `moveSurface` logs extensively via `dlog` in DEBUG. When building Phase 2, keep the logging shape — it's useful for the inevitable cross-window drag debug pass.
- Bonsplit's `.ownProcess` drag visibility is the correct choice today and will stay correct in the new model. The only cross-process boundary we will ever cross is the c11mux socket; drag-drop is fine to stay intra-process.
- `AppSessionSnapshot.version` should bump at Phase 2; include a migration step that re-normalises embedded workspace data into the new top-level collection. Now formalised in §Session schema v2 above.

## Open questions for Atin — resolved 2026-04-19-PM (review-pack pass)

Resolutions captured inline; numbering matches the triage doc at `.lattice/plans/cmux-25-plan-review-pack-2026-04-19T1511/triage-2026-04-19-PM.md`. Per-section text above has been revised to reflect these. Group 1 (20 obvious edits) was applied en bloc and is not enumerated here; see the triage doc for the bulk list.

### Group 2 — architectural decisions

- **G2.1 Pane single-home vs multi-home.** **Resolved:** Single-home for v1. A pane lives in exactly one frame at a time. `workspace.spread all_on_each` cut from v1; tracked for v1.1 in the wishlist. Rationale: multi-home requires offscreen-texture / IOSurface / view-proxy abstraction; out of v1 scope and would inflate Phase 2 well past the 3w cap.
- **G2.2 Lifecycle owner.** **Resolved:** `Surface` owns runtime objects (PTY, Ghostty, MTL); `Pane` is a grouping/layout primitive holding 1..N surfaces and pane-level scrollback. Plan text in earlier revisions said "pane owns PTY/Ghostty/MTL" — that conflicted with both the locked hierarchy and current code (`Sources/Workspace.swift`, `Sources/GhosttyTerminalView.swift`). Amended throughout.
- **G2.3 FrameID.** **Resolved:** `FrameID: UUID` as first-class identity; `{workspace_id, window_id}` are fields. v1 enforces "one frame per tuple" at the API layer. Cost: ~1 day design + small code delta in Phase 2 sub-PR 3. Door open for v1.1 frame-mirror/present without an identity refactor.
- **G2.4 PaneAttachment ledger.** **Resolved:** Land at Phase 2 sub-PR 3. ~50 lines + serialization. Single source of truth for pane↔frame relations. Unlocks `tree --by-display`, `pane.move`, `workspace.spread`, placement events, and CMUX-26 hotplug.
- **G2.5 Close-window orphan-pane rule.** **Resolved:** **Option (a) — destroy panes with the window** (today's behavior preserved). Reviewer consensus was option (c) park-or-migrate; Atin chose (a) for v1 simplicity. Parked/headless registry state is explicitly NOT in v1; if it ever ships it lives in CMUX-26. Pane-level scrollback survives moves but does not survive window-close-driven destruction.
- **G2.6 Scrollback ownership.** **Resolved:** Pane-level. Surfaces contribute their own buffers; the pane is the owner for persistence, hibernation, and tab-switch preservation. Aligns with G2.2's "Surface owns runtime, Pane groups" — scrollback is a durable aggregate, not a PTY-generated stream. CMUX-26 hibernation hibernates the pane as a unit.
- **G2.7 Empty-window state.** **Resolved:** Show a "New Workspace" CTA screen with *New Workspace* / *Open Recent* / *Drag a Workspace Here* actions when a window has no selected workspace or its selected workspace was deleted. No silent auto-creation; no auto-close.
- **G2.8 Multi-host resolver.** **Resolved:** Caller's window wins if determinable; fall back to MRU otherwise. Applies to focus/select/read commands by default. Strict targeting and broadcast available as opt-in flags later (not v1). See §Multi-host resolver policy under §4 Focus model.
- **G2.9 Cut `workspace.spread all_on_each` from v1.** **Resolved:** Yes (consequence of G2.1).
- **G2.10 Publish stable ref scheme.** **Resolved:** Yes, at Phase 2. See §Stable ref scheme contract under §Socket API additions.
- **G2.11 Reframe as "Pane-first c11mux."** **Resolved:** Yes — public charter, plan title, CHANGELOG entry, ticket body, and cmux-skill intro paragraph reframe around pane-first language. Multi-frame is one consequence; v1.1 unlocks (pane.attach, frame.mirror, broadcast, workspace.present) follow from the same primitive elevation. The product story is the primitive.
- **G2.12 Dogfooding.** **Resolved:** Non-gate. Ship the feature behind the `CMUX_MULTI_FRAME_V1` flag exposed in Settings; let opt-in adoption be the validation. No named cohort, no formal soak rota. Atin's note: "rude requirements" — formal cohort signoff is theatre at Stage 11's team size.
- **G2.13 Accessibility at v1.** **Resolved:** Explicit non-goal for v1. No new VoiceOver / keyboard-only acceptance bar for new multi-frame surfaces. Existing accessibility behavior is preserved (no regressions). v1.1 carries an accessibility pass as a wishlist item.
- **G2.14 `SidebarMode.primary` → `.director` rename.** **Resolved:** Deferred. The case doesn't ship at v1 (G1.13 deletes the stub); the naming decision happens when sync mode is actually designed. Logged in the wishlist.
- **G2.15 Consumer grep before shim removal.** **Resolved:** Yes, do the grep. Documented in the deprecation section of `workspace.move_frame_to_window` above; results paste into the shim-removal PR description.

### Group 3 — wishlist tracking

All 20 evolutionary items captured at `docs/cmux-25-v1.1-wishlist.md`, tiered (high-signal / medium-signal / moonshot) with one-line blurbs and reviewer citations. No Lattice tickets created at this pass; promotion to a ticket happens when a specific item is picked up. The wishlist doc is referenced from this plan and from CMUX-25's ticket body.

## Open questions for Atin — resolved 2026-04-19

Resolutions captured inline; question numbering preserved so future readers can trace the trail. Per-section text above has been revised to reflect these.

1. **Cross-display latency tolerance.** **Resolved:** No formal target at v1. Land the feature, measure later; open a follow-up perf ticket if multi-display regressions surface in real use. Rationale: CMUX-15 shipped without a perf gate and this is the same posture. Bonsplit + Ghostty are GPU-accelerated; likely fine, but we don't invest in a measurement rig until we have a reason to.

2. **Sidebar symmetry guarantee.** **Resolved:** Per-window independent sidebars at v1 (Atin's Option 1), with the data structures architected so a future release can add a "sync" mode where one window is the primary sidebar and the others become viewports (Atin's Option 3). Explicitly out of v1: sync-mode UX, primary-sidebar designation, sidebar-edge configurability (left/right per window) — the last is a logged v1.1 wishlist. Session persistence round-trips per-window sidebar mode to keep forward compat. Rationale: per-window independent matches the parallel-agents workflow (different workspace on each monitor); sync mode is a follow-up power-user affordance for walkthrough / single-task-deep-focus use.

3. **Hibernation / hotplug default.** **Resolved:** No runtime hotplug handling at v1. Windows stay alive; macOS auto-migrates them to surviving displays when a monitor disconnects. No hibernation store, no auto-reconnect, no display-affinity memory. All of that is a v2 follow-up ticket outside the CMUX-16 sub-ticket set. Rationale: Atin's direction to scope v1 narrowly — "users spawn windows and assign them to monitors" — and defer intense system-integration work until real usage tells us what's needed. Merge-two-windows-into-one logged as a far-future wishlist.

4. **Spread distribution heuristic.** **Resolved:** `ceil(N/D)` fill leftmost-first. 5 panes across 3 displays → `[2, 2, 1]`. Rationale: deterministic, CLI-documentable, matches left-to-right reading order. `--weights` CLI flag available as an override. "Equal spread + remainder on primary" rejected because "primary" is non-deterministic across operator rigs.

5. **Super-workspace.** **Resolved:** Backlog, not in v1 envelope. Atin interpreted this as the sidebar-sync question (Q2), which is a different axis; the original Q5 intent (a named grouping of workspaces that bulk-spread together) is a higher-level label layer and is not load-bearing for the Emacs-frames behavior. Option C registry supports it cheaply as a future addition. No sub-ticket at v1.

6. **`workspace.move_to_window` semantics at Phase 2.** **Resolved:** Rename to `workspace.move_frame_to_window` at Phase 2. Old name forwards to the new one for one release as a thin shim, logs a deprecation notice in DEBUG, and surfaces a `deprecation_notice` field in the response so automation can find migration sites. CHANGELOG at Phase 2 documents the rename and the shim window. Shim removed one release later. Rationale: Atin's direction — "we're creating a new primitive" (frames are now first-class); the socket API name should reflect that rather than carry the pre-refactor shape forward invisibly.

## Primitive hierarchy (confirmed)

The spike now locks nomenclature. Any future code or docs should use these terms consistently:

- **Window** — NSWindow, one per visible frame of c11mux on macOS.
- **Sidebar** — window-local UI that selects which workspace this window hosts. Left edge at v1. `SidebarMode` enum is single-case `.independent` at v1; the type exists so a future minor release can add cases without a schema break. The earlier `.primary` / `.viewport` stubs and the `broadcastSelection` no-op are NOT in v1 (Resolution G1.13).
- **Workspace** — process-scoped logical container; has a name, git branch, status pills, owns a set of Pane IDs. A single workspace can be hosted in zero, one, or many windows simultaneously (one frame per window per workspace at v1; G2.3 keeps the door open for relaxing this).
- **WorkspaceFrame** — one bonsplit tree rendering a workspace inside a specific window. Identity is `frameId: UUID`; `{workspaceId, windowId}` are fields on the record. Leaves reference Pane IDs (not Pane objects).
- **Pane** — process-scoped object in `PaneRegistry`. Holds **durable identity** (`pane:<UUID>`), the **pane-local metadata blob**, and the **pane-level scrollback aggregate**. Groups 1..N **Surfaces** (tabs). Moves across frames are free (no surface-runtime churn). Pane is single-home at v1.
- **PaneAttachment** — fact-table record `{ paneId, frameId, leafPath, orderingHint }` published by Phase 2 as the single source of truth for "which pane is where." Lives in `PaneRegistry`; mutated only via the attachment APIs.
- **Surface** — the content + runtime inside a pane: terminal, browser, or markdown. **Owns the runtime objects**: PTY (terminal), `WKWebView` (browser), markdown view (markdown), and the MTL/Ghostty layer where applicable. One or more per pane.
- **Tab** — UI affordance rendered when a pane holds more than one surface. A pane with one surface has no visible tab bar. Tabs ≠ surfaces strictly; surfaces are the content + runtime, tabs are the rendering.
