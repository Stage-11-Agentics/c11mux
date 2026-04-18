# TP-c11mux-tier1-persistence-plan-Gemini-Evolutionary-20260418-0046

### Executive Summary
This plan isn't just about surviving an app restart; it is stealthily transforming c11mux from a terminal multiplexer into a "workspace hypervisor" for AI agents. By decoupling an agent's rich contextual state from its transient PTY process, you are building the foundation for a durable memory layer. This could evolve into a system where AI workflows are persistent, shareable, and fully detached from the lifecycle of the host application or the terminal shell.

### What's Really Being Built
Beneath the surface of "retaining sidebar chips on restart," this plan builds an **out-of-process state management and resurrection engine**. Currently, terminal-based AI agents are ephemeral shell tasks. You are building the infrastructure to treat them as durable entities—almost like serialized virtual machines—whose UI (the terminal pane) can be detached, killed, and perfectly reattached or reconstructed later.

### How It Could Be Better
1. **Standardized Resurrection Protocol:** The `ClaudeSessionIndex` (Phase 4) is a brilliant "observe-from-outside" hack, but it doesn't scale infinitely. Instead of c11mux learning the internal storage formats of every new agent, c11mux should define a `resume_command` canonical key in the Module 2 metadata spec. Agents can self-report exactly how they should be resurrected (e.g., `cmux set-metadata --key resume_command --value "claude --resume {id}"`). The heuristic scan becomes a fallback, not the primary mechanism.
2. **From Recreate to Export:** Phase 5 introduces `cmux surface recreate`. This is incredibly powerful. Elevate this to `cmux workspace export`. By serializing the entire workspace layout, canonical metadata, and resume commands into a single JSON artifact, you unlock the ability to share complex, multi-agent workspace configurations between operators or machines.

### Mutations and Wild Ideas
*   **The "Fork" Primitive:** If c11mux can recreate a surface from metadata, it can duplicate it. An operator watching Claude go down a bad path could hit "Fork" (or `cmux surface fork`), and c11mux would spin up a new pane with the same CWD, same model, and same session ID. 
*   **Phantom Panes (Zero-Cost Scale):** A surface doesn't need to hold an active PTY to exist in the UI. A "resumable" surface could be rendered as a tombstone or a skeleton pane in the split tree. Click it, and it resurrects the agent. This allows an operator to have a workspace with 50 "parked" agent tasks that consume zero CPU or memory until explicitly interacted with.
*   **Time-Travel Debugging:** By snapshotting the metadata and the PTY scrollback simultaneously, c11mux is effectively taking save states of the agent's brain. This could evolve into letting an operator roll back a surface to what it looked like 3 snapshots ago.

### What It Unlocks
*   **Deep Linking into Agent Contexts:** External tools (like Lattice or Spike) could construct a `cmux://` URL that, when invoked, automatically generates the metadata and layout for a task, opens c11mux, constructs the panes, and boots the agents.
*   **Zero-Fear Environment:** OS updates, accidental window closures, or crashes lose their sting. The cognitive load of "setting up the workspace" drops to near zero.

### Sequencing and Compounding
The sequencing (identity -> storage -> data -> UI) is fundamentally sound. However:
*   **Phase 4 (Claude Index) could be decoupled:** Phase 4 feels like a specific integration masquerading as core plumbing. If you introduce the `resume_command` canonical key in Phase 2, Phase 4 simply becomes an external cron/daemon task that writes to that key, cleanly separating the "how we store resume state" from the "how we guess Claude's state."
*   **Compound Phase 3 with Phase 5:** Stale status entries (Phase 3) shouldn't just be passive indicators; they should be active triggers. Clicking a stale status pill in the sidebar should trigger the same Recovery UI (Phase 5) resume action as the title bar chip.

### The Flywheel
**The State Gravity Flywheel:**
As c11mux proves it can reliably hold and restore agent state, agent developers are strongly incentivized to push *more* context into c11mux's metadata store rather than hiding it in proprietary local databases. The more rich data agents push to c11mux, the more indispensable c11mux's UI (title bars, sidebars, recovery flows) becomes to the operator. This creates a moat: operators will demand that any new agent they use supports c11mux's metadata protocol natively.

### Concrete Suggestions
1.  **Add `resume_command` to Canonical Keys:** Amend the M2 spec to include a `resume_command` (string) key. Phase 5's Recovery UI should execute this string if present, completely bypassing the need to hardcode `claude --resume` logic into the UI layer.
2.  **Indefinite Stale Status:** In your open questions, you ponder aging out stale statuses. Do not age them out. An operator reopening a project after a two-week vacation will find it immensely valuable to see exactly what was running when they left, even if it is deeply stale. Let the user or the new agent clear it.
3.  **Lazy Loading for Restored Surfaces:** When a workspace is restored, don't spawn a dead shell `zsh` prompt in the panes that have a known resume path. Render a custom Ghostty surface that just says "Claude was running here. [Press Enter to Resume]". 

### Questions for the Plan Author
1.  If an agent proactively writes a `resume_command` to its metadata via the M2 socket before an app restart, shouldn't that take absolute precedence over the `ClaudeSessionIndex` heuristic scan?
2.  How does `cmux surface recreate` handle complex environment variables or specific shell environments (e.g., `nix develop`) that might have been active when the original agent was launched? Does it capture them, or just the `cwd`?
3.  Could the "stale" visual treatment (opacity/italics) be applied not just to the sidebar pills, but to the restored terminal scrollback itself, making it visually distinct from a live, interactive session?