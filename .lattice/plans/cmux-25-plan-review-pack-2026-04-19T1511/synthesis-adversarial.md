# Adversarial Review Synthesis — CMUX-25 (Multi-window c11mux, Emacs-frames v1)

- PLAN_ID: `cmux-25-plan`
- Scope: CMUX-25 (v1 phased) + CMUX-26 (v2 hotplug dependency)
- Reviewers: Claude (Opus), Codex, Gemini
- Synthesized: 2026-04-19
- Gemini note: shorter output due to API quota — treated as a complete but brief third opinion.

---

## Executive Summary

All three reviewers independently conclude that the plan's **architectural direction is correct** (process-scoped pane ownership + per-window `WorkspaceFrame`), but that its **behavioral contract for a workspace hosted in multiple windows is under-specified to the point of being unsafe to implement.** The specific convergent critique is that `PaneRegistry`, as described, solves dictionary access but not lifecycle, not rendering, not focus, not persistence, and not drag-in-flight — which is where the hard bugs live.

The plan is **most confident where it should be least confident** (cross-window drag "should work", Phase 2 is "~2 weeks", `CAMetalLayer`/Ghostty surface "untouched" on move, feature flag "retires after Phase 3"), and **most silent where the consequences are largest** (what happens to an `NSView` when two windows render the same workspace, what happens to orphaned panes when the last hosting window closes, what the rollback path is if Phase 2 lands broken).

The single highest-priority risk — flagged explicitly by Claude and Codex, and dramatized by Gemini into the review's strongest claim — is that **the plan permits states the underlying platform cannot render.** Gemini's framing: an `NSView`/`CAMetalLayer` can only have one superview, so `workspace.spread all_on_each` and any "same workspace in two windows" posture is a hard AppKit invariant violation unless the plan either (a) bans duplicate live rendering, or (b) introduces a separate render-host abstraction (offscreen textures / IOSurface sharing / per-frame view proxies), neither of which is designed.

**Recommendation consensus:** do not start Phase 2 until a multi-frame invariants document exists, `all_on_each` is either cut or explicitly designed, pane-move is specified as a transaction with lifecycle states, close-window semantics are nailed down, the persistence migration gets a real framework (not a bullet), and the feature flag retirement becomes a usage-based gate rather than a duration.

---

## 1. Consensus Risks (Multiple Reviewers Concurred)

Numbered by priority. Each item shows which reviewer(s) surfaced it and — where they exist — the specific code paths and line numbers that make it load-bearing.

### 1.1 Multi-frame workspace invariants are missing — the single biggest gap
**Flagged by:** Claude, Codex, Gemini.

None of the reviewers can find a table or contract in the plan that enumerates, for every piece of state, whether it is **shared across frames** or **per-frame**: focused pane, selected tab in multi-surface panes, sidebar selection, notification badges, drag-source visual state, Cmd+W semantics, workspace-rename propagation, keyboard-shortcut "current surface" resolution, notification jump target, socket "active workspace."

Codex grounds this in the existing code: `contextContainingTabId` (`Sources/AppDelegate.swift:11286`), `tabManagerFor(tabId:)` (`Sources/AppDelegate.swift:11295`), notification-open routing (`Sources/AppDelegate.swift:11319`, `Sources/AppDelegate.swift:11364`), and `mainWindowContainingWorkspace` (`Sources/AppDelegate.swift:4389`) all resolve by **first-match**. In a multi-frame world these are not implementation details; they are broken invariants unless the plan explicitly picks a resolver rule.

Claude adds the UX angle (sidebar "hosted elsewhere" badge deferred; two windows can show the same workspace selected in both sidebars with zero visual indication — the `⧉ 3` badge is orientation, not nice-to-have).

**Why this is #1:** Phase 2 is the ownership refactor. Every resolver call site that survives Phase 2 with "first match" semantics embeds ambiguity the plan is supposed to remove.

### 1.2 `all_on_each` (and duplicate live rendering in general) collides with AppKit's one-superview invariant
**Flagged by:** Claude, Codex, Gemini.

Gemini: "An `NSView` (and its backing `MTLLayer` for Ghostty) can only exist in one window hierarchy. If Window A and Window B both render Workspace 1, AppKit will aggressively rip the view out of Window A to place it in Window B." Consequence: `all_on_each` is not a minor option — it is the hardest possible interpretation of "pane references."

Codex: the plan doesn't address whether the same `NSView` / `WKWebView` / `GhosttyNSView` is mounted in multiple windows, or whether each frame gets a view proxy over shared process state. "AppKit views and layers do not have multiple superviews."

Claude: reparenting `CAMetalLayer` across `NSWindow` backing stores is not a pointer-move — it involves reacquiring Metal device references, backing-store sampling factors (retina factor, HDR tone map, color space), and can cause a transient black frame. The plan asserts "PTY / Ghostty surface / MTL layer ... untouched"; reality is "reparented with a reinit dance."

**Consensus remediation (agreed by all three):** either cut `all_on_each` from v1, ban duplicate live rendering outright and fail fast at the registry layer, or commit design time to a render-host / offscreen-texture abstraction. Do not leave this implicit.

### 1.3 `PaneRegistry` actor isolation ≠ transaction model; lifecycle races are under-specified
**Flagged by:** Claude, Codex, Gemini.

All three point out that "actor-isolated" serializes access to a dictionary but does not make a pane move atomic across the registry, the source `WorkspaceFrame` Bonsplit tree, the destination `WorkspaceFrame` tree, focus state, selected surface, sidebar badges, notification state, session autosave, and AppKit first responder — several of which live on `@MainActor`. Bonsplit itself is `@MainActor` (`vendor/bonsplit/Sources/Bonsplit/Internal/Controllers/SplitViewController.swift:5`).

Concrete race scenarios the plan does not address:
- Two concurrent `pane.move` calls for the same pane validate against the same source, then detach/attach in conflicting order.
- Drag-drop and keyboard-move race on the focused pane.
- Drag in flight when the **source window closes** mid-drag (Gemini's zombie scenario; Codex: `Sources/AppDelegate.swift:11222` unregister vs. `Sources/Workspace.swift:9344` / `Sources/Workspace.swift:9380` `moveBonsplitTab`).
- Destination frame closes after drop validation but before attach.
- Stale focus-reassert callback fires after a newer move (`Sources/AppDelegate.swift:5015`, `Sources/AppDelegate.swift:5044`).
- Session autosave snapshots between detach (`Sources/Workspace.swift:10045`) and attach (`Sources/Workspace.swift:8013`).
- `workspace.spread` creates N windows; user cancels / closes one mid-spread.

Gemini adds the specific dimension: synchronous AppKit callbacks like `performDragOperation` and `windowWillClose` cannot cleanly await an async registry; the choice is block-main-thread (deadlock risk) or defer (use-after-free / visual-glitch risk).

**Consensus remediation:** define `pane.move` as a first-class transaction with explicit states (`live`, `moving`, `closing`, `orphaned`), lease IDs, idempotency, and rollback semantics. Decide whether `PaneRegistry` is main-actor-bound or cross-actor and own the consequences.

### 1.4 Cross-window drag-drop: "should work" is not evidence
**Flagged by:** Claude, Codex, Gemini.

All three reject the plan's §3 claim that `.ownProcess` pasteboard visibility plus existing `AppDelegate.moveSurface` / `locateSurface` window-walking are sufficient. Codex grounds this in the actual drag plumbing: pasteboard type is defined (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift:705`), but real drag state is controller-local (`vendor/bonsplit/Sources/Bonsplit/Internal/Controllers/SplitViewController.swift:17`) with an external fallback (`vendor/bonsplit/Sources/Bonsplit/Internal/Views/PaneContainerView.swift:407`, `PaneContainerView.swift:411`, `PaneContainerView.swift:428`). The pasteboard type is necessary; it is not sufficient.

AppKit edge-case matrix that "one integration test" does not cover:
- Drag to minimized sibling window (no drag-enter).
- Drag across Spaces (not a valid drop target unless "all Spaces").
- Drag to/from a fullscreen window.
- Source window closes mid-drag.
- Target frame/window closes after drop validation but before attach.
- Mission Control interrupt mid-drag.
- Mixed-DPI drag (1x ↔ 2x display).
- Concurrent intra-window divider drag in another window (N Bonsplit controllers now, not one).
- Drag over `WKWebView` / browser portal layers (existing defensive code in `Sources/ContentView.swift:335` `DragOverlayRoutingPolicy` and `Sources/Panels/CmuxWebView.swift:1150`).
- Stale pasteboard carrying both file URL and internal types.
- Source window loses key status during drag.
- Drop onto inactive workspace views kept alive in a `ZStack`.

**Consensus remediation:** either (a) define an explicit cross-window drag matrix that must pass before v1 ships drag, or (b) ship CLI-only at v1 and add drag at v1.1 with a dedicated validation pass. Claude specifically notes the "fall back to CLI" escape hatch in the plan is reasonable but surrenders the feature's primary UX — a half-working drag is worse than no drag, because operators blame the feature, not its absence.

### 1.5 Closing a window: what happens to its panes is undefined
**Flagged by:** Claude, Codex, Gemini.

The plan says "closing a window destroys its frames, never its panes — remaining-only-on-that-window panes either migrate to another frame of the same workspace or hibernate." But:

- Hibernation is **explicitly deferred to v2** (plan §6).
- If no other frame of the workspace exists, the migration branch doesn't apply.
- Existing close path is destructive: `TabManager.closeWorkspace` tears down all panels (`Sources/TabManager.swift:2206`); `unregisterMainWindow` clears notifications for every workspace in that window (`Sources/AppDelegate.swift:11235`); the confirmation prompt still says "This will close the current window and all of its workspaces" (`Sources/AppDelegate.swift:4917`), which is now wrong.

Gemini's framing: **v1 ships a memory / PTY leak.** Closing Window A orphans its panes in `PaneRegistry` with no UI to recover them and no hibernation to flush them to disk. They leak PTYs and memory until app restart.

Claude's framing: the plan has three legal answers (orphan, destroy, destroy-with-confirm), picks none, and therefore ships whichever one emerges from implementation — almost certainly the worst (orphan, or crash).

Codex's framing: this is not a v2 hotplug problem. It is a v1 close-window problem. The line between CMUX-25 and CMUX-26 was drawn straight through necessary cleanup logic.

**Consensus remediation:** pick v1 behavior — destroy, destroy-with-confirmation listing affected panes, auto-migrate to any other frame of the same workspace, or ship a minimal hibernation stub pulled forward from v2. Do not let this emerge from implementation.

### 1.6 No perf target = silent regression vector, precisely where the plan adds fan-out
**Flagged by:** Claude, Codex.

CLAUDE.md explicitly marks typing-latency-sensitive hot paths: `WindowTerminalHostView.hitTest()`, `TabItemView` with `.equatable()`, `TerminalSurface.forceRefresh()`. The plan touches all three classes of path:

- Second-window hitTest during typing in the first window.
- Combine / `objectWillChange` fan-out to N window subscribers for shared registry mutations.
- Cross-window Metal layer management.
- Actor hops for pane data read from `@MainActor` views.
- Socket commands that today do main-thread sync reads (`Sources/TerminalController.swift:3198`) and scan all windows / workspaces (`Sources/AppDelegate.swift:4782`) now return more data and scan more objects.

Codex cites the socket threading policy (CLAUDE.md) as directly violated by the no-target posture: the plan adds global data to `identify` and `tree` — exactly the telemetry hot paths the policy warns against.

Claude: "Same posture as CMUX-15" is not analogous. CMUX-15 added a grid (geometry on one window). This adds inter-window fan-out.

**Consensus remediation:** even without a target *number*, add a perf canary at Phase 1 — keystroke→onscreen latency, `cmux tree` response time, frame creation latency, sidebar update coalescing under high-frequency telemetry — captured pre-Phase-2 and re-run after each phase. Codex proposes concrete minimum budgets for `identify`/`tree`/`pane.move`/typing latency at 3 windows × 30 panes.

### 1.7 Feature flag retirement timing is unsafe; retirement gate is a duration, not a condition
**Flagged by:** Claude, Codex, Gemini.

The plan retires `CMUX_MULTI_FRAME_V1` after Phase 3 soaks on main for a release cycle. All three reviewers reject this:

- Phases 4 (sidebar state), 5 (display spread), and 6 (split creation) are high-risk user-facing work that lands **after** the flag retires — no kill switch for the pieces most users actually exercise.
- "One release cycle" is a duration. A duration can pass without any multi-window user exercising the code path. The objective gate should be *usage*.
- Gemini: "Leaks and subtle lifecycle bugs in terminal emulators often take weeks of continuous uptime to report. Retiring the flag before Phases 4–6 are even shipped leaves the team with no kill-switch when the orphaned-pane leak starts crashing user machines."
- Claude: soak is theatrical if N=1 operator (Atin). No telemetry, no usage threshold, no defined test matrix, no sign-off list, no "bug found during soak" rule.
- No explicit rollback policy if a week-two race appears — does the release cycle reset? does Phase 4 pause? who owns the decision?

**Consensus remediation:** keep the flag until all six phases have soaked (Codex / Gemini), or split into per-risk-area flags (Codex), or tier retirement — default-on but env-var still disables for N releases (Claude). Set a usage-based or operator-count-based gate, not a duration.

### 1.8 Persistence migration is under-designed
**Flagged by:** Claude, Codex.

Current persistence has a hard version check, not a migration pipeline (`Sources/SessionPersistence.swift:5`, `Sources/SessionPersistence.swift:466`), and stores workspaces inside each window's `SessionTabManagerSnapshot` (`Sources/SessionPersistence.swift:447`, `Sources/SessionPersistence.swift:452`). The plan's "schema bump with migration that synthesises workspace entries from each window's embedded list" is one sentence for what is a real problem:

- Need a migration framework (old model rejects mismatched versions outright).
- Need duplicate-workspace merge rules — old snapshots have independent per-window workspaces that may be "the same logical workspace" by title/path.
- Need stable frame IDs and conflict resolution for focused panel / selected workspace.
- Need a way to preserve panel IDs while splitting layout from pane data.
- **Reverse migration is not covered** (Claude) — users who roll back from a Phase-2 build lose session state silently.

### 1.9 "`SidebarMode.primary` / `.viewport` seams" are speculative YAGNI with real cost
**Flagged by:** Claude, Codex, Gemini.

The plan ships enum cases and a session-persistence field for a sync-mode feature that has no design. Problems:
- Dead code rots (Claude).
- At v1 every snapshot writes `.independent`. When the real feature ships, migration is from "always `.independent`" to a new state machine — the "seam" saves nothing (Claude).
- If any future branch/fixture/downgrade writes `.primary` or `.viewport`, v1 needs a defined decode/fallback behavior (Codex).
- Future sync mode is not just selection broadcast — it touches sidebar visibility, command palette scoping, notification jump routing, window close semantics, focus ownership, and `workspace.select`. A no-op `broadcastSelection` trains the codebase to think sync mode is a callback when it is really an ownership mode (Codex).
- Gemini: because each window has its own Bonsplit tree, a viewport window syncing to Workspace X won't "mirror" the primary — it will show X in whatever arbitrary layout Window B last recorded. The layout is explicitly not synced. The seam is a footgun contradicting its own layout contract.

**Consensus remediation:** don't carry stub values. Store only `.independent`, decode unknown future values to `.independent` with a warning, keep future modes internal or feature-flagged, and design the full future ownership model separately before adding public modes.

### 1.10 `workspace.move_to_window` deprecation window is too short
**Flagged by:** Claude, Codex, Gemini.

One release is arbitrary for a public socket API. DEBUG-only log warnings are invisible to Release callers (Claude). Automations are often unowned — shell aliases, `jq` pipes, sibling Stage11 projects, the cmux skill file, cmuxterm-hq CI, beta users — and don't read `deprecation_notice` JSON fields (Gemini). Usage is not instrumented (Codex).

**Consensus remediation:** do a consumer grep before coining the removal release; minimum two releases; surface the deprecation in CLI stderr as well as JSON; log usage in a countable way; consider keeping the alias permanently unless there's concrete maintenance cost.

### 1.11 Phase 2 estimate is internally contradictory and almost certainly wrong
**Flagged by:** Claude, Codex (implicit).

The plan §1 says the whole registry refactor is "4–6 weeks across 3–4 sub-tickets." The ticket body consolidates everything into one ticket and keeps Phase 2 at "~2 weeks." `TabManager.swift` is 5,283 lines; `AppDelegate.moveSurface` touches `detachSurface`/`attachDetachedSurface`/`locateSurface`/`mainWindowContexts` across dozens of call sites (Claude). Codex's framing: the plan describes types more than invariants, and that's backwards — the hard problem isn't adding `PaneRegistry`, it's proving every ID-bearing call site has an unambiguous answer under multi-hosting.

**Consensus remediation:** do the call-site audit, re-estimate honestly (4 weeks probable; 2 is aspirational), and make Phase 2 acceptance depend on **removing first-match workspace ownership lookups**, not on merely introducing the new types.

---

## 2. Unique Concerns (Single-Reviewer)

Each worth investigating even without consensus.

### From Claude only

1. **Bonsplit's single-tree-per-controller contract may break under "same pane leaf in two trees"** (Assumption A1). Bonsplit was designed with implicit uniqueness — if it internally caches or indexes panes for divider-drag or keyboard navigation, those caches are now inconsistent across controllers.
2. **SwiftUI view-model plumbing was not rethought.** Two frames viewing the same workspace both subscribe to the shared registry and both trigger view rebuilds on every pane update — and one may be on 144 Hz, the other on 60 Hz. `@EnvironmentObject` / `objectWillChange` fan-out is not dimensioned; no debouncing or per-frame subscription scoping.
3. **Forward-flag `CMUX_MULTI_FRAME_V1` gates an architectural change, not a behavioral one.** The flag-off path must *also* implement the refactor but preserve single-frame-per-workspace semantics. That is a dual-mode system with its own bug surface — how/where the rejection of a second frame happens (registry, socket, UI) is unspecified.
4. **The v1 "do nothing on hotplug" stance still interacts with existing display-aware session persistence.** A session save after a monitor disconnect writes the new (macOS-migrated) position as though the user intended it — next launch restores to the wrong display. `DisplayRegistry` publishes `displaysChanged`; silent drift while nobody listens is the category of bug the deferral was supposed to avoid.
5. **Accessibility is unconsidered** — VoiceOver, keyboard navigation, and window ordering for a workspace in two windows.
6. **CLI JSON schema changes break strict validators.** New nouns (`display_ref`, `window_ref`, `workspace_ref`, `pane_ref`, `frame_ref`, `--display`, `--by-display`) are backward-incompatible for consumers validating schemas.
7. **Observability is absent.** No events, no logging, no `cmux tree --by-window` confirmed, no way to enumerate "all frames of all workspaces" for debugging, no "which windows host this pane" query.
8. **Reality stress test — combined disruptions:** Atin on vacation + macOS 26.2/26.3 changes drag behavior + Ghostty submodule rebase changes surface-init semantics. No mechanism to pause the soak clock.
9. **Cmd+~ window cycling** implicitly changes the sidebar's "active" workspace. The plan says "Cmd+~ does NOT re-focus" — that resolves focus but not sidebar behavior.

### From Codex only

10. **The socket surface remains window-first at v2.** `v2ResolveTabManager` resolves by explicit window → workspace → surface → panel → active manager (`Sources/TerminalController.swift:3486`). In a multi-frame model, `workspace_ref` alone does not identify a frame, `surface_ref` may identify a pane visible in more than one frame, and response payloads carry one `window_ref`. Need either a `frame_ref`, a visibility list, or a caller-scoped resolution rule.
11. **Test strategy is too thin.** Missing: duplicate-hosting tests, one-frame-closed-while-another-remains, concurrent same-pane moves, stale drag source teardown, socket focus policy across windows, no-app-activation for non-focus commands, autosave during move transactions, `all_on_each` rendering or explicit non-support, old-API compatibility.
12. **Early warning signs the plan should monitor** (concrete triggers):
    - Any code path still named `tabManagerFor(tabId:)` after Phase 2.
    - Any `workspace_ref` socket command returning exactly one `window_ref` without stating caller-scoped resolution.
    - Any move implementation with separate public `detach` and `attach` calls but no transaction object.
    - Any persistence migration without duplicate/merge fixtures.
    - Any drag test covering only two visible normal windows on the same Space.
    - Any snapshot schema bump that still rejects older versions instead of migrating.
    - Any feature-flag removal PR before Phases 4–6 have soaked.

### From Gemini only

13. **`CMUX_DISABLE_STABLE_PANEL_IDS` exists as a rollback safety net today.** How does Phase 2's sweeping refactor guarantee existing consumers who rely on current ID semantics don't break? (Raised as Q6 with no corresponding plan language.)
14. **The Emacs-frames north-star framing is misleading.** Emacs-frames only work because Emacs controls rendering down to the buffer level. Stapling frames onto AppKit `NSView`s means shared views across windows require offscreen textures or equivalent — the plan does not acknowledge this constraint.

### From Claude only — hindsight list (treated as early-warning catalogue)

15. "We should have kept the flag as a kill switch permanently. Retiring saves three conditionals; it eliminates the rollback lever when a regression surfaces at release N+3."
16. "We should have shipped v1 with an ugly `⧉ 3` 'hosted elsewhere' indicator. Without it the operator has no cue."
17. "We should have written the multi-frame invariants doc before Phase 2, not discovered them via bug reports."
18. "We should have built a per-frame layer hierarchy integration test at Phase 2 — Metal-layer reparenting works on the dev rig and fails on Intel MBP + XDR + UltraFine on a TB chain."

---

## 3. Assumption Audit — Merged and Deduplicated

Categorized **load-bearing** (plan collapses if false) vs. **cosmetic** (plan adjusts but survives) vs. **invisible** (not stated but assumed). Duplicates across reviewers merged; attribution in brackets.

### Load-bearing

**LB1.** *Same `NSView` / `CAMetalLayer` / `WKWebView` can be rendered by multiple `WorkspaceFrame`s concurrently, or reparented across `NSWindow`s without reinit cost.* **Likelihood: low-to-false.** [Claude A5, Codex 2, Gemini LB1]. AppKit's one-superview invariant plus Metal/Ghostty surface binding to a specific view make this either false (duplicate live rendering) or a reinit dance the plan doesn't describe (cross-window move).

**LB2.** *`PaneRegistry` actor isolation is a sufficient concurrency model for pane moves.* **Likelihood: false.** [Claude A5/I4, Codex 4, Gemini LB2]. Actor isolation serializes the dictionary; it does not make the move atomic across Bonsplit (`@MainActor`), focus, sidebar, autosave, and AppKit first-responder state.

**LB3.** *A workspace hosted in multiple windows without every existing first-match lookup becoming ambiguous.* **Likelihood: false without explicit resolver rules.** [Claude §Blind spots, Codex 1]. Concrete first-match sites: `Sources/AppDelegate.swift:11286`, `:11295`, `:11319`, `:11364`, `:4389`.

**LB4.** *Moving a pane across windows is "unlink leaf in frame A, link leaf in frame B; Pane object untouched."* **Likelihood: low as written.** [Claude A5, Codex 2, Gemini LB1]. `CAMetalLayer` reparenting requires Metal-device reacquisition, sampling factors, color space; Ghostty surface init may bind to host view.

**LB5.** *Every call site that reaches `workspace.panels[panelId]` today routes through the registry after Phase 2.* **Likelihood: low without explicit audit.** [Claude A3, Codex (implicit)]. Internal contradiction between plan §1 (4–6 weeks for 3–4 sub-tickets) and ticket body (~2 weeks for the biggest phase).

**LB6.** *`workspace.spread all_on_each` is implementable with shared live surfaces.* **Likelihood: false without multi-renderer design.** [Codex B, Gemini stress test]. Either cut from v1 or design offscreen/IOSurface multi-host.

**LB7.** *Closing a window destroys frames, never panes — remaining panes migrate or hibernate.* **Likelihood: contradicted by v1 scope.** [Claude A4, Codex 3, Gemini "v1 orphaned pane leak"]. Hibernation is v2. Migration requires another frame to exist. Plan doesn't pick a behavior.

**LB8.** *Cross-window drag-drop works at v1 with minimal code change because `.ownProcess` pasteboard visibility already allows it.* **Likelihood: moderate-to-low.** [Claude A2, Codex 5, Gemini cosmetic]. Pasteboard type is necessary, not sufficient. Missing matrix: minimized, cross-Spaces, fullscreen, source-closes-mid-drag, Mission Control, mixed-DPI.

**LB9.** *Bonsplit has no contract change — same controller, more instances per workspace.* **Likelihood: moderate.** [Claude A1]. Bonsplit's internal pane indexes / divider-drag caches may assume unique leaf ownership across a controller.

**LB10.** *Session persistence schema bump + migration is a bullet-point-sized task.* **Likelihood: low.** [Claude A6, Codex "much harder than stated"]. Existing code rejects version mismatch outright (`Sources/SessionPersistence.swift:5`, `:466`). Need framework, duplicate-merge rules, frame IDs, forward+reverse migration.

**LB11.** *No formal perf target at v1 is safe because regressions will be obvious later.* **Likelihood: false.** [Claude, Codex]. Typing-latency hot paths are well-documented in CLAUDE.md; the plan adds fan-out to exactly those paths. "Measure later" = bisect after symptoms.

**LB12.** *Feature flag can retire after Phase 3 soaks one release cycle.* **Likelihood: false.** [Claude, Codex, Gemini]. Phases 4–6 land after retirement; duration is not a condition; N=1 operator makes soak theatrical.

**LB13.** *One-release deprecation window for `workspace.move_to_window` is sufficient.* **Likelihood: false without consumer grep.** [Claude, Codex, Gemini]. DEBUG-only log is invisible to Release; automations don't parse `deprecation_notice`.

### Cosmetic

**C1.** `ceil(N/D)` fill-leftmost spread distribution. [Claude B1] — easy to change.
**C2.** `Cmd+Opt+Shift+<Arrow>` for split-overflow. [Claude B4] — bikeshed.
**C3.** `display:left` / `display:center` / `display:right` addressing. [Claude B3] — fine, though "center only when N odd" is ambiguous for 4-monitor rigs.
**C4.** `SidebarMode.primary` / `.viewport` exist as stubs. [Claude B2 cosmetic, Codex 7 load-bearing, Gemini challenged] — three reviewers disagree on severity; treat as load-bearing per consensus §1.9.

### Invisible (not stated but assumed)

**I1.** Closing a window with a workspace's only frame leaves panes reachable somehow. No UI path designed. [Claude I1]
**I2.** Sidebar at v1 will list *all* workspaces in the registry — including those hosted elsewhere — with no visual cue until `⧉ 3` badge ships "later." [Claude I2]
**I3.** Cmd+~ window cycling doesn't interact with sidebar "active workspace" semantics. [Claude I3]
**I4.** `PaneRegistry` (actor-isolated) can be read from `@MainActor` SwiftUI views with bounded actor-hop cost and no async boundary at read sites. [Claude I4, Gemini "async hop into synchronous UI"]
**I5.** Status/log/progress updates (already flagged in CLAUDE.md socket threading policy) don't fan out N-way to all windows hosting a workspace-frame for the target pane. [Claude I5]
**I6.** Bonsplit's tab-drag gesture does not mutate source-tree state until drop commit; if it does, cross-tree drops require revert. [Claude I6]
**I7.** `v2ResolveTabManager` / `v2ResolveWindowScope` can be swapped atomically — plan does not specify which commands get caller-scoped vs. registry-scoped resolution. [Codex]
**I8.** Existing display-aware session persistence harmlessly ignores `displaysChanged` while v1 declares hotplug a no-op. [Claude T5]
**I9.** No external integrations (the cmux skill file, `claude-in-cmux`, cmuxterm-hq, Stage11 siblings) assume per-window workspace ownership. [Claude Q18]

---

## 4. The Uncomfortable Truths (Recurring Hard Messages)

Grouped by theme. Messages that appear in multiple reviews are marked **[consensus]**.

### 4.1 **The plan confuses data-model design with product design.** [consensus: Claude T8, Codex "types more than invariants," Gemini "clean data, messy UI"]
The primitive hierarchy is clean. The invariants contract is absent. You can ship a compilable multi-frame codebase that is still window-first in every behavior that matters to a user, because the resolver rules, transaction boundaries, rendering constraints, and close-window semantics were never written down.

### 4.2 **The plan is more confident about the existing code than the code warrants.** [consensus: Claude T8, Codex]
"Should work." "Minimal code change." "Natural generalisation." "Pane object itself is untouched." Each is a prediction, not a proof. The existing `moveSurface` is a detach/attach *between workspaces* layered on workspace-owned panels (`Sources/AppDelegate.swift:4084`, `:4208`, `:4221`) — it is not the same operation as moving a process-scoped pane between frame references.

### 4.3 **The v1/v2 boundary is drawn through necessary cleanup logic, not across a technical seam.** [consensus: Codex, Gemini]
Hotplug is correctly deferred. But close-window semantics, minimized-window drag, fullscreen/Spaces drag, and last-frame pane survival are all direct consequences of v1 multi-window hosting — not v2 hotplug. Deferring them guarantees a degraded v1 where orphaned panes leak and edge-case drags silently fail.

### 4.4 **"We'll learn from v1 soak" is a hope, not a plan.** [consensus: Claude T1/T6, Codex "soak theatrical"]
With N=1 operator and no objective gate, CMUX-26 defaults are designed by the same agent that designed CMUX-25, reading the same data. The feedback loop doesn't close without more operators. "A release cycle" is not a gate.

### 4.5 **The plan architects for futures it doesn't have designs for.** [consensus: Claude T4, Codex, Gemini]
`SidebarMode.primary/.viewport`, the `broadcastSelection` no-op, serializing unwired enum values — all commit API surface, session-persistence fields, and enum cases to a feature with no design and no documented demand. When the feature ships, real migration starts from "always `.independent`" — so the seam saves nothing and leaks potential footguns.

### 4.6 **The "two-week Phase 2" estimate is a tell.** [Claude T3 explicit; Codex implicit]
Anyone who has read `TabManager.swift` (5,283 lines) and audited `moveSurface`'s ~50 call sites through `mainWindowContexts` and come out saying "two weeks" has not yet done the call-site audit. The honest number is in §1 of the plan (4–6 weeks for "3–4 sub-tickets"); the ticket body consolidated and kept the aspirational estimate.

### 4.7 **The plan's optimism is pervasive and the governance rules that should counteract it are soft.** [Claude T8]
Every "should work," every "untouched," every "minimal code change" is unbacked by a specific test. Feature-flag retirement is a duration. Deprecation window is a duration. Soak is a duration. None are usage or evidence-based.

### 4.8 **Atin is the bottleneck and the soak cohort simultaneously.** [Claude T1]
Code review, design sign-off, flag retirement, v2 defaults — all depend on one operator. That is acceptable for the review layer; it is deeply fragile for the soak-evidence layer.

### 4.9 **The v1 shape ships a memory / PTY leak by construction.** [Gemini primary claim; Codex implicit]
No hibernation + "close window destroys frames, never panes" + "no other frame to migrate to" = orphaned panes in the registry, reachable by no UI, flushed to no disk. Leaks until restart.

### 4.10 **Emacs-frames are a rendering claim, not a UX claim.** [Gemini]
The north-star framing imports Emacs-frame semantics without importing Emacs's rendering pipeline. Emacs controls its own buffer-level compositor; c11mux does not. The plan permits rendering states AppKit cannot produce without an offscreen/IOSurface layer that isn't designed.

---

## 5. Consolidated Hard Questions for the Plan Author (Deduplicated & Numbered)

Merged from all three reviews. Duplicates collapsed; source attribution in brackets. Ordered roughly by blast radius (highest first).

### Architecture & rendering (highest priority)

**Q1.** Exactly what happens at the `NSView` / `CAMetalLayer` / `WKWebView` level when Window A and Window B both render Workspace 1 simultaneously? Is duplicate live rendering banned at the registry layer, supported via an offscreen/IOSurface abstraction, or emergent? [Claude Q3, Codex 2, Gemini 1]

**Q2.** Is `workspace.spread all_on_each` in v1 scope? If yes, where is the multi-renderer design for one pane visible in multiple windows? If no, remove it from the plan. [Codex 11, Gemini stress test]

**Q3.** Has reparenting a `CAMetalLayer` / Ghostty surface across `NSWindow` backing stores actually been prototyped, or is "untouched" an assumption? If not prototyped, when? [Claude Q3]

**Q4.** What are the complete multi-frame invariants? For every piece of state in Workspace / Pane / Surface, is it shared across frames or per-frame? Specifically: focused pane, selected tab (multi-surface panes), sidebar selection, notification badges, drag-source visual state, Cmd+W semantics, workspace-rename consumers, keyboard-shortcut "current surface" resolution. [Claude Q1, Codex "invariant table"]

**Q5.** When the same workspace is hosted in windows A and B, what does `workspace_ref` alone resolve to for every socket command (`workspace.select`, `surface.focus`, `pane.focus`, `read-screen`, `send`, `tree`, notification jumps)? Caller window? Focused window? All frames? Error requiring `window_ref`? [Codex 1, Claude Q14, Gemini 4]

**Q6.** Can the same pane ID appear in two live `WorkspaceFrame`s simultaneously? If yes, how are Ghostty surface, MTL layer, browser `WKWebView`, first responder, and input ownership represented? If no, how is the rule enforced and where does it fail fast? [Codex 2]

### Lifecycle, transactions, concurrency

**Q7.** Does `PaneRegistry` run on the main actor, its own actor, or both? What is the transaction boundary for `pane.move` across registry, frame, focus, sidebar, and persistence state? [Codex 5, Claude Q5]

**Q8.** How does the plan prevent two concurrent moves of the same pane from both succeeding partially? Specify leases, lifecycle states (`live`/`moving`/`closing`/`orphaned`), idempotency, and rollback semantics. [Codex 6]

**Q9.** What state does a pane enter while it is being dragged but not yet dropped? Still owned by source, leased, moving, or duplicated? [Codex 7]

**Q10.** What happens if the drag source window closes before the target drop executes? [Codex 8, Claude §drag-drop edge cases]

**Q11.** What happens if the target window/frame closes after drop validation but before attach? [Codex 9]

**Q12.** How does synchronous `performDragOperation` / `windowWillClose` interact safely with an actor-isolated `PaneRegistry` when migrating a pane — without deadlocking the main thread or risking use-after-free? [Gemini 3]

### Close-window semantics (v1, not v2)

**Q13.** What is the exact close-window behavior for a window containing frames with panes not referenced by any other frame? Destroy, orphan, destroy-with-confirm listing affected panes, auto-migrate to any other open workspace, or ship a minimal hibernation stub pulled forward from v2? Pick one. [Claude Q2, Codex 3, Gemini 2]

**Q14.** What is the exact close-window behavior for a window containing a frame of a workspace also visible in another window? Silent close-this-viewport, close-all-frames, or prompt? [Codex 4, Claude Q13]

**Q15.** Without v2's hibernation, what is the exact code path for a `Pane` in `PaneRegistry` when its last hosting `WorkspaceFrame` is destroyed by a window close? Does it leak, or does it die? [Gemini 2]

### Drag-drop validation matrix

**Q16.** What specific scenario matrix must pass before cross-window drag ships in v1 (not "one integration test")? Minimum: drag-to-minimized, cross-Spaces, cross-fullscreen, source-window-closes-mid-drag, target-frame-destroyed-during-drag, Mission Control interrupt, mixed-DPI, drag across `WKWebView` / browser portal layers, concurrent divider-drag in a sibling window, window loses key status during drag, drop onto inactive workspace views kept alive in a `ZStack`, stale pasteboard mixing file URL + internal types. [Claude Q9, Codex 10]

### Phase 2 discipline

**Q17.** What is the Phase 2 call-site audit? How many files / functions touch `workspace.panels`, `workspace.bonsplitController`, `tabManager.tabs`, `owningTabManager`, `contextContainingTabId`, `tabManagerFor(tabId:)`, `mainWindowContainingWorkspace`, `mainWindowContexts`? Honest count reframes the Phase 2 estimate. [Claude Q4, Codex "remove first-match lookups"]

**Q18.** Is `PaneRegistry`'s actor isolation compatible with `@MainActor` SwiftUI reads of pane state, and if yes, how many actor hops per view render? If `@MainActor`-isolated cache, how is it invalidated? [Claude Q5]

**Q19.** What must be true before Phase 2 is considered complete besides "the code compiles and old behavior still works"? The acceptance criteria need invariant-level proof, not just green CI. [Codex 20]

**Q20.** Who owns the multi-frame invariants doc (Q4) and when is it written? If the answer is "during Phase 2," Phase 2 is under-specified; the doc must exist first. [Claude Q12]

### Persistence migration

**Q21.** How will old snapshots migrate when they contain independent per-window workspaces that happen to have the same name/path? Are they merged or kept separate? [Codex 14]

**Q22.** What is the migration framework for `SessionSnapshotSchema.currentVersion = 1` snapshots, given the current loader rejects version mismatches outright (`Sources/SessionPersistence.swift:5`, `:466`)? [Codex 15]

**Q23.** What is the reverse migration for the session-persistence schema bump at Phase 2? If a user runs a Phase-2 build then rolls back, does their session survive? [Claude Q11]

### Performance

**Q24.** What are the minimum performance budgets for `identify`, `tree`, `pane.move`, sidebar updates, and typing latency with 3 windows × 30 panes? Without numbers, provide at least a benchmark canary captured at Phase 1 and re-run after each phase. [Codex 12, Claude §perf]

**Q25.** How does the plan integrate with the typing-latency hot paths called out in CLAUDE.md? Specifically: does Phase 2 add allocations in `TerminalSurface.forceRefresh`, change `TabItemView.Equatable` semantics, or touch `WindowTerminalHostView.hitTest`? [Claude Q20]

### Rollback / governance

**Q26.** What is the rollback path if Phase 2 lands and a critical regression surfaces? Revert one commit? Schema migration is one-way. Can the flag disable the new ownership model at runtime, or only at process start? [Claude Q6]

**Q27.** Why does the feature flag retire after Phase 3 rather than after all six phases soak? If Phase 3 shows a week-two race, what is the explicit rollback/hold policy (flag stays, Phase 4 pauses, release cycle resets) and who owns the decision? [Codex 16/17, Claude Q7, Gemini 5]

**Q28.** What objective gate retires `CMUX_MULTI_FRAME_V1` — a usage threshold, telemetry count, defined test matrix, sign-off list? [Claude Q7]

**Q29.** Who exercises this feature during soak besides Atin? Named list. If N=1, the soak period is theatrical. [Claude Q8]

**Q30.** Given `CMUX_DISABLE_STABLE_PANEL_IDS` exists as a rollback safety net today, how does Phase 2's sweeping refactor guarantee existing consumers of current ID semantics don't break? [Gemini 6]

### API, CLI, socket surface

**Q31.** Which consumers of `workspace.move_to_window` exist today, and will each be migrated before the shim-removal release? Grep across Stage11 siblings, Atin's personal tooling, the cmux skill file, `claude-in-cmux`, cmuxterm-hq CI, beta users. [Claude Q10, Codex 18]

**Q32.** Should `workspace.move_to_window` remain as a permanent alias if the only downside is semantic ugliness? [Codex 19]

**Q33.** Which socket commands are allowed to activate or order-front windows under the new model, and how is the socket focus policy (CLAUDE.md) preserved? [Codex 13]

**Q34.** Does Cmd+~ (window cycle) change the "active workspace" for socket commands that operate on the "current workspace"? Today this is unambiguous; now a single workspace can span windows. [Claude Q14]

### Observability

**Q35.** What telemetry or dlog events are added to track frame creation, pane migration (including cross-window), drag attempts (attempted / succeeded / failed per matrix cell), and hotplug-induced window migration? [Claude Q15]

### External dependencies

**Q36.** What is the plan if Bonsplit's single-tree-per-controller contract breaks under "same pane leaf in two trees" (assumption A1 / LB9)? Fix Bonsplit, add a secondary index layer, or change the plan shape? [Claude Q19]

**Q37.** Are there any external integrations (the cmux skill file, `claude-in-cmux`, cmuxterm-hq tests, Stage11 sibling projects) that assume per-window workspace ownership? The plan mentions `tests_v2/` and `cmuxterm-hq`; no audit of their assumptions. [Claude Q18]

### Scope sequencing

**Q38.** When does CMUX-26 actually start? "Once v1 has soaked" is unbounded with N=1 operator. Set a calendar date or measurable condition. [Claude Q16]

**Q39.** What is the rollback posture if the drag-drop matrix fails in Phase 3? Is v1.1 "redo drag" or "ship drag without verifying the matrix"? [Claude Q17]

**Q40.** If a viewport window (future sync mode) selects Workspace X but has a completely different Bonsplit tree layout for Workspace X than the primary window, how does that fulfill the stated walkthrough use case? The layout itself is not synced. [Gemini 4]

---

## 6. Minimum-Change Recommendations Before Phase 2 Starts

Synthesized from the reviewers' independently-proposed remediation lists. Ranked by leverage.

1. **Write the multi-frame invariants document.** It's Phase 0 of Phase 2, not a Phase 2 deliverable.
2. **Cut `workspace.spread all_on_each` from v1** unless multi-renderer panes are explicitly designed.
3. **Specify `pane.move` as a transaction** with lifecycle states, leases, idempotency, and rollback.
4. **Pick v1 close-window behavior** for "workspace with no visible frames" (orphan / destroy / destroy-with-confirm / migrate / pulled-forward hibernation stub). Not emergent.
5. **Do the Phase 2 call-site audit** and re-estimate honestly. Publish the number.
6. **Land a persistence migration framework** (not a schema-bump bullet) with duplicate/merge fixtures and a documented reverse migration.
7. **Keep the feature flag through all six phases** — or split by risk area. Replace duration-based retirement with a usage/evidence gate.
8. **Build a perf canary at Phase 1** for keystroke latency, `cmux tree` / `identify` response time, frame creation cost, sidebar update coalescing under telemetry burst. Re-run after each phase.
9. **Prototype `CAMetalLayer` / Ghostty surface reparenting in a minimal harness** before committing Phase 2 to "untouched" language.
10. **Do a consumer grep for `workspace.move_to_window`** before picking the shim-removal release; extend the window or keep the alias permanently unless maintenance cost is concrete.
11. **Expand the drag-drop acceptance matrix** beyond one integration test; define cells that must pass.
12. **Drop `SidebarMode.primary` / `.viewport` stubs** until sync mode has a design. Decode unknown future values to `.independent` with a warning if any escape into snapshots.
13. **Make Phase 2 acceptance depend on removing first-match workspace ownership lookups**, not merely introducing `PaneRegistry`.

---

## 7. Closing Synthesis

The three reviewers agree on direction, diverge on flavor, and converge on a single diagnosis: the plan's **types are further along than its contracts**. The architecture is sound; the behavioral contract is missing in exactly the places where "it compiles" and "it works" most often come apart in large AppKit codebases — shared UI state across windows, Metal-layer lifetimes, drag-in-flight teardown, and resolver ambiguity for IDs whose uniqueness assumption just quietly ended.

Gemini makes the sharpest claim (AppKit cannot render what the plan permits). Codex makes the most grounded critique (existing first-match resolution sites are named and cited). Claude makes the broadest one (governance is soft where it needs to be objective, Phase 2 is under-estimated, the soak cohort is theatrical). Three different emphases, one consistent message: **do not start Phase 2 without the invariants doc, the transaction spec, the close-window decision, and an honest estimate.**
