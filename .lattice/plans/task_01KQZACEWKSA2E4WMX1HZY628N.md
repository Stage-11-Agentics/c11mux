# C11-32: Workspace-switch performance umbrella

# Workspace-switch performance — umbrella roadmap

## Problem

Long-standing perf issue: workspace switches commonly take 1–6 s with outliers up to 90 s under heavy load. A live `sample(1)` showed ~64% of main thread spent in `-[NSView _layoutSubtreeWithOldSize:]` recursion ~30 levels deep — AppKit Auto Layout walking the full bonsplit pane tree of every mounted workspace on every switch, even though only one is visible.

Per-switch timeline (pre-fix) at 7 workspaces / ~9 surfaces:

| dt | event |
|---|---|
| 0 ms | `selectedTabId` setter (sync, innocent — sub-ms) |
| 1,530 ms | `ws.view.selectedChange` (SwiftUI body cascade fully drained) |
| 1,672 ms | last `ws.swiftui.update` for surfaces |
| ~3,668 ms | `ws.unfocus.defer` — silent gap = AppKit layout cascade #1 |
| ~5,118 ms | `ws.select.asyncDone` — silent gap = AppKit layout cascade #2 |

## Roadmap

### Phase 0 — OSSignpost instrumentation ✅ DONE
Always-on (DEBUG and Release) `os_signpost` facade so Instruments can graph the switch path; release-safe Sentry breadcrumb `workspace.switch.complete` with `dt_ms`. Phase events at every existing `ws.*` dlog site.

**Shipped in:** PR #127 / branch `perf/workspace-switch-instrumentation` / commit `4ac704b8`.

### Phase 1 — Hide off-screen workspaces from AppKit layout ✅ DONE
`AppKitHiddenWrapper` (`NSViewControllerRepresentable` hosting `NSHostingController<Content>`, toggling `host.view.isHidden`) wraps every `WorkspaceContentView` in `ContentView.terminalContent`. AppKit's `_layoutSubtreeWithOldSize:` short-circuits at hidden subviews, so off-screen workspaces' subtrees are skipped entirely. SwiftUI subtree preserved; surfaces don't dismount/remount.

**Shipped in:** Same commit as Phase 0.

**Measured impact** (11 workspaces / ~20 agents loaded):

| Metric | Baseline | Phase 0+1 | Improvement |
|---|---|---|---|
| `handoff.start` dt (SwiftUI cascade) | ~1,500 ms | 17–77 ms | ~30–80× |
| `asyncDone` median | ~1,000 ms | ~325 ms | ~3× |
| `asyncDone` p95 | ~6,000 ms | ~1,200 ms | ~5× |
| `asyncDone` worst seen | 90,790 ms | 2,426 ms | tail eliminated |

### Phase 2 — Eliminate the deferred portal bind 🔄 IN PROGRESS
Currently surfaces mount in SwiftUI before their host containers are in an NSWindow → `ws.hostState.deferBind reason=hostNoWindow` fires for each → portal bind is deferred to `onDidMoveToWindow` callback (GhosttyTerminalView.swift:9344-9370 / 9462-9469) → when the deferred bind fires after the first AppKit layout cascade, it triggers a second one.

Two candidate fixes:
- **(a)** Pre-attach host containers eagerly so they're in the window before SwiftUI mounts the surface (synchronous bind in `updateNSView`).
- **(b)** Defer SwiftUI mount until host is in window via a guard at the surface boundary.

Implementation agent active in c11 surface (pane:52 / `phase2-impl`) at the time of writing.

**Expected impact:** collapses the second AppKit layout cascade. On heavy switches this is the 700–1,500 ms `last swiftui.update → unfocus.defer` gap. Could roughly halve heavy-switch `asyncDone`.

### Phase 3 — Defer non-essential async-block work past the visible flip
Today the queued `DispatchQueue.main.async` block in `selectedTabId.didSet` runs `focusSelectedTabPanel` + `updateWindowTitleForSelectedTab` + `markFocusedPanelReadIfActive` together. `panel.focus()` invalidates layout, triggering a third cascade (the `unfocus.defer → asyncDone` gap of 150–350 ms).

**Fix:** split into two queued blocks. Block 1 (immediate): focus only — needed for input routing. Block 2 (next runloop tick after first frame paint): title update + read mark + any other side-effects.

**Expected impact:** moves the third cascade out of the user-perceived switch window, even if the underlying work cost stays. Smaller, lower-risk than Phase 2. May be moot if Phase 2 already collapses both remaining cascades; decide after Phase 2 lands.

### Phase 4 — Narrow `terminalContent`'s ForEach observation
Phase 1 stops AppKit from laying out invisible workspaces, but the SwiftUI body of every mounted `WorkspaceContentView` still re-evaluates on every `selectedTabId` flip. The `ForEach(mountedWorkspaces)` in `ContentView.terminalContent` re-creates prop bindings (`isWorkspaceVisible`, `isWorkspaceInputActive`, `workspacePortalPriority`) for each mounted workspace whenever any of them changes. So 7 mounted workspaces' bodies + their pane trees + every surface's `updateNSView` all re-evaluate per switch.

**Fix:** hoist per-workspace presentation state into per-workspace `ObservableObject`s (e.g., `WorkspacePresentationStore`). Each `WorkspaceContentView` observes only its own slice. The ForEach iteration only varies on workspace identity; props don't change. Workspaces whose state didn't change skip body re-eval, skip `updateNSView`, skip the whole subtree's SwiftUI cascade.

**Expected impact:** cuts the SwiftUI body-eval cascade from O(mounted) to O(2) — the workspace going inactive + the one going active. Probably 50–150 ms on heavy switches. Also reduces ambient main-thread work during agent activity.

**Effort/risk:** Medium / medium. Localized to ContentView + WorkspaceContentView. State propagation must preserve handoff-during-retiring and background-prime semantics that `terminalContent` currently encodes inline.

### Phase 5 — Narrow `@EnvironmentObject TabManager` into smaller stores
`TabManager` is held as `@EnvironmentObject` in ~4 root views (`ContentView`, sidebar root, `NotificationsPage`, `SidebarEmptyArea`). Any `@Published` change in `TabManager` — `selectedTabId`, `tabs`, `isWorkspaceCycleHot`, `pendingBackgroundWorkspaceLoadIds`, status mutations, history mutations — re-evaluates **all four** root views, regardless of which property they actually read. This is the structural reason ambient activity (panel-title coalesce, status updates, agent output triggering badge changes) feels heavy even when nothing visible is changing.

**Fix:** split `TabManager`'s published surface into smaller `ObservableObject`s — `WorkspaceSelectionStore` (`selectedTabId`), `TabsListStore` (`tabs`), `WorkspaceStatusStore` (status/badges), `WorkspaceCycleStore` (cycle/hot state). Each root view observes only the slice it needs. `TabManager` itself stays as the orchestrator but stops being a single broadcast source.

**Expected impact:** the single biggest fix for *ambient* "system feels sluggish" (separate from switching). Every TabManager publish stops being a 4-way broadcast. Pays off across the entire app. Likely cuts SwiftUI body-eval volume by 5–10× under heavy agent activity.

**Effort/risk:** High / medium. `TabManager` is 3,000+ lines used everywhere; this is a careful refactor, not a fix. But mechanical (move `@Published` markers; introduce sub-stores; thread through environment) — no new logic. Ideally spread over 2–3 PRs.

### Phase 6 — Bonsplit nesting reduction
The 30-level `_layoutSubtreeWithOldSize:` recursion comes from bonsplit. Each split level adds ~5 NSView wrappers (`NSSplitView` + 2× `SplitArrangedContainerView` + 2× `NSHostingController.view`); each pane adds another `PaneDragContainerView` + `NSHostingController.view` + `PaneContainerView`.

**Fix candidates:**
- Drop `SplitArrangedContainerView` wrappers; let `NSSplitView`'s `arrangedSubviews` host content directly. Each wrapper exists for `mouseDownCanMoveWindow=false` and `masksToBounds`; both can be set on the hosted view directly or via a subclass.
- Collapse the per-pane `PaneDragContainerView` + nested hosting view chain into a single subclassed hosting view that absorbs the drag-container responsibilities.

**Expected impact (with caveats):** the visible workspace's layout cost is what's left after Phase 1 — currently 700–1,500 ms on heavy switches. AppKit's Auto Layout cost isn't linear in tree depth, but reducing depth by ~30% plausibly shaves 30–50% off that. So Phase 6 might take heavy-switch asyncDone from ~1,500 ms → ~750–1,000 ms. Median (already ~325 ms, dominated by lighter switches) probably barely moves.

**Worth-it threshold:** c11 owns its bonsplit fork, so the upstream-coordination cost is gone — this is purely a "structural risk vs perf gain" decision. Each wrapper exists for a reason (drag handling, layout binding, focus routing); pulling them risks regressions in typing latency, drag-and-drop, focus restoration. **Do not start Phase 6 until Phases 2–4 land and we re-measure.** If heavy-switch tail is still in the 800–1,500 ms range and attributable to bonsplit depth (verifiable in a fresh `sample`), Phase 6 becomes justified. If by then tail is sub-500 ms, skip it.

## Cross-cutting observations

- **Ghostty cost is intrinsic.** Per-surface NSView + Metal layer + renderer thread are baseline. No phase tries to remove these; all phases target architectural cost (SwiftUI cascades, AppKit Auto Layout traversal, deferred binds).
- **Typing latency hot paths must NOT regress.** `TerminalSurface.forceRefresh()`, `TabItemView` equatable + `.equatable()`, `WindowTerminalHostView.hitTest()`. Verified intact through Phase 1; each subsequent phase must preserve.
- **Test method:** for each phase, build with `./scripts/reload.sh --tag <name>`, exercise with realistic workspace state, extract per-phase dt breakdown from `/tmp/c11-debug-<tag>.log` `ws.*` events, compare to baseline.

## Status

- Phase 0 + Phase 1: shipped (PR #127, awaiting review/merge).
- Phase 2: implementation in progress (sub-agent active).
- Phases 3–5: planned, not started.
- Phase 6: gated on Phase 2–4 results.
