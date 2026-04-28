# Conversation Store Architecture

**Status:** Draft. Awaiting Trident plan review.
**Owner:** TBD (operator delegates after plan review converges).
**Supersedes:** `notes/session-resume-fix-plan.md` (the C11-24 hot-fix plan, now obsolete).
**Related:** PR #89 (current C11-24 implementation, shipped in 0.43.0 opt-in / 0.44.0-pre default-on), PR #94 (held release).

## TL;DR

c11 grows a first-class `Conversation` primitive decoupled from any specific TUI process. Each surface that hosts an agent has one or more `ConversationRef`s persisted across c11 restarts. Per-TUI **strategies** in c11 own how to capture and resume conversations using whatever signals each TUI provides: hooks where available, on-disk file scrape as fallback. Wrappers shrink to "declare the kind." This replaces the per-TUI bespoke wrapper pattern that ships in 0.43.0/0.44.0-pre, fixes the SessionEnd-clears-on-quit race, fixes the codex multi-pane "last wins" collapse, and opens a path to remote/cloud agents and conversation history without re-architecting again.

## Why we're doing this

Three concrete failures, observed in 0.44.0 staging QA on 2026-04-27:

1. **Two Codex panes opened in the same project, both restored to the most-recent global Codex session ("B")** — not their own. The current registry hardcodes `codex resume --last\n`. The wrapper has no mechanism to capture per-pane Codex session ids (Codex 0.124 has no `--session-id` injection flag, no SessionStart-style hook).
2. **Two Claude panes both restored blank.** Capture today writes `claude.session_id` to per-surface metadata via the SessionStart hook. The SessionEnd hook clears that key when claude exits. On Cmd+Q, c11 kills terminals; claude exits; SessionEnd fires; metadata cleared, racing the snapshot capture in `applicationShouldTerminate`. By next launch, per-surface session ids are gone.
3. **Opencode and Kimi do not resume at all.** Their wrappers launch fresh because neither TUI exposes an injection flag or hook surface that the bespoke wrapper pattern can hang off.

(1) and (3) are not bugs in the implementation. They are the inevitable consequences of the architecture: the wrapper-only pattern cannot capture what the TUI does not expose. (2) is a race between the TUI's lifecycle hook and c11's shutdown sequence; patching it inside the current architecture means special-casing "is the parent c11 dying?" inside a hook handler that has no visibility into c11 state.

The fix that moves us forward replaces the architecture, not the patch.

## Structural problems with the current pattern

1. **N TUIs = N bespoke wrappers + N capture surfaces.** Every new agent (opencode, kimi, future LLM CLIs) is a fresh integration. Many TUIs offer no lifecycle hook; the wrapper has nothing to hook into and chooses between "fresh launch" or "best-effort by side channel."
2. **Capture and clear go through the same hook.** SessionEnd clears what SessionStart wrote. There is no architectural difference between "TUI ended because user typed `/exit`" and "TUI ended because c11 killed it during shutdown." Both fire the same hook. The first should clear; the second should not.
3. **The ref lives in a single place: per-surface metadata of one snapshot.** No global awareness, no history, no portability. Once you delete the snapshot or the workspace, the conversation is unreachable even if the TUI's own session file on disk still exists.
4. **The wrapper-set ref is opaque to c11.** c11 only knows about `claude.session_id` because SessionStart writes that exact key. A future agent that uses `conversation_id` instead would need another hook handler with another reserved key. The naming is per-TUI rather than per-c11; reserved keys keep growing.
5. **Fragile against env-var loss.** The hook writes to "the surface identified by `CMUX_SURFACE_ID` in the hook process's environment, falling back to focused-surface if missing" (`CLI/c11.swift:7238-7266`). The fallback is silent. Any env-stripping shell behavior between c11-launched shell → TUI → hook subprocess routes the write to whichever surface happens to be focused at hook-fire time.

## Alternatives considered (and rejected)

- **Approach A: Harden the current pattern.** Skip-clear when `isTerminatingApp` is set; document codex degenerate case more loudly. Cheapest path. Rejected because it does not address the structural problems above; we would re-confront them with the next TUI integration and the next race condition.
- **Approach B: PTY hibernation (tmux model).** A long-running c11d daemon keeps TUI processes alive across c11 GUI restarts; the GUI re-attaches on launch. Rejected because OS sleep, kernel panic, power loss, or system reboot all kill the daemon and lose every conversation. The point of resume is to survive *those* events.
- **Approach D: Operator-marked checkpoints.** Explicit user action to checkpoint a conversation. Rejected as the primary mechanism because it puts the burden on the operator for what should be transparent. Worth keeping as a future *additional* mechanism (manual `c11 conversation push --source manual`) on top of the auto pipeline.

## Mental model

c11 grows an internal `Conversation` primitive. A Conversation is a persistable pointer to *a continuation of agent work*. It is owned by c11, lives across TUI process death, and is keyed by an opaque id whose interpretation is delegated to a per-kind strategy.

```
Surface ──hosts──▶ Conversation ──interpreted-by──▶ ConversationStrategy
                        │
                        └── carries: kind, id, capturedAt, capturedVia, state, payload
```

A surface hosts at most one *active* Conversation at a time (v1). It may carry a history of past Conversations. A Conversation belongs to a kind (`claude-code`, `codex`, `opencode`, `kimi`, `claude-code-cloud`, …) and the kind selects the strategy.

A Strategy is a pair of Swift functions:

- `capture(surface, signals) -> ConversationRef?` — produces the current ref from whatever signals are available right now (push-hook, pull-scrape, wrapper-claim).
- `resume(surface, ref) -> ResumeAction` — describes how to bring the conversation back when c11 respawns the surface.

Both are pure given their inputs. The strategy is stateless. The `ConversationStore` owns lifecycle.

## Schema

### `ConversationRef` (persisted)

```swift
struct ConversationRef: Codable, Sendable {
    let kind: String                                 // "claude-code", "codex", future…
    let id: String                                   // Opaque to c11; strategy interprets.
    let capturedAt: Date                             // When this ref was last refreshed.
    let capturedVia: CaptureSource                   // hook | scrape | wrapperClaim | manual
    let state: ConversationState                     // alive | suspended | tombstoned | unknown
    let payload: [String: PersistedJSONValue]?       // Kind-specific extras (cwd, model, transcript path, …)
}

enum CaptureSource: String, Codable { case hook, scrape, wrapperClaim, manual }
enum ConversationState: String, Codable { case alive, suspended, tombstoned, unknown }
```

### `ResumeAction` (transient, returned by strategy)

```swift
enum ResumeAction: Sendable {
    case typeCommand(text: String, submitWithReturn: Bool)
    case launchProcess(argv: [String], env: [String: String])
    case replayPTY(scrollback: String)
    case composite([ResumeAction])
    case skip(reason: String)
}
```

### Surface ↔ Conversation mapping (persisted)

A surface persists a *list* even though v1 only ever populates one entry. List shape leaves room for history without a schema break.

```swift
struct SurfaceConversations: Codable, Sendable {
    let active: ConversationRef?
    let history: [ConversationRef]   // v1: always empty.
}
```

This lives separately from `surface.metadata`. Surface metadata stays for surface configuration (`terminal_type` as a kind hint, `cwd`, agent role). Conversations have their own store and lifecycle.

## Capture

Two signal sources, fused inside the strategy. Push primary, pull as fallback and crash-recovery primary.

### Push (primary)

When a TUI exposes a lifecycle hook, the wrapper proxies it into c11 via a thin CLI command:

```
c11 conversation push --kind <k> --id <id> --source hook [--payload '{...}']
```

The CLI command uses `CMUX_SURFACE_ID` from its env. **It does not fall back to focused-surface** (the fallback is the silent-misroute footgun documented above). Errors out cleanly if `CMUX_SURFACE_ID` is unset. The store writes the ref immediately, marks `capturedVia = .hook`.

### Pull (fallback + crash recovery)

The strategy can scrape the TUI's on-disk session storage on demand:

- **At every autosave tick** (lightweight: `stat` the directory, find the most-recently-modified session matching this surface's filter, no I/O on the file unless newer than the cached ref). Cost: one `stat` per TUI per autosave per surface.
- **At quit** (`applicationWillTerminate`), forced. Captures any session the hook might have missed.
- **At launch on crash recovery** (no `shutdown_clean` flag found), forced. Replaces any cached push value, since that value may be 100ms stale and the on-disk file may have advanced.

Reconciliation rule: latest `capturedAt` wins, with source-priority tiebreaker on close timestamps (push > scrape > wrapperClaim > manual). Provenance is recorded so debugging is possible without instrumentation.

### Wrapper-claim (lowest priority)

The wrapper, at launch, issues `c11 conversation claim --kind <k> --cwd "$PWD"` so the surface has *something* before the TUI fires its first hook. For TUIs that never fire hooks, this is the only push-side signal the strategy ever sees.

## State machine

```
            ┌──────────────────────────────┐
            │                              │
            ▼                              │
    ┌────────────┐   wrapper claim   ┌────────────┐
    │ (no ref)   │ ─────────────────▶ │  unknown   │
    └────────────┘                    └────────────┘
                                            │
                          first hook /      │
                          first scrape      ▼
                                       ┌────────────┐
                                       │   alive    │
                                       └─────┬──────┘
                                             │
                                             ├── TUI exits via user `/exit`
                                             │   (and isTerminatingApp == false)
                                             ▼
                                       ┌────────────┐
                                       │ tombstoned │  ← do not auto-resume
                                       └────────────┘

                                             │
                                             ├── c11 shutting down (isTerminatingApp)
                                             │   OR c11 crashed
                                             ▼
                                       ┌────────────┐
                                       │ suspended  │  ← auto-resume on next launch
                                       └────────────┘
```

`unknown` is the resting state when c11 came up after a crash and found a ref it cannot classify. Strategy re-runs pull-scrape, then transitions to `suspended` (re-trustworthy) or `tombstoned` (TUI's session file is gone).

`alive → tombstoned` only fires when the strategy can determine "user explicitly ended this." For claude that's the SessionEnd hook *and* `isTerminatingApp == false`. For codex (no hook), the strategy cannot distinguish; it never tombstones autonomously. It treats every absent-on-restore session-file as `tombstoned`.

`alive → suspended` fires when c11 starts shutting down. The store walks all surfaces, sets active refs to `suspended`, then the snapshot is written.

## Crash recovery

**The marker:** c11 writes `~/.c11/runtime/shutdown_clean` (a one-byte file) at the start of `applicationWillTerminate`, deletes it at the end of `applicationDidFinishLaunching`. If on launch the file is absent, we crashed (or sleep-killed, or power-died, or kernel-panicked).

**On crash:**

1. Load the most recent snapshot.
2. For every active ref in the snapshot, transition state to `unknown`.
3. Run pull-scrape for every `unknown` ref. Update or tombstone based on result.
4. Proceed with normal restore, including resume.

The pull-scrape on crash recovery is the "primary source on death." Push values are not trusted until they are fresh again.

## Per-TUI strategies

### Claude Code

- **Capture push:** SessionStart hook → `c11 conversation push --kind claude-code --id <session_id> --source hook`. Writes the ref with `state = .alive`.
- **Capture pull:** Scrape `~/.claude/sessions/` (path verified at impl) for the most recent session matching the surface's cwd. The strategy stores cwd in the ref payload to narrow the scrape.
- **State transitions:** SessionEnd hook fires → `c11 conversation tombstone --kind claude-code --id <session_id> --reason session-end-hook`. The CLI checks `isTerminatingApp` (queryable via socket) and, if true, no-ops. If false, tombstones.
- **Resume:** `typeCommand("claude --dangerously-skip-permissions --resume <id>", submitWithReturn: true)`.

### Codex

- **Capture push:** Wrapper at launch issues `c11 conversation claim --kind codex --cwd "$PWD"`. The store mints a placeholder id (`<surface-uuid>:<launch-ts>`). No hook surface from codex itself.
- **Capture pull:** Scrape `~/.codex/sessions/*.jsonl` (path verified at impl). Filter: same cwd as the surface AND modification time ≥ wrapper-claim time AND modification time ≥ surface's last activity timestamp. Picks the matching session id; updates the ref's `id` from placeholder to the real one.
- **State transitions:** No hook to detect tombstone. Treat absent-on-restore as `tombstoned`.
- **Resume:** `typeCommand("codex resume <session-id>", submitWithReturn: true)` — the *specific* id, not `--last`. This is the upgrade.

### Opencode

- **Capture push:** Wrapper claim only.
- **Capture pull:** TBD at impl — opencode's session storage needs reverse engineering. If none exists, strategy is fresh-launch-only.
- **Resume:** `launchProcess(argv: ["opencode"], env: [:])`.

### Kimi

Same shape as opencode. Strategy starts as fresh-launch; grows scrape support if/when kimi's session storage is mapped out.

### Future kinds

A new kind is one Swift file implementing the two functions. No app-wide changes. The `ConversationStrategyRegistry` is a hardcoded enum-shaped struct; we are not building a plugin system.

## Wrapper changes

Wrappers shrink to:

```bash
# Pseudo-shape; real wrappers stay bash.
1. Detect c11 environment (CMUX_SURFACE_ID + live socket). Pass through if absent.
2. c11 conversation claim --kind <my-kind> --cwd "$PWD" >/dev/null 2>&1 &
3. (For TUIs with hooks: inject the necessary flags so hooks fire `c11 conversation push`.)
4. exec "$REAL_TUI" "$@"
```

The current `c11 claude-hook session-start` collapses to `c11 conversation push --kind claude-code --id <id-from-stdin>`. The `claude-hook` CLI subcommand stays as a thin translator (parses the SessionStart JSON payload, calls `conversation push`) so existing hook configurations keep working. Metadata-writing logic (`claude.session_id` reserved key) moves out.

The codex wrapper gains the `claim` call (the current wrapper omits this; it only sets `terminal_type` via `set-agent`). The `set-agent --type` call stays for sidebar chip rendering and other metadata consumers.

## CLI surface

```
c11 conversation claim --kind <k> [--cwd <path>] [--id <id>]
c11 conversation push --kind <k> --id <id> --source <hook|scrape|manual> [--payload <json>]
c11 conversation tombstone --kind <k> --id <id> [--reason <text>]
c11 conversation list [--surface <id>] [--workspace <id>] [--json]
c11 conversation get --surface <id> [--json]
c11 conversation clear --surface <id>
```

`list` and `get` are observability for operators and agents. `clear` is the explicit "wipe this surface's conversations" escape hatch.

All commands resolve `--surface` from `CMUX_SURFACE_ID` if unset, **without falling back to focused-surface**. If the env var is missing and no flag was given, the command errors out.

## Snapshot integration

### Per-workspace embedded (source of truth)

Every workspace snapshot grows a `surface_conversations: { surface_id: SurfaceConversations }` field alongside the existing `panels` array. On capture, the `ConversationStore` is asked to dump active+history refs for every surface in the workspace; the result writes into the snapshot.

On restore, the executor reads the field, populates the in-memory `ConversationStore` for the new surfaces, then schedules the resume pass that already exists in `Workspace.scheduleAgentRestart` — but the pass now consults `ConversationStore` + strategy registry instead of the inline `pendingRestartCommands` registry lookup.

### Global derived index (read-only view)

A `~/.c11/conversations.index.json` aggregates active-and-suspended refs across all known snapshots. It is a *derived* view, rebuilt on launch by scanning `~/.c11-snapshots/`. If corrupted or out of sync, rebuilt without ceremony.

v1 ships the in-memory build only; the on-disk file lands when caching becomes worth it. The persistent file is *not* the source of truth; the snapshots are. This index enables future UI ("bring back any past claude conversation into a new pane") without locking us into that UI now.

## Blueprints

Blueprints stay state-free templates. They do **not** carry conversation refs. Spawning a blueprint creates fresh surfaces with no active conversations; the wrapper-claim flow populates conversations from the moment the user starts the TUI.

The Conversation primitive does not appear in the blueprint schema. If we ever ship "blueprints with pinned conversations" (v2+ feature), it lands as an additive optional field; v1 makes no provision for it but does not foreclose it.

## Conversation history

Persisted shape is `SurfaceConversations { active: Ref?, history: [Ref] }`. v1 only ever populates `active`; `history` is empty in writes and ignored on reads.

When we ship history (v1.x or v2):

- Tombstoned refs move to `history` rather than being deleted.
- Surface UI surfaces history as a "previous conversations" picker.
- The strategy can resume from history with the same `resume(surface, ref)` call.

No code changes required to v1 to enable this; just do not break the field shape.

## Remote / cloud forward-compat

`ConversationRef.kind` and `ConversationRef.id` are opaque to the store. A future `claude-code-cloud` strategy interprets `id` as a remote conversation URL; its `resume` action might be `launchProcess(argv: ["claude-cloud", "resume", id])` or `typeCommand` of a CLI invocation. The `ConversationStore` does not need to know.

The same primitive could host SSH-tunneled remote agents, web-hosted Claude conversations, or future agent services. v1 ships local strategies only; the seam is what matters.

## ResumeAction execution

The current `Workspace.scheduleAgentRestart` already runs on the main actor with a 2.5 s delay (`SessionPersistencePolicy.agentRestartDelay`). It stays. The change is what runs inside it.

```swift
private func scheduleAgentRestart(...) {
    let plans = pendingRestartPlans(from: snapshot)  // [(panelId, ResumeAction)]
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        for (panelId, action) in plans {
            self?.execute(action, on: panelId)
        }
    }
}

func execute(_ action: ResumeAction, on panelId: UUID) {
    switch action {
    case .typeCommand(let text, let submit):
        guard let panel = panels[panelId] as? TerminalPanel else { return }
        if submit { TextBoxSubmit.send(text, via: panel.surface) }
        else      { panel.surface.sendText(text) }
    case .launchProcess(let argv, let env):
        guard let panel = panels[panelId] as? TerminalPanel else { return }
        panel.runProcess(argv, env: env)
    case .replayPTY(let scrollback):
        guard let panel = panels[panelId] as? TerminalPanel else { return }
        panel.surface.appendScrollback(scrollback)
    case .composite(let actions):
        actions.forEach { execute($0, on: panelId) }
    case .skip(let reason):
        Diagnostics.log("conversation.resume.skipped panel=\(panelId) reason=\(reason)")
    }
}
```

## Concurrency

The `ConversationStore` is accessed from multiple threads:

- Socket handlers (off-main) on every CLI call (`claim`, `push`, `tombstone`, `list`).
- Main actor on snapshot read/write at quit + restore.
- Autosave timer thread on pull-scrape ticks.

Use a serial dispatch queue for store mutations + reads; expose `async` accessors. State transitions are the critical-section boundary; capture/resume strategy calls happen outside the lock.

## Failure modes and how each is handled

| Failure | Today | With ConversationStore |
|---|---|---|
| Hook fires after shutdown begins | Clears metadata | `isTerminatingApp` check; no transition |
| Hook env strips `CMUX_SURFACE_ID` | Silently routes to focused | CLI errors out; no write; pull-scrape catches up |
| TUI crashes before hook fires | No ref captured | Pull-scrape on next autosave catches it |
| c11 crashes | Snapshot may be stale | `unknown` transition + forced pull-scrape on launch |
| Two panes same TUI same cwd | "last wins" | Strategy reconciles by per-surface activity timestamp |
| Sleep / power-off mid-session | Same as crash | Same as crash |
| TUI session file deleted out-of-band | Silent stale resume | Pull-scrape returns nothing → tombstone |
| Wrapper not on PATH (system update) | Silent loss of capture | Wrapper-claim absent → strategy degrades to pull-scrape only; no regression |

## Testing

- **Unit tests** for each strategy's `capture` and `resume` against fixture session-storage layouts. No live TUIs.
- **Unit tests** for the state machine: every transition exercised, including the `isTerminatingApp` gate.
- **Unit tests** for crash recovery: simulate missing `shutdown_clean` flag, verify `unknown` transition + pull-scrape behavior.
- **Integration test** for snapshot round-trip: workspace with N surfaces, each with a different conversation kind, captured + restored, refs match.
- **Manual QA matrix** (operator-driven): the 4-pane Claude/Codex test that exposed the bug today, plus crash-recovery (`kill -9 c11`), plus mixed-kind workspaces.

We do not ship a regression test that lives in `WorkspaceSnapshotRoundTripAcceptanceTests.swift` for the bug observed today; we ship the architecture that makes the bug structurally impossible.

## Rollout

- **No migration.** Pre-release software. The existing `claude.session_id` reserved key in surface metadata is dropped. Snapshots in flight that contain it are read once for backward-compat at v1.0 launch (one release window) and dropped from snapshots written after.
- **No feature flag for the architecture.** The new design is the only design. The current `agentRestartOnRestoreEnabled` policy flag stays as the global on/off (off-by-default with env-var to flip on, until a v1.0 promotion in a later release).
- **0.44.0 ships with the conversation-store as its marquee feature.** The other 25+ upstream picks ride along. The held PR #94 gets the implementation diff stacked onto its branch (or, more likely, the branch is recreated from main after impl merges to keep history clean). The current 0.44.0 changelog entry for "Claude Code session resume across c11 restarts" gets rewritten to describe the conversation-store version.

## Out of scope (do not ship in this work)

- Cloud / remote agent strategies.
- Conversation history UI ("show me past sessions").
- Plugin system for third-party strategies.
- Cross-machine conversation portability.
- "Resume conversation X in a new pane in a fresh workspace" UX (the global index gets an in-memory build; UI to consume it is a later piece).
- Replacing the current `claude-hook` CLI surface (stays as the hook entry point; just routes to `conversation push`).
- Persisting the global derived index to disk (in-memory only in v1).
- Any change to blueprint schema.

## Open questions for plan review

These are the calls I want pressure-tested before implementation starts:

1. **Pull-scrape cadence.** Every autosave tick (~30 s, confirm) per TUI per surface. Is the I/O cost acceptable? Alternative: only at quit + on-demand at every push.
2. **Tombstone determination for hookless TUIs.** Codex's strategy cannot distinguish tombstone from suspended. Current rule: "absent-on-restore = tombstone." Better signal possible? (Reading codex session-file `last_message_role` to detect "session looked complete"?)
3. **Hook payload routing.** Should `c11 claude-hook session-start` keep its full handler (existing telemetry breadcrumbs + sessionStore) or fully collapse to `c11 conversation push`? The latter is cleaner; the former preserves the existing breadcrumb taxonomy.
4. **Strategy resolution at restore.** When the snapshot says `kind = "claude-code-2"` but no strategy is registered, what happens? Skip with `Diagnostics.log` (proposal) or hold the ref in the store and offer a "no strategy" UI? Lean toward skip.
5. **Wrapper-claim id format.** `<surface-uuid>:<launch-ts>` is suggested. Better placeholder shape? Strategies need to recognize it as "still a placeholder" during pull-scrape so they know to replace.
6. **`shutdown_clean` location.** `~/.c11/runtime/shutdown_clean` — alternatives (per-c11-instance file, snapshot directory, sentinel inside the snapshot itself)?
7. **`history` field on disk.** Write as empty array, or omit from JSON? Codable defaults make this near-no-op either way.
8. **`ResumeAction.replayPTY`.** Premature? No v1 strategy emits it. Could ship without and add when we have a use case.
9. **Wrapper PATH gating.** Should the wrapper short-circuit when `CMUX_DISABLE_AGENT_RESTART=1`? Today it unconditionally writes the claim regardless of restart policy; the policy only gates the *resume* pass. Cleaner if the wrapper bails too.
10. **In-flight 0.44.0 changelog rewrite.** The current draft entry for "Claude Code session resume across c11 restarts" (#89) needs a rewrite to describe the conversation-store version. Done at impl time, but plan-review should know to expect it.
11. **Concurrency model specifics.** Serial dispatch queue is named above; is an actor (Swift concurrency) cleaner here? c11 is gradually moving to actor-isolation; this might be a good place to push that.
12. **Where does `isTerminatingApp` get queried by the CLI?** New socket method `system.is_terminating`, or piggyback on an existing one? CLI tombstone command needs a way to ask.

## References (current code; line numbers will shift)

- `Sources/AgentRestartRegistry.swift` — current registry; replaced by per-kind strategies.
- `Sources/Workspace.swift:336-426` — current `pendingRestartCommands` + `scheduleAgentRestart`; refactored to consume `ResumeAction`.
- `Sources/AppDelegate.swift:2765-2783` — `applicationShouldTerminate` / `applicationWillTerminate` snapshot capture; gains `shutdown_clean` write.
- `CLI/c11.swift:13244-13582` — current `runClaudeHook`; refactored to route through `conversation push|claim|tombstone`.
- `CLI/c11.swift:7238-7266` — current `resolveSurfaceId`; the `nil → focused-fallback` is the source of the env-loss footgun. Fallback removed for the conversation CLI surface; behavior preserved (with deprecation warning) elsewhere if external callers depend on it.
- `Resources/bin/claude` — current wrapper; rewritten smaller.
- `Resources/bin/codex` — current wrapper; gains `c11 conversation claim` call.
- `Sources/SessionPersistence.swift` — snapshot schema; gains `surface_conversations` field.
- `Sources/WorkspaceSnapshotStore.swift` — snapshot read/write; round-trips the new field.
- `notes/session-resume-fix-plan.md` — the C11-24 hotfix plan, now obsolete.
