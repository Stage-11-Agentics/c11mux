# Adversarial Plan Review: c11mux-tier1-persistence-plan

### Executive Summary
This plan is directionally right on persistence goals, but it underestimates the difficulty of its prerequisite and overestimates the reliability of its recovery story. The single biggest issue is Phase 1: "stable panel UUIDs" is framed as deleting `oldToNewPanelIds`, but current constructors hard-generate IDs (`TerminalSurface`, `TerminalPanel`, `BrowserPanel`, `MarkdownPanel`) and do not accept restore-time IDs. This is not a cleanup; it is a cross-cutting identity refactor with high regression risk.

Second-order issue: the plan’s proposed snapshot shapes for metadata (`[String: String]`, `[String: String]` sources) do not match the live store (`[String: Any]` + `{source, ts}` sidecar). Without correcting that, Phase 2 either drops type information or breaks canonical keys like numeric `progress`.

Risk posture: high for Phase 1 and Phases 4–5, medium for Phases 2–3.

### How Plans Like This Fail
1. **Identity refactors disguised as simplifications.** “Remove remap” sounds small; actual implementation changes object-creation contracts across terminal/browser/markdown surfaces and all restore call paths.
2. **Schema optimism.** Plans assume additive optional fields are free, then discover live model types and wire formats diverged from the plan document.
3. **Private-internal dependency creep.** “Observe from outside” becomes “depend on another tool’s private on-disk format,” then breaks silently on upstream update.
4. **Autosave coupling feedback loops.** Hooking high-frequency metadata writes to autosave invalidation without real write-rate telemetry causes constant snapshot churn.
5. **Value asymmetry.** Plumbing phases are rigorously specified; user-visible recovery phases are heuristic-heavy and underspecified.

### Assumption Audit
1. **Assumption: Phase 1 is mostly deletion.**
Reality: restore creates new panels via constructors that generate new UUIDs. No restore-time ID injection exists today. This is load-bearing and likely larger than planned.

2. **Assumption: metadata can be stored as strings.**
Reality: `SurfaceMetadataStore` stores JSON-like `Any`, and canonical key `progress` is numeric. String-only snapshot fields are structurally incompatible.

3. **Assumption: `metadataSources` can be string→string.**
Reality: store sidecar tracks at least `{source, ts}` per key. Flattening loses timestamp semantics and weakens precedence/debug behavior.

4. **Assumption: status snapshot is already fidelity-complete.**
Reality: persisted `SessionStatusEntrySnapshot` omits URL, priority, and format currently present in runtime `SidebarStatusEntry`. Restoring from this shape degrades behavior silently.

5. **Assumption: autosave hooks only need metadata revision.**
Reality: current autosave fingerprint hashes many counts, not full values; status value changes at same cardinality can be missed. Adding metadata revision alone leaves adjacent blind spots.

6. **Assumption: scanning `~/.claude/projects` is stable enough.**
Reality: this is an undocumented external storage format; any upstream change can silently break association and resume UX.

7. **Assumption: resume injection is safe.**
Reality: `panel.send_text("claude --resume <id>\n")` is context-agnostic; non-shell foreground apps/REPLs can produce wrong or destructive behavior.

### Blind Spots
1. **Module 2 spec governance gap.** M2 spec explicitly states in-memory only. This plan changes that contract but does not include an explicit spec amendment/migration note.
2. **Phase 1 implementation scope gap.** No mention of adding injectable IDs to panel/surface constructors and related callsites.
3. **Status fidelity gap.** Plan restores status entries but ignores currently omitted fields (`url`, `priority`, `format`) in snapshot schema.
4. **Conflict with concurrent workspace-metadata plan.** Two independent persistence expansions (workspace and surface metadata) target same snapshot system and autosave cadence, without a joint throughput/race analysis.
5. **Telemetry gap.** No target metrics for snapshot size distribution, autosave frequency under metadata churn, or Claude index hit/miss correctness.
6. **Privacy/expectation gap.** Reading transcript files for previews introduces a data-sensitivity shift that is not acknowledged in rollout or settings.
7. **Failure UX gap.** Resume failure handling is hand-waved; no command timeout/retry/backoff spec, no deterministic fallback behavior.

### Challenged Decisions
1. **Decision to lock stable panel IDs first.**
Counterargument: this is the hardest, riskiest primitive in the plan and currently under-scoped. Alternative: ship persistence keyed by remap initially, then harden stable IDs as a dedicated refactor with its own burn-down.

2. **Decision to persist full metadata blob with no persistent whitelist split.**
Counterargument: open-ended payloads can bloat snapshots and persist low-value/high-churn data. Alternative: persist canonical keys + explicitly allowlisted custom keys first.

3. **Decision to keep schema version at v1 despite shape expansion.**
Counterargument: version neutrality now increases future ambiguity. Alternative: bump snapshot version and codify fallback decoding paths.

4. **Decision to use agent-specific canonical keys (`claude_session_id`, `codex_session_id`).**
Counterargument: vendor-specific key proliferation is likely. Alternative: neutral session envelope (`agent_kind`, `agent_session_id`, `resume_command`).

5. **Decision to infer and write session association on focus.**
Counterargument: focus is noisy; inferred writes can overwrite meaningful state unless precedence and recency rules are explicit and testable.

### Hindsight Preview
1. We will wish we split this into **Tier 1a (durability)** and **Tier 1b (recovery UX)** instead of coupling them.
2. We will wish Phase 1 had a standalone design doc for ID lifecycle across panel classes before any code touched restore logic.
3. We will wish we had metric gates before shipping: max snapshot size, autosave frequency under churn, index precision/recall.
4. We will wish we had defined a generic external-session adapter contract before hardcoding Claude-first semantics.
5. We will wish we had a safe execution gate before sending resume commands into terminal surfaces.

Early warning signs to add now:
- Autosave writes per minute while idle typing = 0 but metadata churn active.
- Snapshot file >10 MiB sustained for normal workflows.
- High rate of resume command failures per click.
- Frequent inferred-session overwrite of existing session keys.

### Reality Stress Test
Most likely three disruptions:
1. **High-frequency metadata writes** (status/progress churn from agents).
2. **External format drift** in Claude session storage layout.
3. **Concurrent title-bar/workspace metadata merges** causing rebases and subtle behavior divergence.

Combined effect:
- Autosave writes become near-continuous every tick, snapshot size climbs, and performance complaints appear.
- Resume chip quality degrades (wrong/missing associations) with no immediate signal.
- Team velocity drops due to repeated merge/behavior regressions in shared UI + persistence surfaces.

### The Uncomfortable Truths
1. The plan’s “80% built” framing is true for persistence plumbing, false for identity stability and trustworthy recovery UX.
2. Phase 1 is the most dangerous phase but has the lightest risk treatment.
3. Phase 4 converts c11mux from agent-host primitive into an implicit parser of third-party internal state.
4. The current plan is likely to ship durable metadata before it ships reliable recovery, creating a perception gap versus stated motivation.
5. Without stronger guardrails, this can become a maintenance burden disguised as a reliability feature.

### Hard Questions for the Plan Author
1. How exactly will restored panel IDs be injected, given current constructors always generate UUIDs?
2. Why does the plan’s proposed metadata snapshot type differ from the live metadata store type and canonical key typing?
3. Are you intentionally dropping status entry `url`, `priority`, and `format` on restore, or is that an unnoticed fidelity loss?
4. Why is schema version not bumped when snapshot semantics expand materially?
5. What are the concrete correctness metrics for Claude association (precision/false-positive rate)?
6. What is the explicit precedence rule when inferred session IDs conflict with declared/explicit writes?
7. What is the safe-execution policy before sending resume commands into a terminal (prompt detection, confirmation, or dry-run)?
8. What is the rollback switch if stable-ID restore causes regressions in focus/scrollback/layout flows?
9. How will this plan coordinate with workspace-metadata persistence so autosave/fingerprint behavior stays coherent?
10. What privacy stance do you want for indexing local transcript files, and is there a user-visible opt-out?
11. If Claude’s storage format changes, what fails fast and who gets alerted?
12. Why commit to agent-specific canonical keys now instead of a neutral resume contract?
13. What phase exit criteria prove Phases 4–5 are trustworthy enough to expose as a primary recovery affordance?
14. What is the plan if Tier 2 PTY persistence lands earlier and changes the value proposition of Phase 5?
15. Is the intended outcome to restore historical context only, or to drive active command execution? Those are different trust bars and should not share the same default action.
