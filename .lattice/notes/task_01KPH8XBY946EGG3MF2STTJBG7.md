# CMUX-6 — Tier 1 cleanup: remove rollback scaffolding

Pure deletion chore. Do not pick up until Tier 1 Phases 1–3 (and ideally 4) have been stable in production for at least one release. If any issue surfaced that required a rollback flag, keep the scaffolding until root cause is fixed.

## What to delete

All live today; grep-confirmed 2026-04-18.

### `CMUX_DISABLE_STABLE_PANEL_IDS` (Phase 1)

- `Sources/SessionPersistence.swift:28-32` — docstring + `stablePanelIdsEnabled` predicate.
- `Sources/Workspace.swift:228-234` — docstring referencing the flag plus the `oldToNewPanelIds` identity-map remap kept as a safety net. With this flag gone the remap collapses to identity and can be deleted too — the entire `oldToNewPanelIds` local and every pass-through parameter thread.

### `CMUX_DISABLE_STABLE_WORKSPACE_IDS` (Phase 1.5)

- `Sources/SessionPersistence.swift:44-50` — docstring + predicate.
- `Sources/TabManager.swift:5093` and surrounding branch.

### `CMUX_DISABLE_METADATA_PERSIST` (Phase 2)

- `Sources/PersistedMetadata.swift:80-86` — the `isDisabledByEnv` predicate.
- `Sources/Workspace.swift:6248` — docstring.
- `Sources/AppDelegate.swift:3798` — matching branch.
- Every call site that reads the predicate.

### `CMUX_DISABLE_STATUS_ENTRY_PERSIST` (Phase 3 / CMUX-3)

Only if Phase 3 (CMUX-3) added it. Grep for the symbol before deleting — if the flag was never introduced, skip this bullet.

### Documentation sweep

- `docs/socket-api-reference.md` — remove the rollback env var section.
- `docs/c11mux-tier1-persistence-plan.md` — mark the Phase 1–3 rollback sections as "removed in vX.Y.Z" (don't delete the plan doc itself; it's a useful retrospective).
- Any operator-facing docs that mention the flags.

## How to verify

1. `rg -n 'CMUX_DISABLE_STABLE_PANEL_IDS|CMUX_DISABLE_STABLE_WORKSPACE_IDS|CMUX_DISABLE_METADATA_PERSIST|CMUX_DISABLE_STATUS_ENTRY_PERSIST'` returns zero hits across the repo (Sources + docs + tests + scripts).
2. `rg -n 'oldToNewPanelIds'` returns zero hits after the identity-map is collapsed.
3. Existing Tier 1 persistence test suites (`cmuxTests/SessionPersistence*`, `tests_v2/test_*persistence*.py`, `tests_v2/test_status_entry_persistence.py`) remain green on CI.

## Risk

Low — pure deletion of dead branches. Biggest failure mode is missing a reference that still reads the flag; the grep gate above catches that. No new behavior, no new tests, no schema changes.

## Size estimate

~300 LoC deleted (feels bigger than it is because the identity-map threading touches several signatures). Single PR.

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Pinned exact file:line anchors for each rollback flag plus a grep gate for "done." Chore-level fidelity.
