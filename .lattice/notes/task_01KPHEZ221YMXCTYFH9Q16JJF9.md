# CMUX-14 — Lineage primitive on the surface manifest

Plan note for whoever picks this up. Task-level fidelity — detailed spec already in the ticket body.

## The intent in one line

Promote lineage from a skill-level `::`-in-title convention to a first-class canonical `lineage` key on the surface manifest, so tooling can query and reason over the ancestor chain instead of parsing strings.

## Source of truth

The ticket body itself (via `lattice show CMUX-14 --full`) is the implementation spec. It's complete: schema, CLI, server semantics, skill updates, out-of-scope items, acceptance criteria. Read it before implementing — this note is only a pick-up pointer with execution anchors pulled in.

## Key shape (locked)

```jsonc
{
  "lineage": {
    "version": 1,
    "ancestors": [
      { "surface_ref": "surface:5",  "title_snapshot": "Login Button",     "role_snapshot": "feature-agent",      "spawned_at": "…" },
      { "surface_ref": "surface:12", "title_snapshot": "Multi-Agent Review","role_snapshot": "review-orchestrator","spawned_at": "…" }
    ]
  }
}
```

Ordering is root-first: `ancestors[0]` = furthest ancestor, `ancestors[-1]` = immediate parent. Matches the `A :: B :: C` reading.

## Where the work lives

- Canonical keys registry: `Sources/WorkspaceMetadataKeys.swift`. Add `lineage` alongside existing keys with `reserved_key_invalid_type` validation on the shape above.
- `SurfaceMetadataStore` at `Sources/SurfaceMetadataStore.swift` — already carries typed JSON + source tiers (`explicit > declare > osc > heuristic`). Lineage writes via `source: .explicit`; no new source tier.
- `cmux set-parent` is the new sugar — composes the chain server-side. CLI skeleton follows `cmux set-metadata` patterns; socket method `surface.set_parent` is a thin wrapper that reads parent's lineage, appends the parent itself, and writes the result to the child.
- `cmux get-lineage` reads the stored chain and live-resolves titles by default; `--snapshot`, `--format chain`, `--json`, `--surface <ref>` are the variants.
- Skill updates: `skills/cmux/SKILL.md` and `skills/cmux/references/orchestration.md` currently teach the `::` string convention. Extend to prefer `cmux set-parent` over manual title composition; sub-agents orient via `cmux get-lineage --format chain` rather than parsing the title string. Keep the `::` display convention.

## Server semantics for `set-parent`

1. Load `parent.metadata.lineage.ancestors` (or `[]`).
2. Compose new entry for the parent itself: `{surface_ref: <parent>, title_snapshot: parent.title, role_snapshot: parent.role, spawned_at: now}`.
3. Append to the parent's ancestors → the child's new chain.
4. Validate: depth ≤ 16, no cycle (child not in chain).
5. Write `child.metadata.lineage = {version: 1, ancestors: <chain>}` with `source: .explicit`.
6. Emit normal `metadata.changed` signal — no new plumbing.

## Validation rules (ship all of these)

- `ancestors` array length 0–16; length 17+ rejected with `reserved_key_invalid_type`.
- Per entry: `surface_ref` required string; `title_snapshot` required string ≤ 256 chars (matches existing `title` cap); `role_snapshot` optional string ≤ 64 chars; `spawned_at` optional RFC 3339 string (server fills `now` if absent).
- No cycles: child's surface ref must not appear in its own ancestors.
- Total `lineage` blob ≤ 4 KiB (well under 64 KiB per-surface manifest cap).
- Violations → `reserved_key_invalid_type`.

## Resolution

`get-lineage` default: overlay live `title`/`role` from each resolvable `surface_ref` onto its snapshot. Entries whose `surface_ref` no longer resolves surface the snapshot as-is with `stale: true` in JSON output.

## Out of scope (future tickets)

Explicitly deferred — do not bundle into this ticket:

- Title-bar breadcrumb widget (chip row from `lineage`).
- Auto-derivation of `title` from `lineage` when title is unset.
- `cmux tree` lineage annotations.
- Parent-rename push propagation (live-resolve covers the common case).
- Cross-window lineage test pass (works transparently but needs explicit coverage).

## Acceptance criteria (ticket body — not invention)

1. Canonical `lineage` key validated + stored + retrievable via `cmux get-metadata --key lineage`.
2. `cmux set-parent <ref>` composes server-side, writes to child, rejects cycles and over-depth.
3. `cmux get-lineage` variants: default resolved JSON; `--snapshot`; `--format chain`; `--surface`.
4. Socket method `surface.set_parent` available.
5. Skill files teach `set-parent` / `get-lineage` as canonical; `::` retained as display-layer default.
6. Test coverage for: round-trip, depth-16 accepted / depth-17 rejected, cycle rejection, live-vs-snapshot fallback, malformed-entry validation.
7. All skill references and examples updated.

## Relationship to CMUX-11

CMUX-11 (nameable panes) intentionally keeps pane lineage at the **prose layer** — a single text field agents compose. CMUX-14 gives **surfaces** structural lineage. The two coexist: panes stay textual; surfaces get queryable structure. Don't unify them.

## Size estimate

~250 LoC canonical-key validation + `set-parent` server + `get-lineage` CLI; ~150 LoC tests; ~80 LoC skill markdown updates. Single PR feasible.

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Ticket body already adequate; this note pulls the spec into a pick-up brief with file anchors, validation rules, and explicit coexistence with CMUX-11 so future implementors don't relitigate.
