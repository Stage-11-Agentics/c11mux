# Standard Plan Review — CMUX-25 (Multi-window c11mux, Emacs-frames, phased)

**Reviewer:** Claude Opus 4.7
**Plan:** `/Users/atin/Projects/Stage11/code/cmux/.lattice/plans/task_01KPHHQZA4XZTQD4BQCGQYC7FR.md`
**Sibling tickets:** CMUX-25 (v1 implementation, phased), CMUX-26 (v2 hotplug backlog), CMUX-16 (parent spike, done)

---

## Executive Summary

This is a strong plan. It does the hardest thing a plan can do: it picked an architecture (Hybrid C — process-scoped pane registry + per-window `WorkspaceFrame`) that *generalises an existing gradient* rather than fighting it, and it resisted the gravitational pull toward the two easy-wrong answers (bonsplit-spanning-windows or super-workspace-as-label). The six resolved CMUX-16 questions show this is not a first-draft design; they read like a real negotiation between ambition (Emacs-frames for terminals — genuinely novel) and scope (ship v1 without rewriting bonsplit, without hotplug, without sidebar-sync UX).

The single most important thing: **Phase 2 is the load-bearing wall.** Phases 1, 3, 4, 5, 6 are all either additive (1, 5, 6) or cosmetic around an already-fixed ownership model (3, 4). If Phase 2 lands clean, v1 ships. If Phase 2 drifts, everything drifts. My concern is less "is the plan right?" (it is) and more "is the Phase 2 estimate honest?" (~2 weeks is tight; details below). I'd also sharpen the feature-flag semantics — at present the flag means two different things in different phases.

**Verdict: Ready to execute, with three sharpening asks** (Phase 2 estimate, feature-flag semantics, and two pieces of scope that should be named-and-not-slipped). See Readiness Verdict.

---

## The Plan's Intent vs. Its Execution

The plan's underlying intent is not "ship multi-window c11mux." It's "make c11mux's pane model *truly* process-scoped so that multiple NSWindows can be viewports onto shared state — the Emacs-frames property." The multi-window UX is the surface; the registry refactor is the soul.

The plan *does* recognise this — Phase 2 is correctly named the biggest lift, and the Hybrid C decision is framed as "the boundary is the pane registry, not the split tree," which is exactly right. But the execution narrative has one soft spot: the plan talks about Phase 2 as "refactored ownership, no visible multi-window behavior" (shipped behind a flag, preserving single-frame-per-workspace semantics). That's a reasonable *derisking* story, but it's also a trap. If Phase 2 preserves single-frame semantics, there's no way to tell — from the inside, while building it — whether the new primitives actually work for multiple frames. Phase 3 is the earliest point where the registry gets exercised against its actual design load, and by then the Phase 2 code is on main.

**Recommendation:** Phase 2 should land with *one concrete multi-frame test path*, even if it's gated behind a dev-only flag separate from `CMUX_MULTI_FRAME_V1`. Something like "with `CMUX_MULTI_FRAME_V1=1` and `CMUX_MULTI_FRAME_V1_SHOW_SECOND_FRAME=1`, `workspace.spread` opens a second window and renders the same workspace in both." That's not Phase 5 yet (no distribution logic, no CLI polish), but it's a smoke test that proves the registry is actually doing its job before Phase 3 starts relying on it.

Aside from that, intent→execution alignment is tight. The nomenclature lock (§Primitive hierarchy) is a real gift to future readers. The explicit "CMUX-23/24 cancelled, folded into CMUX-25" audit trail is the right kind of honest.

---

## Architectural Assessment

### The big call: Hybrid C (process-scoped panes, window-scoped frames)

This is the right decomposition. Three reasons:

1. **It respects bonsplit's contract.** Bonsplit owns one `SplitNode` tree per `BonsplitController`, rendered inside one `PaneContainerView`. Option A (one tree spanning windows) would require bonsplit to grow a "render my left subtree in window 1 and my right subtree in window 2" primitive, which breaks encapsulation and bleeds multi-window awareness into what should be a pure splits library. Rejected correctly.

2. **It matches where the existing code is already gradient-pointing.** `AppDelegate.moveSurface` already walks `mainWindowContexts.values` via `locateSurface`. `Workspace.detachSurface(panelId:)` already returns a `DetachedSurfaceTransfer`. The socket is already process-scoped. The refactor is less "add a new layer" and more "finish what was started." That's the cheapest kind of architectural move.

3. **It makes pane migration a pointer operation, not a lifecycle event.** A pane moving windows = unlink leaf in frame A, link leaf in frame B. The PTY, Ghostty surface, MTL layer don't know and don't care. That's a property you want; Option B (super-workspace) would make cross-window move a full migrate-and-rebuild, with all the flashing and latency that implies.

### The smaller calls

- **Per-window independent sidebars** (with `SidebarMode` seam): right call. The parallel-agents workflow wants independent selection; sync mode is a power-user affordance for a narrow workflow (screen-share walkthroughs, single-task deep-focus reviews). Building the seam now for a UX that may or may not be needed later is usually wrong, but here it's cheap — it's an enum value and a stub method — and the seam pays off in session-persistence forward compat. Proportional.
- **Per-window focused pane** (not global focus): correct for the same reason `Cmd+~` in every native macOS app doesn't re-focus. Matching platform convention is the right default; breaking it needs justification, not the other way around.
- **Cross-window drag-drop at v1, with CLI-only fallback.** The cost-benefit is right: `.ownProcess` pasteboard visibility already does most of the work, the fallback plan is explicit, and the architecture doesn't depend on drag succeeding. Low-risk ergonomic sugar.
- **Spread with `ceil(N/D)` leftmost-first.** Deterministic, CLI-documentable, reads left-to-right. Good default; `--weights` override for power users. No complaint.
- **Opt-in split-to-new-window.** Right call; auto-overflow is surprising. The post-v1 toast is a nice touch but correctly deferred.

### The one thing I'd reframe

The plan frames `WorkspaceFrame` as "one bonsplit tree per {workspace, window} pair" — fine as a data description, but it slightly understates the primitive's novelty. `WorkspaceFrame` is *also* the unit of multi-viewport rendering: it's the thing that means "I am window 3's view of workspace `agents`." A `WorkspaceFrame` can exist without any panes (empty viewport), and multiple frames of the same workspace can exist in different windows (multi-viewport). Naming-wise this is fine — "frame" as in Emacs frame — but the documentation-voice should make the multi-viewport aspect more explicit. Otherwise readers will see `WorkspaceFrame` and think "container for bonsplit tree" when the interesting thing is actually "viewport identity."

---

## Is This the Move?

### What typically goes wrong in plans like this

1. **Ownership refactor without a behavioral test.** Team refactors the data model to be "more correct," lands it behind a flag that preserves old semantics, and then discovers during Phase 3 that the new model doesn't actually support the new UX. The flag becomes permanent; the refactor becomes tech debt with a ribbon on it. Addressed above; Phase 2 needs a multi-frame smoke test.

2. **Feature-flag turns into fossil.** `CMUX_MULTI_FRAME_V1=1` currently has an unclear retirement story — the plan says "flag retires after Phase 3 soaks on main for a release cycle," but "soaks" isn't a shipping criterion and "one release cycle" doesn't have a definition that couldn't be stretched. Flags that protect refactors are disproportionately prone to this because there's no user demand to kill them; they just sit. Recommend a concrete retirement criterion — e.g., "flag removed in the release immediately following Phase 6's merge, unless a P0 regression is filed referencing the flag." No subjective "soak" window.

3. **Session-persistence migration that's schema-correct but data-lossy.** The plan's migration story ("re-normalise embedded workspace data into the new top-level collection") is directionally right, but "re-normalise" is doing a lot of work in that sentence. The old schema has workspaces embedded inside each window's `SessionTabManagerSnapshot`. The new schema has workspaces at top level, referenced by ID from windows. What happens if the *same* workspace ID appears in two windows' snapshots in a pre-migration save file? (Today it can't — workspaces are window-owned — so every workspace appears exactly once.) Good. But what if a future save file (with the new model allowing one workspace hosted in multiple windows) gets read by an older client (e.g., someone rolling back)? The schema-version check catches that, but does the plan require a forward-incompatible schema bump, or a forward-compatible additive bump? The plan says "schema version bump" — I read that as incompatible, which is fine, but it should be explicit that rollback from a post-Phase-2 build to a pre-Phase-2 build *will discard session state* (or gracefully downgrade). Worth stating.

4. **The 5,283-line `TabManager.swift` rename-plus-thinning.** The plan's framing — "rename `TabManager` → `WindowScope`, drop `tabs: [Workspace]` as source of truth, replace with `hostedWorkspaces: [UUID]`" — is the right surgery, but it's surgery on a 5,283-line file that is also the busiest file in the codebase per the incidental findings note ("more growth would be hostile to diff review"). A rename plus a data-model shift plus a thinning in the same PR is three things. The plan should commit to a sub-ordering inside Phase 2: (a) rename mechanical, no semantic change, land green; (b) extract `WorkspaceRegistry` from `TabManager`, land green; (c) introduce `PaneRegistry`, migrate panel ownership, land green; (d) introduce `WorkspaceFrame`, thin `WindowScope` down. Otherwise the review burden of a single Phase 2 PR is untenable.

5. **Socket API rename that's "one release" of shim.** The deprecation strategy is right in spirit but squishy in practice. "One release" means what — the next `0.X.0` bump? The next tag pushed? Between two weekly releases? The plan specifies CHANGELOG documentation, a `deprecation_notice` response field, and DEBUG-log warnings — all good. But the shim removal criterion should be "shim removed in the release tagged at least 30 days after Phase 2's merge commit lands on main" or similar — not "one release cycle," which could be a week or a quarter depending on mood.

### Is the phasing sound?

Mostly yes. The critical-path call — Phase 1 blocks Phase 2; Phase 2 blocks everything — is correct. Phase 1 being a pure-additive CLI surface that doesn't touch window scoping is a smart opener: it gives the team a full shakedown of the display ref plumbing (parse, resolve, error codes, positional aliases, tests) before the hard refactor starts. Good de-risking.

The "Phases 3–6 can run in parallel" claim deserves scrutiny. Parallelising Phase 3 (cross-window pane migration) and Phase 4 (sidebar split) is fine — mostly disjoint surface areas. Phase 5 (`workspace.spread`) depends on Phase 3's `pane.move` primitive being in shape, and on Phase 4's per-window selection being correct. Phase 6 (split-into-new-window) depends on Phase 1's display resolver. So the dependency graph is:

```
1 → 2 → { 3, 4 } → 5
        { 3, 6 }
```

Phases 3 and 4 are truly parallel post-Phase-2. Phase 5 depends on both. Phase 6 depends on Phase 3 but not Phase 4. The plan's "parallel after 2 lands" is almost right but slightly optimistic; sharpen the dependency graph and say so.

---

## Key Strengths

- **The architecture respects bonsplit's contract.** Hybrid C means bonsplit doesn't change at all. Leaves reference opaque `PaneID`s; the host resolves them. This is the cleanest possible boundary — bonsplit stays a pure splits library, and cmux owns all the multi-window plumbing. That's the right separation of concerns.

- **The existing code gradient is honoured.** The plan explicitly calls out that `moveWorkspaceToWindow` / `moveSurface` already walk windows; `.ownProcess` pasteboard already allows cross-window drag; socket is already process-scoped. The refactor isn't inventing new concepts so much as finishing what was started. Low risk per unit of progress.

- **Naming is taken seriously.** Locking `Window → Sidebar → Workspace → WorkspaceFrame → Pane → Surface → Tab` as a primitive hierarchy (and writing it down, in the ticket, in the plan) is worth its weight in future-session-clarity. Most codebases develop these terms organically and end up with inconsistency.

- **Feature flag scoping is the right granularity.** The flag isn't "multi-window v1" (too coarse) and isn't "per-phase" (too fine). It's "the set of changes that are semantically invisible when off and semantically multi-frame when on." That's right. (See weaknesses below on retirement criteria.)

- **Deprecation path is explicit, not hand-waved.** Response-field `deprecation_notice` plus DEBUG logs plus CHANGELOG entry plus shim-removal-in-next-release. This is the right protocol — automation callers can grep for the notice, humans get the CHANGELOG, lazy callers get a DEBUG log. Better than the industry median.

- **The deferred-to-v2 boundary is honest.** Runtime hotplug is genuinely hard (scriptable display-toggle rigs, `didChangeScreenParametersNotification`, affinity memory). Deferring it to CMUX-26 with a depends-on link, and telling v2 to "re-survey operator behavior before starting," is mature planning. The v1 scope ("users spawn windows and assign them to monitors manually") is defensible and testable.

- **Session persistence thinks about forward compat.** The `sidebarMode` field serialised at v1 (only `.independent` wired, but seam preserved) is the right move for something that will grow. Cheap now, saves a migration later.

---

## Weaknesses and Gaps

### 1. Phase 2 estimate is aggressive

Two weeks for: `PaneRegistry`, `WorkspaceRegistry`, `WorkspaceFrame`, `TabManager` → `WindowScope` rename, thinning a 5,283-line file, session-persistence schema bump + migration, socket API rename with deprecation shim, feature flag wiring. For a team of 1 engineer, this is a 3–4 week job with standard care; 2 weeks only works if (a) the engineer is already deeply familiar with `TabManager`, `Workspace`, and `SessionPersistence`, and (b) nothing unexpected surfaces (e.g., the socket V2 resolver helper `v2ResolveTabManager` has more call-sites than the plan anticipates, or the session migration has edge cases around deleted workspaces with in-flight PTYs).

**Downstream effect if the estimate is wrong:** Phase 3/4/5/6 estimates all key off "Phase 2 landed clean." If Phase 2 spills into week 3, the ~7-week total (1 + 2 + 1 + 1 + 0.6 + 0.6) is actually 8–10 weeks. That's not a disaster, but it should be named — and the release/flag-retirement plan should absorb it.

**Sharpening ask:** Either widen the Phase 2 estimate to 3 weeks with a clear sub-ordering (see Point 4 above), or commit to the 2-week estimate with a tripwire — if at day 10 there's no working `WorkspaceFrame` rendering a shared workspace, pause and re-plan.

### 2. Feature flag has two meanings

In the plan, `CMUX_MULTI_FRAME_V1=1` serves two purposes:
- **During Phase 2:** preserves single-frame-per-workspace semantics; the flag gates *internal refactor soak*.
- **After Phase 3+:** enables multi-frame *user-visible behavior*.

That's two different flags wearing one name. A developer reading Phase 2's "ships behind the flag" doesn't know whether the flag is "on = refactor visible, no UX change" or "on = new UX." Ambiguity here will cause confusion in PR descriptions, CI test matrices, and dogfooding instructions.

**Sharpening ask:** Either (a) make the flag UX-gated only (Phase 2 lands with the flag default-off and semantically inert, Phase 3 is where the flag starts gating user-visible behavior), or (b) split into two flags (`CMUX_MULTI_FRAME_REGISTRY=1` for Phase 2 ownership, `CMUX_MULTI_FRAME_UX=1` for Phase 3+). I'd pick (a) — one flag, clear semantics.

### 3. No smoke test for Phase 2's multi-frame machinery

As noted in §The Plan's Intent — Phase 2's "preserves single-frame-per-workspace semantics" means the new registry isn't exercised for its design purpose until Phase 3. That's risky. Phase 2 should land with at least one developer-accessible path to spawn a second `WorkspaceFrame` on an existing workspace, even if it's behind a debug menu item or an env var — just to prove the pointer-swap actually works.

**Downstream effect:** Phase 3's "add drag-drop, add `pane.move`, add keyboard shortcut" is currently scoped as a *pure additive* phase. If Phase 2 shipped with latent bugs, Phase 3 turns into Phase 2.5 (fix registry bugs) + Phase 3 (actually add UX), blowing the 1-week estimate.

### 4. The `TabManager.swift` thinning needs sub-ordering

5,283 lines, plus a class rename, plus a data-model shift, plus an ownership move, plus a new registry, plus a new frame type — that's not a PR, that's a sprint. Phase 2 as currently written is essentially one big PR from the review perspective. It should be ordered as ~4 sub-PRs, each landing green, each with a rollback story.

### 5. Rollback story is missing

What happens if Phase 2 lands on main and a P0 bug surfaces three days in? The feature flag is intended for forward-only protection ("flag off = old behavior"), but:
- The `TabManager` → `WindowScope` rename is not flag-gated (types can't be renamed behind a flag).
- The session-persistence schema bump is not flag-gated (the save file is one shape or the other).

So flag-off doesn't actually roll back to pre-Phase-2. A rollback means `git revert`, which after a 2-week PR is painful and merge-conflict-rich against whatever else lands simultaneously.

**Sharpening ask:** State the rollback story explicitly. Options: (a) "Phase 2 is irreversible on main; the tripwire is a 2-day manual-test bake on a staging tag before merging." (b) "Phase 2 lands in a series of sub-PRs, each independently revertible." (c) "Phase 2 lands on a long-running branch, QA'd on that branch for a week before merging." I'd pick (b).

### 6. Estimates for Phases 5 and 6 (~3 days each) are optimistic

Phase 5 (`workspace.spread`): three modes (`one_pane_per_display`, `existing_split_per_display`, `all_on_each`), the second of which requires splitting an existing bonsplit tree along vertical dividers matched to display count. That's not a small algorithm — it involves deciding where vertical cuts land when the tree has nested horizontal/vertical splits, handling edge cases (single pane, tree deeper than the display count), and testing across 1/2/3/4-display configurations. Plus the `--weights` override. Three days is tight.

Phase 6 (split-into-new-window): similar. CLI flags, window creation on target display, keyboard shortcut, plus the 480px minimum-width hint (deferred to post-v1, okay). Three days is *possible* if the display resolver from Phase 1 and the window creation from Phase 2 both already work cleanly. Call it four days to be safe.

**Net effect:** Nothing catastrophic, but the total estimate (~7 weeks) is probably 8–9 weeks in practice. Worth naming.

### 7. Session-persistence schema bump forward-compat for CMUX-26

The plan says window snapshots carry `sidebarMode` at v1 as a forward-compat seam for sync mode. Good. But CMUX-26's scope requires *per-window last-known-display tracking* — is that also seamed in at Phase 2?

Checking the plan — §6 says: "Each window tracks the display it was last on (`NSScreen.cmuxDisplayID`)" under the v2 scope. And CMUX-26's ticket says "schema already set up in CMUX-25 Phase 2." But I don't see an explicit `lastKnownDisplayID: UInt32?` field in the `SessionWindowSnapshot` extension called out in the plan. The plan mentions "Window frame + display snapshot (as today, already display-aware via `SessionDisplaySnapshot` / `resolvedWindowFrame`)" — which may or may not capture the affinity bit.

**Sharpening ask:** Explicitly list every field being added to `SessionWindowSnapshot` at Phase 2, including any CMUX-26 forward-compat seams. If the affinity field isn't being added, CMUX-26's schema-is-already-set-up claim is false and v2 will need its own migration. Better to do it now.

### 8. `Cmd+~` vs `Cmd+Shift+Ctrl+<Arrow>` vs `Cmd+Opt+Shift+<Arrow>` — keyboard-map real estate

Three new multi-modifier shortcuts land in v1:
- `Cmd+Shift+Ctrl+<Arrow>` — move focused pane to neighboring-display window (Phase 3)
- `Cmd+Opt+Shift+<Arrow>` — split overflow to next display (Phase 6)
- Plus the existing `Cmd+~` window cycle unchanged

No mention of whether these collide with: Ghostty's own keybindings, cc/codex/gemini TUI keybindings, user-configured shortcuts in Terminal.app peers (which users may reflexively try), or macOS system shortcuts. Also no mention of how users re-learn muscle memory across three similar modifiers on arrow keys.

**Sharpening ask:** Audit the keybinding table against Ghostty's default map and mention in the plan that no conflicts were found (or fix the ones that exist). This is a 30-minute check that could save post-launch toil.

### 9. The incidental finding about `CMUX_TAB_ID` is unresolved

The plan notes: "`CMUX_TAB_ID` memory note (workspace UUID ≠ tab UUID) is still on main. While reading session restore I saw no new code around it. Not in spike scope; worth a 1-line fix ticket separately."

This is a known-open correctness thing, flagged but not ticketed. Either ticket it now (before the review closes) or absorb it into Phase 2's scope — the whole point of Phase 2 is to clean up exactly this kind of naming/identity confusion, and it'd be cheap to fix while already in the file.

---

## Alternatives Considered

### Alternative A: Skip Phase 1, fold it into Phase 2

The plan opens with Phase 1 (display registry + CLI surface, 1 week, no behavior change). This is deliberate de-risking — a pure-additive foundation phase that lets the team learn display-ref plumbing before the registry refactor. An alternative would be to fold Phase 1 into Phase 2 as sub-PR (a), on the theory that the display registry is only interesting once you have multi-window behavior to address.

**Why the plan's choice is better:** Phase 1's CLI surface is useful *today* (pre-multi-window) for operators targeting `cmux window new --display left`. Shipping it as a standalone phase gives operators (and agents) the mental model of display refs before any scoping refactor lands, which is the right order for adoption. Also, Phase 1 doubles as a shakedown of the display-ref parsing code, error codes, and positional-alias edge cases — all of which Phase 2/3/5/6 will lean on. The 1-week cost is money well spent.

### Alternative B: Ship cross-window drag-drop as v1.1, not v1

The plan ships drag-drop at v1 with a CLI-only fallback. Alternative: ship CLI-only (`pane.move`) at v1, defer drag-drop to v1.1.

**Why the plan's choice is better:** Drag-drop is free-ish because the AppKit constraints already allow it (`.ownProcess` visibility, cross-window dragging sessions, existing `locateSurface` walk). The only work is auditing accidental window-scoping and writing one integration test. Deferring it wouldn't save meaningful time and would leave the v1 UX feeling incomplete — users *will* try to drag a tab between windows, and finding they can't would be a papercut. The fallback plan (CLI-only if AppKit misbehaves) is correctly written.

### Alternative C: Build sync-mode sidebar UX at v1 instead of just the seam

The plan ships per-window independent sidebars at v1, with a `SidebarMode` enum seam for a future sync-mode feature. Alternative: build the full sync-mode UX at v1 so operators have the choice from day one.

**Why the plan's choice is better:** Sync-mode UX has design unknowns (which window is "primary"? user-designated or automatic? how does focus transfer when the primary closes?). Shipping independent-only at v1, with the seam for later, is right-sized: the sidebar code's shape is fixed now (so sync-mode won't require a painful second refactor), but the UX design can happen in parallel with v1 usage feedback. Classic "land the primitive, defer the UX."

### Alternative D: Defer the `workspace.move_to_window` rename

The plan renames at Phase 2 with a shim. Alternative: keep the old name, rationalise in a v2 cleanup pass.

**Why the plan's choice is better:** The name `workspace.move_to_window` is actively misleading under the new model (windows don't *own* workspaces anymore; they host *frames* of them). Deferring the rename ships a correctness-fiction in the public API, which agents will write automation against and then have to migrate. Renaming now, with a well-documented shim, is the right call.

### Alternative E: Different workspace-model (Option B, super-workspace)

The plan selected Hybrid C. Option B (workspace-per-window + super-workspace label) would be cheaper up-front.

**Why the plan's choice is better:** Option B doesn't deliver the Emacs-frames property — it's just a UI label over the existing ownership. Moving a pane between "siblings" under Option B is a full workspace migration (lifecycle event for the PTY and surface), not a pointer swap. The spike explicitly rejected this and the reasoning is sound. Hybrid C is genuinely more work, but the work buys the target architecture.

---

## Readiness Verdict

**Verdict: Ready to execute, with three sharpening asks.**

The architecture is right. The decomposition is right. The deferrals are honest. The plan does not need rethinking.

The three sharpening asks before starting Phase 2:

1. **Phase 2 sub-ordering and estimate.** Commit to either 3 weeks with a 4-PR sub-ordering (rename → `WorkspaceRegistry` extraction → `PaneRegistry` + panel migration → `WorkspaceFrame` + thinning), or 2 weeks with a day-10 tripwire. Current "2 weeks, one big push" is too tight and not reviewable.

2. **Feature-flag semantics.** Make `CMUX_MULTI_FRAME_V1` mean one thing — UX-gated only. Phase 2 lands flag-default-off, semantically inert (i.e., old session files still load, no behavioral change for users with flag off). Or split into two flags with clear names. Either way, write one sentence about what "on" means in each phase.

3. **Session-persistence schema fields.** Enumerate every field added to `SessionWindowSnapshot` and `AppSessionSnapshot` at Phase 2, including any CMUX-26 forward-compat seams (affinity, hibernation markers). This is a 30-minute write-up that prevents CMUX-26 from needing its own migration.

None of these block the spike sign-off. They're Phase 2 kickoff prerequisites.

---

## Questions for the Plan Author

1. **Phase 2 estimate:** Is 2 weeks predicated on a specific engineer already familiar with `TabManager`/`Workspace`/`SessionPersistence`, or is it a generic estimate? Either way, would you support widening to 3 weeks if the sub-ordering breaks into 4 PRs?

2. **Feature-flag semantics:** When `CMUX_MULTI_FRAME_V1=1` during Phase 2 (pre-Phase-3), what *visible behavior* differs from flag-off? If the answer is "nothing" (the flag is purely for refactor soak), why does Phase 2 need a flag at all vs. flag-default-off-and-no-op-until-Phase-3?

3. **Rollback story:** If Phase 2 lands on main and a P0 surfaces, what's the rollback protocol? Is it `git revert` (risky for a 2-week PR) or is Phase 2 structured as revertible sub-commits?

4. **Phase 2 smoke test:** Does Phase 2 land with a developer-accessible way to prove the registry supports multiple `WorkspaceFrame`s on one workspace (even if behind a debug flag), or does the first real multi-frame test wait until Phase 3?

5. **Session schema fields:** Beyond `sidebarMode`, what fields does `SessionWindowSnapshot` gain at Phase 2? Specifically — is `lastKnownDisplayID` added now as a CMUX-26 forward-compat seam, or does CMUX-26 need its own migration?

6. **Session migration forward compat:** If a user rolls back from a post-Phase-2 build to a pre-Phase-2 build, does their session state survive (via graceful downgrade) or is it discarded (schema-version mismatch, start fresh)? Which is the intent?

7. **`workspace.move_to_window` shim retirement:** What's the concrete "one release cycle" criterion — a specific number of days on main, the next minor version bump, or something else? The plan leaves this subjective.

8. **`CMUX_MULTI_FRAME_V1` retirement criterion:** Same question — "flag retires after Phase 3 soaks on main for a release cycle" is subjective. Is there a bug-free-day count, a user-count threshold, or a specific version?

9. **Keybinding conflicts:** Has `Cmd+Shift+Ctrl+<Arrow>` and `Cmd+Opt+Shift+<Arrow>` been audited against Ghostty's default keybindings and common TUI shortcuts (cc, codex, vim, emacs-in-terminal)? If yes, note it; if no, adding the check to Phase 1 would be a small insurance premium.

10. **Phase 5 `existing_split_per_display` algorithm:** How does the tree get split when it has nested horizontal/vertical splits that don't cleanly match the display count? Is the algorithm spec'd anywhere? Three days is tight if the algorithm needs designing mid-phase.

11. **Phase 3/4 parallelism:** Who owns each? If they're the same engineer, parallelism is fictional and the estimate should be additive (1 + 1 = 2 weeks), not 1 week wall-clock.

12. **Phase 2 acceptance criteria:** The plan lists Phase 2 scope but not explicit acceptance criteria. What test or set of tests, when green, says "Phase 2 is done"? (Registry round-trips, session migration tests, socket rename tests, existing test suites still green with flag off and flag on?) This is the kind of thing that keeps Phase 2 from silently extending.

13. **`CMUX_TAB_ID` fix:** The incidental-findings note flags this as "worth a 1-line fix ticket separately" — is that ticket being created? If it's cheap to absorb into Phase 2 (you're already in the file), worth doing there.

14. **`WorkspaceFrame` multi-viewport semantics:** Can two `WorkspaceFrame`s of the same workspace in different windows render *different* bonsplit layouts (e.g., window A shows a 2x2 grid, window B shows a single pane) — or are they synchronised to the same layout? The plan leans toward independent ("one bonsplit tree per {workspace, window}"), which means *different* — worth confirming. If independent, what does "drag pane from frame A to frame B of the same workspace" mean semantically?

15. **CMUX-26 display-affinity schema:** CMUX-26's ticket says "schema already set up in CMUX-25 Phase 2" — is that an explicit commitment in this plan, or is it aspirational? If explicit, please call out the fields by name in Phase 2's scope.

16. **Nomenclature for the "no workspace selected" window state:** The plan mentions fallback behavior on relaunch when a workspace is deleted ("falls back to the first workspace in the registry or an empty 'choose a workspace' state"). What's that empty-state called in the nomenclature — is a window with no `WorkspaceFrame` still a valid `WindowScope`, or does it have a distinct type/state? Small but worth locking for the session-persistence shape.

17. **Dogfooding plan:** Who runs with `CMUX_MULTI_FRAME_V1=1` during Phases 3–6 development, on what rig (single-monitor dev laptops won't exercise the feature), and for how long before the flag retires?

---

## Closing Thought

The thing I most respect about this plan is what it didn't do. It didn't propose rewriting bonsplit. It didn't propose super-workspaces. It didn't propose shipping sync-mode sidebar UX because the seam was cheap. It didn't propose hotplug because v1 doesn't need it. Each of those restraints took a real, considered conversation to resolve — and the resolutions log (CMUX-16's six answered questions) is the plan's best-quality artifact. That's the signal of a spike that did its job.

Ship Phase 1. Widen Phase 2's estimate or sub-order it. Then execute.
