### Executive Summary
This is the right problem and mostly the right phase order, but the current plan is **not yet execution-ready**. The biggest issue is type-model drift: the proposed persistence schema for `SurfaceMetadataStore` downgrades rich JSON metadata/sources into string dictionaries, which would silently lose data and violate Module 2 semantics. The second issue is feasibility drift: “stable panel UUIDs” is treated as a small restore tweak, but in current code panel IDs are freshly generated in multiple panel/surface constructors, so this is a broader refactor than the plan acknowledges.

My recommendation: keep the phased structure, but revise Phase 1/2 design details before implementation starts.

### The Plan’s Intent vs. Its Execution
The intent is strong and coherent: make M-series metadata durable, preserve identity across restart, and provide a practical recovery affordance rather than pretending PTY resurrection already exists.

Where execution drifts from intent:
1. **Metadata durability is specified in a lossy shape.** Plan Phase 2 proposes `metadata: [String: String]?` and `metadataSources: [String: String]?` (plan lines 146-147, 161-162), but the live store is `[String: Any]` plus source records `{source, ts}` (`Sources/SurfaceMetadataStore.swift`:53-58, 255-263). This would drop non-string values (e.g. canonical `progress`) and source timestamps.
2. **“Stable UUIDs” is framed as local cleanup, but implementation touches core constructors.** Restore currently remaps `oldToNewPanelIds` (`Sources/Workspace.swift`:224-232, 491-507). New panel/surface IDs are minted in constructors (`Sources/GhosttyTerminalView.swift`:2641, `Sources/Panels/BrowserPanel.swift`:2553, `Sources/Panels/MarkdownPanel.swift`:72). This is a deeper change than “remove mapping.”
3. **Status persistence spec doesn’t match current status model fidelity.** `SidebarStatusEntry` includes `url`, `priority`, `format` (`Sources/Workspace.swift`:67-70), but `SessionStatusEntrySnapshot` currently stores only `key/value/icon/color/timestamp` (`Sources/SessionPersistence.swift`:199-205). Plan Phase 3 doesn’t address this gap.
4. **Plan says “per-surface and per-workspace status pills”** (line 212), but current `statusEntries` is workspace-scoped (`[String: SidebarStatusEntry]` on `Workspace`) and socket writes target tab/workspace state (`Sources/TerminalController.swift`:14929-14959).

### Architectural Assessment
The decomposition (identity → durable metadata/status → external session association → UX) is good. It creates a clean dependency chain and avoids building recovery UI on top of volatile substrate.

Key architectural concerns:
1. **Phase 2 representation must be lossless JSON, not string maps.** This is the highest-risk gap and must be fixed in design, not in implementation details later.
2. **Phase 1 needs an explicit strategy for ID injection vs. persistence aliasing.** The plan currently assumes direct ID reuse without acknowledging constructor-level ID generation.
3. **Autosave/fingerprint is currently cardinality-based, not value-based.** `TabManager.sessionAutosaveFingerprint()` includes counts for `statusEntries`, `metadataBlocks`, etc. (`Sources/TabManager.swift`:4892-4899), so value-only changes can miss normal 8s autosave cadence. Plan correctly identifies this, but needs concrete design for both status and metadata paths.
4. **Module spec alignment is currently inconsistent.** M2 spec says in-memory only (`docs/c11mux-module-2-metadata-spec.md`:21). Tier 1 should explicitly amend/supersede that contract to avoid consumer confusion.

### Is This the Move?
Yes, with revision. The direction is pragmatic and valuable. The bets are mostly right:
1. Durable metadata before recovery UI.
2. Preserve continuity of identity and status semantics.
3. Use external observation for Claude session linkage instead of invasive hooks.

What I would do differently:
1. Tighten Phase 2 data model first (lossless JSON + sidecar fidelity) before any Phase 4/5 work.
2. Decide whether true stable panel IDs are worth the constructor-level refactor now, versus introducing a persistent alias layer for Tier 1.
3. Specify autosave mutation tracking as explicit revision counters (workspace + metadata store), with no-op dedupe rules to prevent churn.

### Key Strengths
1. **Correct layering discipline.** The plan puts substrate durability before UI affordances.
2. **Good sequencing and PR slicing.** Phases are scoped in a way that can be reviewed and reverted incrementally.
3. **Reality-based non-goals.** Defers PTY survival to Tier 2 instead of overpromising.
4. **Explicit attention to autosave behavior.** Calls out a real failure mode rather than assuming periodic save solves everything.
5. **Cross-plan coordination awareness.** Correctly claims the surface-level persistence item parked by the workspace metadata companion plan.

### Weaknesses and Gaps
1. **Critical: metadata schema is lossy vs live store contract.**
   Downstream effect: canonical/custom metadata corruption, especially numeric/object values; broken round-trip guarantees.
2. **Critical: source sidecar fidelity is reduced.**
   Downstream effect: loses `ts` semantics and weakens precedence/debug observability model from M2.
3. **High: stable-ID implementation complexity is understated.**
   Downstream effect: likely schedule slip or risky late redesign if constructor-level impacts are discovered mid-Phase 1.
4. **High: status stale-flag clearing path is underspecified.**
   Current dedupe (`shouldReplaceStatusEntry`) can skip rewrites on identical payload (`Sources/TerminalController.swift`:338-356), so a stale marker may never clear unless logic changes.
5. **High: status snapshot omits fields currently used in runtime status rendering.**
   `url/priority/format` are not currently persisted and the plan doesn’t reconcile this.
6. **Medium: Claude index assumptions are brittle as written.**
   Real directories include mixed entries, not just `.jsonl`; “first+last line only” is insufficient for robust first-user preview extraction.
7. **Medium: operational details for recovery commands are incomplete.**
   Needs explicit command sanitization/quoting and localization plan for new UI strings.
8. **Low: one factual drift in current-state description.**
   Plan cites `~/.config/...` snapshot path; current implementation uses Application Support path.

### Alternatives Considered
1. **Stable runtime panel IDs vs persistent alias IDs.**
   Alternative: keep runtime UUID remap but add a durable `persistent_surface_id` used for metadata/status/recovery mapping. Lower implementation risk, but user-facing surface IDs still change across restart.
2. **Embed metadata in `SessionPanelSnapshot` vs dedicated sidecar file.**
   Alternative: sidecar persistence file keyed by workspace+panel IDs. Keeps session snapshot simpler but introduces multi-file consistency concerns.
3. **In-app Claude filesystem indexing vs external helper/CLI adapter.**
   Alternative: shell out to `claude` (or adapter) for session discovery. Reduces coupling to private on-disk format but adds runtime dependency and latency.
4. **Always-on auto-association vs explicit/manual association command.**
   Alternative: only set `claude_session_id` via explicit user/agent action. Lower privacy/perf risk, but less automatic recovery.

### Readiness Verdict
**Needs revision before execution.**

Conditions to move to Ready:
1. Replace Phase 2 string dictionaries with a lossless Codable JSON representation and full sidecar record persistence (`source` + `ts`).
2. Add an explicit Phase 1 implementation note for how IDs are injected/reused across Terminal/Browser/Markdown panel creation (or switch to alias strategy).
3. Define exact stale-status semantics and clearing behavior even when status payload repeats unchanged.
4. Define autosave mutation tracking concretely (revision counters and no-op dedupe rules).
5. Add a short spec-amendment note reconciling Tier 1 with M2’s current “in-memory only” text.

### Questions for the Plan Author
1. For Phase 1, do you want true stable runtime `panelId`s (constructor-level ID injection), or would a stable persistent alias satisfy Tier 1 goals with lower risk?
2. If true stable IDs are required, where will ID-injection happen for terminal surfaces (`TerminalSurface`), browser panels, and markdown panels?
3. Should Phase 2 persist metadata as full JSON values (including numbers/bools/objects/arrays) to preserve M2 semantics?
4. Should `metadata_sources` persist full `{source, ts}` records rather than source strings only?
5. How should conflicts resolve if `SessionPanelSnapshot.title` and restored metadata `title` disagree on restore?
6. Do you want to persist full `SidebarStatusEntry` fidelity (`url`, `priority`, `format`) or intentionally downgrade on restart?
7. Should `staleFromRestart` clear on *any* post-restart write for the key (even identical value), and if so how will dedupe logic be adjusted?
8. Is `statusEntries` intentionally workspace-scoped only, or do you intend to introduce true per-surface status state in this plan?
9. For autosave, do you prefer revision counters (`workspaceStatusRevision`, `surfaceMetadataRevision`) or content hashing, and at which layer will each live?
10. Should M2 spec be amended in this PR series to document persistence, or do you want Tier 1 to be the normative override document?
11. For Claude indexing, should path discovery respect an override (env/config) instead of hardcoding `~/.claude/projects`?
12. Should session-association metadata keys be namespaced (e.g. `agent.claude.session_id`) to reduce collision risk?
13. Is storing/using `firstUserMessagePreview` acceptable from a privacy perspective, or should preview be opt-in/off by default?
14. For `surface recreate`, what shell(s) must the one-liner target (zsh only vs bash/fish), and what quoting guarantees are required?
15. Are Phase 4/5 intended to be feature-flagged initially, given external format coupling to Claude’s on-disk structure?
