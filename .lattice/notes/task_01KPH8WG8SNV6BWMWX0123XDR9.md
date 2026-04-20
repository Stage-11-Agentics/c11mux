# CMUX-3 — Tier 1 Phase 3: persist `statusEntries`

Plan note for whoever picks this up. Closes out Tier 1a durability.

## The intent in one line

Workspace sidebar status pills survive restart, flagged stale until the agent refreshes them — all fields round-trip.

## Source of truth

Phase 3 section of `docs/c11mux-tier1-persistence-plan.md` (lines 342–435). Read that before touching code; the note below is just the pick-up brief.

## Where the work lives

- Live model: `struct SidebarStatusEntry` at `Sources/Workspace.swift:62-89` (fields: `key, value, icon, color, url, priority, format, timestamp`).
- Workspace storage: `statusEntries: [String: SidebarStatusEntry]` at `Sources/Workspace.swift:4973`.
- Snapshot type: `SessionStatusEntrySnapshot` at `Sources/SessionPersistence.swift:238-244` (today carries only `key, value, icon, color, timestamp` — missing `url/priority/format`).
- Snapshot site: `statusEntries.values.sorted(…).map { … }` at `Sources/Workspace.swift:171-181`.
- Discard site: `statusEntries.removeAll()` at `Sources/Workspace.swift:263` (this is the line to replace with a stamping restore).
- Dedupe: `shouldReplaceStatusEntry` at `Sources/TerminalController.swift:338-356` — nonisolated static. Must gain the stale→live override.

## Sequence of changes

1. **Extend `SessionStatusEntrySnapshot`** with optional `url: String?`, `priority: Int?`, `format: String?`, `staleFromRestart: Bool?`. All optional → schema stays v1 (decision #5 in the plan doc).
2. **Extend the snapshot call site** in `Workspace.sessionSnapshot(...)` to emit the new fields from each live `SidebarStatusEntry`.
3. **Add `staleFromRestart: Bool = false`** to `SidebarStatusEntry` itself. Default false; set to `true` on restore.
4. **Replace `statusEntries.removeAll()`** at `Workspace.swift:263` with the stamping restore that reads `snapshot.statusEntries` and rebuilds each entry with `staleFromRestart: true`. `agentPIDs.removeAll()` on the next line stays — PIDs from a prior boot are meaningless.
5. **Patch `shouldReplaceStatusEntry`** so a stale→live transition always returns true even when `(value, color, url, priority, format)` are byte-identical. Keep the existing payload comparison as the fallback; the stale override sits on top.
6. **Sidebar rendering** (`ContentView.swift:12221+`, the `SidebarStatusEntry` consumer around line 12273) renders stale entries with reduced emphasis: opacity ~0.55 and italic. One narrow view change.
7. **Rollback env var** `CMUX_DISABLE_STATUS_ENTRY_PERSIST=1` — app-launch-scope flag; when set, skip the snapshot→restore and keep the `removeAll()` behavior. Document in `docs/socket-api-reference.md` alongside the other Tier 1 rollback flags so CMUX-6 can sweep it later.
8. **Observer plumbing on `SurfaceMetadataStore`** (deferred from Phase 2) likely lands in this same PR — see the Phase 3 section of the plan doc for why.

## Tests

- `cmuxTests/StatusEntryDedupeTests.swift` — unit-test `shouldReplaceStatusEntry` across: fresh entry, identical payload no-op, stale→live override, stale→stale no-op.
- `cmuxTests/StatusEntrySnapshotTests.swift` — round-trip a `SidebarStatusEntry` with all fields set (including `url`, non-default `priority`, `.markdown` format) through `SessionStatusEntrySnapshot` encode/decode.
- `tests_v2/test_status_entry_persistence.py` — set status via socket with all fields, force snapshot, restart tagged app, read status, assert fields + stale flag; write identical status, assert stale flag clears.
- **Never run tests locally** (per `feedback_cmux_never_run_xcodebuild_test`) — use `xcodebuild -scheme cmux build` to confirm compilation only, let CI run them.

## Rollback / risk

- Single env var flip (`CMUX_DISABLE_STATUS_ENTRY_PERSIST=1`) returns to pre-Phase 3 behavior.
- Schema stays v1 — optional decoding means older builds reading a newer snapshot are unaffected; newer builds reading an older snapshot just get `nil` for the new fields.
- `agentPIDs` stays cleared — don't expand scope.

## Prerequisites

- Phase 2 (CMUX-2 #13) merged. CMUX-2 is `in_progress`; this unblocks when it lands.

## Size estimate

~150 LoC app (snapshot fields + restore stamping + dedupe patch + sidebar styling) + ~80 LoC tests. Single PR.

## Open questions

- [ ] Aging rule for `staleFromRestart` (auto-clear after N days vs hold forever). Plan doc defers — carry forward.
- [ ] Sidebar stale treatment: opacity vs italic vs both vs an icon badge. Visual call; propose both and screenshot-review.

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Expanded the 32-line plan stub into a pick-up note pinning file:line anchors, sequenced changes, and test surface; Phase 3 section of the plan doc remains the deep reference.
