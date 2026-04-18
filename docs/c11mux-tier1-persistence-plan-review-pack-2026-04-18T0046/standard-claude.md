# Standard Plan Review — c11mux-tier1-persistence-plan (Claude)

**Reviewer:** Claude (Opus 4.7)
**Plan file:** `docs/c11mux-tier1-persistence-plan.md`
**Date:** 2026-04-18

---

## Executive Summary

This is a **genuinely good plan**. It picks a clean, tractable line through a problem that is objectively messy — restart durability for features (M1/M3/M7) that were shipped against an in-memory store the whole time — and it does so without detouring into the Tier 2 rabbit hole (PTY persistence via `cmuxd`). The decomposition into five phases is principled, not cosmetic: Phase 1 removes a structural blocker (the `oldToNewPanelIds` remap) that every subsequent phase would otherwise have to route around; Phases 2 and 3 turn two adjacent in-memory stores durable using the same snapshot mechanism; Phase 4 delivers the observe-from-outside resume affordance the motivation promised; Phase 5 makes it user-visible.

The single most important thing: **Phase 1 is load-bearing, and its risk surface is understated.** Stable panel UUIDs change a runtime invariant — today a fresh `UUID()` is minted on every restore, which means every downstream map is *guaranteed* to have a disjoint keyspace between boots. Dropping that guarantee is correct, but at least three places in the codebase (the M2 store, status entries, scrollback replay) currently survive because the remap acts as a firewall. The plan names the remap call sites but I'd like more certainty that it has enumerated *all* surface-id-keyed state — especially anything that is keyed by surface id but lives outside `Workspace.swift` (the socket listener, any external consumers that cached surface ids, Lattice if it's watching).

The plan is **ready to execute with minor revisions** (see Readiness Verdict). Phase 4's scope is the one place I'd push back on — it's doing more than it says it is.

---

## The Plan's Intent vs. Its Execution

**Stated intent:** (1) make M-series features survive restart, (2) offer a one-tap recreate/resume for destroyed sessions without hooking into the agents.

**Does execution match intent?** Mostly, with one drift:

- Phase 1–3 execute the first half cleanly. Metadata persistence is a direct, additive extension of the snapshot format. The status-entry "stale" flag is a nice touch that preserves the "ephemeral" semantics of the original decision while still surfacing the information operators need.
- Phase 4 is where intent drifts. The plan frames it as "the Claude session index — observe from outside." The motivation invokes the `feedback_c11mux_no_agent_hooks.md` memory correctly. But the execution choice — **write `claude_session_id` into surface metadata on every focus event, 1s debounced** — is actually a *side-effecting inference*, not pure observation. It's writing to a persistent store based on a best-guess heuristic (most-recent jsonl in a cwd-slug directory). That's closer to M1's `terminal_type` heuristic than to a pure index. The plan should own this honestly: Phase 4 is *heuristic source attribution for Claude sessions*, and it belongs in the same precedence chain as M1 (`source = heuristic`, overridable by `declare`/`explicit`).
- Phase 5 then trusts that `claude_session_id` at face value to populate the resume chip. If the heuristic is wrong (user cd'd between sessions, multiple concurrent Claude sessions in the same cwd, a cold terminal in a Claude-heavy cwd that never ran Claude), the resume chip will offer to resume the wrong session. This is not fatal, but the plan doesn't address it.

**Recommendation:** Reframe Phase 4 as "Claude-session heuristic source" and route its writes through `SurfaceMetadataStore.setInternal(..., source: .heuristic)`. Then the plan's existing "external write wins" rule (open question 4) falls out of the M2 precedence chain for free.

---

## Architectural Assessment

**Decomposition quality: good.** Each phase is independently landable, independently testable, and independently revertable. The dependency graph (1 → 2,3; 2 → 4; 2,4 → 5) is honest — there's no hidden "this only works if phase N+2 ships" coupling.

**Is this the right structure?** Mostly yes. Two architectural observations:

1. **Phase 1 is a prerequisite, but the plan treats it as "also Phase 1."** Stripping the panel-id remap is the kind of change that either works completely or doesn't. It doesn't *need* the rest of this plan to land to be worth doing — it simplifies restore logic, improves debuggability, and removes a class of bugs (any call site that incorrectly uses the post-remap id when it should use the pre-remap id, or vice versa). I'd consider shipping Phase 1 as its own small, orthogonal cleanup PR *before* this plan begins, so that if it uncovers unknown-unknowns (see Weaknesses below), those don't block the metadata work.

2. **There's no `PersistenceCoordinator` layer, and the plan is right not to invent one.** The alternative architecture — "create an orchestrator that owns metadata, status, and scrollback persistence, and delegates to sub-stores" — would be a classic over-abstraction trap. Every one of the three things being persisted lives in a different place (`SurfaceMetadataStore`, `Workspace.statusEntries`, per-panel terminal scrollback) and has different validation, truncation, and restore semantics. The plan's "each store owns its own save/load hook, called by `AppSessionSnapshot.build`" structure is correct. Resist future pressure to collapse this into a unified store.

**Alternative framing I'd consider:** Invert Phase 1 and Phase 2. Make `SurfaceMetadataStore` persistent *first* with a remap (temporarily writing through the old→new mapping), then strip the remap in Phase 2. This would mean Phase 2 gets a "no-op" rename step where metadata keys are retargeted post-restore, but it also means Phase 2 can ship independently without betting on Phase 1's correctness. The plan's ordering is defensible (cleaner end state, no throwaway remap code), but the inverted ordering is lower-risk. Worth naming and deciding explicitly.

---

## Is This the Move?

**Yes, with one bet I'd reconsider.** Common failure patterns for plans like this, and how this one fares:

- **"Let's also persist X while we're in there"** — plan avoids this well. Explicit "does not persist titleBarCollapsed" list is good discipline.
- **"Schema versioning deferred forever"** — plan sensibly keeps v1 and uses optional fields. Correct for additive changes. The failure mode is when someone later adds a *non-optional* field or changes a type and forgets to bump the version. Adding a `// When adding required fields or changing types, bump SessionSnapshotSchema.currentVersion` comment near the struct would cost nothing.
- **"The heuristic/index will stay in a happy path forever"** — Phase 4's Claude index is where I'd worry. Reading `~/.claude/projects/` is fine until Claude changes its on-disk format (they do, semi-regularly — there was a schema change in late 2025) or until a user has 10,000 sessions in a cwd and the "cheap line count" isn't so cheap anymore. Plan mentions 30s caching, which helps, but doesn't mention format versioning for the jsonl files it's parsing.
- **"Tests test the plumbing, not the outcome"** — the plan's test list is mostly behavioral (round-trip via socket, verify via CLI) which is the right instinct. The exceptions are the UI tests in Phase 5 which the cmux testing policy warns against running locally — those need to go through CI. The plan doesn't say that explicitly.

**The bet I'd reconsider:** Phase 4 ships Claude-only with a promise of "Codex/Gemini parity when the format stabilizes." Historically these "we'll do it later" abstractions either (a) never get done, leaving Claude as the one privileged agent, or (b) get done asymmetrically, yielding three different code paths. Given that c11mux is agent-agnostic by design (per the feedback memory), shipping Claude-first is a philosophical tension. I'd argue for *either*:
  - Ship Phase 4 with a `SessionIndex` protocol from day one (the plan says "avoid premature abstraction" — but one concrete impl + a protocol is not premature; two concrete impls with a protocol extracted later tends to produce a bad protocol), OR
  - Explicitly defer Phase 4 and 5 until Codex's session store is understood, shipping only 1–3 first.

---

## Key Strengths

- **Phase 1 is framed as a prerequisite, not a nice-to-have.** Recognizing that stable UUIDs unblock *everything downstream* is exactly right. This is the kind of foundational simplification that plans often defer and regret.
- **"Schema stays at v1, new fields optional"** is correct for the change being made. Bumping the version here would be over-conservative — old snapshots decode fine, old apps reading new snapshots ignore unknown keys. The plan's instinct matches how `JSONDecoder` actually behaves.
- **`staleFromRestart` flag is a small, well-considered piece of design.** It resolves the tension between "these entries are meaningful historical context" and "displaying them as live is misleading." Greying out / italicizing is the right UI treatment — it doesn't require a schema bump on the sidebar rendering path.
- **Companion-plan hand-off is explicit.** The plan directly claims the parking-lot item from the workspace-metadata plan and names it. No ambiguity about who owns what. This is the kind of cross-plan hygiene that prevents the two agents from stepping on each other.
- **Autosave fingerprint incorporation is named.** I checked `AppDelegate.sessionFingerprint` at `AppDelegate.swift:3548` — it's real, and autosave does skip unchanged ticks. A metadata revision counter is the right integration (option 1 in the plan). If the plan had missed this, autosave wouldn't fire on metadata-only changes and the feature would silently stop working between user-visible triggers. Catching this in the plan is good diligence.
- **Rollout table is honest about "indirect" vs "direct" user visibility.** Phase 2 fixes things operators don't know are broken; Phase 3 adds visible stale-chip treatment; Phase 5 is the feature they'll ask for. This is the right sequencing for both engineering risk and user trust.

---

## Weaknesses and Gaps

- **Phase 1's "Risks" section is thin.** It covers UUID collision (negligible, correctly dismissed) but not the real risk: *unknown-unknowns in external consumers of panel ids.* The socket API exposes surface/panel ids to CLIs and agents (Lattice in particular). If an agent cached a panel id before the restart and passes it back post-restart, today that id is stale (new UUID generated) and the agent gets a graceful `surface_not_found`. With stable UUIDs, the id is *valid again* — which might actually be what consumers want, but it's a semantic change that deserves a paragraph. The plan should audit: (a) is any surface id persisted outside cmux? (b) if so, does "stable across restart" change the caller's expectations? Lattice integration in particular should be checked.
- **Scrollback replay interaction is underspecified.** `SessionScrollbackReplayStore.replayEnvironment` writes a tempfile per panel and passes the path via env var at panel creation. Today, the tempfile is cleaned up... when? I didn't trace this, but if the path includes the old UUID and panel creation now uses the same UUID, there's a chance of stale-tempfile reuse across multiple restarts. Probably fine, but Phase 1 should spot-check this path.
- **`staleFromRestart` isn't described in the snapshot format.** Phase 3 adds the field to `SidebarStatusEntry` but doesn't say whether it's *persisted* in `SessionStatusEntrySnapshot`. If an entry is stale, save again, then restore again — does it stay stale? If yes, the "next write clears it" rule becomes the only way to ever clear it, even after a subsequent graceful save. If no, the flag is lossy. Plan needs to say which.
- **Phase 3's "agent refresh clears the flag" assumes the agent will refresh.** What if the agent never runs again? The status entry stays marked stale forever. Open question 1 acknowledges this but doesn't resolve it. A 72-hour auto-clear is a reasonable default; I'd lean toward building that in, not parking the decision.
- **Phase 4's disk-scanning module has zero protection against a malicious or corrupted `~/.claude/projects/` tree.** A symlink loop or a malformed jsonl with a 100-char "first message preview" that's actually 10MB unparseable bytes. The plan says "read-only, graceful []" but doesn't name the failure mode. If the scan panics or hangs, the surface focus path hangs. Serial queue is good; a timeout on the scan wouldn't hurt.
- **Phase 5's "recreate" CLI is vague.** `cmux surface recreate [<surface-id>]` emits "a shell-paste-able one-liner" — but what format? A single command? A script? Does it include env vars (cwd, TERM)? This is the user-facing deliverable and it's described in one sentence. Needs a concrete example.
- **No migration story if Phase 1 lands and stalls.** If Phase 1 ships and Phase 2 is delayed, the app behaves fine (stable ids, still-ephemeral metadata). But if Phase 2 lands and gets reverted, the schema already has the new optional fields. Plan should note: reverting Phase 2 means dropping fields from the struct, which old app versions will silently ignore (fine), but newer versions with the revert will drop already-persisted user metadata on first save. Probably acceptable given optionality, but worth naming.
- **Testing policy tension.** The cmux `CLAUDE.md` explicitly says "Never run tests locally." Phase 3's "Visual regression: mount `SidebarStatusChip` with `staleFromRestart=true` in a hosting view" is exactly the kind of test that needs to run in CI (the `cmux-unit` scheme is OK, but the NSHostingView test category has historically been flaky in CI). Plan should either specify which scheme runs each test, or acknowledge the CI-vs-local split explicitly.
- **The plan doesn't discuss the socket-threading policy implications.** `CLAUDE.md` has explicit rules: "Do not use `DispatchQueue.main.sync` for high-frequency socket telemetry." Phase 2's metadata-store persistence needs to work with the existing off-main socket handlers — today `SurfaceMetadataStore` uses its own `DispatchQueue` and is off-main-safe. The save-hook (called from `AppSessionSnapshot.build` on the main actor) needs a clear rule: is it OK for main actor to call `store.snapshot(for:)` synchronously? The plan's `snapshot(for:)` signature says nothing about threading.

---

## Alternatives Considered

**Alternative 1: Keep the panel-id remap, make metadata keyed by a stable "surface slug" instead.**
Invent a new id (e.g., `workspace-id + spatial-position` or a user-visible slug), use it for metadata/status keys, and let the runtime `panelId` remain regenerated. *Worse* — introduces a second id system, and spatial positions shift when panels are added/closed mid-session.

**Alternative 2: Move the whole metadata blob into its own JSON file per surface, not into the session snapshot.**
A `~/.config/c11mux/metadata/<surface-id>.json` per surface. *Worse for v1* — fragments the persistence story (two files to keep in sync), makes atomic save harder, duplicates the infrastructure the session snapshot already has. Might make sense later if metadata gets large, but not now.

**Alternative 3: Skip the `ClaudeSessionIndex` entirely and require agents to write `claude_session_id` via `declare`.**
Pure observe-from-outside becomes pure agent-self-declaration. *Worse for the motivation* — the whole point is to recover surfaces whose agents are *gone*. If the only way to know the Claude session id is for Claude to have written it, we lose the recovery case when Claude has died. The on-disk scan is structurally necessary.

**Alternative 4: Ship Phase 4 + 5 first, persist nothing; populate `claude_session_id` at surface-focus and make the resume chip work immediately without restart at all.**
*Interesting.* This is actually a usable intermediate state: even before restart persistence works, operators get "resume Claude session" on any surface that has run Claude recently. But it doesn't deliver the "surface restart recovery" motivation, and the plan's ordering correctly front-loads the foundational pieces. The value is that Phase 4's logic could be built and tested independently before Phase 1 lands — might accelerate the Phase 4 critical path.

---

## Readiness Verdict

**Needs minor revision.** The plan is sound in its bones. Five specific revisions would take it from "ready modulo caveats" to "go-ready":

1. **Expand Phase 1's risk analysis** to include external consumers of panel ids (socket API, Lattice integration, cached ids in agent sessions). Audit all places panel ids cross a process boundary.
2. **Specify whether `staleFromRestart` is persisted across subsequent saves.** Two lines. Leaning: yes, it's persisted; the next live `sidebar.set_status` clears it; a time-based auto-clear (72h) is a follow-up, not open-question-parked.
3. **Reframe Phase 4 as "Claude-session heuristic"** and explicitly route writes through the M2 precedence chain at `source: .heuristic`. Removes the "external write wins" hand-wave from open question 4.
4. **Give Phase 5's `cmux surface recreate` a concrete output example.** One code block. What does the CLI emit for (a) a bare terminal with a directory, (b) a Claude surface with session id, (c) a browser surface?
5. **Name the testing split (CI vs. local unit).** Explicit per-phase: "python tests_v2 runs on the VM; Swift hosting-view tests run via `xcodebuild test -scheme cmux-unit` in CI; e2e tests trigger `test-e2e.yml`." This matters because the cmux testing policy is strict about this and a plan that says "add UI test" without specifying where it runs has landed as broken tests in the past.

None of these are blockers. None should take more than an afternoon to resolve. After revision, the plan ships.

---

## Questions for the Plan Author

1. **Panel-id audit.** Have you enumerated every place panel ids are persisted *outside* the session snapshot? Specifically: does Lattice cache panel ids? Does the socket API expose them to long-lived CLI sessions? If I restart cmux and an external process calls `surface.get_metadata` with a pre-restart id, today it fails gracefully — post-Phase-1, it succeeds with possibly-surprising data. Is that the desired behavior?

2. **Phase 1 ordering.** Would you consider shipping Phase 1 as a standalone PR before this plan starts, decoupling the panel-id cleanup from the persistence work? The benefit is isolating the risk; the cost is an extra roundtrip. Which outweighs?

3. **`staleFromRestart` persistence.** When a stale entry is saved into a new snapshot (via the 8s autosave, before the agent clears the flag), does the persisted entry retain the stale flag? If yes, should it "age out" after N hours even without an agent write? If no, what marker distinguishes "stale from the boot before this one" vs "freshly restored"?

4. **Claude session heuristic source.** Can Phase 4's `claude_session_id` write go through `SurfaceMetadataStore.setInternal(..., source: .heuristic)`, so that an agent's explicit `declare` or `explicit` write naturally wins? This would replace the bespoke "external write wins" rule in open question 4 with the existing precedence chain.

5. **Multiple concurrent Claude sessions in one cwd.** If a user has two Claude surfaces in the same cwd, both active, the heuristic will pick the most-recently-modified transcript for both. Is that acceptable, or does the heuristic need to be aware of which transcript a given surface "belongs" to? (E.g., by tracking when the surface started vs. when each transcript started.)

6. **Claude transcript format drift.** The jsonl format has changed at least once in Claude Code's history. Does `ClaudeSessionIndex` need to handle multiple format versions? What happens on a transcript it can't parse — silent skip, log, or surface an error?

7. **Size metric for metadata.** Open question 2 asks about a metric for real-world metadata sizes. Where would that metric live — OSLog, a debug dump command, a telemetry hook? Is there prior art in cmux for "field an engineer can grep" metrics?

8. **Codex/Gemini parity decision.** Will Phases 4 and 5 ship Claude-only as written, or will you extract a `SessionIndex` protocol up front? I've argued above for one of "ship both" or "defer both" rather than "ship one and abstract later." Which do you prefer?

9. **Phase 5 `cmux surface recreate` output format.** What's the concrete shape of the output? A single `;`-separated one-liner? A here-doc? A `#!/bin/bash` script fragment? Example for a Claude-session surface would settle this.

10. **Recovery-failure fallback chain.** Open question 5 names this: what exactly happens if `claude --resume <id>` fails? Is there a catch-all fallback ("start fresh") or does the terminal get an error message and wait for operator input? Who writes the error to the sidebar log — the CLI dispatcher or a separate Claude-failure handler?

11. **Title-bar collapse decision.** Non-persistence of `titleBarCollapsed` is a design call that might surprise users who build muscle memory around a collapsed title bar. Have you tested this assumption with any actual usage, or is it pure "simpler is better" reasoning? (This is probably fine, but it's an opt-out that deserves a one-line justification.)

12. **Agent-PID clearing.** Phase 3 keeps `agentPIDs` cleared on restore, correctly — a PID from a prior boot is meaningless. But the companion `statusEntries` that reference those PIDs (e.g., "claude_code Running") will now survive marked stale. Is the stale treatment strong enough visually to signal "this PID is gone, don't try to send a signal"? Or should stale status entries with PID-dependent meaning be filtered out?

13. **Autosave fingerprint implementation.** Option 1 (monotonic counter per mutation) is preferred. Where does the counter live — on the store instance, on the `Workspace`, on a global? If a workspace is closed and reopened, does its counter reset? (Probably irrelevant for correctness but matters for log interpretation.)

14. **Testing — local vs. CI split.** Phase 3's "Visual regression" test is the kind of NSHostingView-based test that has been flaky in this codebase. Will this run under `xcodebuild -scheme cmux-unit` (which the project considers "safe local") or does it need the full e2e harness (`test-e2e.yml`)? The plan doesn't specify.

15. **Interaction with in-flight M7 amendment.** The M7 amendment plan lists "Persistence across restart" as an M2 parking-lot item. This plan claims it. Is there coordination with the M7 agent to ensure they don't land a parallel persistence hook that conflicts? The `git status` shows `docs/c11mux-module-7-expandable-title-bar-amendment.md` as untracked and `Sources/SurfaceTitleBarView.swift` as modified — M7 work appears to be in-flight locally.

16. **Companion workspace-metadata plan overlap.** The workspace-metadata plan also extends `SessionWorkspaceSnapshot`. These two plans will both touch `Sources/SessionPersistence.swift` at `:330` (workspace snapshot) and `:243` (panel snapshot). Which lands first, and if they land simultaneously, who rebases? A named merge-order convention would prevent the classic "two plans, same struct, messy conflict" outcome.

17. **Scrollback-replay file lifecycle.** `SessionScrollbackReplayStore` writes tempfiles into `FileManager.default.temporaryDirectory/cmux-session-scrollback/`. With stable panel UUIDs, these filenames will be predictable across boots. Is cleanup happening today? If not, that's a latent leak regardless of Phase 1, but Phase 1 might make it slightly more predictable (and thus slightly easier to collide with).

---

## Closing Note

This plan reflects a clear understanding of the codebase and correct instincts about what to build vs. what to defer. My pushback is mostly "name the risks you already understand" and "close the Phase 4 abstraction decision." Given the author's self-awareness elsewhere in the document (the explicit "does not" appendix, the honest rollout table, the acknowledgment of the companion plan), I expect these revisions to be fast. Ship it.
