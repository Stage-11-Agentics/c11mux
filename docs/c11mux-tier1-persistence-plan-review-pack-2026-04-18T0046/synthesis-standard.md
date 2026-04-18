# Standard Review Synthesis — c11mux Tier 1 Persistence Plan

**Synthesis date:** 2026-04-18
**Reviewers synthesized:** Claude (Opus 4.7), Codex, Gemini
**Plan under review:** `docs/c11mux-tier1-persistence-plan.md`

---

## Executive Summary

All three reviewers agree the plan's **direction and phase decomposition are correct**: durable surface metadata before recovery UI, observe-from-outside for Claude session association, and explicit deferral of Tier 2 (PTY survival). All three recognize Phase 1 (stable panel UUIDs) as the quiet structural enabler that unblocks the rest.

They diverge sharply on **readiness**:

1. **Gemini:** Ready to execute.
2. **Claude:** Needs minor revision (5 specific fixes, each an afternoon of work).
3. **Codex:** Needs revision before execution — identifies two structural gaps that would cause silent data loss or schedule slip if implementation started today.

The most load-bearing disagreement is over **Phase 2's schema fidelity**. Codex flags a critical lossy-representation bug (the proposed `[String: String]` persisted form downgrades the live `[String: Any]` metadata store and drops source timestamps) that neither Claude nor Gemini caught. If Codex is right — and a cross-check against `Sources/SurfaceMetadataStore.swift:53-58, 255-263` suggests it is — this is a hard blocker, not a minor revision.

The second highest-confidence concern is **Phase 4's heuristic semantics**. Claude, Codex, and Gemini independently raise variants of "the disk scan will overwrite valid metadata or misattribute sessions in edge cases." This is the feature with the most unowned risk and the thinnest specification.

**Consolidated verdict:** Needs revision before execution. The fidelity fix (Codex #1, #2) is a blocker; the Phase 1 constructor-refactor scope (Codex #3), Phase 4 semantics (all three), and stale-flag clearing logic (Claude + Codex) are near-blockers. The remaining items are minor.

---

## 1. Where Models Agree (Highest-Confidence Findings)

1. **Phase 1 is load-bearing and correctly framed as a prerequisite.** All three treat stable panel UUIDs as the foundational simplification that unblocks every downstream phase. None disputes the direction.

2. **The tiered decomposition is the right bet.** All three explicitly endorse shipping Tier 1 (context durability) before Tier 2 (PTY survival). Claude calls it "a clean, tractable line"; Codex calls it "pragmatic and valuable"; Gemini calls it "exactly the right bet for maintaining product velocity."

3. **Observe-from-outside (Phase 4) is philosophically correct.** All three praise the decision to read Claude's filesystem rather than require agent-side hooks. Gemini calls it "brilliant, unblocking"; Claude invokes `feedback_c11mux_no_agent_hooks.md`; Codex lists it as a correct architectural bet.

4. **`staleFromRestart` is a good design instinct** but its lifecycle is underspecified. All three raise concerns about how/when stale flags clear and whether they accumulate into visual clutter indefinitely.

5. **Phase 4 disk-scanning has real operational risk.** All three independently flag directory-scale concerns (Gemini: "tens of thousands of files or slow network mount"; Claude: "10,000 sessions in a cwd"; Codex: "brittle as written"). All three want bounded, timeout-guarded, or cached behavior.

6. **Autosave fingerprint integration is a real issue that the plan correctly identifies** but all three want a more concrete design than the plan currently specifies (monotonic counter vs. content hash, where the counter lives, what triggers a bump).

7. **The plan appropriately defers or excludes the right things** — PTY persistence, `titleBarCollapsed`, schema version bumps. All three endorse the "does not persist" appendix as good discipline.

8. **Phase 1 has unaudited downstream consumers.** Claude and Gemini both call this out explicitly (Claude: socket API, Lattice; Gemini: "AppKit-wrapped components… internal buffers or caches"). Codex frames the same concern structurally (constructor-level ID generation is broader than the plan acknowledges).

---

## 2. Where Models Diverge (Disagreement as Signal)

1. **Readiness verdict — the split is 1 / 1 / 1.**
   - Gemini: **Ready.** Treats Phase 1 as a "quiet simplifier" and the rest as mostly prerequisite plumbing under the UI surface.
   - Claude: **Needs minor revision.** Identifies five specific gaps but calls none a blocker.
   - Codex: **Needs revision before execution.** Identifies two critical gaps (metadata fidelity, source-sidecar fidelity) that would silently corrupt M2 semantics if implementation started today.

   The disagreement itself is signal: Gemini reviewed the plan structurally, Claude reviewed the plan against the codebase at function-call granularity, and Codex reviewed the plan against the *live data contract* of `SurfaceMetadataStore`. The deeper the read, the stronger the "not yet ready" verdict.

2. **Phase 2 schema fidelity — Codex alone catches this.** Codex identifies that the plan's proposed `metadata: [String: String]?` and `metadataSources: [String: String]?` would silently downgrade the live `[String: Any]` store and drop the `{source, ts}` records documented in M2. Neither Claude nor Gemini flagged this. If Codex is correct about the live store (the line references check out), this is a blocker that the other two reviews missed.

3. **Phase 1 scope — Codex is the pessimist.** Claude treats Phase 1 as an additive simplification with an underspecified risk surface. Codex asserts the implementation is strictly deeper: panel IDs are minted in at least three constructors (`GhosttyTerminalView.swift:2641`, `Sources/Panels/BrowserPanel.swift:2553`, `Sources/Panels/MarkdownPanel.swift:72`), making this a constructor-level refactor rather than "remove the mapping." Gemini touches the area obliquely (edge cases around SwiftUI view reset). Codex's reading is the most specific and, if accurate, re-scopes Phase 1 materially.

4. **Phase 4 abstraction timing.** Claude argues explicitly for *either* "ship with a `SessionIndex` protocol from day one" *or* "defer Phase 4+5 until Codex/Gemini format stabilizes." Codex proposes a feature flag and questions privacy implications (`firstUserMessagePreview`). Gemini accepts the Claude-only shipping path without flagging asymmetry. This is a real strategic decision the plan hasn't made.

5. **Stale-flag clearing mechanism.** Claude proposes a 72-hour auto-clear as a reasonable default. Codex identifies a concrete blocker: the existing `shouldReplaceStatusEntry` dedupe in `TerminalController.swift:338-356` will skip rewrites on identical payloads, so a stale marker may never clear unless the dedupe logic is adjusted. Gemini suggests a "Clear Stale Statuses" context menu action. Three different mechanisms, all valid, none mutually exclusive, but the plan picks none.

6. **Alternative persistence shape.** Codex considers a sidecar per-surface JSON file (and correctly calls it worse for v1). Claude considers the same alternative and reaches the same conclusion. Gemini frames only the unified architectural alternative ("Agent State Recovery Protocol") and correctly rejects it. No actual disagreement, but different alternatives surfaced.

7. **Fingerprint implementation.** Gemini and Claude both endorse the monotonic counter (O(1), requires discipline). Codex agrees in principle but adds a constraint neither of the others raises: "revision counters with no-op dedupe rules to prevent churn." Codex wants the dedupe explicit; Gemini wants only the counter confirmed in-memory; Claude asks where the counter lives. All three are pointing at the same underspecification from different angles.

8. **Status snapshot field coverage.** Codex alone identifies that `SidebarStatusEntry` has `url`, `priority`, and `format` fields (`Sources/Workspace.swift:67-70`) that the persisted `SessionStatusEntrySnapshot` does not carry (`Sources/SessionPersistence.swift:199-205`). Neither Claude nor Gemini noticed this fidelity gap.

---

## 3. Unique Insights by Reviewer

### Claude (Opus 4.7) — unique contributions

1. **Reframing Phase 4 as "heuristic source attribution"** and routing its writes through `SurfaceMetadataStore.setInternal(..., source: .heuristic)`. This collapses the plan's bespoke "external write wins" rule into the existing M2 precedence chain — an architectural consolidation neither other reviewer proposed.
2. **Concrete ordering inversion of Phase 1 and Phase 2.** Make metadata persistent first with a temporary remap, then strip the remap. Lower-risk rollout path that neither Codex nor Gemini named.
3. **Companion plan coordination risk.** Explicitly identifies that `docs/c11mux-module-7-expandable-title-bar-amendment.md` is untracked locally and that M7's "persistence across restart" parking-lot item is being claimed by this plan — a concrete rebase/merge-order problem.
4. **Scrollback-replay tempfile lifecycle.** Stable panel UUIDs make `FileManager.default.temporaryDirectory/cmux-session-scrollback/` filenames predictable across boots. Whether cleanup exists today is unchecked; if not, collisions become more likely.
5. **Cmux testing-policy specificity.** Phase 3's NSHostingView-style test needs an explicit scheme choice (`cmux-unit` vs `test-e2e.yml`). Gemini doesn't mention tests; Codex mentions them abstractly.
6. **Alternative 4: ship Phase 4 + 5 first with no persistence.** Delivers "resume Claude session" on any recently-used surface before restart durability exists. Intermediate state nobody else considered.

### Codex — unique contributions

1. **Metadata schema is lossy (blocker).** The only reviewer to check the plan's schema against `Sources/SurfaceMetadataStore.swift` and catch that `[String: String]` silently drops non-string values.
2. **Source sidecar fidelity loss (blocker).** The `metadataSources: [String: String]?` in the plan drops the `{source, ts}` tuples the live store tracks — a direct M2 spec violation.
3. **Phase 1 scope — constructor-level.** Names exact file/line citations (`GhosttyTerminalView.swift:2641`, `Sources/Panels/BrowserPanel.swift:2553`, `Sources/Panels/MarkdownPanel.swift:72`) showing Phase 1 is a constructor refactor, not a remap removal.
4. **Status entry field gap.** Identifies `url/priority/format` fields on `SidebarStatusEntry` not carried by `SessionStatusEntrySnapshot`.
5. **Stale clearing blocked by existing dedupe.** Cites `TerminalController.swift:338-356` showing identical payloads are skipped, meaning stale flags can't clear through the normal write path.
6. **Workspace-scoped vs. per-surface status semantics.** Catches that the plan says "per-surface and per-workspace status pills" but `statusEntries` is currently only workspace-scoped (`[String: SidebarStatusEntry]` on `Workspace`).
7. **M2 spec amendment needed.** `docs/c11mux-module-2-metadata-spec.md:21` says "in-memory only" — Tier 1 should explicitly supersede this.
8. **Privacy consideration for `firstUserMessagePreview`.** Is storing the first user message acceptable, or should preview be opt-in/off by default?
9. **Claude projects directory path override.** Should discovery respect an env/config override rather than hardcoding `~/.claude/projects`?
10. **Factual drift in plan's current-state description** (plan cites `~/.config/…`, implementation uses Application Support path).
11. **Alternative: persistent alias ID instead of truly stable runtime ID.** Lowest-risk implementation path Claude also considered but Codex specifies more precisely.

### Gemini — unique contributions

1. **"Identity should be immutable."** Framing Phase 1 as a principle-driven simplification rather than a tactical fix. Neither other reviewer states the principle this directly.
2. **"Filesystem as public API."** Explicit framing of why Phase 4's disk scan is robust: it treats Claude's on-disk layout as a public contract and decouples from agent internals.
3. **Scan scaling concern is operational, not code-shape.** Gemini names the real-world failure modes (slow network mount, cumulative growth over a year) in a way neither other reviewer does.
4. **Stale status UX.** Bulk-clear via context menu affordance — an end-user action neither Claude nor Codex proposes.
5. **Reverse-overwrite on restore.** If the user ran Claude in a directory outside cmux while cmux was closed, the Phase 4 scan on next focus could overwrite a validly-restored `claude_session_id` with a newer but irrelevant one. Claude and Codex touched related concerns but Gemini frames the specific attack: restore + outside-cmux activity → clobber on focus.

---

## 4. Consolidated Questions for the Plan Author (Deduplicated, Numbered)

**Priority A — blockers / near-blockers (address before implementation)**

1. **Metadata persistence fidelity.** Will Phase 2 persist metadata as full JSON values (preserving numbers, booleans, arrays, objects) rather than the proposed `[String: String]`? How will this be encoded (e.g., `Codable` wrapper around `AnyJSON`)? (Codex #3)

2. **Source sidecar fidelity.** Will `metadataSources` persist full `{source, ts}` records rather than source strings only, to preserve M2 precedence and observability? (Codex #4)

3. **Phase 1 scope — true stable IDs or persistent alias?** Do you want true stable runtime `panelId`s (requires constructor-level ID injection in `TerminalSurface`, `BrowserPanel`, `MarkdownPanel`), or is a stable persistent alias sufficient to meet Tier 1 goals with lower risk? (Codex #1; Claude #2 echoes with ordering twist)

4. **If stable IDs, where does ID injection happen?** Concretely name the constructor signatures being modified for each panel/surface type. (Codex #2)

5. **Stale-flag clearing logic.** Given that `shouldReplaceStatusEntry` dedupes identical payloads (`TerminalController.swift:338-356`), how does a stale marker actually clear when the agent rewrites an identical status? Should dedupe be adjusted to treat the stale→live transition as a replace? (Codex #7)

6. **`staleFromRestart` persistence across subsequent saves.** When a stale entry is re-serialized by the 8s autosave before the agent clears it, does the persisted form retain the stale flag? If yes, what is the aging rule (none / 72h auto-clear / agent-only clear)? (Claude #3)

**Priority B — semantic / architectural decisions**

7. **Phase 4 write routing.** Can the Phase 4 `claude_session_id` writes flow through `SurfaceMetadataStore.setInternal(..., source: .heuristic)`, letting the existing M2 precedence chain (`declare`/`explicit` beats heuristic) replace the bespoke "external write wins" rule? (Claude #4)

8. **Restored-value clobbering.** If the user ran Claude in a directory *outside* cmux while cmux was closed, could the Phase 4 debounced-focus scan overwrite a validly-restored `claude_session_id` with a newer but irrelevant one? How is this prevented? (Gemini #4, Claude-adjacent)

9. **Multiple concurrent Claude sessions in one cwd.** Two active Claude surfaces in the same cwd will both match the most-recent transcript. Is that acceptable, or does the heuristic need surface-start-time awareness? (Claude #5)

10. **Phase 1 external consumer audit.** Are panel IDs persisted or cached outside cmux (Lattice, long-lived CLI sessions, agents holding panel IDs across restarts)? Post-Phase-1, those IDs will silently become valid again instead of failing gracefully — is that the desired behavior? (Claude #1)

11. **`statusEntries` per-surface vs. workspace-scoped.** Plan text says "per-surface and per-workspace status pills" but the live model is workspace-scoped only (`[String: SidebarStatusEntry]` on `Workspace`). Is per-surface intended for this plan, or is this a typo? (Codex #8)

12. **Status snapshot field coverage.** Will the persisted `SessionStatusEntrySnapshot` be extended to carry `url`, `priority`, and `format` from `SidebarStatusEntry`, or is downgrading on restart intentional? (Codex #6)

13. **Codex/Gemini parity for Phase 4/5.** Ship Claude-only as written with a documented follow-up? Ship with a `SessionIndex` protocol now? Or defer Phase 4/5 until the other agents' session stores are understood? (Claude #8)

**Priority C — operational & UX details**

14. **Phase 5 `cmux surface recreate` output format.** Give a concrete example for each surface type (bare terminal with cwd, Claude surface with session id, browser surface). Target shell? Quoting guarantees (zsh only vs bash/fish)? (Claude #9; Codex #14)

15. **Recovery-failure fallback chain.** What happens when `claude --resume <id>` fails? Catch-all fallback? Error surface in sidebar? Who writes the error — CLI dispatcher or a Claude-failure handler? (Claude #10)

16. **Claude projects directory scaling and safety.** Bounded depth search? mtime-sort before parse? Timeout on the scan? Handling for symlink loops, oversized jsonl, or a malformed first-line preview? (Gemini #1; Claude gap)

17. **Claude transcript format drift.** Does `ClaudeSessionIndex` need multi-version handling? Behavior on unparseable transcripts — silent skip, log, or surface error? (Claude #6)

18. **Privacy: `firstUserMessagePreview`.** Is capturing and persisting the first user message acceptable by default, or should previews be opt-in? (Codex #13)

19. **Claude projects path override.** Should path discovery honor an env/config override rather than hardcoding `~/.claude/projects`? (Codex #11)

20. **Agent key namespacing.** Should session-association metadata keys be namespaced (e.g., `agent.claude.session_id`) to reduce collision risk across agents? (Codex #12)

21. **Bulk-clear stale statuses.** Without auto-aging, an abandoned workspace accumulates greyed-out pills forever. Need a "Clear Stale Statuses" context menu action? (Gemini #2)

22. **Agent-PID-dependent status entries.** Restored status entries referencing now-dead PIDs (e.g., "claude_code Running") — is the stale treatment strong enough visually to signal "don't try to signal this PID"? (Claude #12)

**Priority D — coordination & meta**

23. **Autosave fingerprint concrete design.** Revision counters vs. content hashing, at which layer (workspace, metadata store, status store)? In-memory only or persisted? No-op dedupe rules to prevent autosave churn? (Codex #9; Claude #13; Gemini #5)

24. **M2 spec reconciliation.** `docs/c11mux-module-2-metadata-spec.md:21` says "in-memory only." Amend M2 in this PR series, or make the Tier 1 plan the normative override document? (Codex #10)

25. **Companion workspace-metadata plan overlap.** Both plans touch `Sources/SessionPersistence.swift` at `:330` (workspace snapshot) and `:243` (panel snapshot). Which lands first? Named merge-order convention? (Claude #16)

26. **In-flight M7 coordination.** `docs/c11mux-module-7-expandable-title-bar-amendment.md` and modified `Sources/SurfaceTitleBarView.swift` are untracked/uncommitted locally. Has M7 been coordinated with to avoid parallel persistence hooks? (Claude #15)

27. **Phase 1 as standalone PR.** Ship Phase 1 as an orthogonal cleanup PR *before* this plan begins, to isolate unknown-unknowns in ID stability? (Claude #2)

28. **Feature-flagging Phase 4/5.** Given the external coupling to Claude's on-disk format, should Phase 4/5 ship behind a flag initially? (Codex #15)

29. **Testing — CI vs. local split.** Explicit per-phase: which tests run under `xcodebuild -scheme cmux-unit` (safe local), which need the VM / `test-e2e.yml`, which need the Python `tests_v2` socket harness? The `cmux` testing policy is strict about this. (Claude #14)

30. **Size metric for metadata.** Where does a metric for real-world metadata sizes live — OSLog, debug-dump command, telemetry hook? (Claude #7)

31. **Title-bar collapse non-persistence.** Pure "simpler is better" reasoning, or validated against actual usage? One-line justification would settle it. (Claude #11)

32. **Phase 1 view-state reset implicit dependency.** Have we verified no SwiftUI view or AppKit-wrapped component relies on receiving a *new* panel UUID to clear its internal buffers/caches on restore? (Gemini #3)

33. **Fingerprint counter lifecycle.** In-memory only? Reset across workspace close/reopen? Matters for autosave correctness and log interpretation. (Claude #13; Gemini #5)

34. **Factual drift in plan.** Plan cites `~/.config/...` for snapshot path; implementation uses Application Support. Correct the plan text. (Codex Weaknesses #8)

---

## 5. Overall Readiness Verdict (Synthesized)

**Needs revision before execution.**

This synthesis adopts Codex's verdict over Gemini's/Claude's because two of Codex's unique findings — lossy metadata representation and lossy source-sidecar fidelity — would **silently corrupt** the M2 contract if implementation started today. Silent-corruption risks are structurally worse than the revision-scale issues Claude flags and the operational risks Gemini flags. They belong at the front of the queue.

**Blockers (must resolve before implementation):**

1. Replace `[String: String]` metadata representation with lossless JSON encoding. (Q1)
2. Replace `[String: String]` metadata-sources representation with full `{source, ts}` records. (Q2)
3. Decide Phase 1 scope: true stable IDs (constructor refactor in 3+ files) vs. persistent alias (lower risk, slight indirection). (Q3, Q4)
4. Specify stale-flag clearing behavior against the existing `shouldReplaceStatusEntry` dedupe. (Q5)
5. Specify stale-flag persistence lifecycle (per-save serialization, aging rule). (Q6)

**Near-blockers (resolve before Phase 4/5):**

6. Route Phase 4 writes through M2 precedence chain as `source: .heuristic` (or explicitly document why not). (Q7)
7. Prevent Phase 4 from clobbering validly-restored session IDs on first focus. (Q8)
8. Decide Codex/Gemini parity strategy: protocol from day one, ship Claude-only, or defer. (Q13)

**Minor (can be resolved during implementation):**

- Concrete `cmux surface recreate` output example (Q14)
- Scan bounds/timeout/safety for `ClaudeSessionIndex` (Q16)
- Autosave fingerprint concrete design (Q23)
- M2 spec amendment note (Q24)
- Companion plan / M7 coordination (Q25, Q26)
- Testing scheme specificity per phase (Q29)
- Factual drift: `~/.config` → Application Support (Q34)

**Estimated time to "ready":** ~1–2 days of design work on the plan document (primarily Q1–Q8), with the implementation itself unchanged in shape but meaningfully different in the metadata encoding, Phase 1 scope, and stale-flag logic.

**Confidence ordering of this synthesis' verdict:** High on blockers 1–2 (Codex made direct line-level citations against the live store); high on blockers 3–5 (Codex's structural arguments are supported by Claude's and Gemini's weaker variants of the same concern); medium on near-blockers 6–8 (correct-but-arguable architectural calls).

Once the blockers are resolved, the plan is structurally sound and the phase ordering correct. All three reviewers agree the underlying bet — Tier 1 context durability before Tier 2 PTY survival, observe-from-outside for Claude — is the right move.
