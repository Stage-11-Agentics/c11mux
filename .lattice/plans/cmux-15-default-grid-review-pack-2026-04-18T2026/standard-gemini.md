# Standard Plan Review

### Executive Summary
The intent of utilizing massive 4K real estate is logical, but the plan has severe mathematical and architectural flaws. Constructing a 3x3 grid through sequential binary splits without adjusting the dividers will result in extremely lopsided columns and rows (e.g., 50% / 25% / 25% instead of 33% / 33% / 33%). Additionally, deferring this layout until after the first surface renders will cause a jarring visual "pop-in" effect—a massive layout shift 0.5s after the user opens a new workspace. The plan requires fundamental rethinking around how and when splits are calculated.

### The Plan's Intent vs. Its Execution
**Intent:** Provide a uniform parallel-work layout perfectly sized to the user's monitor without requiring manual split commands. 
**Execution:** The algorithm outlined in the plan fundamentally fails to produce a uniform grid. Because `bonsplit` uses binary partitions dividing the *available* space in half on every split, sequentially splitting the "right" or "bottom" pane results in progressively narrower subdivisions (halves, quarters, eighths). The intent of a clean grid fails at the math layer. 

### Architectural Assessment
The choice to hook the layout creation into `spawnDefaultGridWhenReady` (mirroring `sendWelcomeWhenReady`) is an architectural misstep. The welcome layout does this because it needs to execute shell commands (`sendText`) on the newly minted Ghostty surfaces once they are ready. The default grid does not require shell commands. Waiting for a surface to render only to fracture it instantly into 9 panes is a poor user experience. The tree structure should be built before the view mounts.

Additionally, `Workspace.newTerminalSplit(from: UUID, ...)` requires a `UUID`, but the plan's pseudo-code passes `TerminalPanel` objects directly (`panes[i-1]`). Even more critically, `newTerminalSplit` does not accept a `dividerPosition` parameter, nor does `BonsplitController.splitPane` return the newly created split node's ID, leaving the plan with no mechanism to adjust the lopsided dividers.

### Is This the Move?
9 panes (3x3) by default for a 4K monitor is a drastically aggressive assumption. While 4K has the pixels to support it, 9 simultaneous shell prompts and Ghostty surface allocations on every `Cmd+N` might introduce significant CPU spikes, visual overload, and completely violate the "host and primitive, not configurator" principle of lightweight terminals. A 2x2 grid (4 panes) is a much safer maximum default, even on larger displays. 
Furthermore, enabling this behavior entirely via a hidden `UserDefaults` key without a GUI toggle guarantees friction for users who prefer single-pane workflows.

### Key Strengths
- **Signal Selection:** Utilizing pixel dimensions (`screen.frame`) rather than unreliable physical inch conversions is the correct, deterministic approach.
- **Opt-Out Safety:** Respecting saved layouts (which utilize `restoreSessionSnapshot`) ensures explicit user intent is never clobbered.
- **Rollout Strategy:** Hiding the feature behind a `UserDefaults` feature flag allows for a safe, revertible rollout.

### Weaknesses and Gaps
1. **Lopsided Grids:** The binary split sequence algorithm produces 50%/25%/25% distributions. Equal column and row sizing requires either manually tweaking `dividerPosition` or a new API in `BonsplitController`.
2. **Visual Pop-in:** Asynchronous layout generation causes a jarring layout shift every time a workspace opens, turning a smooth interaction into a janky flash.
3. **Resource Spike:** Creating 9 Ghostty surfaces and launching 9 shells simultaneously might induce the exact typing and system latency `CLAUDE.md` explicitly warns against.
4. **Missing API Capabilities:** The necessary API to define or adjust `dividerPosition` directly via `Workspace.newTerminalSplit` does not exist. 

### Alternatives Considered
- **Synchronous Tree Construction:** Pass the `screenFrame` directly into `TabManager.addWorkspace` and compute the full Bonsplit tree (with correct divider proportions) synchronously inside `Workspace.init`, before the views are even mounted. This eliminates the pop-in entirely.
- **Proportional Split Helpers:** Extend `BonsplitController` or `Workspace` with a native `splitEvenly(into:)` method that automatically calculates and sets `dividerPosition` ratios as the binary tree is built, saving every consumer from doing fractional math.

### Readiness Verdict
**Needs rethinking.** The plan cannot be implemented as written without resulting in severely uneven pane sizes and a jarring visual pop-in. The core algorithm must be redesigned, and the architectural timing of the split should be synchronous.

### Questions for the Plan Author
1. How do you plan to achieve equal column/row sizes when sequential binary splits naturally halve the remaining space?
2. Given `Workspace.newTerminalSplit` does not accept a `dividerPosition` and `bonsplit` does not readily expose the new split ID, how will you correct the lopsided dividers?
3. Can we build the split tree synchronously within `Workspace.init` or immediately after workspace creation to avoid the 0.5-second visual "pop-in"?
4. Are you confident that spawning 9 simultaneous Ghostty surfaces and shells is a safe performance default, or should we cap the layout at 2x2 (4 panes)?
5. `Workspace.newTerminalSplit` takes a `UUID`, but your loop algorithm passes the `TerminalPanel` object directly. How will you reference the correct IDs in the final implementation?