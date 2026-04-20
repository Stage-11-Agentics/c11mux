# Adversarial Plan Review

### Executive Summary
This plan introduces a massively opinionated default behavior with severe technical and UX flaws. The core heuristic—using monitor pixel dimensions instead of window size—is fundamentally broken for macOS, where window management is standard. Furthermore, the proposed grid construction algorithm ignores the realities of a binary split tree, guaranteeing an asymmetric layout of decaying pane sizes rather than a balanced grid. Combined with the performance cost of spawning up to 8 new terminal instances asynchronously, this plan risks causing significant stuttering and UX disruption for every new workspace created by default.

### How Plans Like This Fail
- **Extrapolating edge cases into defaults:** A 3x3 grid of empty terminals inheriting the *exact same* working directory is a niche workflow masquerading as a universal default. Most users split when they have a specific task in mind.
- **Naïve algorithm design:** Ignoring the mathematical realities of the underlying data structure (`bonsplit` binary tree).
- **Ignoring the "Window Manager" user:** Assuming an app is running full-screen on a 4K monitor. Users who tile their apps will receive unreadable, cramped pane grids.
- **Asynchronous disruption:** Hooking into "surface-ready" means the grid spawns *after* the initial terminal appears. This introduces a jarring "flash-and-split" effect right when the user might start typing.

### Assumption Audit
1. **Assumption (Load-bearing, Fatal):** Monitor size is a better proxy than window size for real estate. *Reality:* If a user tiles their window to be 800x600 on a 4K display, spawning 9 terminals yields panes of ~266x200 pixels—completely unusable. The plan states it "tracks the thing the user actually cares about," but the user actually cares about the window's real estate, not the monitor's.
2. **Assumption (Load-bearing, Fatal):** A simple `for` loop of `workspace.newTerminalSplit` creates an even grid. *Reality:* `newTerminalSplit` splits the target in half. Splitting `A` horizontally yields `A(50%)` and `B(50%)`. Splitting `B` horizontally yields `A(50%)`, `B(25%)`, `C(25%)`. The algorithm outlined in the plan guarantees a completely unbalanced layout.
3. **Assumption:** Spawning 8 new `Ghostty` surfaces asynchronously is performant enough to be a default. *Reality:* Terminal instantiation is heavy. Doing 8 back-to-back will likely block the main thread or cause a stutter, interrupting the user's initial keystrokes.
4. **Assumption:** Users want up to 9 empty terminal prompts in the exact same directory automatically. *Reality:* This is visually noisy and provides little utility out of the box without specific commands running in them.

### Blind Spots
- **Focus and input interception:** Since the grid spawns asynchronously after the initial terminal is ready, what happens if the user types `ls -la[Enter]` immediately upon workspace creation? The rapid layout reflow or focus shifts might swallow or misdirect keystrokes.
- **Memory footprint:** 9 Ghostty surfaces per new workspace is a massive baseline overhead. What happens if a user creates three workspaces quickly?
- **Divider adjustments:** The plan contains absolutely no mention of `setDividerPosition`.
- **Window movement:** If the window is moved from a 4K display to a laptop display immediately after creation, does the grid remain 3x3? The plan says "Non-goal: Reshuffling panes," but the result is a permanently cramped workspace.

### Challenged Decisions
- **Opt-out rather than Opt-in (`defaultEnabled = true`):** Changing the fundamental behavior of "New Workspace" from a single clean terminal to 9 terminals is extremely aggressive. This should be disabled by default or driven by a first-run onboarding screen.
- **Monitor resolution vs. Window frame:** The plan explicitly rejects using the window size. This is hostile to anyone who uses window management utilities (Magnet, Amethyst, Rectangle) or simply prefers smaller windows.
- **Async Spawning:** Waiting for the initial terminal to become "ready" to spawn 8 more panes means the user sees one UI state, then another. It's not a seamless "land in a parallel-work layout."

### Hindsight Preview
- In six months, we'll be dealing with bug reports titled "Why is my third column half the width of the first column?" because the binary split algorithm wasn't balanced.
- We'll see complaints about the app being laggy when creating a new tab, tracked down to the instantiation cost of 9 simultaneous PTYs and surfaces.
- We'll have users on 4K monitors asking how to disable the "annoying automatic 9-pane split" because they keep their cmux window in a 1024x768 corner.

### Reality Stress Test
- **Disruption 1:** The user has a 4K monitor but uses a tiling window manager that restricts the app to 1/4 of the screen. *Result:* The app still spawns 9 terminals into a tiny box, rendering them all unreadable.
- **Disruption 2:** The user is a fast typist and hits `Cmd+T` followed by a command. *Result:* The async `spawnDefaultGridWhenReady` fires mid-keystroke. The terminal reflows, potentially breaking the shell prompt, and input is disrupted.
- **Disruption 3:** The user opens 5 new workspaces to start different SSH sessions. *Result:* 45 Ghostty surfaces are spawned, consuming massive amounts of memory and CPU for empty prompts.

### The Uncomfortable Truths
- The grid construction algorithm simply does not work as intended. It will not produce an evenly sized 3x3 grid without explicit `setDividerPosition` calls.
- The 9-pane layout is a novelty. It looks cool in screenshots but is highly impractical for real-world usage unless the panes are pre-populated with specific tasks (e.g., top, tail, build).
- We are confusing "monitor pixel density" with "user intention."

### Hard Questions for the Plan Author
1. How do you prevent geometrically decaying pane sizes (e.g., 50%, 25%, 25%) given that `bonsplit` relies on binary splits and your algorithm doesn't adjust divider positions?
2. If a user tiles their cmux window to 800x600 on a 4K display, why is it correct to spawn a 3x3 grid of 266x200 terminals?
3. What is the measured latency and main-thread blocking time of spawning 8 Ghostty surfaces simultaneously on an M1 machine?
4. Since the split happens asynchronously *after* the initial terminal is ready, how do we guarantee that user keystrokes entered during the delay aren't swallowed, misdirected, or visually corrupted by the layout reflow?
5. Why are we forcing 9 terminals sharing the exact same working directory on users by default instead of making this an opt-in feature?
