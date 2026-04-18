# Evolutionary Review — c11mux Tier 1 Persistence Plan

- **Plan:** c11mux-tier1-persistence-plan
- **Reviewer:** Claude (Opus 4.7) — Evolutionary lens
- **Date:** 2026-04-18
- **Source:** `docs/c11mux-tier1-persistence-plan.md`

---

## Executive Summary

On the surface this plan reads as cleanup: stabilize panel UUIDs, persist two in-memory dictionaries, wire a resume chip, ship. That framing undersells it. What this plan actually does — and what the authors should lean into — is **promote the `panelId`/`surfaceId` from a transient runtime handle to a stable, observable identity that c11mux (and anything else) can hang structured state off of**. That's the hinge.

Once panel UUIDs are stable and `SurfaceMetadataStore` is durable, every future feature that wants to remember something about "this terminal across time" gets essentially free. The Claude session index in Phase 4 is the first application of that primitive; it is not the last, and the plan would be stronger if it treated it as the first of a family instead of a one-off.

The biggest evolutionary opportunity: **reframe Phase 4 as the first "external-session adapter" and turn the canonical-key set into a registry other adapters can extend**. That's what unlocks codex, gemini, aider, jupyter kernels, `devenv`/`nix develop`, docker-compose projects, ssh/mosh targets — anything that writes session artifacts to disk. c11mux becomes the macOS meta-resumer, not just a Claude-resumer. That's a much bigger position than the plan currently claims, and it's reachable with the same effort if you choose the right abstractions in Phase 4.

A secondary, under-valued opportunity: the stale-status machinery in Phase 3 is a prototype for a much more general concept — **time-of-liveness per metadata key**. If every metadata key carried a "last-fresh" timestamp (which the sidecar already half-does via `ts`), the sidebar could render freshness decay across the board (status is 3s old vs. 3h old vs. pre-restart), and recovery becomes a continuum rather than a binary. Worth at least naming now even if deferred.

The plan's sequencing is mostly correct but under-compounds. Each phase's output could be a much stronger input to the next with small additions. Suggestions below.

---

## What's Really Being Built

The plan says: "make metadata and status survive restart, add resume chip."

Underneath that, three primitives are being quietly introduced:

1. **Stable surface identity.** Panel UUIDs become first-class external-facing keys, not just in-process handles. This is the load-bearing change — every other claim in the plan (metadata durability, recovery UI, Claude associations) rests on it.
2. **A durable, observable metadata plane.** Today `SurfaceMetadataStore` is ambient runtime state. After Phase 2 it becomes the canonical place where "what this surface is / was doing" is recorded, with `metadata_sources` attribution already in place per M2. That's a significant latent capability for agents and ops dashboards.
3. **An observe-from-outside session graph.** Phase 4 establishes the pattern that c11mux watches external agent disk artifacts without requiring the agent to cooperate. This is stated in the memory (`feedback_c11mux_no_agent_hooks.md`) as a design principle; Phase 4 is the first place it becomes concrete infrastructure. It deserves a real home in the architecture, not a single file called `ClaudeSessionIndex.swift`.

If you squint, this plan is building **the coordinate system between "what's happening right now in a pane" and "what the rest of my machine remembers about that work."** That's a durable position — the value grows with every additional agent, toolchain, and side-channel artifact that gets linked in.

The plan names some of this implicitly (the architecture diagram in lines 66–78 is basically this). It should name it explicitly — this is the thing to optimize for, and the current Phase 4 scope is too narrow for the position it's pointing at.

---

## How It Could Be Better

### 1. Rename "Phase 4: Claude session index" → "Phase 4: External session adapters"

The plan acknowledges this at line 312–321 ("Cross-agent generalization"), then punts to "the module is named concretely to avoid premature abstraction." That's defensible, but the protocol cost is small and the payoff is large.

Proposal:

```swift
protocol ExternalSessionAdapter {
    static var kind: String { get }                                 // "claude", "codex", "aider", ...
    static func sessions(forCwd: String, limit: Int) -> [ExternalSession]
    static func mostRecent(forCwd: String, within: TimeInterval) -> ExternalSession?
    static func resumeCommand(for session: ExternalSession) -> String
}

struct ExternalSession {
    let adapterKind: String          // "claude"
    let id: String                   // adapter-native id (UUID for Claude, path for Codex, etc.)
    let cwd: String
    let startedAt: Date
    let lastModified: Date
    let preview: String?
    let extraMetadataKeys: [String: String]  // adapter-specific extras
}

// Registry
enum ExternalSessionAdapterRegistry {
    static var adapters: [ExternalSessionAdapter.Type] = [ClaudeAdapter.self]
    static func mostRecent(forCwd: String) -> ExternalSession?  // tries adapters in order
}
```

Ship `ClaudeAdapter` as the only implementation in Phase 4. The abstraction exists (so adding codex is a 100-line PR), but there's no second implementation yet. This is cheap insurance with measurable near-term value — the c11mux skill already encourages "clear codex / clear gemini" workflows, so Codex adapter will come.

The canonical keys also generalize: instead of `claude_session_id`, use `external_session_id` + `external_session_kind`, or nest under a namespaced key (`session.kind`, `session.id`, `session.started_at`). The latter plays nicer with the existing M2 canonical-key table because it groups adapter-native fields under one umbrella.

### 2. Replace "stale from restart" with "freshness / liveness" as a general property

Phase 3 introduces `staleFromRestart: Bool`. It's a single bit glued to one origin event. But the sidecar already has `ts` per key, and what operators actually want to know is "how old is this status?" — not "was it set before the last restart?"

A small upgrade:

- Drop `staleFromRestart`.
- Render freshness by age: fresh (<30s) = full color, cooling (30s–5min) = normal, stale (5min–24h) = dimmed, ancient (>24h) = heavily dimmed + italic.
- "Pre-restart" becomes a visual consequence of age, not a separate flag.
- Add a `lastSeenLiveAt` workspace-level timestamp in the snapshot. Everything older than that is, by construction, pre-restart; no per-entry bit needed.

This is a smaller surface, handles "I stepped away for 4 hours" the same way it handles "app restarted," and opens up later UX like "show only actively-updating workspaces" as a pure filter on age. Workspaces that haven't ticked in days fade visually on their own.

### 3. Persist collapse state instead of skipping it

The plan decides title-bar collapse state stays ephemeral (decision 4, line 54). Two users will ask for this on day one, because they set a description once and want the card to stay in the state they left it in. Cost is minimal — two Bool fields on the snapshot, default to the existing default on missing. Skipping it is a mild foot-gun that will cause a followup PR. I'd flip the decision.

### 4. Stop discarding `agentPIDs` entirely — add a "verified alive" column instead

The plan drops `agentPIDs` on restart because "a PID from a prior boot is meaningless." True, but not entirely — if you persist the PID *and* a `boot_id` (from `sysctl kern.boottime`), you can detect on restore whether the kernel has rebooted. If boot_id matches, the PID might still be alive and worth a `kill -0` check. That turns "definitely dead" into "possibly alive, verify" for the common case where cmux was quit and relaunched without a reboot.

Small addition. Real leverage — it's the one thing that moves this plan fractionally toward Tier 2 PTY survival without actually moving PTY ownership into cmuxd.

### 5. Treat `SessionPanelSnapshot` as the canonical restore contract and migrate toward a versioned record type

Right now the plan decides "schema stays at v1, new fields are optional" (decision 5). Fine for the current PRs. But once `metadata` and `metadata_sources` are in the snapshot, the snapshot is carrying structured, versioned data that other tools (Lattice, remote daemon) might want to read. It's worth writing down an explicit "version these together" rule now rather than later: `currentVersion` in `SessionSnapshotSchema` should bump when the *semantics* change (not just when fields appear), and there should be a documented migration policy for when that happens.

This is a DECISIONS.md entry, not a code change — but the plan is a good moment to make it.

### 6. Make the 32 MiB ceiling testable, not aspirational

Decision 2 accepts a 32 MiB worst-case snapshot ceiling. Open question 2 says "add a metric so we can see real-world sizes." That metric should ship with Phase 2, not as a followup. It's a one-line addition to the snapshot save path (`log size in bytes + per-surface metadata byte counts when > N`). Once it's there, you have the data to decide if you need pruning before you have a bug report.

---

## Mutations and Wild Ideas

### A. Snapshot-as-artifact: let humans see, diff, and share them

If the snapshot contains structured, persistent metadata, the file becomes *legible*. Ship a `cmux session export --pretty --json` that renders it in a stable shape (sorted keys, resolved surface ids, no transient fields). Now:

- A user can share "what was I doing last Tuesday" as a text blob with a teammate.
- Two machines' snapshots can be diffed to see what differs.
- An agent can `cmux session export` to have a structured view of the whole workspace graph — far richer than `cmux tree` alone.

Not in this plan. But if you know you'll want it, ensure the snapshot stays human-legible and diff-friendly (sort keys, stable ordering of panels).

### B. Session snapshots as *commits*

Instead of one snapshot overwritten every 8s, write them append-only into a ring of N (say 50) snapshots under `~/.config/c11mux/snapshots/`. Cheap (~32 MiB × 50 = 1.6 GiB worst case; in practice far less; truncate old ones). Now "restore from before I broke everything" is a real capability. A `cmux session checkpoints` CLI lists them; `cmux session restore <checkpoint>` picks one.

Cost: storage layer rewrite. Payoff: catastrophically good UX for "I rebooted and lost everything" *and* "I accidentally closed the wrong workspace." The two problems collapse into one.

### C. Claude adapter's preview text is a title-bar description source

Phase 4 pulls `firstUserMessagePreview` out of the jsonl. That's a perfect candidate for *auto-populating* the surface title or description if the operator hasn't set one. A surface running a Claude session could default its sidebar row subtitle to "→ Fix the oldToNewPanelIds remap" based on the user's first message. This is "free" — you already have the data, the sidebar already renders metadata descriptions (per companion plan). Write the session's first message to `metadata["description"]` with `source: heuristic`. Agent-authored or user-authored writes take over via the M2 precedence ladder.

This turns Phase 4 from "a resume button exists" into "every recent Claude session surfaces its purpose at a glance." Much higher user value for the same work.

### D. Pipe external session metadata through M3's sidebar chips

M3 already has `model` and `terminal_type` chips. Phase 4 could feed those from the Claude transcript's model field (which is written in the jsonl metadata). Consequence: a restored terminal surface re-acquires its model chip without any agent ever running. The chips are accurate even in a "nothing running" state, which is the scenario users *most* need them in.

### E. "Restart journal" — surface what survived and what didn't

When c11mux restarts, write a structured report to a new workspace (or notification feed): "Restored 12 surfaces across 4 workspaces; 8 had Claude sessions available to resume; 3 had stale statuses; 2 had known last-commands." This is cheap (it's just reading the snapshot summary) and hugely reassuring — it turns "did it really restore?" into a visible receipt.

### F. Workspace-level "recipe" snapshots

Combine this plan with the companion workspace-metadata plan: after both land, you have surface metadata + workspace metadata + stable ids + session snapshots. That's enough to *derive* a workspace recipe — a declarative manifest of "this workspace was N panels in these directories running these agents." Persist and share that recipe; you've just built a primitive for workspace templates (`cmux workspace new --from-recipe code-review.yaml`). Nobody planned this, but it falls out naturally if you sequence the two plans right.

### G. Lattice integration: treat c11mux surfaces as ticket attachments

Lattice is the project-tracking system in the Stage 11 stack. Once c11mux has stable surface ids *and* persistent metadata, a Lattice ticket could carry "attached surfaces" by uuid, which c11mux can resolve and re-focus / re-open. Now "close this ticket and reopen it tomorrow" doesn't lose the working context. This is an integration that *needs* the Tier 1 persistence to even be coherent. Worth naming as a downstream target.

---

## What It Unlocks

Once this plan ships:

1. **Durable agent identity.** M1 / M3 / M7 stop being "works while running, forgotten on restart." The M-series features become real.
2. **External-session association as a library primitive.** Any future adapter (Codex, Aider, Gemini, Jupyter, pytest sessions) is a small amount of code on top of the Phase 4 skeleton.
3. **Workspace recipes (with companion plan).** A workspace's complete state is expressable as a document. Share, template, restore across machines.
4. **Remote workspace parity.** `LatticeRemoteWorkspace` has a direction to head in — if a remote cmuxd can surface its metadata dictionaries, the local app can render another machine's state identically. Tier 1 persistence makes the data shape authoritative enough that cross-machine rendering is feasible.
5. **Time-aware metadata rendering.** Once `ts` is durable per key, every render path can honor "how fresh is this?" — opens filters, decays, sorting.
6. **Agent-agnostic "what's running" dashboards.** The combination of terminal_type + running-state markers + external-session links is a pretty complete summary of "what agents this machine is running." External tools can subscribe to `cmux sidebar list --json` and build a global view. This generalizes to a fleet view of multiple cmux installations.
7. **Debugging across restarts.** Pre-restart logs persisting gives you the ability to reproduce a bug state across app relaunches. Today that's a dead-end.
8. **Recovery as a design principle.** Once "restart is not catastrophic" is true for metadata, the social contract changes — operators trust the tool more, try bolder things, reboot without fear. That's a flywheel on user ambition.

---

## Sequencing and Compounding

The plan's order is correct: Phase 1 is a prerequisite for everything, 2 is a prerequisite for 4/5, 3 is independent but small.

Three small resequencing suggestions:

### (a) Land the snapshot size metric with Phase 2, not later

Open question 2 asks when to add a size metric. Answer: in the same PR as Phase 2. It's a one-line addition (log `snapshot.count` + per-panel metadata bytes if > 1 KiB). Deferring it means you'll add it after the first size-related incident, not before.

### (b) Move the adapter-registry skeleton into Phase 4's first PR

Don't ship `ClaudeSessionIndex` as a concrete-named module and then refactor later. Ship the protocol + registry + ClaudeAdapter in one PR. Extra cost: ~50 lines. Savings: a future refactor PR that touches every call site. The plan's current approach is classic "YAGNI, extract later" — which is usually right, but here the second adapter is clearly coming (Codex) and the abstraction is tiny.

### (c) Split Phase 5 into 5a (chip) and 5b (CLI)

`cmux surface recreate` is a CLI affordance; the title-bar chip is a UI affordance. Both are valuable but have different review audiences (UI reviewers vs. socket/CLI reviewers). Two PRs merge faster than one. Chip first (higher user-visible impact), CLI second.

### Compounding opportunities

- **Phase 3 stale-status → Phase 4 Claude association.** When a status is stale from restart, check `ExternalSessionAdapterRegistry.mostRecent` for that surface's cwd; if a recent session exists, upgrade the stale pill's tooltip to "Resume Claude session." The stale-status rendering becomes the anchor point for recovery, not just a dimmer color.
- **Phase 2 metadata → Phase 4 preview.** When a Claude session's preview is fetched, write it as `heuristic`-source `description`. The sidebar row's subtitle immediately improves across all restored surfaces.
- **Phase 4 index → Phase 3 statusEntries.** If a Claude session was active just before restart, seed a stale status pill from the jsonl's last message. Now "this was working on X" shows up in the sidebar *even without* an agent restart, because the external session's on-disk state tells us.

None of these are expensive. All of them make each phase's output compound into the next.

---

## The Flywheel

A loose flywheel already exists; small changes make it spin faster.

**The loop:**

1. Stable surface ids + persistent metadata → more features are safe to build against `panelId`.
2. More features writing to `SurfaceMetadataStore` → the metadata blob becomes richer.
3. Richer blob → external tools (Lattice, remote daemon, dashboards) get more out of reading it.
4. External tools consuming the blob → more pressure to keep the blob accurate and durable.
5. That pressure → more investment in things like size monitoring, schema versioning, adapter parity.
6. More investment → more features are safe to build against `panelId`. Loop.

**What accelerates it:**

- A documented canonical-key registry per M2 that adapter authors can amend. Make it easy to land a new key.
- A CLI command that dumps the blob for any surface (`cmux surface inspect`), so operators see the primitive directly and start asking for more.
- An external read-only surface for the blob, perhaps a Unix socket `SUBSCRIBE` or a file-based tail — let external tools observe without polling.

**What stalls it:**

- If `SurfaceMetadataStore` evolution gets gated on committee reviews, nobody adds keys, and the blob stays thin.
- If persistence is opt-in per key (it isn't in this plan — full snapshot is good), producers won't bother.

This plan sets the flywheel up. Explicit next step: ensure the path to adding a canonical key is documented and easy (it's sketched in the M2 spec but not in this plan).

---

## Concrete Suggestions

Highest-leverage, most actionable — pick the ones that resonate:

### 1. Swap "Phase 4: Claude session index" for "Phase 4: External session adapters (Claude first)"

Ship the protocol, registry, and one adapter. Document the 100-line recipe for adding the second. Already sketched in "How It Could Be Better" section 1.

### 2. Make the first adapter write Claude's first-user-message as a `source: heuristic` `description`

One extra line in the Phase 4 focus handler. Immediately improves sidebar subtitle quality for every restored Claude surface. Free UX win.

### 3. Replace `staleFromRestart` with `lastSeenLiveAt` workspace-scoped timestamp

One field on the workspace snapshot. No per-entry flag. Render freshness as a gradient of ts age. Covers "restart" and "idle" with one mechanism.

### 4. Ship the snapshot size metric in Phase 2

One log line in `AppDelegate.autoSaveSessionIfNeeded`. Closes open question 2 before it becomes a bug report.

### 5. Flip the title-bar collapse decision

Persist `titleBarCollapsed` and `titleBarUserCollapsed`. Two optional Bools on the panel snapshot. Users will ask for this; pre-empt the followup PR.

### 6. Add `boot_id` capture to the snapshot; keep `agentPIDs` across same-boot restarts

Use `sysctl kern.boottime`. When `boot_id` matches on restore, attempt `kill -0` on each PID and keep verified-alive ones. Drops the rest. Slightly softens the "definitely dead" assumption without moving to Tier 2 PTY survival.

### 7. Ship `cmux surface inspect <surface-id>` alongside Phase 5's `cmux surface recreate`

Give operators and agents a way to *read* the primitive directly. Cheap, pairs with the recreate command, accelerates the flywheel by making the blob legible.

### 8. Document the canonical-key amendment path

Add a short section to the M2 spec (or a new `docs/c11mux-canonical-keys.md`) describing exactly how to propose + graduate a new key. Right now the spec says "by explicit module spec that amends this table" but not *how*. One-page recipe removes friction from future adapter authors.

### 9. Add a "restart journal" surface

After a restart that restored anything, emit a summary to the notification feed ("Restored 12 surfaces, 8 resumable"). Trivial to implement (the restore code knows these counts already), huge UX confidence payoff.

### 10. Reserve the workspace-level `metadata.lastSeenLiveAt` canonical key now

Even if not consumed yet, reserve the key in the companion workspace-metadata plan so Phase 3's freshness rendering has a clear home later.

---

## Questions for the Plan Author

Numbered, aimed at decisions that would unlock the most evolutionary potential:

1. **Is this plan really about "persistence" or about "external identity?"** If it's the latter, Phase 4 is the centerpiece and Phases 1–3 are prerequisites. That reframing might change what you invest in per phase — e.g., more effort on the adapter protocol, less on title-bar collapse state. Which is it?

2. **Will a Codex adapter land within 3 months?** If yes, build the adapter registry now (concrete recommendation above). If no, stay with the concrete Claude implementation and extract later. Your honest read here.

3. **Does the Stage 11 remote workspace effort (`LatticeRemoteWorkspace`) need this data shape?** If remote cmuxd will surface its metadata to a local viewer, the snapshot schema is effectively a wire protocol. That changes the bar for schema versioning, optional-field handling, and the case for explicit version bumps on semantic changes.

4. **Should c11mux eventually write to agent-native session stores (bi-directional), or stay strictly read-only?** The plan commits to read-only (line 294). This is a load-bearing choice — it's the "observe from outside" principle. But there are cases where c11mux could, say, rename a Claude session for organizational purposes. Worth naming whether that door stays closed forever or is parked for v2.

5. **What's the intended relationship between `SurfaceMetadataStore` durability (this plan) and Lattice ticket metadata?** If a surface is associated with a Lattice ticket, where does the association live — in c11mux's `metadata["lattice_ticket"]`, in Lattice's ticket data, or both? The answer informs how canonical-key growth is coordinated across the two systems.

6. **Do you want snapshot append-only checkpoints, or is overwrite-in-place fine?** Related to wild-idea B. The marginal cost of checkpoint history is small; the marginal value (time-travel recovery) is large. Is there a reason to stay with in-place overwrite beyond "simpler"?

7. **What's the invalidation model for the Claude session index cache?** The plan says 30s cache per cwd. But if the user just sent a message, they probably want the index to reflect it within a second or two. Worth considering an invalidate-on-focus signal instead of a pure TTL, or a filesystem watcher on `~/.claude/projects/` (cheap, modern macOS).

8. **Is "stale" the right semantic for the Phase 3 render?** "Stale" implies "might be wrong." An alternative framing: "historical" (definitely pre-restart, rendered as a past-tense statement rather than a muted-present-tense statement). The visual language can follow either — but they're different signals. Which do you want to send?

9. **What's the policy if `claude --resume` fails on the chip click?** Open question 5 gestures at this but doesn't commit. Does the chip disappear after one failed resume? Does it fall back to the other chain steps automatically? What does the operator see? This is the most user-visible failure mode of the plan.

10. **Should the Phase 5 chip eventually gain a kebab-menu alternative** (e.g., "Resume…", "Start fresh", "Open transcript in browser", "Copy session id")? Shipping the single-action chip now is right; deciding now whether the *affordance* is single-action forever or grows into a multi-action slot affects the M7 title-bar layout work.

11. **Would you entertain surfacing the Claude transcript's first user message as the default description** (wild-idea C)? It's a small change with large UX impact and is strictly additive on top of the plan as written. This is probably the single most valuable "free" enhancement available.

12. **Is the 32 MiB ceiling a hard constraint or a soft one?** Accepted in decision 2, but what triggers action if real-world usage approaches it? A user with 50 workspaces × 10 surfaces × rich descriptions could plausibly touch it. Is the plan OK with "we'll add pruning later" or does Phase 2 want a pruning hook built in from the start?

13. **How does this plan interact with the `c11mux-workspace-metadata-persistence-plan.md` companion?** The companion claims workspace-level durability, this one claims surface-level. Both ship `metadata: [String: String]?` on their respective snapshot types. Worth deciding: (a) should the CLI share verbs (`cmux set-metadata` with `--workspace` vs. `--surface`)? (b) is there a story for one reading the other's keys?

---

## Closing Thought

The plan as written is a solid cleanup + recovery pass. It will ship, it will be useful, and the Phase 5 chip will get demoed at meetings. But the real prize is infrastructure: once you have stable ids + durable observable metadata + external-session adapters, you have the ingredients for a *lot* more than a resume chip. The authors already sense this — the closing line "Ship small. Phases 1–3 first" is right discipline. But the framing of Phase 4 as "Claude session index" sells the position short. It's the first adapter in a family. Name it that way in the plan, build the tiny registry, and every future capability compounds into the same primitive.

If that reframing costs one extra PR and 100 lines of Swift, it's the best-leveraged decision in the document.
