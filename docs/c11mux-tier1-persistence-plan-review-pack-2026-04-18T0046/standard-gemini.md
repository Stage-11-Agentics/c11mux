# Standard Plan Review

### Executive Summary
This is an exceptionally pragmatic and high-leverage plan. By separating "surface metadata and context persistence" (Tier 1) from "live PTY survival" (Tier 2), this plan delivers the vast majority of the perceived value—recovering the *context* and *intent* of a workspace—for a fraction of the engineering cost. The decision to observe Claude sessions from the outside (Phase 4) rather than waiting for agent-side hooks is a brilliant, unblocking move. This plan is structurally sound and ready to execute.

### The Plan's Intent vs. Its Execution
The intent is to prevent the M-series features (custom titles, roles, model labels) from vanishing on restart, and to provide a low-friction recovery path for the agents that were running. The execution aligns perfectly with this intent. Rather than fighting the ephemeral nature of processes, the plan embraces it: it saves the metadata, flags the process status as `staleFromRestart`, and offers a 1-click resume command. It turns a catastrophic loss of context into a minor speed bump.

### Architectural Assessment
The decomposition is excellent. Phase 1 (Stable panel UUIDs) is the quiet enabler: by dropping the `oldToNewPanelIds` remap, the codebase actually gets *simpler* while gaining the prerequisite for stable metadata mapping.
Opting to piggyback on the existing `SessionPanelSnapshot` (Phase 2) rather than building a parallel `SurfaceMetadataStore` persistence engine is the right architectural choice—it keeps the source of truth unified.

An alternative framing could have been a unified "Agent State Recovery Protocol" requiring agents to push their recoverable state to c11mux before exiting. The plan's choice to observe from the outside (Phase 4 disk scanning) is far superior because it requires zero cooperation from the agents, ensuring it actually ships.

### Is This the Move?
Absolutely. Projects like this often get bogged down trying to solve "perfect session resume" (Tier 2, moving PTY ownership to a daemon). That can take months. This Tier 1 plan gives operators their visual context back immediately and provides a "Resume" button that handles the 90% case. Prioritizing this over daemon-level PTY survival is exactly the right bet for maintaining product velocity.

### Key Strengths
*   **Simplification via Identity:** Removing `oldToNewPanelIds` (Phase 1) is a strong application of the principle that "identity should be immutable."
*   **Honest UX:** Marking `statusEntries` with `staleFromRestart` (Phase 3) is a masterclass in UI honesty. It doesn't lie to the user about the process being alive, but it doesn't throw away the context either.
*   **Outside-In Observation:** Phase 4's `ClaudeSessionIndex` relies on the filesystem as a public API. This decoupling pattern makes the integration robust against agent internal changes.

### Weaknesses and Gaps
*   **Disk I/O on Focus (Phase 4):** Scanning `~/.claude/projects/` on surface focus, even debounced and off-main, carries some risk. If an operator's Claude projects directory grows to tens of thousands of files over a year, or sits on a slow network mount, this scan could become a recurring CPU/IO tax.
*   **Stale Status Clutter (Phase 3):** If stale statuses are never aged out, an abandoned workspace will forever show greyed-out pills from months ago. The plan leans towards "let the user clear them," but without a bulk-clear affordance, this could become visual noise.
*   **UUID Stability Edge Cases (Phase 1):** While removing `oldToNewPanelIds` is correct, we must be absolutely certain that no downstream SwiftUI view or internal cache relies on the panel UUID *changing* to trigger a refresh or reset of transient view state upon restore.

### Alternatives Considered
*   **Hashing vs. Monotonic Counter for Fingerprint (Phase 2):** The plan considers hashing the dicts vs. a monotonic counter to trigger autosave. Hashing is deterministic but O(N); the monotonic counter is O(1) but relies on strict discipline to bump it on *every* mutation path. The plan prefers the counter, which is better for performance, provided the encapsulation in `SurfaceMetadataStore` is tight.

### Readiness Verdict
**Ready to execute.** The sequence of PRs is well-defined, and the prerequisites (Phases 1-3) can land invisibly before the UI surfaces them.

### Questions for the Plan Author
1.  **Phase 4 (Disk Scan) Scaling:** How does the `ClaudeSessionIndex` scan behave if the `~/.claude/projects/` directory contains thousands of old session files? Should we consider a bounded depth search or relying on mtime sorting provided by the OS before parsing JSONL?
2.  **Phase 3 (Stale Status):** If we do not age out stale status entries, do we need a "Clear Stale Statuses" context menu option on the workspace or sidebar so operators can clean up a dead workspace without manually closing panes?
3.  **Phase 1 (Identity):** Have we verified that `GhosttyTerminalView` or any other AppKit-wrapped components don't implicitly rely on receiving a new Panel ID to clear their internal buffers or caches upon restore?
4.  **Phase 4 (Association):** If an operator restores a session, the metadata already contains `claude_session_id` from Phase 2 persistence. Will the Phase 4 focus-debounced scan accidentally overwrite a valid restored session ID with a newer (but irrelevant) one if the user happened to run Claude in that directory outside of cmux while it was closed?
5.  **Phase 2 (Fingerprint):** If we use a monotonic counter in `SurfaceMetadataStore` to trigger `AppDelegate.autoSaveSessionIfNeeded`, is this counter strictly in-memory? (Assuming yes, since autosave diffs the fingerprint against the last save, an in-memory counter is sufficient, but worth confirming).