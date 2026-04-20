# Adversarial Plan Review — CMUX-25 (Multi-window c11mux, Emacs-frames v1)

- PLAN_ID: `cmux-25-plan`
- MODEL: Claude
- Reviewed: 2026-04-19
- Plan under review: `.lattice/plans/task_01KPHHQZA4XZTQD4BQCGQYC7FR.md`
- Covers: **CMUX-25** (v1 phased implementation) and its dependency **CMUX-26** (v2 hotplug)

---

## Executive Summary

The plan's architecture (Hybrid C: process-scoped `PaneRegistry` + per-window `WorkspaceFrame`) is the right answer to the north-star goal. The prose is confident, the primitive hierarchy is clean, and the six-phase staging is defensible. That said, **several load-bearing claims are asserted rather than proven**, and the weakest of them are exactly where a halfway-working multi-window terminal becomes an operator-hostile product:

1. **The "one WorkspaceFrame per {workspace, window}" invariant is under-specified.** Nothing in the plan enumerates what breaks when a workspace is hosted in *two* frames simultaneously — focus, selection, status pills, notification badges, sidebar "jump to frame" semantics, Cmd+W, tab-bar drag reentry. The plan treats "multiple viewports onto shared state" as a property that falls out of the data model. It doesn't. Every UI state that was silently per-window-because-there-was-only-one-window is now a consistency bug waiting to ship.

2. **`PaneRegistry` is declared actor-isolated but the lifecycle is shared with `@MainActor` AppKit state** (PTYs, Ghostty surfaces, MTL layers, NSView hierarchies). That seam is where every "why did closing window B kill my PTY in window A?" bug lives. The plan says "Moving a pane across windows = unlink the leaf in frame A, link it as a leaf in frame B; the Pane object itself (PTY, Ghostty surface, MTL layer) is untouched." That's a *goal*, not a design. The actual design — reparenting a `CAMetalLayer` / `NSView` across NSWindow backing stores — is not addressed.

3. **Cross-window drag-drop is asserted to "work at v1 with minimal code change" on the basis of reading API headers, not exercising them.** The plan's entire evidence is "should work" plus one integration test. The known-hard AppKit cases (drag-to-minimized, Spaces crossing, fullscreen, source-window-closes-mid-drag, Mission Control, drop target geometry on offscreen siblings) are not enumerated, let alone tested. The "fallback to CLI-only" escape hatch is reasonable — but v1.1 timing for "reinstate drag" is unspecified, and a half-working drag is worse than no drag.

4. **"No perf target at v1" is defensible posture, but there is no perf canary either.** CMUX-15 shipped without a perf gate *for a feature that was a single-window grid*. Multi-window across displays crosses refresh-rate domains, Metal backing stores, and input-latency-sensitive paths (the CLAUDE.md explicitly calls out `hitTest`, `TabItemView`, `TerminalSurface.forceRefresh` as hot paths). "We'll measure later if it bites" means: we'll measure when an operator tells us typing got laggy, by which point Phase 2 is six weeks old and the regression bisect is expensive.

5. **The feature-flag retirement rule ("after Phase 3 soaks on main for a release cycle") is the single most fragile governance decision in the plan.** One release cycle for a refactor that rewires the entire workspace/pane ownership model is not enough soak if the UX bugs are intermittent or operator-rig-specific (hotplug, Spaces, monitor-class). There is no objective bar for "soak passed." No telemetry. No opt-out channel during soak. No rollback plan if a Phase-3 bug appears in week 2 of soak with the flag already retired.

**Single biggest issue:** Phase 2 is called "~2 weeks" and is where the entire ownership model gets rewritten. `TabManager.swift` is 5,283 lines. `AppDelegate.moveSurface` alone touches `detachSurface`/`attachDetachedSurface`/`locateSurface`/`mainWindowContexts` across ~50 call sites. Re-homing all of this — plus splitting `SidebarState`, plus adding session-persistence schema migration, plus renaming the public socket API with a shim — in two weeks is aggressive to the point of being a tell that the author has not yet done the call-site audit. **Phase 2 is almost certainly 4–6 weeks in reality, and the plan's pacing cascade (Phases 3–6 in parallel after 2 lands) depends on Phase 2 being merge-clean.**

Concern level: **moderate-to-high** on execution; **moderate** on architecture (the direction is right; the details are under-specified).

---

## How Plans Like This Fail

Plans that sever a deeply-coupled ownership seam in a large UI codebase typically fail in one of these patterns. This plan is vulnerable to most of them:

### 1. "The refactor was clean, the semantics leaked"
You move `panels` from `Workspace` to `PaneRegistry`, every call site compiles, tests pass — and then in production a pane closes when the window does because one of the ~40 `removeSurface` / `closePanel` / `pruneSurfaceMetadata` call sites still assumes window-scoped lifecycle. **Mitigation present?** No. The plan describes the new types and says "Rename `owningTabManager` → `workspaceRegistry` reference" but does not audit the lifecycle touch-points. The phrase "Panel lifecycle (PTY spawn/teardown, Ghostty surface create/destroy) moves here from `Workspace`" is one sentence. It's going to be a week of work by itself.

### 2. "The data model is right, the view model is wrong"
`WorkspaceFrame` is defined, but SwiftUI's `@EnvironmentObject` / `@ObservedObject` plumbing wasn't rethought. Now two frames viewing the same workspace both subscribe to the shared registry and both trigger view rebuilds on every pane update — and one of those views lives on a 144Hz display and the other on 60Hz. **Mitigation present?** No. `ContentView` changes are sketched ("sidebar view moves from reading `@EnvironmentObject var tabManager: TabManager` to reading `@EnvironmentObject var workspaceRegistry: WorkspaceRegistry`") but the Combine/publisher surface is not dimensioned. No mention of `objectWillChange` fan-out, debouncing, or per-frame subscription scoping.

### 3. "We flagged it, then the flag decayed"
Feature flags that gate *architectural* changes are different from feature flags that gate behavior. `CMUX_MULTI_FRAME_V1` gates Phase 2 (ownership refactor). That means the flag-off code path has to *also* implement the refactor but with single-frame-per-workspace semantics preserved. That is not a feature flag — that's a dual-mode system with its own bugs. **Mitigation present?** No. "Preserves single-frame-per-workspace semantics at this phase — no visible multi-window behavior, just refactored ownership" — how does the registry enforce single-frame-per-workspace when flag is off? What code path rejects a second frame? Is the rejection at the registry layer, the socket layer, the UI layer? Unspecified.

### 4. "The migration ran, the migration was wrong"
`AppSessionSnapshot` schema bump at Phase 2 with a migration from the current format. The current format has embedded workspace data per-window. The migration collapses that into a top-level workspace collection. What happens if a user ran a dev build with the flag on, has a session snapshot with multiple frames per workspace, then rolls back to a pre-Phase-2 build? Forward migration is specified; **rollback migration is not.** Schema migrations that aren't reversible are a trap.

### 5. "The soak period was quiet because nobody used it that way"
The plan says the flag retires after Phase 3 soaks on main for a release cycle. Who's running it with 3 monitors during soak? This is Atin's rig and possibly one other dev. Operators on single-laptop-display will never exercise cross-window drag, `workspace.spread`, or pane migration — so their quiet soak is evidence of nothing. **Mitigation present?** No. No explicit "eat-your-own-dogfood for N weeks on the multi-monitor rig" gate. No telemetry event counting frame creations, cross-window moves, spread invocations. No channel for the one person actually using it to report "something's weird."

### 6. "We deferred hotplug and hotplug happened anyway"
CMUX-26 defers runtime `didChangeScreenParametersNotification` handling. But **c11mux already listens to display changes** (session persistence is display-aware). If the v1 code does nothing special on disconnect, what happens to a window whose `WorkspaceFrame` was rendered on the departing display? macOS migrates the NSWindow. Does c11mux's internal display-id cache stale? Does `DisplayRegistry` publish `displaysChanged` while there is no handler? The plan says "16a consumes for CLI enumeration only; runtime hotplug response is deferred to the v2 follow-up ticket" — but the signal is still being published. Silent drift in `DisplayRegistry` while nobody is listening is the exact category of bug the deferral was supposed to avoid.

### 7. "The API rename worked, the ecosystem broke silently"
`workspace.move_to_window` → `workspace.move_frame_to_window` with one-release shim. The plan assumes there is no external automation depending on the old name beyond "one release." **How would the author know?** There is no enumeration of consumers: operator scripts, other Stage11 projects' automation, Atin's personal shell tooling, the `claude-in-cmux` skill doc, cmuxterm-hq CI, third-party users of the beta. The shim logs a DEBUG deprecation — that's invisible to anyone running a Release build, which is most external users.

---

## Assumption Audit

Grouped by load-bearing vs cosmetic. Load-bearing = plan collapses if false. Cosmetic = plan adjusts but survives.

### Load-bearing

**A1. "Bonsplit still owns one tree per BonsplitController; we just create N controllers per workspace (one per frame) instead of one."** (§Code change sketch → vendor/bonsplit)
> Quote: "no contract change. Bonsplit still owns one tree per BonsplitController; we just create N controllers per workspace (one per frame) instead of one."

*Likelihood this holds: moderate.* Bonsplit was designed with the *implicit* assumption that a tree's PaneIDs are uniquely owned by that tree. Having the same PaneID leaf appear in two BonsplitControllers in different windows is a new constraint. If Bonsplit internally caches or indexes panes (divider-drag target lookups, tab focus, keyboard navigation), those caches are now inconsistent across controllers. Not addressed.

**A2. "`.ownProcess` pasteboard visibility already allows intra-process cross-window; `AppDelegate.moveSurface` / `locateSurface` already walk all windows."** (§3)
> Quote: "Conclusion: cross-window drag-drop should work at v1 with minimal code change."

*Likelihood this holds: moderate.* Walking windows in a socket command handler is one thing. A drag gesture requires drop-target SwiftUI views to be mounted in every window, receive drag enter/exit notifications across window boundaries, and resolve geometry correctly when the source window is not frontmost. The codebase already has `WindowTerminalHostView.hitTest` as a known typing-latency hot path (CLAUDE.md "Pitfalls"). Cross-window dragging adds drop-target hit-testing to a second window *while a drag is in flight* — that's a new hitTest pressure regime. Not considered.

**A3. "Every call site that reaches `workspace.panels[panelId]` today routes through the registry."** (§1, "Cost of C")
*Likelihood this holds: low without an explicit audit.* The plan estimates "4–6 weeks of focused work" for the registry refactor but the ticket body assigns **~2 weeks** to Phase 2. Either the estimate in §1 is stale or the ticket body underestimates. Both can't be right. Given `TabManager` is 5,283 lines and `moveSurface` touches `mainWindowContexts` across 10+ code paths in AppDelegate alone, 2 weeks is the aspirational estimate; 4-6 is the honest one.

**A4. "Closing a window destroys its frames, never its panes — remaining-only-on-that-window panes either migrate to another frame of the same workspace or hibernate."** (§1)
*Likelihood this holds: depends on "or hibernate" being in v1.* §1 says "or hibernate." Then §6 says hibernation is **deferred to v2**. Contradiction. If there's no hibernation at v1, and no other frame of the workspace to migrate to, then closing a window either:
- orphans the pane (pane alive in registry, not rendered anywhere — garbage collection problem, socket `tree` still shows it, focus cycling shows nothing), or
- destroys the pane (violates A4), or
- forces the user to confirm destroy (UX not specified).
**The plan does not pick.**

**A5. "Moving a pane across windows = unlink the leaf in frame A, link it as a leaf in frame B; the Pane object itself (PTY, Ghostty surface, MTL layer) is untouched."** (§1)
*Likelihood this holds: low as written.* Ghostty's `CAMetalLayer` is attached to a specific `NSView`'s layer tree in a specific `NSWindow`. Re-parenting a `CAMetalLayer` across NSWindow backing stores is not a pointer-move; it involves reacquiring Metal device references, backing-store sampling factors (retina factor, HDR tone map, color space), and sometimes a transient black frame. The plan asserts untouched; the reality is "reparented with a reinit dance." Not specified.

**A6. "Session persistence schema bump at Phase 2 with a migration that re-normalises embedded workspace data into the new top-level collection."** (§6)
*Likelihood this holds: likely, but reverse migration is not covered.* One-way migration is a standing trap if users move between Release and Debug/tagged builds.

### Cosmetic

**B1.** Spread uses `ceil(N/D)` fill-leftmost. Fine; easy to change later.
**B2.** `SidebarMode.primary` / `.viewport` are stubs. Fine *if* the seam is actually clean (see §Challenged Decisions).
**B3.** `display:left` / `display:center` / `display:right` addressing. Fine. (Though "center only when N odd" is a footgun for 4-monitor rigs — ambiguity by design.)
**B4.** `Cmd+Opt+Shift+<Arrow>` for split-overflow. Bikeshed. Defer.

### Invisible (not stated, assumed)

**I1.** Assumes that when a user closes a window with workspace X's only frame, workspace X's remaining panes continue to exist in the registry and can be brought back by opening a new window. No UI path is designed for that scenario.

**I2.** Assumes the Sidebar, which today lists "this window's workspaces," will at v1 list *all* workspaces in the registry — including those currently hosted in other windows. How are those rendered? Greyed? Marked with a "hosted elsewhere" badge? The plan mentions a `⧉ 3` badge and says "v1 can ship without the badge." Without the badge, two windows can show the same workspace selected in both sidebars with no visual indication.

**I3.** Assumes cross-window focus (Cmd+~) works identically to today. macOS handles window focus, not c11mux. But the sidebar-selection-follows-window model means that Cmd+~ now implicitly changes the sidebar's "active" workspace. Does that cancel in-progress typing in a TerminalSurface? Does it reset focus to the newly-active window's focused pane? Today this is clean because per-window sidebar was identical across windows. Now sidebars can show *different* workspaces. The plan says "Cmd+~ does NOT re-focus" — that resolves focus but not sidebar behavior.

**I4.** Assumes `PaneRegistry` (actor-isolated) can be called from SwiftUI views that are `@MainActor`. Actor hops add async boundaries. Any view property that today reads a pane detail synchronously now needs an async wrapper or a MainActor-published cache. Not designed.

**I5.** Assumes that status/log/progress updates (already high-volume on the socket hot path per CLAUDE.md "Socket command threading policy") don't fan out to all windows hosting a workspace-frame for the target pane. If a pane is in one registry but two windows render it, both windows' sidebars subscribe. That's fine — but CLAUDE.md's explicit warning against `DispatchQueue.main.sync` on telemetry hot paths means the publisher-subscriber chain needs to be off-main for parse and dedupe, then hop on-main per window. Not designed.

**I6.** Assumes bonsplit's tab-drag gesture does not mutate source-tree state until drop commit. If it does (e.g., for visual feedback during drag), the source tree state must be reverted if the drop lands in a sibling window's tree. Cross-tree drops are new.

---

## Blind Spots

### Multi-frame same-workspace invariants (the big one)

Almost nothing in the plan enumerates what it means to have **the same workspace hosted in two windows at once.** This is the north-star feature, and yet:

- **Focus ambiguity:** Each window tracks "its focused pane." Both windows' focused panes may be in the same workspace. `cmux identify` returns the caller window's focused pane. What about `workspace.focus` (if it exists) — which window's frame gains focus?
- **Selection:** Sidebar selection is per-window, so both windows can have workspace X selected. Fine. But `workspace.rename` or `workspace.close` — do both windows reflect the change? (Probably yes via registry.) Does the window that initiated the `workspace.close` get asked "this workspace is open in 1 other window — close anyway?" Unspecified.
- **Pane-to-tab promotion:** When a pane gains a second surface, bonsplit renders a tab bar. If that pane is visible in two frames, both tab bars render. Both are interactive. Two operators on the same rig (or the same operator with two windows visible) can click different tabs in different frames. Which is the "current tab" for keyboard shortcuts that target "current surface"?
- **Drag-from-A-while-visible-in-B:** User drags a tab from its rendering in window A. It's still being rendered in window B. What does B show during the drag? Ghost tab? Greyed? Nothing?
- **Cmd+W (close current tab/surface):** Does it close the surface (affects both frames) or untab-from-this-frame-only? Closing the surface is the only sane answer (surfaces are shared), but the gesture feels like "close from my view."
- **Cmd+N (new surface in current pane):** New surface appears in both frames' rendering of that pane. Is that intentional or a tab-bar flicker?

**None of these are addressed.** The plan mentions "multiple viewports onto shared state" but doesn't enumerate which state is shared and which is per-viewport. This gap will produce a string of "why is this weird?" bugs across the soak period, each individually minor, collectively defining product quality.

### Teardown races in `PaneRegistry`

> Quote (ticket body): "Introduce `PaneRegistry` (process-scoped, actor-isolated): panes become first-class process objects."

Actor isolation solves concurrent-access-to-the-dictionary. It does not solve:
- **Concurrent `pane.move` and window close.** Socket command `pane.move` lands on the PaneRegistry actor. Simultaneously, user closes the window containing the source frame. Who wins? If `pane.move` won, the pane survives but its source frame is gone — fine. If window close started tearing down the source frame first, the pane's view layer hierarchy may be in a transitional state. The actor-isolated registry doesn't see the view layer.
- **Drag-in-progress when source window closes.** User starts a drag in window A. Window A gets an NSWindow close event (e.g., user hits Cmd+W on the *window*, or the window closes because a workspace move completes). Drag session is orphaned on the NSDraggingSession side but the TabTransferData still exists on the pasteboard. If the drop lands, what pane is being moved?
- **Teardown during `workspace.spread`.** Spread creates N windows. Each window creation is async (NSWindow creation is main-thread, but frame setup / bonsplit controller creation / pane leaf reference assignment may involve actor hops). If the user cancels / closes one window mid-spread, the half-created frame's pane references are stale.

The plan's actor-isolation claim does not extend to the AppKit/SwiftUI lifecycle it depends on.

### Drag-drop edge cases specific to macOS

The plan's §3 is 14 lines on drag-drop. Actual AppKit reality:
- **Drag-to-minimized window:** NSWindow that's minimized doesn't receive drag-enter. Drop target in a minimized sibling silently doesn't exist. Expected but not mentioned.
- **Drag across Spaces:** NSWindow in a different Space is not a valid drop target unless "all Spaces" is set. macOS handles this; cmux doesn't need to. But the UX feels like "drop didn't work." Should c11mux offer a hint?
- **Drag to fullscreen window:** Fullscreen NSWindows have modified drag behavior. Drop targets may not activate until the source window's Space is switched.
- **Source window closes mid-drag:** Known AppKit hazard. Swizzled `draggedOntoWindow` in AppDelegate — are the swizzles window-scoped?
- **Drag and Mission Control:** If the operator triggers Mission Control mid-drag (F3), the drag session is paused. On resume, state may be inconsistent.
- **Drag from window A while bonsplit is mid-divider-drag in window B:** Two concurrent drag gestures in one process. Bonsplit's drag state is presumably per-controller, so this *should* work — but the plan has N controllers now, not one, and their interaction isn't tested.
- **High-DPI / mixed-DPI drags:** Dragging a tab from a 1x display to a 2x display. The drag preview scaling is macOS's problem; the drop geometry must be correct across scale boundaries. Unverified.

"One integration test" is not coverage for this surface.

### Observability

Zero mentions of logging, telemetry, or diagnostics for the new primitives. Questions that have no answer:
- How do I enumerate "all frames of all workspaces" for debugging? (Likely `cmux tree --by-window`, but the plan adds `--by-display`; `--by-window` existence is implied, not confirmed.)
- How do I see "which windows currently host this pane"? (Needed when debugging "pane appears to be frozen" — it might be frozen *in window A* but fine in window B, which is information only a registry inspector can provide.)
- What dlog events does cross-window migration emit? The plan says existing `moveSurface` dlog shape should be preserved; it doesn't specify the new events.

### Accessibility

VoiceOver, keyboard navigation, and window ordering are not mentioned. If a workspace is hosted in two windows, VoiceOver rotor navigation that today says "Workspace: Backend, 3 panes" now has to say something about "also visible in another window." Unconsidered.

### The CLI's mental model

Adding `--display`, `--by-display`, `display_ref`, `window_ref`, `workspace_ref`, `pane_ref`, and `frame_ref` to the socket surface is a lot of new nouns. The plan doesn't include a CLI help-text audit. Operators will have to relearn `cmux tree` output — JSON schema changes with new fields are backward-incompatible for any consumer that validates strict schemas. Not addressed.

---

## Challenged Decisions

### "No formal perf target at v1 (per resolved Q1)"

**Plan text:** "No formal perf target at v1. Land feature, measure later."

**Counterargument:** The CLAUDE.md explicitly enumerates typing-latency-sensitive hot paths. Multi-window adds:
1. A second window's hitTest running during typing in the first (if mouse is over it).
2. Combine publishers fanning out to N window subscribers.
3. Cross-window Metal layer management.
4. Actor hops for pane data that views read.

Every one of these is a silent regression vector. Without a target, nobody writes a benchmark, nobody benchmarks before/after Phase 2, and the first operator to notice latency has no data to bisect with. "Same posture as CMUX-15" is not analogous — CMUX-15 added a grid, which is geometry on one window. This adds inter-window fan-out.

**What the plan should have:** even without a target number, add a benchmark suite at Phase 1 that measures keystroke→onscreen latency, `cmux tree` response time, and frame creation latency, captured pre-Phase-2 and re-run after each phase. No number required; just the data.

### "Feature flag retires after Phase 3 soaks on main for a release cycle"

**Plan text:** CMUX-25 acceptance: "All six phases land on main behind the feature flag `CMUX_MULTI_FRAME_V1=1`; flag is retired after Phase 3 soaks."

**Counterargument:** "A release cycle" isn't a gate; it's a duration. A duration can pass without any multi-window user exercising the code path. The objective gate should be *usage*, not *time*.

**Alternatives the plan doesn't consider:**
- Retire the flag when telemetry shows N multi-window sessions have run for M days with zero crash reports referencing registry/frame symbols.
- Retire the flag only after someone outside Atin's rig runs it for a week.
- Keep the flag forever as a kill switch (operational cost is low).
- Tiered retirement: `CMUX_MULTI_FRAME_V1=1` becomes default-on after Phase 3 soak, but the env var still disables it for 2 more releases. Removes silent lock-in.

### "Deprecation shim for `workspace.move_to_window` — one release window"

**Plan text:** "Shim is removed one release after 16b lands."

**Counterargument:** One release cycle is an arbitrary deadline for a public socket API. What counts the downstream consumers? Atin's personal tooling? Other Stage11 projects? The cmux skill file that agents read? Third-party users of tagged beta builds?

**Right answer is probably two releases, not one,** unless there's telemetry proving zero old-name callers. The plan mentions surfacing `deprecation_notice` in the response for automation-find — good — but doesn't propose running any grep across known Stage11 consumer code paths before coining the removal release.

### "`SidebarMode.primary` / `.viewport` exist as seams but only `.independent` is wired"

**Plan text (§4 / §2):** "values exist, only `.independent` is wired at v1"; `broadcastSelection` is a no-op.

**Counterargument:** Dead code seams have a terrible track record. They either rot (when the sync-mode work picks up, the stubs are wrong because they encoded an understanding from 6 months ago), or they confuse code-readers (who see `.primary` referenced in type signatures but find no implementation). The claim that the seam "admits a clean future implementation" is unfalsifiable at v1 — by definition, it's only clean if the future implementation fits it, and there is no future implementation yet.

**Better:** don't carry stub values. When sync mode becomes real in a later release, add them then. Serializing `sidebarMode` in session snapshots at v1 is forward compatibility; adding enum cases that no code produces is forward-commitment.

**Specifically risky claim:** "Session persistence (`SessionWindowSnapshot`) serialises `sidebarMode` per window so future sync-mode state survives relaunch." At v1 every snapshot writes `.independent`. When v2 or a later release introduces `.primary`, migration is needed *from `.independent` always* to the new state machine — no real data survives relaunch because no real data was ever written. The "seam" saves nothing.

### "Cross-window drag-drop: ship at v1"

**Plan text (§3):** "Ship at v1 (extend existing bonsplit gesture)… If a blocking AppKit issue surfaces, fall back to CLI-only cross-window move and reinstate drag at v1.1."

**Counterargument:** Drag is the ergonomic primary path. A failed drag with no visual indication of why (drop target silently rejects, or drag enters but drop does nothing) is worse than a missing drag because the operator thinks the feature is broken rather than absent. "Fall back to CLI" saves the ticket but surrenders the feature's main UX.

**Alternative:** ship CLI-only at v1, drag at v1.1 with an explicit "drag validation pass" (a week of focused cross-window drag testing in all the scenarios I listed above). This is unpopular because it's slower, but the failure mode is strictly better.

### "Phase 2 is ~2 weeks"

**Plan text (ticket body):** "Phase 2 — Workspace/pane registry refactor (~2 weeks)"
**Plan text (§1):** "Rough estimate: 4–6 weeks of focused work across 3–4 implementation sub-tickets."

**Contradiction.** §1 was written when the work was split across 3–4 tickets; ticket body consolidates to one ticket and keeps the aggregate but reassigns "~2 weeks" to the biggest phase. It doesn't add up. 4–6 weeks for the whole refactor suggests Phase 2 alone is 3+ weeks. The ticket body's "~2 weeks" is optimistic.

### "CMUX-26 depends on CMUX-25 Phase 2"

**Counterargument:** The v2 ticket describes display-affinity tracking and hotplug handling. The plan §6 says v1 does nothing on disconnect — "windows stay alive; macOS auto-migrates them to surviving displays and c11mux does nothing." But c11mux *already* has display-aware session persistence. If c11mux does nothing on runtime hotplug, does it still update persisted display state on the next session save? If yes, a session save after a monitor-disconnect writes the new (macOS-migrated) display position as though the user intended it — next launch restores to the wrong display. **The v1 "do nothing" stance has a subtle interaction with existing persistence that is not addressed.**

---

## Hindsight Preview (things we'll wish we'd done)

Two years from now, most likely:

1. **"We should have built a per-frame layer hierarchy integration test at Phase 2."** Reparenting Metal layers across NSWindow backing stores is the kind of thing that works on the dev rig and fails on the user's Intel MacBook Pro with external Pro Display XDR + LG UltraFine on a Thunderbolt chain. No such test is planned.

2. **"We should have kept the flag as a kill switch permanently."** Retiring the flag saves three conditionals. It also eliminates the rollback lever when an obscure regression surfaces at release-N+3.

3. **"We should have written the multi-frame invariants doc before Phase 2, not discovered them via bug reports."** The "what state is shared vs per-viewport" table is implicitly encoded in the SwiftUI view hierarchy and the registry boundaries. Making it explicit in a doc forces the design to close.

4. **"We should have tested the drag with source-window-closes."** Every refactor that changes window ownership breaks at least one "what happens when source goes away mid-operation" edge case.

5. **"We should have shipped v1 with the Sidebar 'hosted elsewhere' indicator, even ugly."** Without it, two windows can show the same workspace selected and the operator has no cue. The `⧉ 3` badge is not a nice-to-have, it's orientation.

6. **"We should have decided what happens to a workspace when its last-hosting window closes, before we shipped."** Orphaned-in-registry panes, hibernate, destroy-with-confirm — pick one. v1 that doesn't pick ships the worst option by default (orphaned or crashy).

7. **"We should have done a consumer grep before renaming `workspace.move_to_window`."** Discovering a shell script in a Stage11 sibling project that breaks post-shim-removal is a trivial-to-prevent embarrassment.

### Early warning signs the plan should watch for (and has no explicit mechanism to detect)

- CI test time for cmux-unit or socket tests grows >20% after Phase 2. (Proxy for actor hop overhead.)
- `cmux tree` response time grows noticeably when many panes exist. (Proxy for registry-walk inefficiency.)
- User reports "type lag in window A when window B is active." (Proxy for hitTest or publisher fan-out pressure.)
- Any crash with `PaneRegistry` or `WorkspaceFrame` in the stack. (Proxy for lifecycle races.)
- Session restore logs a warning ("workspace referenced by window snapshot not found"). (Proxy for schema migration bug.)

None of these have explicit monitoring or dashboards planned.

---

## Reality Stress Test

**Three simultaneous disruptions most likely to hit this plan:**

1. **Atin goes on vacation or gets pulled onto a higher-priority project.** CMUX-16 sign-off, CMUX-25 code review, and the Phase 2 design discussions all depend on him. The plan is reviewed and implemented primarily by agents; the one human in the loop is the bottleneck. What happens if his review lag doubles? Phases queue. Flag doesn't retire (no human to call "soak passed"). v2 ticket (CMUX-26) never starts because "default TBD based on v1 operator feedback" has no operator feedback.

2. **A macOS point release changes drag-session behavior.** Apple ships macOS 26.2 or 26.3 during the Phase 3 window. AppKit drag APIs are not a ABI-stable contract in the way you'd hope. `.ownProcess` visibility, dragging session pasteboard lifetime, and swizzled `draggedOntoWindow` are all potential regression surfaces. With no dedicated drag integration test suite and no CI matrix against macOS versions, a regression would ship.

3. **A Ghostty submodule update changes surface-init semantics.** The plan's "PTY / Ghostty surface / MTL layer move here from `Workspace`" is a pointer-move assertion. If Ghostty upstream changes how surface initialization binds to a host NSView/NSWindow — e.g., adds renderer context acquisition that requires the target window at init — then the "untouched on move" promise breaks. The ghostty fork is tracked at `docs/ghostty-fork.md`; no mention in CMUX-25 of coordinating with Ghostty work.

**Combined failure mode:** Atin is out, macOS 26.3 ships breaking drag behavior, Ghostty upstream rebases in a surface-init change, and Phase 2 landed on main last week with the flag on for Atin only. Nobody catches the drag regression until the first operator tries it, by which point the Phase 3 soak period is half over and the flag retirement is on a countdown. The plan has no mechanism to pause the soak clock.

---

## The Uncomfortable Truths

**T1. This plan was written by an agent, for a human reviewer who is also the only person who will exercise the feature during soak.** The soak period is theatrical if Atin is the only multi-monitor user. Calling one person's dev usage "soak" is soak in name only.

**T2. The "one phased ticket instead of six" decision was driven by management preference (Atin's redirect), not by technical coupling.** Phases 3–6 really are parallelizable; separate tickets would make parallelism and ownership clearer. The consolidation makes status tracking cleaner for the human but makes the work's structure less legible to agents picking up individual phases. If multiple agents take Phases 3/4/5/6 in parallel (as is encouraged), they need to coordinate through ticket comments on a single ticket — less ergonomic than separate tickets with cross-references.

**T3. The two-week Phase 2 estimate is a tell.** Anyone who has read `TabManager.swift` (5,283 lines) and `AppDelegate.swift` (~5000 lines of which ~60 call sites touch `mainWindowContexts` or `moveSurface`) and come out saying "two weeks" is either an agent that hasn't done the call-site audit or a very optimistic planner. The §1 estimate (4–6 weeks for "3–4 sub-tickets") is the honest one. The ticket body's "~2 weeks" for one phase is aspirational.

**T4. The "architect for a future sync mode but don't build it" seam is speculative YAGNI.** It commits API surface, session-persistence fields, and enum cases to a feature that has no design and no user demand documented. The cheap thing is to add them when the feature ships. The seam costs nothing to remove *right now* — and something real if anyone writes code that assumes it's wired.

**T5. Deferring hotplug to v2 is the right call *if and only if* v1 actually does nothing on hotplug.** The plan says "c11mux does nothing" but the existing `DisplayRegistry` will still publish `displaysChanged` (per §Code change sketch). An unhandled signal is a subtle lie that invites "but nothing was supposed to happen" when the behavior drifts.

**T6. "We'll learn from v1 soak" is not a plan.** It's a hope. CMUX-26 depends on v1 operator feedback to set its defaults. If v1 operators (plural) don't emerge — or if the operator population stays at N=1 (Atin) — then CMUX-26 will be designed by the same agent that designed CMUX-25, reading the same data. The feedback loop promised by the deferral doesn't close without more operators.

**T7. The plan quotes Atin's direction ("deliberately scope v1 to 'user spawns windows and assigns them to monitors manually'") as rationale for hotplug deferral.** That's a scope decision, not a technical one. The technical case for deferring hotplug — that system integration is hard to test without a display-toggle rig — is stronger than the scope case. Leading with scope language ("narrow by design") makes it harder to re-open the decision if the technical work turns out to be easier than expected.

**T8. The plan's optimism is pervasive.** "Cross-window drag-drop should work at v1 with minimal code change." "No contract change in bonsplit." "The Pane object itself is untouched." Each assertion is a prediction, not a proof. The plan would be stronger with fewer "should work"s and more "here is how we'll verify."

---

## Hard Questions for the Plan Author

Numbered, unsoftened. I've flagged the ones where "we don't know" is the current answer and that is a problem.

1. **What are the complete multi-frame invariants?** For every piece of state in Workspace / Pane / Surface, is it shared across frames or per-frame? Specifically: focused pane, selected tab (for multi-surface panes), sidebar selection, notification badges, drag-source visual state, Cmd+W semantics, workspace-rename consumers. *We don't know* — this table doesn't exist yet and is Phase 2's unacknowledged prerequisite.

2. **What exactly happens when the last window hosting a workspace closes?** Is the workspace destroyed, orphaned in the registry, auto-migrated to another open window, hibernated, or does the close prompt? §1 says "migrate or hibernate" but hibernation is explicitly deferred to v2. Pick one for v1. *We don't know.*

3. **Reparenting a `CAMetalLayer` / Ghostty surface across NSWindow backing stores — has this actually been prototyped, or is "untouched" an assumption?** If not prototyped, when? *We don't know.*

4. **What is the Phase 2 call-site audit?** How many files, how many functions, touch `workspace.panels`, `workspace.bonsplitController`, `tabManager.tabs`, `owningTabManager`? An honest number reframes the Phase 2 estimate. *Suspect we don't know; claim that we do via §1's 4-6 week aggregate is hand-wavy.*

5. **Is `PaneRegistry`'s actor isolation compatible with the SwiftUI `@MainActor` reads of pane state, and if yes, how many actor hops per view render?** Or do we maintain a `@MainActor`-isolated cache? If cache, how is it invalidated? *We don't know.*

6. **What is the rollback path if Phase 2 lands and a critical regression surfaces?** Revert one commit? The schema migration is one-way. Can the flag disable the new ownership model at runtime, or only at process start? *We don't know.*

7. **What objective gate retires `CMUX_MULTI_FRAME_V1`?** "Soaks on main for a release cycle" is a duration. Specify a usage threshold, a telemetry count, a defined test matrix, or a sign-off list. *We don't know — and "we don't know" here is the blast radius.*

8. **Who exercises this feature during soak besides Atin?** Named list. If N=1, the soak period is theatrical. *Need a real list; current answer is implicit "Atin."*

9. **For cross-window drag-drop, what is the specific scenario matrix that must pass before the v1 fallback to CLI-only is declined?** Drag-to-minimized, cross-Spaces, cross-fullscreen, source-window-closes-mid-drag, mixed-DPI, Mission Control interrupt. *We don't know — "one integration test" is not a matrix.*

10. **Which consumers of `workspace.move_to_window` exist today, and will each be migrated before the shim removal release?** Grep across Stage11, Atin's personal tooling, the cmux skill file, cmuxterm-hq CI, beta users. *We don't know — plan relies on deprecation notice in response, which Release-mode callers can't see (dlog is DEBUG-only).*

11. **What is the reverse migration for the session-persistence schema bump at Phase 2?** If a user runs a Phase-2 build then rolls back, does their session survive? *We don't know; one-way migration is implied.*

12. **Who owns the multi-frame invariants doc (Q1) and when is it written?** If the answer is "during Phase 2," the answer is wrong — it must exist before Phase 2 starts or Phase 2 is under-specified. *We don't know.*

13. **How does `workspace.close` behave when the workspace has frames in 2+ windows?** Silent close-all-frames? Prompt? Refuse and require explicit `--all` flag? *We don't know.*

14. **Does Cmd+~ (window cycle) change the "active workspace" for socket commands that operate on the "current workspace"?** Today this is unambiguous (one workspace per window, window focus defines active). Now a single workspace can span windows, and the active workspace depends on active window. Spec this. *We don't know.*

15. **What telemetry or dlog events are added to track frame creation, pane migration, cross-window drag attempts, and hotplug-induced window migration?** *We don't know — plan has no observability section.*

16. **When does CMUX-26 actually start?** "Once v1 has soaked" is unbounded. With N=1 operator and no objective gate for the flag retirement, CMUX-26 is effectively "eventually, maybe." Set a calendar date or a measurable condition. *We don't know.*

17. **What is the rollback posture if the drag-drop edge-case matrix fails in Phase 3?** "Fall back to CLI" — but CLI-only for cross-window move is itself an ergonomic regression from the north-star UX. Is v1.1 just "redo drag" or is it "ship drag without verifying the matrix"? *We don't know.*

18. **Are there any external integrations (the cmux skill file, `claude-in-cmux`, cmuxterm-hq tests, Stage11 sibling projects) that assume per-window workspace ownership?** The plan mentions `tests_v2/` and `cmuxterm-hq`; no audit of their assumptions. *We don't know.*

19. **What is the plan if Bonsplit's single-tree-per-controller contract breaks under "same pane leaf in two trees" (A1)?** Fix bonsplit, add a secondary index layer, or abandon the plan shape? *We don't know.*

20. **How does the plan integrate with the typing-latency-sensitive hot paths called out in CLAUDE.md?** Specifically: does the Phase 2 refactor add allocations in `TerminalSurface.forceRefresh`, change `TabItemView.Equatable` semantics, or touch `WindowTerminalHostView.hitTest`? The plan doesn't mention these explicitly — which means nobody has checked. *We don't know.*

---

## Closing

The architecture direction is correct. The execution plan is under-specified in the places that cost the most (multi-frame invariants, lifecycle races, drag-drop edge cases, Metal layer reparenting), confident in the places it shouldn't be (Phase 2 duration, "should work" drag), and governed by soft rules where it needs objective gates (flag retirement, shim removal, soak sign-off).

Strongest recommendation in priority order:

1. **Write the multi-frame invariants doc before Phase 2 starts.** It's Phase 0.
2. **Do the Phase 2 call-site audit and re-estimate honestly.** 4 weeks is probably right; 2 is aspirational.
3. **Build a perf canary at Phase 1**, even without a target number.
4. **Set an objective flag-retirement gate** (usage-based or operator-count-based), not a duration.
5. **Prototype `CAMetalLayer` / Ghostty surface reparenting in a minimal harness** before committing Phase 2 to the "untouched" design.
6. **Do a consumer grep for `workspace.move_to_window`** before picking the shim-removal release.
7. **Pick v1 behavior for "workspace with no visible frames"** (orphan vs destroy vs hibernate-stub) rather than leaving it to emerge.
8. **Drop the `SidebarMode.primary` / `.viewport` stubs** until the sync-mode feature has a design.
