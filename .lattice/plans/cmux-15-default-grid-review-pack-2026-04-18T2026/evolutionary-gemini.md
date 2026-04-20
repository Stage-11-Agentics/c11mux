# Evolutionary Plan Review: CMUX-15 Default Grid

### Executive Summary
The biggest opportunity here isn't just auto-spawning a static grid; it's laying the foundation for **environment-aware, auto-adapting workspace templates**. By reading screen dimensions and reacting dynamically on workspace creation, c11mux is taking the first step toward intelligent layout orchestration that adapts not just to hardware, but eventually to project type, context, and developer intent.

### What's Really Being Built
Beneath the surface, this plan is building a **Workspace Templating Engine** driven by hardware context. The "default grid" is just the first template. The real infrastructure being laid down is the capability to intercept workspace creation, read environment signals (screen size), and systematically dispatch a sequence of splits (`gridSplitOperations`) before handing control to the user. You are building the programmatic API for layout generation.

### How It Could Be Better
- **Declarative Layout Abstraction**: Instead of hardcoding `gridSplitOperations` with nested `for` loops, represent layouts as a declarative data structure (e.g., a mini-AST mapping to bonsai trees). This makes it easier to test, serialize, and eventually allows users to define custom layouts without recompiling.
- **Math-Driven vs. Breakpoint-Driven**: Instead of arbitrary pixel breakpoints (3840x2160), use a proportional math-driven approach: `cols = max(1, screenWidth / optimalPaneWidth)`, `rows = max(1, screenHeight / optimalPaneHeight)`. This naturally scales to ultrawides and weird orientations without needing endless `switch` cases.
- **Progressive Disclosure**: Dropping 9 empty panes on a user might be cognitively overwhelming and resource-intensive. Consider a "ghost" grid where panes are visible as structural outlines but only fully spawn a Ghostty surface when focused or clicked.

### Mutations and Wild Ideas
- **Context-Aware Grids**: What if the grid is driven by the repository context? If the workspace opens in a Next.js project, it spawns a specialized grid: one pane runs `npm run dev`, another tails logs, and two are open for commands.
- **The "Infinite Canvas" Grid**: Don't constrain the grid to the physical monitor. Spawn a massive virtual grid (e.g., 5x5) and let the user pan around it like a map, only showing 2x2 or 3x3 on the screen at a time.
- **Agent-Driven Layouts**: Expose this grid-generation capability to agents via the socket. Claude Code could request `cmux layout 2x2` when it realizes it needs to run multiple parallel commands and show the user the output simultaneously.

### What It Unlocks
- **Template Ecosystem**: Once the programmatic grid generation exists, it unlocks "named layouts" that users can trigger via the Command Palette (e.g., "Layout: Code Review", "Layout: Systems Monitoring").
- **Smart Session Restoration**: The logic built to generate a grid programmatically can be repurposed to make session restoration more resilient when moving between different monitors (e.g., gracefully degrading a 3x3 saved session to a 2x2 grid when opened on a laptop).

### Sequencing and Compounding
1. **Ship the Layout Engine Primitive**: First, build a pure function `applyLayout(tree: LayoutTree, to: Workspace)`. This decouples the "how to split" from the "when to split".
2. **Ship the Hardware-Detection Mapping**: Bind the screen size logic to generate a `LayoutTree` and feed it to the engine.
3. **Ship User Overrides (Later)**: Once the declarative tree exists, it becomes trivial to let users specify a `default_layout.json` in their config. 
By shipping the layout engine as a distinct primitive, you make it reusable for saved session restoration and user templates.

### The Flywheel
The flywheel here is **Layout Discovery and Personalization**. The more users experience the default grid, the more they will want to tweak it. If you allow users to easily save their *current* pane arrangement as the new "Default Grid", they will craft perfect layouts for their specific workflows. This personalization makes the app stickier, reducing the friction of opening new workspaces to zero, which in turn leads to more workspaces being created.

### Concrete Suggestions
1. **Refactor Grid Construction**: Define a lightweight tree enum: `enum LayoutNode { case leaf, indirect case split(SplitOrientation, LayoutNode, LayoutNode) }`. Write a recursive function to apply this to a Workspace. This is much less brittle than imperative loops managing focus states.
2. **Handle Ultrawides Elegantly**: Use the math-driven approach mentioned above. Set `baseWidth = 1200` and `baseHeight = 700`. Calculate `cols = max(1, width / baseWidth)` and `rows = max(1, height / baseHeight)`. A 5120x1440 monitor naturally becomes 4x2, avoiding the need for special-case buckets.
3. **Protect Focus Routing**: The plan states `focus: false` for all splits. Ensure that the initial pane explicitly regains or retains focus at the *end* of the sequence, and that the order of pane creation doesn't mess up Cmd+[ navigation order.

### Questions for the Plan Author
1. Will 9 simultaneous Ghostty surfaces on a 4K monitor cause a CPU/memory spike on workspace creation? Should the surfaces be staggered or lazy-loaded?
2. If a user has a saved session with 1 pane, but opens it on a 4K monitor, does the saved layout truly win, or will the grid logic try to run? (The plan says "saved always wins", but ensure the code path for `addWorkspace` bypasses the grid trigger entirely during restore).
3. For the 5120x1440 ultrawide case, wouldn't a proportional math calculation be cleaner and more future-proof than adding new static resolution thresholds?
4. Are all panes in the default grid strictly terminals, or could we use the `pane-naming` primitive (if it exists) to automatically name them "Terminal 1", "Terminal 2", etc., to aid navigation?