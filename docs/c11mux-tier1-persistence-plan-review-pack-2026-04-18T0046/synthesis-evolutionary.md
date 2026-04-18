# Evolutionary Synthesis — c11mux Tier 1 Persistence Plan

- **Plan:** `docs/c11mux-tier1-persistence-plan.md`
- **Reviews synthesized:** Claude (Opus 4.7), Codex, Gemini
- **Lens:** Evolutionary / Exploratory
- **Date:** 2026-04-18

---

## Executive Summary

All three reviewers independently converge on the same reframing: **this plan is not a restart-persistence cleanup — it is the quiet introduction of a durable state substrate for AI-agent workspaces.** The surface-level deliverables (panel UUIDs, metadata dictionaries, resume chip) are prerequisites for a much larger position:

- **Claude** calls it the "coordinate system between what's happening in a pane now and what the rest of the machine remembers about that work," and urges reframing Phase 4 from "Claude session index" to "External session adapters."
- **Codex** calls it a "surface continuity substrate" combining stable identity + durable semantic state + actionable recovery, and pushes for typed/structured persistence over string-only snapshots.
- **Gemini** calls it an "out-of-process state management and resurrection engine" that transforms c11mux from terminal multiplexer into a "workspace hypervisor for AI agents."

The unanimous message: the plan is solid, but it undersells the position it is actually reaching for. The evolutionary leverage lies in naming the primitive explicitly, making Phase 4 generic from day one, and treating the snapshot as a legible, shareable artifact rather than a private recovery blob.

---

## 1. Consensus Directions (Agreed Across Multiple Models)

1. **Phase 4 should be a generic external-session adapter, not a Claude-specific module.** Claude and Gemini argue this explicitly; Codex implies it via "cross-tool parity through shared session-association contracts." The `ClaudeSessionIndex` naming understates the position — Codex/Aider/Gemini/Jupyter/etc. adapters are inevitable, and the abstraction cost now is small.

2. **Stable panel identity is the load-bearing primitive.** All three reviewers flag that panel UUIDs becoming durable, externally-facing keys is what unlocks every downstream feature (metadata durability, resume chips, cross-session linkage, remote workspace parity). This should be named as the hinge, not an implementation detail.

3. **The plan enables a flywheel of "state gravity."** Claude and Gemini both articulate this explicitly; Codex frames it as "better persisted context → better resume suggestions → more metadata writes → richer associations." Once agents can trust c11mux to preserve state, they will push more into the metadata store, which makes c11mux more indispensable.

4. **Metadata persistence should preserve full fidelity, not collapse to strings.** Codex flags `[String: String]?` explicitly; Claude touches the same concern via schema versioning; Gemini implies it via "shareable workspace configurations." The live store is `[String: Any]` with typed values (e.g. `progress` as number) — string-only snapshots silently narrow future capability.

5. **Stale/freshness semantics deserve upgrade.** Claude wants `lastSeenLiveAt` (age-based freshness gradient) replacing the single `staleFromRestart` bit. Codex wants stale semantics exposed through a structured status read path as part of the API contract. Gemini wants the stale treatment extended visually to scrollback itself. All three see "stale" as under-specified.

6. **Snapshot as legible/shareable artifact.** Claude proposes `cmux session export --pretty --json` for human diffing. Gemini proposes `cmux workspace export` for cross-machine/cross-operator sharing. Codex proposes a "Portable Workspace Capsule" bundle. Same idea, three framings: the snapshot file should be designed to be *read* by humans and other tools, not just by c11mux's restore path.

7. **Recovery should be richer than a single chip.** Claude suggests a kebab menu with alternatives ("Resume…", "Start fresh", "Open transcript", "Copy session id"). Codex proposes a "Recovery Graph" with ranked candidates and a `ResumeCandidate` model. Gemini proposes "Phantom Panes" (lazy-loaded skeletons that resurrect on click). All three see Phase 5's single-action chip as a starting point, not the endpoint.

8. **Stale statuses should persist, not age out.** Gemini argues explicitly for indefinite retention ("operator reopening a project after a two-week vacation"). Codex wants a "clear stale statuses" bulk action rather than auto-aging. Claude frames this as "time-aware metadata rendering" where decay is visual, not deletion-based.

---

## 2. Best Concrete Suggestions (Most Actionable Ideas)

Ranked by leverage (value ÷ cost). Pick aggressively from the top.

1. **Ship the adapter protocol + registry in Phase 4's first PR, with Claude as the only initial adapter.** ~100 extra lines of Swift; no refactor debt when Codex/Gemini/Aider adapters land. (Claude, concurred by Gemini.)

2. **Add `resume_command` as a canonical M2 key.** Let agents self-report how to be resurrected; the heuristic disk scan becomes a fallback. Bypasses hardcoding `claude --resume` logic into the UI layer. (Gemini — highest-leverage single suggestion in its review.)

3. **Write Claude's first-user-message preview as a `source: heuristic` `description`.** One extra line in the Phase 4 focus handler. Every restored Claude surface immediately gets a meaningful sidebar subtitle. (Claude — probably the single most valuable "free" enhancement.)

4. **Replace `[String: String]?` with a `JSONValue`-style codable envelope; make `metadata_sources` a structured `{source, ts}` record.** Preserves typed values end-to-end; future-proofs the schema. (Codex.)

5. **Extend `SessionStatusEntrySnapshot` to full parity with `SidebarStatusEntry`** (`url`, `priority`, `format`, freshness markers) so restore is lossless. (Codex.)

6. **Ship the snapshot size metric in Phase 2**, not as a followup. One log line in `AppDelegate.autoSaveSessionIfNeeded`. Closes open-question #2 before it becomes an incident. (Claude.)

7. **Flip the title-bar collapse decision** — persist `titleBarCollapsed` / `titleBarUserCollapsed` as optional Bools. Pre-empts the day-one user request. Codex suggests keeping it ephemeral but emitting a metric; either way the decision deserves data. (Claude / Codex — split, but both want action.)

8. **Replace `staleFromRestart: Bool` with a workspace-level `lastSeenLiveAt` timestamp** and render freshness as a gradient of age. Covers "restart" and "idle" with one mechanism. (Claude.)

9. **Add revision counters** (`metadataRevision`, `statusRevision`, `logRevision`, `progressRevision`) and hash them in the autosave fingerprint — value-sensitive autosave triggering. (Codex.)

10. **Capture `boot_id` from `sysctl kern.boottime`** alongside the snapshot; keep `agentPIDs` and `kill -0` them on restore when boot_id matches. Softens "definitely dead" into "possibly alive, verify." (Claude.)

11. **Introduce an explicit `ResumeCandidate` model** (`tool`, `command`, `confidence`, `reason`) shared by UI chip and CLI. Supports ranking and alternates instead of a brittle single action. (Codex.)

12. **Ship `cmux surface inspect <id>`** alongside Phase 5's `cmux surface recreate`. Gives operators and agents a way to read the primitive directly. Accelerates flywheel by making the blob legible. (Claude.)

13. **Emit a "restart journal"** summary to the notification feed after any restore ("Restored 12 surfaces across 4 workspaces; 8 resumable; 3 with stale statuses"). Trivial; massive UX confidence payoff. (Claude.)

14. **Make Phase 3's stale pills clickable** — clicking a stale status pill should invoke the same Recovery UI as the title-bar chip. Compounds Phase 3 with Phase 5. (Gemini.)

15. **Prefer `sessions-index.json` when present**, jsonl fallback. More efficient scanning for the Claude adapter. (Codex.)

16. **Shadow-mode Phase 4 before UI exposure** — write inferred associations as low-confidence metadata + telemetry counters; validate ranking quality in CI fixtures before building the chip. (Codex.)

17. **Document the canonical-key amendment path** (short recipe in the M2 spec or new `docs/c11mux-canonical-keys.md`). Removes friction from future adapter authors; directly feeds the flywheel. (Claude.)

18. **Define a durable precedence table for inferred vs. explicit session IDs**, mirroring M2's source precedence style. (Codex.)

---

## 3. Wildest Mutations (Most Creative / Ambitious)

Ideas that exceed the plan's current scope but fall out naturally if the substrate is designed well.

1. **The "Fork" primitive (Gemini).** If c11mux can recreate a surface from metadata, it can duplicate it. Watching Claude go down a bad path → hit "Fork" → new pane with same cwd/model/session spawns. Speculative agent branching becomes a first-class workspace gesture.

2. **Phantom panes / zero-cost scale (Gemini).** A resumable surface doesn't need a live PTY — render it as a tombstone/skeleton in the split tree. Click to resurrect. Operators can park 50 agent tasks at zero CPU/memory cost. The "inactive at rest" model inverts the current "always-running" assumption.

3. **Session snapshots as commits / append-only checkpoints (Claude).** Ring of N snapshots under `~/.config/c11mux/snapshots/`. `cmux session checkpoints` lists; `cmux session restore <checkpoint>` picks. Collapses "I rebooted and lost everything" and "I accidentally closed the wrong workspace" into one problem.

4. **Time-travel debugging of agent state (Gemini).** Snapshot metadata + PTY scrollback together → save states of the agent's brain. Roll back a surface to "what it looked like 3 snapshots ago." Debugging across restarts becomes reproducible.

5. **Workspace recipes / portable capsules (Claude + Codex + Gemini).** Combine Tier 1 surface metadata + workspace metadata + stable ids + snapshots → derive a declarative manifest of "this workspace was N panels in these directories running these agents." Share, template, restore across machines (`cmux workspace new --from-recipe code-review.yaml`). Three reviewers converge on this despite it not being in the plan.

6. **Deep linking into agent contexts (Gemini).** `cmux://` URLs that, when invoked, construct metadata + layout for a task, open c11mux, build the panes, and boot the agents. Lattice tickets or external tools compose them; operators one-click into reproducible workspaces.

7. **Lattice integration as ticket attachments (Claude).** Once surface ids are stable and metadata is durable, Lattice tickets can carry "attached surfaces" by uuid. "Close this ticket and reopen it tomorrow" stops losing working context.

8. **Lazy-loaded "Press Enter to Resume" panes (Gemini).** On restore, don't spawn dead `zsh` prompts for surfaces with known resume paths — render a custom Ghostty surface saying "Claude was running here. [Press Enter to Resume]." Makes the resurrection gesture feel native.

9. **Event-sourced continuity log (Codex).** Append lightweight continuity events (metadata changed, status refreshed, session associated) alongside snapshots. Enables "what changed since crash?" tooling and, with #3, turns Tier 1 into an auditable history layer.

10. **Fleet / cross-machine view (Claude).** Combined with the remote workspace effort, multiple cmux installations become subscribable data sources. An external tool tails `cmux sidebar list --json` and renders a global view of "what agents are running across my machines."

11. **Stale visual treatment extended to scrollback (Gemini).** Opacity/italics not just on sidebar pills but on the restored terminal buffer itself — making pre-restart content visually distinct from live interaction. Reinforces "this is historical" at the primary interaction surface.

---

## 4. Flywheel Opportunities (Self-Reinforcing Loops)

Three loops were identified; they compose.

1. **Claude's "Metadata Gravity" flywheel.**
   - Stable surface ids + persistent metadata → more features are safe to build against `panelId`.
   - More features writing to `SurfaceMetadataStore` → the metadata blob becomes richer.
   - Richer blob → external tools (Lattice, remote daemon, dashboards) get more from reading it.
   - External tools consuming the blob → more pressure to keep it accurate and durable.
   - More investment in monitoring, versioning, adapter parity.
   - → More features safe to build. Loop.
   - **Accelerants:** documented canonical-key registry, `cmux surface inspect` CLI, Unix-socket `SUBSCRIBE` for external observers.
   - **Stallers:** gating key additions on committee review; making persistence opt-in per key.

2. **Gemini's "State Gravity" flywheel.**
   - c11mux proves it reliably holds/restores agent state.
   - Agent developers push more context into c11mux's metadata store instead of proprietary local databases.
   - Operators depend on c11mux's UI (title bars, sidebars, recovery flows) more.
   - Agents that don't support c11mux's metadata protocol feel second-class.
   - → Network effects + moat; new agents arrive with native metadata support.

3. **Codex's "Continuity Confidence" flywheel.**
   - Better persisted context → better resume suggestions.
   - Better resume success → users rely on metadata more.
   - More metadata writes → richer associations + higher confidence scores.
   - Higher confidence → less manual recovery, faster workflows.
   - Faster workflows → more surfaces/workspaces managed in c11mux.
   - → Each restart actively improves future restart quality.

**Composed:** the three loops reinforce each other. Gravity (1) attracts metadata; Gravity (2) attracts agents; Confidence (3) ensures the attraction compounds into better UX rather than noise. The plan lays the groundwork; explicit investment in the accelerants (documented key-addition path, inspect CLI, observable external surface, confidence scoring) makes the flywheels spin meaningfully faster.

---

## 5. Strategic Questions for the Plan Author

Deduplicated and numbered across all three reviews. Questions that would most unlock evolutionary potential.

### Framing & Scope

1. Is this plan really about "persistence" or about "external identity"? If the latter, Phase 4 is the centerpiece and Phases 1–3 are prerequisites — does that reframing change your investment allocation per phase?

2. Will a Codex (or Gemini, Aider, Jupyter) adapter land within 3 months? If yes, the adapter protocol/registry pays for itself immediately; if no, stay concrete.

3. Is the long-term durable identity the **panel UUID**, the **bonsplit tab ID**, or an eventual separate **`surface_identity`**? Naming this now shapes every future schema decision.

### Data Model & Fidelity

4. Should Tier 1 persistence guarantee full-fidelity roundtrip for arbitrary M2 JSON values, or is lossy string-narrowing acceptable? (The live store is `[String: Any]`; the snapshot currently proposes `[String: String]?`.)

5. Is the 32 MiB ceiling a hard constraint or a soft one? What triggers pruning — bug report, or built-in hook? Does Phase 2 want a pruning hook from the start?

6. Should c11mux ever write to agent-native session stores (bi-directional), or stay strictly read-only as the plan currently commits? Is "observe from outside" permanent policy or v1 convenience?

### Recovery Semantics & Precedence

7. If an agent proactively writes a `resume_command` to its metadata (via the M2 socket) before a restart, should that take absolute precedence over the `ClaudeSessionIndex` heuristic scan? (Gemini argues yes — this is the case for a durable precedence table.)

8. Should an inferred `claude_session_id` ever overwrite an explicit agent write, or must explicit always win even when older?

9. What's the minimum confidence threshold for showing one-click resume in the UI? Should the chip route through a generated command preview first, or execute directly?

10. What is the policy if `claude --resume` fails on chip click? Does the chip disappear, fall back through the chain, or surface an error? This is the most user-visible failure mode.

### Freshness & Stale Semantics

11. Is "stale" the right semantic for Phase 3's render, or is "historical" (definitely pre-restart, past-tense framing) a better signal? They're different signals; the visual language can follow either.

12. Should stale status be a UI-only hint or part of the API contract consumed by external tooling?

13. How should staleness behave when only some fields of a status entry are refreshed post-restart — per-key freshness, or per-entry?

14. Should stale statuses age out automatically, or persist indefinitely until cleared by the user/agent? (Gemini argues indefinite retention; Claude suggests visual decay; Codex suggests a bulk-clear action.)

### Schema, Interop & Cross-Machine

15. Does the Stage 11 remote workspace effort (`LatticeRemoteWorkspace`) need this data shape? If so, the snapshot schema is effectively a wire protocol — that raises the bar for versioning and optional-field handling.

16. Do you want to support cross-machine recreation in Tier 1.x (same snapshot, different host), or explicitly defer?

17. What is the intended relationship between `SurfaceMetadataStore` durability and Lattice ticket metadata? Where does a surface↔ticket association live — c11mux's metadata, Lattice's ticket data, or both?

18. How does `cmux surface recreate` handle complex shell environments (e.g., `nix develop`, `direnv`, custom env vars)? Does it capture them, or just cwd?

### Snapshots & History

19. Do you want append-only snapshot checkpoints (ring of N), or is overwrite-in-place fine? Marginal cost is small; marginal value (time-travel recovery, "restore from before I broke everything") is large.

20. What's the invalidation model for the Claude session index cache? Pure 30s TTL, or filesystem watcher on `~/.claude/projects/`, or invalidate-on-focus?

### UX & Surface

21. Would you entertain auto-populating surface descriptions from Claude transcripts' first user message (as `source: heuristic`)? Strictly additive; probably the single highest-value free enhancement.

22. Should the Phase 5 resume affordance eventually gain a kebab-menu alternative ("Resume…", "Start fresh", "Open transcript", "Copy session id"), and if so, does that shape the M7 title-bar layout work now?

23. Should the "stale" visual treatment be applied not just to sidebar pills but to the restored terminal scrollback itself, making pre-restart content visually distinct from live interaction?

### Observability & Trust

24. What telemetry/observability will you capture to decide whether this persistence model is actually improving recovery outcomes? (Codex — this is how you validate the flywheel empirically.)

25. Should Tier 1 include a structured recovery-preview endpoint (`surface.recovery.preview`) so tests can validate ranking logic without UI interaction?

### Companion Plan Alignment

26. How does this plan interact with `c11mux-workspace-metadata-persistence-plan.md`? Shared CLI verbs (`cmux set-metadata --workspace` vs `--surface`)? Cross-reading of keys? Coordinated schema evolution?

---

## Closing Synthesis

The three reviews, read together, deliver a coherent message: **the plan's sequencing is correct, its scope is honest, but its framing is too modest for the primitive it is building.** The load-bearing change is stable surface identity; the quietly strategic change is durable observable metadata; the flywheel ignition point is external-session adapters generalized from day one.

If the plan author takes only three actions from this synthesis, the highest-leverage set is:

1. Rename Phase 4 to "External session adapters" and ship the protocol + registry with Claude as the first adapter.
2. Add `resume_command` to the M2 canonical-key spec so agents can self-describe their resurrection contract, making the heuristic scan a fallback rather than the primary mechanism.
3. Use Claude's first-user-message as an auto-populated `source: heuristic` description, so every restored surface immediately carries semantic context.

Those three changes cost roughly one additional PR, keep the plan's shipping discipline intact, and dramatically enlarge the position c11mux occupies once Tier 1 lands.
