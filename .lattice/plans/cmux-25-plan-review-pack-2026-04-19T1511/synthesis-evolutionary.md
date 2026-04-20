# Evolutionary Synthesis — CMUX-25 Plan Review

**Plan:** `cmux-25-plan` (Multi-window c11mux / Emacs-frames v1)
**Source reviews:** Claude (Opus 4.7), Codex, Gemini
**Stance:** evolutionary / exploratory
**Date:** 2026-04-19

Note: Gemini's review is shorter than the others due to an API quota interruption. It is treated as a complete-but-brief third opinion — its weight comes from agreeing or diverging independently, not from depth.

---

## Executive Summary

All three reviewers converge on the same core insight, stated slightly differently:

- **Claude:** "CMUX-25 is a refactor that turns c11mux's core data model inside out — panes stop being window-local children and become process-scoped, first-class, long-lived objects." Rename to "Pane-first c11mux."
- **Codex:** "The birth of a process-scoped pane runtime and viewport graph, not merely multi-window support. A separation between runtime identity and visual placement."
- **Gemini:** "c11mux stops being a terminal multiplexer and starts being an invisible backend service — a Process-Scoped Surface Orchestrator, an Agent-Native Spatial Window Manager."

The surface feature is "multi-window." The underlying deliverable is a **process-scoped, agent-addressable registry of durable PTY+surface capabilities, decoupled from the UI that renders them** — a capability fabric where windows are one viewer among many (sockets, agents, remote clients, recordings, mobile companion UIs).

The unanimous strategic recommendation: **keep the six-phase sequence intact, but invest modestly more design in Phase 2** to add a small number of seams that turn every downstream mutation from "a rewrite" into "an additive harvest." Three seams recur across all reviewers: (1) stable frame identity, (2) a pane-viewer / pane-attachment ledger separating runtime from placement, and (3) explicit scrollback / lifecycle semantics for panes with zero viewers.

If those seams land at Phase 2, the rest of the plan ships as written — and v1.1 through v2 unlocks multi-viewer panes, broadcast, present mode, agent-addressable pane selectors, headless/parked panes, GUI session-attach, recording/replay, and a macOS-native "pane as OS resource" story.

The bigger ask: **name the shift publicly.** Treat the flag retirement as a product event ("Pane-first c11mux 1.0"), update the charter, and publish a stable `pane:` ref scheme as a public contract. Without the naming, downstream authors and external observers will mistake a platform launch for an internal refactor.

---

## 1. Consensus Direction (Evolution Paths All Three Models Identified)

Paths where two or three reviewers independently converged:

1. **Separate runtime identity from viewport placement.** The central architectural move. Claude frames it as "viewer-set on Pane." Codex formalizes it as `PaneRuntime` + `PaneAttachment` + `PanePlacement` ledger. Gemini calls for `mirrored_from` on `WorkspaceFrame` and many-to-many pane↔workspace. All three say: do not let "one pane = one renderer = one window" become a permanent invariant, even if v1 enforces it at the API layer.

2. **Stable pane identity as a public, process-scoped contract.** All three reviewers want `pane:ref` (and sibling refs — `frame_ref`, `placement_ref`, `display_ref`, `workspace_ref`) to be stable, documented, and agent-addressable. Claude: "the pane ID is canonical; window/display are projections." Codex: stable refs unlock selector-addressable commands. Gemini: "Agent-to-Pane Absolute Addressing" regardless of window.

3. **Panes survive viewer absence (headless / parked / hibernated).** Unanimous. Claude: "a Pane can exist with zero viewers and keep running." Codex: explicit `headless` / `parked` placement state in the ledger, even if hidden from users in v1. Gemini: "Pane Hibernation without losing PTY — fundamentally de-risks multi-monitor undocking." This forces a crisp, registry-encoded answer to "what happens when a window closes" rather than implicit UI behavior.

4. **Multi-viewer / mirror / present as the v1.1 differentiator.** All three call out frame mirroring and present mode as the single clearest story that distinguishes c11mux from tmux, Zellij, iTerm2, WezTerm, and JetBrains detached frames. Claude: `pane.attach` as a new viewport without moving. Codex: `frame.mirror` and `workspace.present --mode follow-focus`. Gemini: Present Mode built on the Phase 4 sync-mode seam.

5. **Agent-native addressing via metadata + selectors.** Claude: "Agent-to-pane addressing as a first-class schema" with `AgentCapabilitySet` and `cmux pane invoke`. Codex: selector-based socket commands (`pane.list --where`, `pane.broadcast --group`, `workspace.spread --by role`). Gemini: `layout_role: "reference"` / `"focus"` as agent-declared spatial intent. The shared direction: agents declare intent through metadata; c11mux resolves it through the registry.

6. **GUI session-attach as the moonshot.** Claude (D), Codex (Zellij-style native GUI), and Gemini (headless daemon + lightweight UI client) all independently arrive at the same evolutionary endpoint: the registry is already socket-addressable, so extending the socket to a streaming session-attach protocol makes c11mux the first GUI multiplexer with tmux-grade detach/reattach and multi-client semantics.

7. **Cross-workspace pane sharing.** All three. The registry makes it structurally free: change `Workspace.paneIDs` from a partition to a set (Claude) / introduce many-to-many `panesByWorkspace` (Gemini) / allow shared read-only placements (Codex). Ship discipline gates it, not architecture.

8. **Sidebar / sync-mode as "director" not "primary."** Claude and Codex independently recommend better naming before the feature ships. Codex generalizes further: sync is not just sidebar selection — it can include layout, focus, pane visibility, and input mode as separate dimensions.

---

## 2. Best Concrete Suggestions (Most Actionable Across All Three)

Rank-ordered by leverage-to-effort. Each entry names the mechanism, estimated scope, and the mutation it unlocks.

1. **Add `FrameID` and keep `{workspace_id, window_id}` as fields, not identity.** (Codex seam #2; Claude aligns.) Phase 2, ~1 day of design + small code change. Prevents `{workspace, window}` from becoming an accidental ceiling. Enforce "one normal frame per tuple" at the API layer in v1; leave the storage model open for mirror, observer, presentation frames.

2. **Add a `PanePlacement` / `PaneAttachment` ledger at Phase 2.** (Codex seam #3; matches Claude's viewer-set.) ~50 lines plus serialization. Fact table with `placementId`, `paneId`, `frameId?`, `windowId?`, `displayRef?`, `state` (attached/headless/hibernated/migrating), `role` (primary/mirror/observer). Every later feature — `tree --by-display`, `pane.move`, `workspace.spread`, CMUX-26 hotplug, sidebar hosted-window counts — becomes a projection or mutation over this ledger.

3. **Decide scrollback ownership at Phase 2: Pane-level, not viewer-level.** (Claude, explicit.) Scrollback is part of the Pane's identity, not the viewport's. Answering this at Phase 2 avoids a CMUX-26 hibernation surprise and a first-obvious-bug when users detach and reattach.

4. **Ship `cmux pane show <pane:ref>` at Phase 2.** (Claude #1.) ~100 lines, one socket handler. Read-only query returning metadata + scrollback sample, works whether or not the pane is rendered anywhere. The smallest possible public assertion that panes are first-class process objects.

5. **Ship `pane.attach` alongside `pane.move` at Phase 3.** (Claude #5.) ~150 lines if the viewer-set / placement ledger is in place. Creates a second viewport onto the same pane without transferring ownership. Turns c11mux from "better window manager" into "first multi-viewer terminal." Highest leverage-to-effort ratio in the entire roadmap per Claude.

6. **Define the v1 close-window rule in the registry, not the UI.** (Codex #5; Claude Q7; Gemini Q1.) All three want this answered crisply before implementation. Consensus recommendation: last attached pane of a workspace migrates to another surviving frame in that workspace; otherwise the pane enters `headless` / `parked` state, even if v1 only exposes it as "restore parked panes" later. Operator trust in "work survives window churn" is the core value prop.

7. **Rename `SidebarMode.primary` → `director` at Phase 4.** (Claude #6.) One enum rename, zero behavior change. Shapes the UX mental model before the feature ships.

8. **Emit placement events on every move.** (Codex #3.) `pane.placement.created` / `.moved` / `.detached` / `.headless`. Builds on the existing `surface.move.*` debug log style. Makes multi-window bugs tractable and gives agents a stream to subscribe to.

9. **Publish a stable `pane:` ref scheme as a public contract at Phase 2.** (Claude #6, Q6; Codex #5 — `tree --json` with `frame_ref`, `pane_ref`, `placement_ref`, `display_ref`, `attachment_role`.) Third-party automation, agent SDKs, and Spotlight/NSUserActivity integration all depend on stability being committed up front.

10. **Broadcast composition surface as v1.1.** (Claude #5; Codex #7.) `.broadcast` scope on the textbox port (already in flight at `docs/c11mux-textbox-port-plan.md`) writing to a selector-based pane group. ~200 lines on top of the port. Generalizes tmux's `synchronize-panes` through metadata, workspaces, windows, and displays. #1 friction point for agent fleet operators.

11. **Make `workspace.spread` selector-aware post-v1.** (Codex #8; Claude implicitly; Gemini with `layout_role`.) `--by role`, `--where 'status=running'`, `--profile review-loop`. Turns display spreading into workflow spreading.

12. **Sidebar chip for viewer count.** (Claude #4.) `⧉ 2` on a pane's sidebar entry when multiple viewports exist; click cycles viewports. ~50 lines. Reinforces multi-viewer as a normal operator behavior (Flywheel 4).

13. **Ship `frame.mirror` before full sidebar sync mode.** (Codex #9.) Mirroring one frame to one display is a tighter, demonstrable step than designing the whole primary-sidebar UX at once.

14. **Ship `workspace.present --source current --display right --mode follow-focus` as a composed command.** (Codex #10; Claude F; Gemini.) Built on `frame.mirror` + focus-follow + read-only input. Gives "Emacs frames, for terminals" a visible, demo-ready story. c11mux's browser + markdown surfaces give it an advantage no TUI multiplexer has.

15. **Agent capability directory at v1.1.** (Claude #7.) `AgentCapabilitySet` on pane metadata + `cmux pane capabilities <pane:ref>` + `cmux pane invoke <pane:ref> <capability> <args>`. ~300 lines. Makes "c11mux is agent-native" real rather than implied.

16. **CHANGELOG framing at flag retirement.** (Claude #14.) Ship flag-off as "Pane-first c11mux 1.0" or similar — a product event, not an internal refactor. Zero code; enormous narrative weight.

17. **Preserve focus by default on every non-focus socket command.** (Codex #12.) Aligns with repo policy and is especially important once agents can rearrange panes across windows while the operator is typing.

18. **Keep `PaneRegistry` actor-isolated, frame/render mutations main-actor-explicit.** (Codex #13.) Repo's socket threading policy already warns against hot telemetry on main; the placement/selector path should follow.

---

## 3. Wildest Mutations (Creative / Ambitious / Risky)

Listed roughly in ascending order of ambition. Each unique to one reviewer or amplified beyond the consensus.

1. **Multi-viewer panes across monitors — "two screens, one terminal."** (Claude B.) Left monitor shows workspace overview; right monitor shows a zoomed view of one specific pane — the *same* pane, scrollback synchronized, one input. No terminal multiplexer has this: tmux "share a session" is two clients over a server; here it's one process, two viewports, zero state divergence.

2. **Pane broadcasting ("Stadium Mode").** (Gemini; reinforced by Claude/Codex.) A single pane broadcasted as PiP into every window's sidebar. If an agent is running a long system-wide compilation, every workspace sees it ambient.

3. **Agent rooms.** (Codex.) A workspace becomes an agent room: coordinator pane, worker panes tagged by task bucket, browser panes tagged as validators, markdown panes as spec, group broadcast, `pane.watch` subscriptions. No other multiplexer has the native GUI object graph + agent status plane to make this feel first-class.

4. **Pane recording & replay as a viewer type.** (Claude E.) `Viewer.kind = .recorder` writes a deterministic VT trace plus metadata timeline. Replay later into any window. Use cases: agent telemetry retro, demo mode with searchable scrollable text (better than screen recording), incident forensics replaying a production session into a sandbox.

5. **Present mode as a first-class frame variant.** (Claude F; Codex; Gemini.) `WorkspaceFrame.kind = .presentation`: big text, hidden chrome, zoomed scrollback, optional annotation overlay, speaker-notes surface on a second display. Keynote-grade polish, terminal-native.

6. **"Follow me" / director mode for demos.** (Claude G.) One window is the director, others are viewports that follow the director's selection. Operator demos to colleague; laptop = director, TV-connected window = viewport. Operator's hands never touch the second display.

7. **Context-Layout Flywheel — c11mux learns display affinity.** (Gemini.) Operator manually drags the browser to display 2; c11mux learns this through the registry; next time a similar task runs, browser spawns on display 2 automatically. The more operators use spatial placement, the less manual layout is needed.

8. **Workspace-as-query (`VirtualWorkspace`).** (Claude I.) Workspaces aren't hand-assembled pane sets — they're persisted queries. "Every red-status pane across every workspace." "Every agent pane idle >10 minutes." "Every pane with port 3000 open." Renders in a `WorkspaceFrame` exactly like a real workspace. Breaks the "workspace is a bag I made" mental model but obviously correct when managing 20–40 panes.

9. **GUI session-attach — "c11mux over the wire."** (Claude D; Codex; Gemini.) Extend the Unix socket to a streaming subscription protocol. A remote c11mux (same user, another machine via SSH forwarding, or a headless daemon locally) subscribes and becomes an additional viewer. Feasible *specifically* here because c11mux is the rare GUI multiplexer with a process-scoped socket, metadata seam, and capability abstraction.

10. **Headless c11mux daemon.** (Gemini.) Architect `PaneRegistry` so it doesn't strictly require an active NSWindow. A background daemon holds all panes/workspaces; lightweight UI clients attach and spawn windows across displays. The structural inverse of today's NSWindow-first model.

11. **Panes as OS-wide resources.** (Claude J.) Once `pane:ref` is stable, process-scoped, and socket-addressable, external apps reference c11mux panes: a Raycast extension for "active c11mux pane," a Stream Deck button to focus `pane:agent-4`, a shell function outside c11mux that pipes into a specific pane. Publish refs as NSUserActivities or via a Spotlight metadata provider. c11mux becomes a first-class macOS citizen — iTerm2 has AppleScript; nobody has "Spotlight search for a terminal pane by title."

12. **Frame composability — save, clone, apply, nest.** (Codex.) `cmux frame.save current --name review-driver`, `cmux frame.apply review-driver --workspace CMUX-25 --display center`, `cmux frame.clone frame:1 --display right --role mirror`. Frames as reusable named views. This is where "Emacs frames, for terminals" becomes bigger than Emacs frames.

13. **Display topology as compute topology.** (Codex.) `cmux workspace.spread --profile review-loop` with left=agents, center=active coding, right=validation. Displays become part of automation profiles, not just geometry.

---

## 4. Flywheel Opportunities (Self-Reinforcing Loops)

Existing flywheels (Claude names two): agent self-reporting via skill, embedded browser compounding over Chrome MCP. The registry refactor creates at least four new loops.

1. **Pane addressability → automation → richer metadata → more addressability.** (Claude Flywheel 3.) Stable, socket-addressable pane IDs let agents write automation ("signal me when pane:agent-3 finishes"); automation exposes missing metadata (ports, status, agent identity); operators file gaps; metadata gets richer; more automation. **Accelerant:** publish a minimal "pane SDK" at Phase 3 — three primitives (subscribe to events, query metadata, send input). Twenty lines of Python to build an agent on it.

2. **Multi-viewer panes → shared workflows → longer-lived panes → more multi-viewer use.** (Claude Flywheel 4.) Once `pane.attach` exists, operators use second viewports for "look-at" purposes (watching a build while working elsewhere); pair operators coordinate via viewports on the same pane; panes live longer because closing a window no longer ends the work; longer-lived panes accumulate state and become more valuable. **Accelerant:** sidebar chip (`⧉ 2`) makes it socially visible that multi-viewer is normal.

3. **Metadata → placement → better metadata.** (Codex.) Agents report `role=builder, task=CMUX-25, status=running`; c11mux spreads builders left, validators right; sidebar shows grouped live work; users/agents rely on those groups, so they report better metadata; better metadata enables better layout, routing, automation. Core agent-native flywheel.

4. **Context-Layout Flywheel.** (Gemini.) The system learns operator spatial preferences through observed placement and auto-applies them to similar future tasks. Each manual drag trains the next auto-spread. "Increasingly predictive and magical" without cloud intelligence — pure product memory.

5. **Session restore → trust → more ambitious layouts.** (Codex.) If panes survive window churn with stable identity, users build bigger spatial workspaces; bigger workspaces make `workspace.spread`, profiles, and frame roles more valuable; more use produces more real topologies to encode into profiles.

6. **Placement logs → regression tests → safer refactors.** (Codex.) Placement events give observable behavior for multi-window flows; testable drag/drop, move, spread, close-window migration, hotplug; safer tests make the registry more reliable; reliability unlocks durable panes as a hard promise.

7. **Saved profiles → repeated workflows → product memory.** (Codex.) `cmux profile.save review-loop` / `cmux profile.apply review-loop --task CMUX-25`. Every successful multi-display setup becomes a reusable profile; setup for next task gets faster; product memory without a cloud backend.

8. **Agent rooms → more agent work → stronger cmux primitives.** (Codex.) The more c11mux hosts clear/coordinator/worker/validator panes with stable identities, the more agents use c11mux-specific primitives; the more agents use those primitives, the more valuable the process-scoped socket and metadata plane become.

9. **Charter-level narrative flywheel (brand).** (Claude.) Every external mention of c11mux ("the terminal multiplexer with process-scoped panes") reinforces that c11mux is architecturally different, not cosmetically different. Attracts operators frustrated by the alternatives; they build automation; the automation becomes a reason others adopt. Requires the naming commitment — "Pane-first c11mux" in CHANGELOG, charter, skill, docs site.

---

## 5. Strategic Questions for the Plan Author

Deduplicated across all three reviews, numbered, grouped loosely by topic.

### Identity, Storage, and the Phase 2 Data Model

1. Is the plan's author comfortable reframing CMUX-25 from "multi-window support" to "pane-first c11mux, of which multi-window is the first demo"? The implementation plan doesn't have to change — the CHANGELOG, charter, and `cmux` skill entries do. (Claude Q1.)

2. Is `WorkspaceFrame` identity permanently `{workspace_id, window_id}`, or can it have a `FrameID` with those as fields? (Codex Q2.)

3. Can one `PaneID` legally appear in more than one `WorkspaceFrame` leaf in the future? If v1 says no, should the Phase 2 data model still allow it? (Codex Q1; Gemini Q2 — "Does `WorkspaceFrame` support being rendered in multiple `NSWindows` simultaneously?".)

4. Are you willing to add the viewer-set / `PaneAttachment` seam at Phase 2? One field, two methods, no behavior change — pays back starting Phase 3. (Claude Q3; Codex #2.)

5. Which state is pane runtime state, and which state is viewport state? Specifically: scroll position, search overlay state, zoom, focused surface, title-bar collapsed state, browser focus. (Codex Q4.)

6. For browser and markdown surfaces, is "pane runtime" the right abstraction, or should `SurfaceRuntime` be the deeper unit and `Pane` mostly group surfaces/tabs? (Codex Q11.) Related: is the "pane ≠ surface" distinction load-bearing for the evolutionary story, or an implementation detail? (Claude Q11.)

7. Are you open to publishing a stable `pane:` ref scheme (and siblings — `frame:`, `placement:`, `display:`, `workspace:`) as a public contract at Phase 2? (Claude Q6.)

### Lifecycle: What Happens When Viewers Disappear

8. Scrollback ownership: Pane-level or viewer-level? Plan is silent; recommended answer is Pane-level. (Claude Q2.)

9. What is the intended default when a window hosting the only frame for a live pane is closed? Options: (a) pane destroyed (v1 today); (b) migrate to another frame of the same workspace; (c) hibernate in the registry, findable via sidebar. Plan implies (b) in a sub-clause — this is product-defining, not an implementation detail. (Claude Q7; Codex Q3.)

10. If a pane is detached from all `WorkspaceFrames`, does it enter a "headless PTY" state, or is it killed? How do agents interact with a headless pane? (Gemini Q1.)

11. How do you want to handle the "pane with zero viewers" state in the UI? A sidebar section "⎇ N detached panes" with one-click re-attach is the obvious answer; shipping it lands differently in Phase 3 vs post-v1. (Claude Q5.)

12. Should there be a user-visible "parked panes" affordance in v1, or can it remain hidden recovery/debug until CMUX-26? (Codex Q13.)

13. Should Phase 2 persist placement *history*, or only current placement? History would help hotplug, restore, and profile suggestions later. (Codex Q10.)

### Socket API, Selectors, and Agent Addressing

14. Should cross-window `pane.move` default to preserving macOS focus unless `focus: true` is passed? Repo's socket focus policy suggests yes. (Codex Q5.)

15. Do agents get a blessed metadata vocabulary for `role`, `task`, `status`, `owner`, `group`, and `capabilities`, or is that intentionally left loose? (Codex Q6.)

16. Should `workspace.spread` distribute by pane creation order, current bonsplit order, last-focus order, or selector order when metadata is unavailable? (Codex Q7.)

17. How much of this should be surfaced through v2 socket APIs immediately vs held as internal model seams until after CMUX-25 lands? (Codex Q14.)

18. Is there appetite for a `pane SDK` doc at Phase 3? ~200-line reference with subscription, query, input examples. Would accelerate Flywheel 1 dramatically. (Claude Q9.)

### Sync, Mirroring, and Present Mode

19. Should `SidebarMode.primary` / `.viewport` be modeled as sidebar behavior only, or as frame synchronization roles that can later include layout/focus/input sync? (Codex Q8.) Related: could the Phase 4 sync seam be used to implement a full Present Mode where one window's viewport navigation is fully slaved to another? (Gemini Q4.)

20. Should `pane.attach` ship at Phase 3 instead of v1.1? ~150 additional lines alongside `pane.move`. (Claude Q4.)

21. What is the smallest acceptable present mode for v1.1? A read-only mirror of the focused frame on a target display may be enough to validate the whole frame-sync direction. (Codex Q12.)

### Feature Flag, Persistence, and Cross-Workspace

22. Is `CMUX_MULTI_FRAME_V1` a user-visible feature flag, a migration guard, or both? What state is allowed to persist while the flag is off? (Codex Q9.)

23. Would allowing panes to belong to multiple workspaces break any assumptions in the Session Persistence schema bump? (Gemini Q5.)

### CMUX-26 Alignment and v2 North Star

24. Do you want to co-design the CMUX-26 hotplug default with the v2 registry's "multi-viewer" implications? Today it reads as "move the window back." With multi-viewer, a richer default is "the pane stays where its highest-activity viewer is; the disappearing display loses only its viewport; on reconnect, the viewport is offered back." (Claude Q8.)

25. How will `cmux identify` report the display of an agent running in a headless, hibernated, or mirrored pane? (Gemini Q3.)

26. What's the deepest feature you'd be willing to bet on for v2? Between (a) GUI session-attach, (b) recording/replay, (c) present mode, (d) virtual workspaces, (e) agent capability directory — one should be picked as the v2 North Star and every v1 seam shaped to make it cheap. Picking late is fine; knowing *which* one is being optimized for is worth more than neutrality across all five. (Claude Q10.)

### Naming and Charter

27. Who owns the charter update at `docs/c11mux-charter.md`? If CMUX-25 is the inflection point from "window manager" to "capability fabric," the charter update is as important as the code. Schedule it as part of Phase 2, not an afterthought. (Claude Q12.)

28. What would prove that CMUX-25 is not merely parity with other multiplexers' multi-window features, but a new c11mux-native capability? Codex's answer: selector-addressable panes plus frame mirroring/present mode. (Codex Q15.)

---

## Closer

The consensus is stronger and more specific than a typical three-way review. All three reviewers — without coordination — arrived at the same architectural realization (runtime identity vs viewport placement), the same set of Phase 2 seams (frame identity, placement/attachment ledger, scrollback/lifecycle semantics), the same v1.1 differentiators (multi-viewer, broadcast, present mode), and the same v2 moonshot (GUI session-attach). The plan does not need to grow. It needs a Phase 2 design spike, a naming commitment, and a public `pane:` ref contract. With those three moves, every mutation above becomes a harvest instead of a rewrite.
