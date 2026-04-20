# CMUX-4 — Tier 1 Phase 4: Claude session index (opt-in)

Plan note for whoever picks this up. Tier 1b recovery layer — ships behind two flags.

## The intent in one line

Observe-from-outside: c11mux scans `~/.claude/projects/` and records which Claude Code session was most recently active for each surface, without hooking into Claude.

## Source of truth

Phase 4 section of `docs/c11mux-tier1-persistence-plan.md` (lines 439–611). Deep reference. This note is the pick-up brief.

## Why this is opt-in

Reading transcript files crosses a trust line. The scan is read-only, writes only the session UUID (never prompt text), and is gated behind two env vars plus a future privacy doc. See the Privacy posture section of the plan doc — don't ship without it.

## Dependencies

- **Prerequisite:** Phase 3 (CMUX-3) landed and Tier 1a stable. Needs `SurfaceMetadataStore` persistence and observer plumbing in place.
- **Re-justify before starting:** once Phases 1–3 land, does the restored metadata already give the operator enough to rebuild manually (cwd + last title + role)? If yes, Phase 4 may shrink to "just record the session pointer from an agent OSC when it's already running" and drop the filesystem scan entirely.
- **Non-goal:** remote-daemon workspaces. `~/.claude/projects/` is local-only in v1; remote variant is explicitly deferred.

## Mechanism (confirmed empirically 2026-04-18)

- Transcript path: `~/.claude/projects/<cwd-slug>/<session-id>.jsonl`.
- Slug rule: every non-alphanumeric character in cwd → `-`. Alphanumeric runs preserved. Leading `-` from the leading `/`.
- Transform is many-to-one (`/foo/bar` and `/foo-bar` both → `-foo-bar`), so the first-line `cwd` field must be parsed and compared exactly. Disambiguation is mandatory, not optional.

## New module

`Sources/ClaudeSessionIndex.swift` (~150 LoC). Surface:

```swift
struct ClaudeSession { id: UUID; cwd: String; startedAt: Date; lastModified: Date; messageCount: Int }
enum ClaudeSessionIndex {
    static var rootOverride: URL?                                             // for tests
    static func sessions(forCwd: String, limit: Int = 5) -> [ClaudeSession]
    static func mostRecent(forCwd: String, within: TimeInterval = 86_400) -> ClaudeSession?
}
```

Bounds (all mandatory):
- Off-main serial queue; per-cwd cache TTL 30s.
- Depth-1 only. `mtime` sort, top-N parsed. 64 KiB per-file read cap (first/last lines only).
- 250ms per-scan timeout, partial results on timeout.
- No symlink following, >10 MiB files skipped, read-only, `[]` on missing dir.

## Recording the association

Writes flow through `SurfaceMetadataStore.set(..., source: .heuristic)` under namespaced canonical keys:

- `agent.claude.session_id`
- `agent.claude.session_started_at`

Namespacing leaves room for future `agent.session_id`/`agent.kind` generalization. **Do not use bare non-namespaced keys.** The M2 precedence chain (`explicit > declare > osc > heuristic`) gives "agent wins over heuristic" for free — no bespoke rule.

## Feature flags

- `CMUX_EXPERIMENTAL_SESSION_INDEX=1` — gates the entire code path. Off by default in v1 release; flip on after bake.
- `CMUX_DISABLE_SESSION_INDEX=1` — enterprise/privacy opt-out, respected even when feature flag is on.

## Trigger points

- Surface focus (debounced 1s).
- Terminal surface creation (feature-flag gated).
- Agent-written `surface.set_metadata` under the namespaced key — M2 precedence handles dominance automatically.

## Clobbering guard

Restored metadata with source `.declare`/`.explicit` is never overwritten by a heuristic scan. Heuristic-over-heuristic only happens when the incoming `startedAt` is strictly greater.

## Tests

- `cmuxTests/ClaudeCwdSlugAlgorithmTests.swift` — table-driven: underscores, dots (double-dash), spaces, Unicode; collision disambiguation via first-line cwd.
- `cmuxTests/ClaudeSessionIndexTests.swift` — synthetic tree via `rootOverride`; recency window, timeout, symlink/size rejects.
- `cmuxTests/ClaudeSessionPrecedenceTests.swift` — explicit write beats heuristic; heuristic-over-heuristic respects `startedAt`.
- `tests_v2/test_claude_session_association.py` — create surface, focus, assert metadata populated with `source=heuristic`.

## Privacy docs

Ship `docs/c11mux-privacy.md` (short) alongside this PR documenting transcript-read behavior and the opt-out.

## Size estimate

~150 LoC new module + ~80 LoC integration + ~250 LoC tests. One PR with the privacy doc.

## Open questions

- [ ] First-release default: env flag off, or ship flipped on by default?
- [ ] Cross-agent generalization (Codex `~/.codex/sessions/`, Gemini TBD) — introduce a `SessionIndex` protocol now or defer until the second integration?
- [ ] Prompt preview: strictly deferred for v1; when do we revisit?

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Expanded plan stub into a pick-up note with the empirically confirmed slug rules, mandatory bounds, two-flag gating, and re-justify checkpoint.
