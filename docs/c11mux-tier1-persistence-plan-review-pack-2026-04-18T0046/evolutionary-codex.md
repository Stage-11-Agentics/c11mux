### Executive Summary
The biggest opportunity is to evolve this from “restart persistence” into a **surface continuity substrate**: stable identity + durable metadata + resumable execution intent. If done well, Tier 1 is not just recovery polish; it becomes the foundation for cross-session automation, reproducible agent workflows, and eventually cross-machine handoff.

Right now, the plan is directionally strong but still framed as a point fix. The evolutionary move is to treat this as a product primitive: every surface should carry enough durable context to be reconstructed, resumed, audited, and repurposed.

### What's Really Being Built
Under the surface, this plan is building three strategic capabilities:

1. **Durable surface identity** (panel continuity across sessions).
2. **Durable semantic state** (metadata + status history, not just layout).
3. **Actionable recovery** (turning persisted context into next actions).

That combination is a proto “stateful agent workspace runtime.” Once those three exist, c11mux can stop being a transient terminal arrangement and become a continuity layer for agent operations.

### How It Could Be Better
1. **Preserve full metadata semantics, not string-only snapshots.**
The plan proposes `SessionPanelSnapshot.metadata: [String: String]?`, but the live store is `[String: Any]` and canonical keys include non-string values (`progress` number). Evolving this as string-only will silently collapse future capability.

2. **Treat status persistence as typed continuity, not partial replay.**
`SidebarStatusEntry` currently carries `icon`, `color`, `url`, `priority`, `format`, `timestamp`, while `SessionStatusEntrySnapshot` only stores a subset. Persisting status without schema parity will create lossy restores and UX drift.

3. **Use revision counters as first-class persistence triggers.**
Autosave fingerprint currently hashes aggregate counts in `TabManager.sessionAutosaveFingerprint()`, not value-level changes. Tier 1 should add cheap monotonic revisions for metadata/status/log/progress and hash those revisions only.

4. **Separate “identity stabilization” from “ID injection mechanics.”**
Plan Phase 1 reads simple, but current panel IDs are generated in `TerminalSurface`, `BrowserPanel`, and `MarkdownPanel` initializers. Make this an explicit migration workstream so timeline/risk is honest.

### Mutations and Wild Ideas
1. **Recovery Graph (not just Resume Chip).**
Model each restored surface as a graph node with edges to inferred sessions, commands, and cwd lineage. UI can then offer ranked recovery actions, not a single button.

2. **Portable Workspace Capsule.**
Export a workspace continuity bundle (layout + metadata + recovery intents) for machine-to-machine handoff. This turns Tier 1 into collaboration infrastructure.

3. **Continuity Confidence Scores.**
Store confidence on inferred associations (`claude_session_id` from scan vs explicit agent write). UI/CLI can choose conservative vs aggressive recovery behavior.

4. **Event-Sourced Continuity Log.**
Instead of snapshot-only semantics, append lightweight continuity events (metadata changed, status refreshed, session associated). This enables “what changed since crash?” tooling.

### What It Unlocks
1. Reliable “resume where I left off” across app restarts.
2. Programmatic recreation pipelines (`surface -> intent -> command`) for automation.
3. Better operator trust: stale-but-visible context instead of total amnesia.
4. Future multi-agent orchestration primitives where surfaces are long-lived identities.
5. Cross-tool parity (Claude/Codex/others) through shared session-association contracts.

### Sequencing and Compounding
Current order is good at a high level, but I’d tune it for compounding:

1. **Phase 0 (new): Data model hardening + compatibility contract.**
Define snapshot encodings for full metadata JSON, metadata source records, and full status entry schema before implementation PRs.

2. **Phase 1: Identity mechanics behind a compatibility bridge.**
Land ID stabilization with a temporary remap fallback path until constructor-level fixed-ID plumbing is complete for all panel types.

3. **Phase 2: Metadata persistence + revision-based autosave hooks together.**
Do not ship metadata durability without value-sensitive autosave triggering.

4. **Phase 3: Status persistence with explicit stale semantics in API shape.**
Expose stale fields through a structured status read path (current v2 sidebar payload is count-centric).

5. **Phase 4: Claude index in shadow mode first.**
Write inferred associations as low-confidence metadata + telemetry counters before UI exposure.

6. **Phase 5: Recovery UI/CLI once ranking quality is proven.**
Show top candidate + alternates rather than a single brittle action.

### The Flywheel
A strong flywheel is available:

1. Better persisted context -> better resume suggestions.
2. Better resume success -> users rely on metadata more.
3. More metadata writes -> richer associations and higher confidence.
4. Higher confidence -> less manual recovery and faster workflows.
5. Faster workflows -> more surfaces/workspaces managed in c11mux.

Engineered correctly, each restart improves future restart quality.

### Concrete Suggestions
1. Replace `[String: String]?` metadata snapshot fields with a codable `JSONValue` envelope and store `metadata_sources` as structured `{source, ts}` records.
2. Extend `SessionStatusEntrySnapshot` to include `url`, `priority`, `format`, and stale/freshness markers so restore is lossless.
3. Add `metadataRevision` in `SurfaceMetadataStore` and `statusRevision`/`logRevision`/`progressRevision` on `Workspace`; hash these in autosave fingerprint.
4. Introduce explicit `ResumeCandidate` model (`tool`, `command`, `confidence`, `reason`) and have both UI chip + CLI consume it.
5. For Claude indexing, prefer `sessions-index.json` when present, with jsonl fallback for robustness.
6. Add a shadow-mode API (`surface.recovery.preview`) before UI click actions; test recovery quality in CI fixtures first.
7. Define conflict policy for inferred vs explicit session IDs as a durable precedence table (mirroring M2 source precedence style).
8. Keep `titleBarCollapsed` ephemeral in Tier 1, but emit a metric/counter so you can decide with data in Tier 1.5.
9. Add a “clear stale statuses” bulk action to avoid long-term sidebar decay if stale entries are retained indefinitely.
10. Add a short compatibility note in docs that panel ID semantics are changing from “runtime-only” to “restart-stable.”

### Questions for the Plan Author
1. Is long-term identity in c11mux the **panel UUID**, the bonsplit tab ID, or an eventual separate durable `surface_identity`?
2. Should Tier 1 persistence guarantee full-fidelity roundtrip for arbitrary M2 JSON values, or is lossy narrowing acceptable?
3. Do you want stale status to be a UI-only hint, or part of the API contract consumed by external tooling?
4. How should stale status behave when only some fields of an entry are refreshed post-restart (per-key vs per-entry freshness)?
5. Should inferred `claude_session_id` ever overwrite an explicit agent write, or must explicit always win even when older?
6. What is the minimum confidence threshold for showing one-click resume in UI?
7. Is `claude --resume <id>` guaranteed stable enough to be a default action, or should UI route through a generated command preview first?
8. Do you want to support cross-machine recreation in Tier 1.x (same snapshot, different host), or explicitly defer that?
9. Should Tier 1 include a structured recovery preview endpoint so tests can validate logic without UI interaction?
10. What telemetry/observability will you capture to decide whether this persistence model is actually improving recovery outcomes?
