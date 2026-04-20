# Evolutionary Review — CMUX-25 (Emacs-frames v1) / CMUX-26 (v2 hotplug)

**Plan:** `cmux-25-plan` (plan file: `.lattice/plans/task_01KPHHQZA4XZTQD4BQCGQYC7FR.md`)
**Reviewer model:** Claude (Opus 4.7)
**Review stance:** evolutionary / exploratory
**Date:** 2026-04-19

---

## Executive Summary

The plan is framed as "multi-window c11mux." It is not. Read carefully, **CMUX-25 is a refactor that turns c11mux's core data model inside out**: panes stop being window-local children and become process-scoped, first-class, long-lived objects addressable from anywhere. NSWindows become viewports (`WorkspaceFrame`s) onto that shared registry. The Emacs-frames analogy is literal, but understates the result.

Everyone else in this market (tmux, WezTerm, Zellij, iTerm2, JetBrains frames, Ghostty+tabs) starts from "a window is a container." c11mux is about to start from "a pane is a process-scoped capability, and windows are just one way to look at it." **That is the leap.** Once the `PaneRegistry` exists, windows are not the only viable viewer: sockets, agents, remote operators, mobile companion UIs, recording pipelines, and CI harnesses are all viewers too. Every feature in the sidebar (status / log / progress), every surface type (terminal / browser / markdown), and every agent-addressable command compounds with this shift.

The biggest evolutionary opportunity is **naming and defending that position now**, not after v1 ships. If the plan authors treat the registry as plumbing — "a refactor to support multi-window" — they will leave the highest-value features on the floor. If they treat the registry as **the product**, with multi-window as its first demo, every follow-up phase (CMUX-26 hotplug, v1.1 sidebar sync, the backlogged super-workspace) becomes a capability compounding on a platform, not a feature hanging off a window manager.

Concrete: I would **rename the concept to "Pane-first c11mux"** in the CHANGELOG and charter, keep the six implementation phases exactly as planned, and bolt three small evolutionary seams into Phases 2–4 that don't extend the scope but make the ten most interesting follow-ups trivial instead of expensive. Details below.

---

## What's Really Being Built

Strip the window-management framing and the actual deliverable is:

**A process-scoped, agent-addressable registry of durable PTY+surface capabilities, decoupled from the UI that renders them.**

Break that down against the primitives the plan locks (`Sources/AppDelegate.swift`, `Sources/TabManager.swift`, `Sources/Workspace.swift`, `vendor/bonsplit/`):

- **Pane** is no longer "a leaf in a split tree that dies when the window closes." It is a **standalone process-scoped object** with a PTY, Ghostty surface, MTL layer, metadata blob, title, status pills, logs, and a stable ID. It can exist with zero viewers and keep running. It can have many viewers simultaneously. (The plan says this in §"Code change sketch" but doesn't dwell on it.)
- **WorkspaceFrame** is a **viewport plus a layout tree** that points into that registry. Not a container. A *query* that renders.
- **Window** becomes a **chrome around one or more viewports**. The sidebar, command bar, and menu bar are all metadata views onto the process-scoped state, not owners.
- **Sidebar + status/log/progress + `cmux tree`** are already process-scoped (per the CMUX charter at `docs/c11mux-charter.md`). This refactor brings the *underlying panes* into the same process-scoped world the metadata already lives in. That alignment is what unlocks the evolutionary surface.

Name it what it is: **a capability fabric.** Terminals are one kind of capability. Browsers are another (already in-tree: `Sources/Panels/BrowserPanel.swift`). Markdown surfaces are a third. Nothing about the registry is terminal-specific — it's about long-lived, addressable, renderable compute units with streams and state.

The plan's ambition stops at "multi-window UI." The architecture reaches further. Decide now whether to name that gap or leave it implicit; the former compounds.

---

## How It Could Be Better

### 1. Promote the registry to a public contract in Phase 2, not an internal refactor

The plan treats `PaneRegistry` / `WorkspaceRegistry` / `WorkspaceFrame` as private Swift types. They should be public-facing *concepts* in the CLI and charter the moment Phase 2 ships. Concretely:

- Every pane in `cmux tree` and `cmux identify` gets a **stable registry-level ID** (`pane:UUID`) independent of which window is showing it. Already in the socket API additions (`pane_ref`, `window_ref`, `display_ref`). Ship this with the framing that **the pane ID is the canonical identity; window/display are projections**, not the other way around. Document this in the CMUX charter and the `cmux` skill at Phase 2.
- Add `cmux pane show <pane:ref>` as a read-only query that works whether or not the pane is currently rendered anywhere. Returns metadata, scrollback sample, status, last-activity timestamp. Low effort; huge conceptual weight — it reifies "panes exist even without windows."

**Why better:** once users and agents think of panes as first-class, every follow-up feature (multi-viewer, hibernation, broadcast, session-attach) has an obvious seat. If the registry stays a private refactor, each follow-up has to re-litigate its own abstraction.

### 2. Build the registry with a viewer-set, not a leaf-reference, from Phase 2

The plan says `WorkspaceFrame.paneLeafReferences: [PaneID]`. Flip the dependency: the `Pane` itself carries `viewers: Set<ViewerID>` where `ViewerID` is a typed union of `{frame(FrameID), socketStream(SubscriptionID), broadcast(BroadcastID), recording(RecordingID)}`. At v1 only `frame` is wired; the other cases are stubs.

**Cost:** one additional field on `Pane` and two methods (`attachViewer` / `detachViewer`). Trivial.

**Benefit:** every future "more than one viewer looking at this pane" feature — multi-frame viewports, live screen-share of a single pane, CI log streaming, agent observation — is additive, not a rework of pane ownership. The current plan's denormalised leaf list works for v1 but forces rewrites on the first N+1 viewer case.

### 3. Give the sidebar's process-scoped store a formal name, and use it everywhere

Phase 4 introduces "process-scoped (shared) store" versus "window-local" but doesn't name the shared store. Name it: **`AppRegistry`** (or `ProcessState`). Compose it from `WorkspaceRegistry`, `PaneRegistry`, `DisplayRegistry`, and the existing metadata stores (`SurfaceMetadataStore`, `PaneMetadataStore`, `TerminalNotificationStore`, `PortScanner`).

**Why better:** right now those stores live as disconnected singletons on `AppDelegate`. Naming the aggregate makes it obvious to Phase 4 authors and future feature authors what "the process-scoped brain" is and how to extend it. It also creates the natural home for #2's viewer-set — viewers live on the registry, not on the UI layer.

### 4. Serialise pane scrollback state at the registry level

A `Pane` today holds a Ghostty surface and an MTL layer that die with their view. Once panes are process-scoped, **scrollback lifecycle** needs an explicit answer. Two choices:

- **Tie scrollback to the Pane (registry-level).** When a pane's last viewer detaches, the scrollback stays in memory. When the pane is finally destroyed (or hibernated), scrollback persists with it.
- **Tie scrollback to the Ghostty surface (viewer-level).** Detaching the last viewer loses scrollback.

The plan is silent. The answer has to be the first — scrollback is part of the Pane's identity, not the viewport's — and Phase 2 should make that explicit. Otherwise CMUX-26 hibernation has an unanswered "do we lose scrollback?" question and operator trust in "panes survive viewer churn" is undermined by a first obvious bug (detach, re-attach, scrollback is gone).

### 5. Ship a minimal `pane.attach` socket command in Phase 3, not Phase 5+

Phase 3 scope is cross-window pane migration via `pane.move`. That's "move a pane from window A to window B (exclusive ownership transfer)." What's missing, and cheap to add, is `pane.attach { pane_ref, window_ref, position }` — **create a second viewport onto the same pane** without moving it. Today the data model doesn't allow it (one-to-one leaf-to-pane). Post-Phase-2 it's three lines of additional code if #2's viewer-set is in place.

**Why ship at Phase 3, not later:** it's the single most evolution-unlocking primitive the refactor enables. Every mutation idea below (screen-share, pane-as-presentation, multi-viewer, agent observation) depends on it. Shipping it at Phase 3 turns the rest of the multi-window story from "a better window manager" into "a fundamentally different thing." Without it, c11mux v1 is JetBrains-detached-editors with a sidebar.

### 6. Gate everything on the feature flag but plan the flag's retirement as a product event

The plan says "Flag retires after Phase 3 soaks on main for a release cycle." Good. But the retirement is not a refactor, it is **the release of a new product layer.** Treat it that way in the CHANGELOG, the docs site, and the `cmux` skill: flag retirement = Pane-first c11mux generally available = the first terminal multiplexer with process-scoped panes. Branded. Named. Memorable. If the retirement lands in a CHANGELOG entry that reads "internal refactor complete," the opportunity is wasted.

---

## Mutations and Wild Ideas

Once panes are process-scoped, addressable, and long-lived, the adjacent space opens up dramatically. In rough order from "obvious extension" to "pretty weird":

### A. Pane broadcasting (`pane.broadcast.input`)

Already discussed in prior-art (see `docs/c11mux-textbox-port-plan-review-pack-2026-04-18T1255/evolutionary-claude.md`). Trivial post-Phase-3: pick N panes, one composition surface, one Enter key, N writes. The existing textbox port fork already has an `.all` scope toggle. Shipping broadcast *on top of* the registry rather than *tacked into* TabManager keeps it clean.

Use case today: "apply this fix across all 5 agent panes." Agent fleet operator's #1 friction. Ship as v1.1.

### B. Multi-viewer panes — "two screens, one terminal"

Put the left monitor's big window on a workspace overview, put the right monitor's window zoomed into one specific pane — and have that pane be the *same* pane, scrollback synchronised, input goes to one place. Pair-programming-within-one-brain. Operator checks "is the build failing" on a secondary monitor while they work on something else on the primary.

**Mechanism:** `pane.attach` from #5 above. Viewer-set from #2. That's it.

**Differentiator:** no terminal multiplexer has this. tmux's "share a session" is two separate clients viewing the same server; here it's one process, two viewports, zero latency, zero state divergence.

### C. Pane hibernation with PTY retention (v2 sweetening)

CMUX-26 mentions an "optional hibernation store" for the undock-redock case. Pull this harder: once panes are process-scoped, **unviewed panes can keep running in the background with full PTY state** and reappear on demand. This is how you get:

- **"Background build panes."** Start `cargo watch` in a pane, detach it from all windows (not close — detach). It keeps running, status/log/progress streams into the sidebar. Re-attach when you want to see the output.
- **"Agent fleet without desktop mess."** 15 concurrent agents, 4 visible, 11 detached-but-running with live status pills. Promote any of them to a viewport when they need attention.

This is **tmux's original value proposition** (processes survive disconnection) but with a GUI and multi-viewer semantics on top. c11mux already has the sidebar signals to make detached panes observable (status / log / progress). The missing piece is the "pane exists with zero viewers" state, which Phase 2 gives you for free.

### D. GUI session-attach — "c11mux over the wire"

This is the big one. The registry is already addressable via a Unix socket. Extend the socket to a **streaming session-attach protocol**: a remote c11mux process (same user, another machine via SSH forwarding, or localhost) can subscribe to the registry, receive pane surface updates, and become an additional viewer.

**Near-term form:** the other c11mux instance shows "remote panes" as ghost entries in its sidebar. Clicking one opens a read-only viewer pane (scrollback + live tail). Next iteration: bidirectional input.

**Why this is possible specifically here:** every other terminal multiplexer either runs headless (tmux, screen, zellij — no GPU rendering to replicate) or doesn't serialise pane state (iTerm2, WezTerm, Ghostty+tabs). c11mux is the rare case of a GUI multiplexer with a process-scoped socket, metadata seam, and capability abstraction. The registry refactor lights up the protocol.

**Use case:** agent running on a remote VM has a c11mux instance; operator's local c11mux can present those panes inline alongside local panes. No SSH-into-tmux-into-whatever chain.

### E. Pane recording & replay

Once a pane is a durable object with a stable ID, recording its surface output is a viewer — not a feature. Attach a recorder viewer; it writes a deterministic stream (not a screen video — a *terminal emulation trace* plus metadata events). Replay later into any window. Use cases:

- **Agent telemetry.** "Replay what agent-4 did for the last 30 minutes" — useful for retro, for debugging prompt drift, for training data.
- **Demo mode.** Record a working session, replay it in a presentation pane with per-keystroke timing. Vastly better than a screen recording because text is searchable, scrollable, diffable.
- **Incident forensics.** A production hotfix went wrong — replay the pane into a sandbox.

This is a *native* capability once panes are registry objects. Today it's a "build a separate recording tool" project; tomorrow it's an additional `Viewer.kind = .recorder`.

### F. Pane-as-presentation ("present mode" on top of frames)

The plan's `workspace.spread` has a `all_on_each` mode (every pane on every display — "rare, useful for screen-share review"). That hint points somewhere bigger. **Present mode** is a viewport that's special-cased for an audience: large text, hidden chrome, zoomed scrollback, optional annotation overlay, speaker-notes surface on a second display.

Mechanism: a new `WorkspaceFrame` variant called `PresentationFrame`. Same bonsplit tree, different rendering settings, potentially synced to a "presenter viewer" on another display. One brain, two audiences (operator and room).

**Use case:** every engineer doing demos, screen-sharing, teaching, or pair-programming with their manager. "Show only pane X, zoomed, other panes hidden; when I Cmd+] the next pane comes in." This is Keynote-grade polish on top of a terminal.

### G. Sidebar sync as "follow me" / "director mode"

The plan calls out sync mode as a v1.1 UX but leaves the design open. The compelling form is not "all sidebars mirror" but **"follow me"**: one window is the primary director, and other windows become viewports that follow the director's selection. The director is broadcasting their working context.

Use case: operator demoing to a colleague — their laptop window is the director, the room's TV-connected window is the viewport. As the operator switches workspaces, the TV follows. When they pick a pane, the TV zooms into it. The operator's hands never touch the second display.

The data structures from Phase 4 are already in place (SidebarMode, broadcastSelection hook). What's needed is the naming/UX: "director" is a better mental model than "primary," which sounds like a failover. Rename before the feature ships.

### H. Agent-to-pane addressing as a first-class schema

Agents already talk to c11mux via the socket and can target panes today (see `cmux` skill). What's missing is a **schema-first contract**: agents register capabilities they expose on panes (e.g. "I can take a screenshot," "I can run a command," "I can pause this stream"), and the registry publishes a directory. Other agents and humans query the directory.

Mechanism: `AgentCapabilitySet` as a new field on `Pane` metadata. Agent registers its capabilities on pane-ready. `cmux pane capabilities <pane:ref>` returns the list. `cmux pane invoke <pane:ref> <capability> <args>` calls it.

This is mid-2026 agent-native infra: a c11mux pane becomes a **queryable, actionable surface** rather than an opaque terminal. Given how many agents run inside c11mux panes already, this compounds fast.

### I. Workspace-as-query, not workspace-as-container (a weird one, worth naming)

Super-workspace is backlogged. A weirder variant: workspaces don't have to be hand-assembled sets of panes; they can be *queries*. "Show me every pane whose status is red across every workspace." "Show me every agent pane that's been idle more than 10 minutes." "Show me every pane with port 3000 open."

The registry already has the metadata (PortScanner, status pills, notifications). A `VirtualWorkspace` is a persisted query. Renders in a `WorkspaceFrame` exactly like a real workspace. Updates live as panes change.

**Why weird:** breaks the "workspace is a bag of panes I made" mental model. But it's obviously correct in a world where operators manage 20–40 panes at once, and it's trivial on top of the registry. Ship as a power-user feature; it won't be the default.

### J. Panes as an OS-wide resource (the ambitious one)

Once a `pane:ref` is stable, process-scoped, and socket-addressable, the logical next step is: other apps on the machine can reference c11mux panes. A Raycast extension that shows "current active c11mux pane." A Stream Deck button that focuses `pane:agent-4`. A shell function outside c11mux that pipes into a specific c11mux pane.

**Mechanism:** publish pane refs as NSUserActivities or via a small Spotlight metadata provider. The refs are stable across sessions (via persistence).

**Differentiator:** c11mux becomes a *citizen of the macOS ecosystem* in a way no other terminal multiplexer has attempted. iTerm2 has AppleScript; nobody has "Spotlight search for a terminal pane by title."

---

## What It Unlocks

In one list, ordered by how soon each becomes feasible after CMUX-25 ships:

1. **Cross-workspace pane sharing** — the same `Pane` referenced by two different workspaces. The spike rejects super-workspace as a separate layer, but once panes are registry-owned, a pane can already be in N workspace frames. The constraint is just whether `Workspace.paneIDs` is a set or a partition. Make it a set, get this for free.
2. **Multi-viewer panes (B above)** — immediate, given #2 and #5 from the "How It Could Be Better" section.
3. **Pane broadcasting (A above)** — v1.1 scope, 40-100 lines of Swift, massive agent-operator value.
4. **Pane hibernation (C above)** — already on the CMUX-26 roadmap; upgrading it from "window survives display disconnect" to "pane survives viewer absence" is what makes hibernation actually interesting.
5. **Recording & replay (E above)** — post-v2, but the registry is ready.
6. **GUI session-attach (D above)** — ambitious, 2-4 weeks, differentiator-class. Start thinking about the protocol at Phase 2.
7. **Agent-capability directory (H above)** — schema work, small code, huge narrative weight for "c11mux is agent-native."
8. **Virtual workspaces (I above)** — post-v2 power user feature.
9. **Present mode (F above)** — a polished, demo-friendly feature that differentiates c11mux from every TUI competitor.
10. **OS-wide pane refs (J above)** — the moonshot. Only feasible because refs are stable.

**New leverage points created by the refactor** (not features — underlying capabilities that downstream work can exploit):

- **Stable, long-lived pane IDs** addressable across the socket, the sidebar, agents, and the CLI. Every automation built on top gets cheaper.
- **A viewer-set model** (if seam #2 lands) that generalises to "N renderers per capability." Streams, recordings, agents, remote clients — all become viewers.
- **A process-scoped metadata seam** where status, logs, progress, and notifications all hang off the pane, not the window. Already mostly there; the refactor completes it.
- **Frame as rendering contract** — `WorkspaceFrame` becomes the stable interface between "the registry" and "a rendering target." Future rendering targets (presentation mode, remote viewer, recording) implement this contract.

---

## Sequencing and Compounding

The plan's six-phase order is correct. What I'd add:

### Phase 1 (display registry) — no change, but one compounding nudge

Add `display_ref` to **every** returned object in every socket response that references a window, not just the ones the plan mentions. Free. Makes every future "route this thing to display X" feature one parameter away.

### Phase 2 (registry refactor) — the compounding phase; add three small seams

This is where every future mutation either becomes cheap or expensive. Add:

- **Viewer-set on Pane** (1 field, 2 methods) — unlocks multi-viewer, recording, remote.
- **Public `pane:` ref scheme in `cmux tree` and `cmux identify`** — unlocks agent-to-pane addressing, Spotlight/external integration.
- **Registry-level scrollback ownership** — answers a question hibernation would otherwise hit head-first.

None of these extend the scope meaningfully. All three pay back starting at Phase 3.

### Phase 3 (cross-window migration) — add `pane.attach` alongside `pane.move`

One command, same underlying plumbing. Turns c11mux from "better window manager" into "first multi-viewer terminal." Ship both together.

### Phase 4 (sidebar split) — wire sync-mode seam with intent, rename `primary` → `director`

The plan already reserves the enum values. Better naming now (director / viewport / independent) is free; it pre-shapes the UX when the feature ships.

### Phase 5 (workspace.spread) — no change

### Phase 6 (split-into-new-window opt-in) — no change

### After Phase 6: the flywheel starts

The flag retires. Ship the v1.1 wishlist as a *bundle*, not a trickle:

- **Pane broadcasting** (cheap post-Phase-3 + textbox port).
- **Sidebar director mode** (seams already in Phase 4).
- **`pane.attach`** (shipped at Phase 3, now documented).

Call the release something like **"Pane-first c11mux 1.0"** to signal the architectural shift. Everything after this compounds on the public primitive.

### Deferred to CMUX-26 (v2) with upgrades

- **Pane hibernation with scrollback retention** — the interesting v2 scope, upgraded from "window hibernation."
- **Display-affinity auto-restore** — as planned, but expressed as "viewer re-attach" not "window move" given the new mental model.

---

## The Flywheel

The existing flywheels in c11mux are:

1. **Agent self-reporting via skill** (each agent that reads the `cmux` skill reports metadata via socket; the sidebar gets richer; operator trust rises; more agents adopted).
2. **Embedded browser compounding over Chrome MCP** (each operator who uses it produces fewer stale browser windows; the skill enshrines it; Chrome MCP use declines; c11mux becomes the preferred web-validation environment).

The registry refactor creates **two new flywheels**:

### Flywheel 3 — Pane addressability → automation → richer metadata → more addressability

As pane IDs become stable and socket-addressable:

- Agents start writing automation against specific panes (e.g. "signal me when pane:agent-3 finishes," "route this log tail to pane:observer").
- Automation exposes *what metadata is missing* (ports, status, agent identity, elapsed time). Operators file gaps.
- Metadata gets richer, making automation more capable.
- More operators build automation. Back to step 1.

**Accelerant:** publish a minimal "pane SDK" at Phase 3 that's just three things — subscribe to pane events, query metadata, send input. Keep it stupid-simple. An agent built on it is two dozen lines of Python. The ecosystem appears.

### Flywheel 4 — Multi-viewer panes → shared workflows → reasons to keep c11mux running → multi-viewer panes

Once `pane.attach` exists:

- Operators start using second viewports for "look-at" purposes (watching a build pane while working elsewhere).
- Pair operators (human + agent, or two humans) use viewports on the same pane to coordinate.
- The habit of "this pane keeps running even when I'm not looking" takes hold.
- Panes live longer, accumulating state, making them more valuable, making operators less willing to close windows. Back to step 1.

**Accelerant:** make it *visible in the UI* when a pane has multiple viewers. A small chip ("⧉ 2 viewports"). Social signal that this is normal and fine.

### A third, slower flywheel — Charter-level narrative

Every external mention of c11mux ("the terminal multiplexer with process-scoped panes") reinforces that c11mux is architecturally different, not cosmetically different. The flywheel here is **brand-level**: differentiating on architecture attracts operators who were frustrated by the alternatives; they build automation; the automation becomes a reason others adopt. Moving from "yet another terminal with tabs" to "the Emacs of terminal multiplexers" is a brand position the registry refactor earns, but the naming has to follow. See Executive Summary.

---

## Concrete Suggestions

A rank-ordered list of small evolutions that build on the locked primitives without breaking them. **Every item is cheap post-Phase-2.** Each entry names the mechanism, estimated scope, and the mutation it unlocks.

1. **Ship `cmux pane show <pane:ref>` read-only command at Phase 2.** `Sources/TerminalController.swift`, one handler, ~100 lines. Returns metadata + scrollback sample. This is the smallest possible assertion that panes are first-class process objects. Enables #2 and #7 below with no new abstraction.
2. **Add `viewers: Set<ViewerID>` to `Pane` at Phase 2.** Field + attach/detach methods + serialisation stub. ~50 lines. Everything multi-viewer downstream becomes additive.
3. **Ship `pane.attach` at Phase 3 alongside `pane.move`.** Socket handler + UI wiring. ~150 lines. Turns the whole system from "multi-window" to "multi-viewer." Largest leverage-to-effort ratio in the entire roadmap.
4. **Sidebar chip for viewer count.** When a pane has >1 viewer, render "⧉ 2" on its sidebar entry. Click cycles between viewports. ~50 lines. Reinforces Flywheel 4.
5. **Broadcast composition surface** (v1.1). Textbox port is already in flight (see `docs/c11mux-textbox-port-plan.md`). Add a `.broadcast` scope that writes to all panes in a selection. ~200 lines on top of the port. Agent fleet operator's #1 friction.
6. **Rename `primary` → `director` in `SidebarMode` at Phase 4.** One enum rename. Better mental model before the feature ships.
7. **Agent capability directory** (v1.1). `AgentCapabilitySet` on pane metadata + `cmux pane capabilities` + `cmux pane invoke` CLI commands. ~300 lines. Agent-native surface becomes real.
8. **Pane recorder viewer** (v2). `Viewer.kind = .recorder` writes a deterministic VT trace + metadata timeline. ~2 weeks. Unlocks replay, demo mode, incident forensics.
9. **Present mode** (v2+). `WorkspaceFrame.kind = .presentation` with big-text rendering + speaker-notes surface. ~3 weeks. Keynote-grade polish, terminal-native.
10. **Remote session-attach protocol** (v2+, major). Extend the Unix socket to a streaming subscription model. Another c11mux can subscribe. ~4-6 weeks. The real moonshot; turns the refactor into a platform.
11. **Virtual workspaces** (v2+). Query-based workspace projection. ~1-2 weeks post-registry. Power-user feature, but genuinely differentiated.
12. **Publish pane refs as NSUserActivity / Spotlight entries** (post-v1). ~1 week. Turns c11mux into a first-class macOS citizen.
13. **Scrollback ownership at the Pane level** (Phase 2 decision). Not a feature — an architectural answer. Must land at Phase 2 to avoid a future migration.
14. **CHANGELOG framing at flag retirement.** Ship the flag-off release as "Pane-first c11mux GA," not "internal refactor complete." Zero code; enormous narrative weight.

---

## Questions for the Plan Author

1. **Is the plan's author comfortable reframing CMUX-25 from "multi-window support" to "pane-first c11mux, of which multi-window is the first demo"?** The implementation plan doesn't have to change; the CHANGELOG, charter, and `cmux` skill entries do. This framing decision gates whether the evolutionary path above is visible to downstream authors or has to be reinvented.

2. **Scrollback ownership: Pane-level or viewer-level?** The plan is silent. My recommendation is Pane-level. Phase 2 should answer this explicitly before writing the migration; otherwise CMUX-26 hibernation will hit it as a surprise. What's the intuition here?

3. **Are you willing to add the viewer-set seam at Phase 2?** One field, two methods, no behavior change. Pays back starting Phase 3 (when `pane.attach` becomes trivial instead of a rework). Small upfront cost, but it is upfront.

4. **Should `pane.attach` ship at Phase 3 instead of v1.1?** The plan defers multi-viewer as a mutation. I think that's the single highest-leverage feature the refactor enables, and shipping it alongside `pane.move` at Phase 3 is ~150 additional lines of Swift. The cost of *not* shipping it at v1: competitors and internal contributors think of c11mux as "a better window manager" rather than "the first multi-viewer terminal."

5. **How do you want to handle the "pane with zero viewers" state in the UI?** The plan describes it ("detached panes") but doesn't specify how operators see them, manage them, or resurrect them. A sidebar section "⎇ N detached panes" with one-click re-attach is the obvious answer; shipping it lands differently in Phase 3 vs post-v1.

6. **Are you open to publishing a stable `pane:` ref scheme as a public contract at Phase 2?** The socket API section already includes `pane_ref` but doesn't commit to stability. If `pane:ref` is a public, persistent, documented identifier from Phase 2 forward, every agent SDK and third-party integration has a stable foundation. If it's treated as implementation-detail-that-leaks, future stabilisation is a breaking change.

7. **What is the intended default for "a pane's window closed — what happens?"** Options: (a) pane is destroyed (v1 behavior); (b) pane migrates to another window of the same workspace; (c) pane hibernates in the registry, findable via sidebar. The plan implies (b) in §1 ("remaining-only-on-that-window panes either migrate to another frame of the same workspace or hibernate") but this is a *product-defining* decision, not an implementation detail, and deserves more than a sub-clause. My vote: (c), with (b) as an option in settings. Operator trust that work survives window churn is the entire value proposition.

8. **Do you want to co-design the CMUX-26 hotplug default with the v2 registry's "multi-viewer" implications in mind?** CMUX-26 currently reads as "move the window back when the display reconnects." With multi-viewer panes, a more interesting default is "the pane stays where its highest-activity viewer is; the disappearing display loses only its viewport; on reconnect, the viewport is offered back." Very different UX, richer mental model, and only makes sense if the Phase 2 seams are in place.

9. **Is there appetite for a `pane SDK` doc at Phase 3?** A ~200-line reference doc in `docs/` with subscription + query + input examples. Would accelerate Flywheel 3 dramatically. Small doc, big leverage, but only valuable if the refs and events are committed public contracts.

10. **What's the deepest feature you'd be willing to bet on for v2?** Between (a) GUI session-attach, (b) recording/replay, (c) present mode, (d) virtual workspaces, (e) agent capability directory — one of these should be picked as the v2 North Star and every v1 seam should be shaped to make it cheap. Picking late (after v1 ships) is fine, but knowing *which* one is being optimised for is worth more than neutrality across all five.

11. **Is the "pane ≠ surface" distinction load-bearing for the evolutionary story, or an implementation detail?** The primitive hierarchy says a pane can hold multiple surfaces (terminal + browser + markdown), with tabs as the rendering affordance. Most of my mutations above treat the pane as the addressable unit. If that's right, the surface distinction stays as-is. If someone wants surface-level addressability ("attach this recorder to only the terminal surface of this pane, not the browser one"), that's a different shape and should be decided early.

12. **Who owns the charter update?** The CMUX charter at `docs/c11mux-charter.md` is the canonical philosophical source for c11mux. If CMUX-25 is the inflection point from "window manager" to "capability fabric" — and I think it is — the charter update is as important as the code. Schedule it as part of Phase 2, not as an afterthought.

---

## One-sentence closer

The plan, as written, ships multi-window c11mux; with three tiny seams added at Phase 2 and a naming commitment, it ships **the first pane-first terminal multiplexer** — and every mutation above becomes a harvest instead of a rewrite.
