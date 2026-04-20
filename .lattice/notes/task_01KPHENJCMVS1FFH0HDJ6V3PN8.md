# CMUX-11 — Nameable panes: metadata layer & `::` lineage mechanism

Plan note for whoever picks this up. High-complexity, multi-PR work — four phases.

## The intent in one line

Give panes (not just surfaces) a first-class metadata layer whose first consumer is an operator/agent-assigned title carrying lineage (`Parent :: Child :: Grandchild`) across the task graph.

## Source of truth

Full implementation plan lives at `docs/c11mux-pane-naming-plan.md` (225 lines, 8 locked decisions, phased deliverables, tests, open questions). Read that before implementing — this note is only the pick-up brief.

## Load-bearing philosophical decision

**It's text. Trust the LLM.** A single free-form string field, not a structured breadcrumb type. `::` is a convention, not a system delimiter. No merge rules, no close-time snapshotting, no auto-copy. The intelligence lives at the LLM layer — c11mux stays unopinionated host.

## Locked decisions (from the plan doc — don't relitigate)

1. Pane title is free-form text; agents compose and mutate.
2. Create-time seeding via optional `--title` on `pane.create` / split commands. Agent composes "my title :: child role."
3. Rename is read-then-write by convention; `pane.set_metadata` response returns prior value so agents have it in hand.
4. Breadcrumb survives ancestor closure — string is frozen narrative.
5. Full `PaneMetadataStore` parity with `SurfaceMetadataStore` — JSON fidelity, source attribution, 64 KiB cap, monotonic revision counter.
6. Windows out of scope in v1.
7. `/clear` cue lives in the skill, not in a c11mux hook.
8. Skill `::` convention is the single source of truth — this plan cross-references it, doesn't re-document.

## Phases (each one PR)

### Phase 1 — `PaneMetadataStore` (in-memory)

Scaffolding. Ships a store nobody uses yet. Mirrors `Sources/SurfaceMetadataStore.swift` API exactly: `set(..., source:)`, `get`, `clear`, `values()`, source precedence `explicit > declare > osc > heuristic`, 64 KiB cap, monotonic revision counter. New file `Sources/PaneMetadataStore.swift`. Wire a store instance per-pane via the same lifecycle that creates/destroys panes in `Workspace`.

### Phase 2 — Socket RPCs + CLI

- `pane.set_metadata`, `pane.get_metadata`, `pane.clear_metadata` socket methods.
- `--pane <ref>` flag on the existing `cmux set-metadata` / `get-metadata` / `clear-metadata` family (mirroring the `--surface` flag plumbing).
- `--title` flag on `cmux new-pane` / `cmux new-split` for create-time seeding.
- **Prior-value-in-response substrate**: `pane.set_metadata` response includes the previous value for the key being set. This is the read-then-write convention's foundation — agents can now rename without an explicit read.
- Telemetry off-main per project socket-command-threading policy.

### Phase 3 — Persistence via `SessionPaneSnapshot` extension

- Extend `SessionPaneSnapshot` (in `Sources/SessionPersistence.swift`) with an optional `metadata: [String: PersistedMetadataValue]?` field. Rides Tier 1 Phase 2 rails — same `PersistedMetadataValue` shape, same `SourceRecord` sidecars.
- Additive-optional decoding; schema stays v1.
- Restore path populates `PaneMetadataStore` before the pane is wired up.
- Respects `CMUX_DISABLE_METADATA_PERSIST=1` for rollback.
- Tests: round-trip fidelity (numeric, string, nested), restore from snapshot, rollback-flag-off path.

### Phase 4 — Skill guidance

- Add a short "pane metadata" section to `skills/cmux/SKILL.md` — cross-references the `::` surface-title convention and adds pane-specific notes: create-time `--title` seeding is the default; read-before-write for renames; `/clear` should prompt the operator to rename the pane.
- Not a re-documentation of the `::` convention — one place to read it.

## Dependencies

- **Phase 3 prerequisite:** Tier 1 Phase 2 (CMUX-2) merged — provides the `PersistedMetadataValue`/`SourceRecord` machinery.
- **Downstream:** CMUX-12 (pane title bar chrome) depends on Phases 1 and 2 — that ticket is the visual consumer.
- **Adjacent:** CMUX-14 (lineage primitive on the surface manifest) formalizes lineage structurally; this ticket keeps pane lineage at the prose layer. The two coexist — panes stay text, surfaces get structure.

## What explicitly does NOT land here

- Pane title bar chrome (CMUX-12).
- Window metadata parity (deferred — windows don't split).
- Structural lineage type on panes (CMUX-14 is the structural analog for surfaces; panes intentionally stay textual).
- UI for renaming via right-click / palette (CMUX-12 territory).

## Visibility for operators pre-chrome

Even before CMUX-12 lands, pane titles are readable via `cmux tree`, `cmux list-panes`, and `pane.get_metadata` RPC. The chrome ticket makes them visible inside the app; this ticket makes them real.

## Size estimate

4 PRs, growing: Phase 1 ~300 LoC; Phase 2 ~400 LoC with CLI; Phase 3 ~250 LoC including restore wiring and tests; Phase 4 ~50 LoC (skill markdown).

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Confirmed plan doc is detailed and pointed this note at it. Extracted the locked decisions, phase-to-PR mapping, and dependencies into a pick-up brief.
