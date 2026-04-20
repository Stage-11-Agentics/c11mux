# Evolutionary Plan Review — cmux-15-default-grid

**Plan:** CMUX-15 — Default pane grid sized to monitor class
**Reviewer:** Claude (Evolutionary)
**Date:** 2026-04-18

---

## Executive Summary

The plan as written is small, tasteful, and surgically scoped. It will ship and nobody will object. That is both its strength and the reason it's interesting to examine evolutionarily — because the *real* opportunity here is not "a grid at spawn time." The real opportunity is that c11mux is one decision away from treating **"what workspace shape do I want right now?"** as a first-class, composable primitive. Monitor-class grid is the seed. The flower is a **Layout System** — named, saveable, shareable, per-workspace-kind, per-project, per-agent-role layouts — that turns workspace creation from "blank slate you have to furnish" into "pick or invoke a scene."

The biggest missed opportunity in the current plan is treating the grid as an inline procedural side-effect of `addWorkspace`. If instead the grid is expressed as the *first, simplest instance* of a declarative `WorkspaceLayout` value type, the same 200 LoC delivers CMUX-15 and pre-builds the data model for every future "smart default" in c11mux: welcome quad, role-based layouts ("coder", "reviewer", "triple-force"), screen-class defaults, restored-session replay, layout sharing, and Lattice ticket-driven spawn.

Ship CMUX-15. But ship it as **Layout v0**, not as a one-off `performDefaultGrid` function.

---

## What's Really Being Built

On the surface: a function that fires `(cols × rows - 1)` splits after workspace creation, gated by screen pixel thresholds.

Underneath:

1. **A second caller of the welcome pattern.** `sendWelcomeWhenReady` is about to go from a single-use first-run quirk to a reusable "wait-for-surface-then-compose" hook. Once there are two callers, there will be many. This is the birth of a post-creation composition pipeline.
2. **A commitment to "workspaces have a shape."** Today a workspace is a bonsplit tree you build up by hand. This plan is the first place where c11mux *decides* a shape for you. Once that's normal, the interesting question is no longer *whether* c11mux chooses — it's *how many shapes* it knows, and *how the user names and reuses them*.
3. **A data point about the hardware.** `DefaultGridSettings.classify(screenFrame:)` is the first piece of code in c11mux that reasons about the user's display class as a typed input to UX. Once that exists, every feature downstream (welcome content density, sidebar width defaults, font preset suggestions, embedded-browser layout) can consume the same signal.
4. **The on-ramp from Lattice to workspaces.** A Lattice ticket is a unit of work. A c11mux workspace is where work happens. If workspaces have named shapes, a Lattice ticket can *request* a shape ("give me a triple-force review grid") and c11mux becomes the visible execution surface for Lattice intents. This plan doesn't say that, but it's what's one layer down.

Naming the thing: **the Layout Primitive**. The capability that evolves is "c11mux knows how to compose an opinionated pane arrangement on demand, by name, from any caller." CMUX-15 is the first layout.

---

## How It Could Be Better

### 1. Replace `performDefaultGrid` with a declarative `WorkspaceLayout`

Instead of a function that hard-codes the split sequence, define:

```swift
struct WorkspaceLayout {
    let name: String
    let ops: [LayoutOp]   // .splitHorizontal(from: paneRef, content: .terminal) etc.
    let initialFocusRef: PaneRef?
    let postCompose: (@MainActor (Workspace) -> Void)?  // send text, open URLs
}

enum LayoutOp {
    case split(from: PaneRef, orientation: SplitOrientation, insertFirst: Bool, content: PaneContent)
}

enum PaneContent {
    case terminal(initialCommand: String?)
    case browser(URL?)
    case markdown(URL)
}
```

Then:
- `WelcomeSettings.performQuadLayout` becomes `WorkspaceLayout.welcome` (a value, not a function).
- `DefaultGridSettings.performDefaultGrid` becomes `WorkspaceLayout.defaultGrid(cols:rows:)` (a factory returning a value).
- The execution engine is a single `@MainActor func apply(_ layout: WorkspaceLayout, to: Workspace, initialPanel: TerminalPanel)` that walks the ops list.

Same 200 LoC. Massively more reusable. Testable without mocking a Workspace — you can snapshot-test the generated `[LayoutOp]` for any `(cols, rows)` and any future layout. The plan already proposes factoring `gridSplitOperations` as a pure function for testing; go one step further and make the entire layout declarative. This is the biggest single improvement available for near-zero extra cost.

### 2. Make screen classification a typed signal, not a tuple

The plan's `(cols: Int, rows: Int)` return type leaks implementation. Prefer:

```swift
enum MonitorClass { case laptop, desktopQHD, desktop4K, ultrawide, unknown }
extension MonitorClass {
    static func classify(screenFrame: NSRect) -> MonitorClass { ... }
    var defaultGrid: (cols: Int, rows: Int) { ... }
}
```

Now the classification is a noun other features can consume (welcome content density, sidebar defaults, font presets, split-button tooltip hints). A `(cols, rows)` tuple is terminal. A `MonitorClass` enum is a reusable piece of environment awareness.

### 3. Name the layouts, don't enumerate them inside settings

The plan has one layout ("default grid") parameterized by three `(cols, rows)` pairs. That's actually three layouts with a shared strategy. Name them:

- `.solo` (1×1)
- `.pair` (2×2) — the laptop default
- `.productivity` (2×3) — the QHD default
- `.studio` (3×3) — the 4K default

Naming gives users language ("set my default to `productivity` even on a 4K"), gives settings UI something to show, and gives Lattice/socket commands something to invoke. `cmux workspace new --layout studio` becomes trivial.

### 4. Fire after `.terminalSurfaceDidBecomeReady`, not on a `0.5s` `asyncAfter`

The welcome path uses `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5)`. That's a magic delay that wallpapers over a race. The plan inherits it. If you're about to run this code on *every* workspace creation (not just first-run), the latency is now a product-quality issue, not a one-time quirk. Use `.terminalSurfaceDidBecomeReady` with a tight timeout fallback; skip the arbitrary sleep. This is in the path the user sees every single new workspace — it deserves precision.

### 5. Persist the chosen layout per workspace at spawn time

Today a restored workspace replays its persisted bonsplit tree. Tomorrow, someone will want "this workspace was born as `studio`; remember that so a future `reset to default grid` does the right thing." Write `layoutName` into the workspace record at creation. Zero cost now; unlocks "reset", "reshape", and "clone this workspace's shape" later.

### 6. Don't ship without a single-key escape hatch

`defaults write com.cmux.app cmuxDefaultGridEnabled -bool false` is not enough friction-reduction for a default-on feature that materially changes behavior for every existing user. At minimum:

- A `cmux new --no-layout` flag on the CLI.
- A one-keystroke "collapse to single pane" in the new workspace, surfaced in the corner of the window for the first 5 seconds (a quiet toast, not a modal).

Opinionated defaults need graceful undo. Shipping opinionated-on without an in-app undo is the #1 way this becomes the feature people hate after 48 hours.

---

## Mutations and Wild Ideas

### Mutation A: Layout-as-LLM-output

The grid is a series of `[LayoutOp]`. An LLM can emit `[LayoutOp]` trivially. Prompt: "I'm starting a Rails triage session." Output: `[terminal cd repo, browser github issues, terminal tail -f log, markdown RAG_NOTES.md]`. c11mux applies it. You've just built "describe the workspace you want in English" without writing a planner — the layout primitive *is* the plan representation. This is a ~200 LoC feature *after* Layout v0 exists; without it, it's a rewrite.

### Mutation B: Monitor-class is the wrong signal; aspect-plus-PPI is right

Pixel thresholds correlate poorly with usable real estate. A 5K iMac 27" and a 4K 32" external both cross 3840×2160 but feel different. The right signal is **physical-usable-inches-per-pane** — target ~11" wide per terminal pane at comfortable readability. Compute from `NSScreen.frame` + `NSScreen.backingScaleFactor` + an estimated PPI. The plan's simple classifier is fine for v0; but note the deeper model so it can replace the classifier without disrupting callers once `MonitorClass` is typed.

### Mutation C: Tie grid cell count to Lattice "tasks in progress"

If the user has 6 in-progress Lattice tickets, spawn a 2×3 with one pane per ticket, each with its working directory set, ticket URL open in a browser cell, and `cmux tab-name` set from the ticket title. This is the Lattice-c11mux bridge nobody has named yet. The plan as written builds the split execution; one additional adapter (`LatticeLayoutProvider`) turns "default grid" into "today's work grid."

### Mutation D: Ghost-grid — show the proposed layout as an overlay before committing

For 1-2 seconds after workspace creation, render a dotted-line overlay showing what splits are about to happen, with the option to "keep it" (do nothing) or "dismiss" (collapse to single pane). This turns the feature from a surprise into a legible proposal. Cheap to build once Layout v0 exists.

### Mutation E: Per-project remembered layout

Workspaces spawned with `cwd = /Users/atin/Projects/Stage11/code/cmux` always want the same shape. Store the last-used layout keyed by `cwd` and suggest it on next spawn. "c11mux knows how you work on this project."

### Mutation F: Tree-sourced grids

Instead of a fixed `(cols, rows)`, let the grid reflect a directory tree: one pane per top-level subproject in a monorepo, auto-cd'd. 4K → shows 9 of 9 subprojects; laptop → shows 4 largest. Same primitive, entirely different product.

### Mutation G: Grid spawn as a first-class `cmux` socket command

`cmux layout apply studio` from any surface recomposes the current workspace. Immediately useful for agents: "my sub-agent just hit a design phase, switch my layout to `productivity` so I can open the ADR." Falls naturally out of Layout v0.

---

## What It Unlocks

Once the layout primitive exists:

1. **Settings UI grows a "Layouts" pane.** Named layouts become a browsable surface. Users can duplicate, rename, share via JSON export.
2. **Socket/CLI gains `cmux layout {apply|save|list}`.** Agents can request specific layouts without writing split code.
3. **Lattice tickets can declare preferred layouts.** A ticket template says "this kind of work uses the `triple-force` layout." c11mux honors it on workspace spawn.
4. **Telemetry gains "layout adoption."** Signal: do people keep the grid, collapse it, or reshape it? Drives classifier tuning and validates the feature.
5. **The welcome quad stops being a special case.** It's just `WorkspaceLayout.welcome` with `isFirstRun: true` gating.
6. **Cross-machine layout portability.** Export your layouts; sync via iCloud or a `cmux` JSON file. "Bring my workstation shape to my laptop."
7. **Demo and onboarding become composable.** New users pick `productivity` and instantly look like a power user. Screenshots in docs use named layouts. Marketing gains a vocabulary.
8. **Multi-monitor (the sibling ticket) composes cleanly.** Per-screen layouts. Move a workspace between monitors → reshape to the target's layout.

The unlock map is substantial. None of it requires building much beyond Layout v0.

---

## Sequencing and Compounding

The plan as written is a single-phase drop. A better sequence:

**Phase 0 (before anything else, ~20 LoC):** Introduce `WorkspaceLayout` value type and `apply(_:to:initialPanel:)` execution engine. Re-express `WelcomeSettings.performQuadLayout` through it. This is pure refactor, zero behavior change. Ship it alone. Now the rails exist.

**Phase 1 (CMUX-15 proper, ~150 LoC):** Implement `MonitorClass`, `WorkspaceLayout.defaultGrid(for: MonitorClass)`, wire to `addWorkspace`. Ship with default-on, behind `cmuxDefaultGridEnabled` flag, with an in-app collapse-to-single gesture.

**Phase 2 (~80 LoC):** Add `cmux layout apply <name>` socket command and `--layout <name>` CLI flag. This is where agents gain the capability; trivial once Phase 0 shipped.

**Phase 3 (~120 LoC):** Settings pane UI for layout picker. "Default layout per screen class" surfaces the classifier. User can override.

**Phase 4 (opportunistic):** Per-project remembered layout; Lattice ticket → layout mapping; export/import.

The plan's current order conflates Phase 0 and Phase 1 and skips the extraction. That's the single thing I'd change in sequencing. The rest flows once Phase 0 exists.

**Underinvestment risk:** If you ship the plan as written, you'll rebuild the same abstraction when mutation A, C, E, or G lands. The 20 LoC of Phase 0 prevents that rebuild. **Overinvestment risk:** low — the abstraction is small and obvious.

---

## The Flywheel

Two candidate self-reinforcing loops are latent in this plan:

**Loop 1 — Layout adoption → layout creation → layout adoption.**
- User sees default grid → likes it → asks "can I save my own?"
- Saved layouts get shared (JSON export, screenshots in the Zulip thread)
- Shared layouts become templates → more users adopt → more layouts created
- Stage 11 seeds the library (`productivity`, `studio`, `triple-force`, `lattice-today`) → new users skip the learning curve

Ignition move: include 3-4 named, high-quality layouts in v0, not just the auto-selected grid. Give users something to *switch to* on day one.

**Loop 2 — Layout → Lattice → Layout.**
- A layout captures "how I work on ticket type X"
- Lattice tickets of that type request the layout on spawn
- Execution inside the layout generates telemetry (which panes were used, which were ignored)
- Telemetry refines the layout for that ticket type
- Better layouts → tickets spawn into better workspaces → more effective execution → more telemetry

Ignition move: ship a minimal `layoutId` column on Lattice ticket records within a month of Phase 1. Even if unused at first, it primes the pump.

Without a small engineering move now, neither loop ignites. With 20-80 LoC, both do.

---

## Concrete Suggestions

1. **Refactor first, ship second.** Do the `WorkspaceLayout` extraction in a separate commit/PR *before* CMUX-15 lands. The current plan's "factor `gridSplitOperations`" sidesteps this by factoring only the split sequence, not the content layer. Go further: factor the whole layout as data.
2. **Ship four named layouts, not one adaptive grid.** Users pick default from `{solo, pair, productivity, studio, auto}`. `auto` runs the classifier. Defaults to `auto` on first launch.
3. **Replace the 0.5s delay with a real readiness signal.** It's acceptable once, unacceptable on every new workspace.
4. **Add `cmux new --layout <name>`** in the same PR. One-line CLI addition if Layout v0 exists. Huge surface-area win.
5. **Add one-keystroke collapse in the new workspace.** A toast: "Default grid applied — press ⌘⇧Z to collapse to single pane." 5-second auto-dismiss. Preserves the opinionated default while giving instant undo.
6. **Record `layoutName` on the workspace record.** Even if unused now. Trivial to add, painful to backfill.
7. **Consider splitting the ultra-wide question.** The plan defers it. Instead, just add `.ultrawide` to `MonitorClass` returning `(4, 2)` or `(3, 2)` — the explicit case is cheaper than the deferred TODO.
8. **Name the thing in user-facing text.** Call it "Smart Start" or "Auto-Grid" or "Workspace Shape" — something memorable. "Default pane grid" is an engineering description, not a feature name.
9. **Build a telemetry ping: "layout retained after 60s?"** Within a week, you'll know if users keep it or collapse it. That signal drives every subsequent tuning decision.
10. **Explicitly document: this primitive replaces the welcome quad's special-casing.** Not in this PR necessarily, but as an ADR. That framing is what gets reviewers to see the layout system, not the grid.

---

## Questions for the Plan Author

1. **Should Phase 0 (the `WorkspaceLayout` extraction and welcome-quad migration) ship as a separate, prior PR?** I'd argue yes. It's a pure refactor, cheap to review, and it changes whether CMUX-15 is a one-off or a foundation.
2. **Named layouts vs. anonymous adaptive grid — which is the product?** "A grid appears" is one feature. "Pick your workspace shape" is a product surface. Which are you building?
3. **What's the intended relationship between CMUX-15 and the welcome quad?** Are they sibling layouts in the same system, or permanently separate code paths? Your answer drives the Phase 0 decision.
4. **Who else should be able to invoke a layout?** Just internal code? Socket/CLI users? Lattice tickets? Third-party agents? Scoping this now determines whether `WorkspaceLayout` needs to be a public type or can stay internal.
5. **What's the escape hatch in-app, not just via `defaults write`?** Opinionated defaults need in-product undo. What does that look like on first encounter?
6. **Is the 0.5s post-ready delay acceptable on every new workspace?** It's a tolerated quirk once; it's a recurring jank if the feature is default-on.
7. **Should `layoutName` be persisted on workspace records from day one?** Cheap now, expensive later. Yes/no?
8. **Ultra-wide: defer or solve?** The plan defers. I'd add `.ultrawide` explicitly — the deferred case is probably cheaper to handle now than to revisit.
9. **Does a Lattice ticket ever request a layout in the next 30 days?** If yes, the socket/CLI entry point needs to land in Phase 1, not Phase 2. If no, Phase 2 is fine.
10. **Telemetry: what's the success metric for CMUX-15?** "Feature shipped" is not enough. "% of workspaces where user retains the grid after 60s" is measurable. Define the metric before shipping — otherwise you can't tune the classifier.
11. **Should the sibling multi-monitor ticket wait for Layout v0, or ship in parallel?** If Layout v0 exists, multi-monitor is "apply a per-screen layout on move." If not, it's a second round of ad-hoc split logic. Sequencing matters here.
12. **Is there a story for a `cmux layout save` (capture the current workspace as a named layout) in the near-term roadmap?** The layout-creation leg of the flywheel needs that command to ignite. Is it on the radar?

---

## Closing

CMUX-15 as written is a fine ticket. CMUX-15 re-framed as **Layout v0** is a foundational move that costs roughly the same, ships roughly the same diff, and quietly lays rails for a dozen downstream features — some in the plan's mutations, most not yet imagined. The refactor cost is measured in tens of lines. The downstream savings are measured in every future feature that wants to compose a workspace.

The question isn't "should we ship the grid?" — yes, obviously. The question is: when future-you wants to ship "describe the workspace you want in English" or "Lattice tickets auto-shape their c11mux workspace" or "share your layout with a teammate," will today's you have made those cheap or expensive? The plan as written makes them expensive. A 20-line refactor, dropped in before Phase 1 lands, makes them cheap.

Ship the grid. Ship it as Layout v0.
