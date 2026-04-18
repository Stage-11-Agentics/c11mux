# TP-c11mux-textbox-port-plan-Gemini-Evolutionary-20260418-1255

### Executive Summary
The proposed TextBox Input feature is currently scoped as a utilitarian patch to work around the terminal's poor multiline text editing ergonomics, especially for AI agents. However, its true evolutionary potential is far greater: this is the first step toward **decoupling the composition layer from the execution layer** in the terminal UI. By formalizing an out-of-band input channel, c11mux can evolve from a traditional PTY emulator into a structured, dual-pane conversational interface for both shell execution and AI collaboration. If evolved well, this feature becomes the bedrock for multimodal prompts, local AI pre-processing, and rich-UI CLI interaction that surpasses the limitations of bracketed paste.

### What's Really Being Built
Beneath the surface of a simple native macOS text box, you are building an **Input Intercept Layer**. You are establishing a semantic boundary where c11mux knows *what* the user is about to send before it becomes an opaque stream of bytes. Currently, terminal emulators act as dumb pipes; the TextBox establishes c11mux as a smart proxy that can analyze, route, decorate, and transform user intent (like intercepting `/` or `@` for agents) before committing it to the shell. This changes the core architecture from a single "Read-Eval-Print Loop" to a distinct "Compose View" and "Output View."

### How It Could Be Better
1. **Decouple from the Pane:** Mounting a `TextBoxInputContainer` below every single terminal pane is a heavy 1:1 coupling. A more powerful architecture would treat the TextBox as a unified, floating "Command Palette" or "Prompt Bar" that anchors to the active context. This reduces memory overhead, simplifies drag-and-drop routing collisions in `ContentView.swift`, and sets the stage for a global AI agent integration that isn't trapped in a single pane's view hierarchy.
2. **Deterministic Agent Detection:** Relying on window title regexes (`Claude Code|^[✱✳⠂]`) to route keystrokes is brittle and creates a cat-and-mouse game with upstream CLI tools. Instead, leverage c11mux's existing socket telemetry (`report_*` commands) or shell integration to definitively declare "An agent is active here."
3. **Beyond Bracketed Paste:** The reliance on a hardcoded 200ms delay after bracketed paste is a glaring fragility, especially for remote SSH sessions or slow PTYs. The system should ideally handshake with the agent (e.g., via socket API) to submit structured prompts directly, falling back to bracketed paste only for legacy shells.

### Mutations and Wild Ideas
- **The Context-Aware Drop Zone:** Instead of just inserting file paths when dragging and dropping, the TextBox could become a rich context builder. Dropping a file while an AI agent is active could automatically wrap it in `<file>` tags or parse it via a local agent, sending the *contents* or an *embedding summary* instead of just a raw filesystem path.
- **Multimodal Preparation:** Terminals are historically text-only, but AI is multimodal. By having a native `NSTextView` wrapper, we could trivially support pasting images or rendering `NSTextAttachment` tokens, transforming them into base64 or temporary file paths when sending to the shell. This turns the terminal into a fully capable chat interface.
- **The "Local-First" Interceptor:** What if the TextBox has its own local, on-device LLM or grammar engine? It could auto-complete commands, correct syntax, or expand natural language into shell commands *before* sending anything to the actual PTY.
- **Reverse Routing:** If the TextBox can route input, could the terminal route output *back* to it? Imagine the shell failing a command, and the TextBox automatically populating with the failed command and an AI suggestion for fixing it.

### What It Unlocks
- **Rich CLI UI Controls:** Once we have a dedicated input space, we can introduce rich interactive elements that don't belong in a character grid: send buttons (already planned), attachment paperclips, context toggles, model selectors, and visual token counters.
- **Pre-Flight Inspection:** A seam where c11mux can inspect user intent *before* it hits the PTY allows for "Are you sure?" intercepts for destructive commands (`rm -rf /`), even before the shell sees them.
- **True Multiline Editing:** Escaping the shell's line-editing constraints (like `zsh`'s `bindkey` quirks or `nano`/`vim` subshells) gives users a consistent, native macOS editing experience with native undo/redo, spellcheck, and cursor navigation.

### Sequencing and Compounding
1. **Phase 1: Abstract the Input Model (Now):** Implement the core model changes (`TerminalPanel.swift`, `Workspace.swift`) and the view integration, but ensure the `InputTextView` is designed to support rich attachments from day one, even if only text is initially implemented.
2. **Phase 2: Harden the Submission (Next):** Defer complex drag-and-drop routing and focus on making the submission mechanism robust. Replace the 200ms heuristic with a dynamic check, or introduce a structured submission API for supported agents.
3. **Phase 3: The Rich Context (Later):** Introduce the drag-and-drop routing, not just for paths, but for rich context inclusion, feeding directly into the AI agent workflow.

### The Flywheel
The flywheel here is **UX Superiority driving Agent Adoption**. By making multiline input and prompt composition significantly less painful than standard terminals, c11mux becomes the de-facto environment for CLI AI agents (like Claude Code, Aider, etc.). As more AI users migrate to c11mux for this UX, developers of these tools will be incentivized to integrate directly with c11mux's socket API, which in turn unlocks even more powerful, structured interactions that standard terminals cannot support, attracting more users.

### Concrete Suggestions
1. **Re-evaluate the 200ms Paste Delay:** Do not hardcode `200ms` for the delayed Return. If it must be a delay, make it a configurable setting (`TextBoxInputSettings.pasteDelay`) so users on slow SSH connections or slow machines can increase it if their prompts get truncated.
2. **Design for Attachments:** When implementing `InputTextView: NSTextView`, explicitly ensure that the subclass can handle `NSTextAttachment` drops, even if the current behavior just extracts the path. This prevents a future rewrite when multimodal support is added.
3. **Scope the View:** Reconsider the per-pane `TextBoxInputContainer`. Investigate the feasibility of a single, workspace-level floating palette that targets the active `GhosttyTerminalView` to reduce memory and view hierarchy complexity.
4. **Agent Socket Handshake:** Draft a proposal for a new c11mux socket command (e.g., `agent.accept_prompt`) that allows supported CLI tools to bypass the bracketed paste hack entirely and receive clean, structured JSON payloads from the TextBox.

### Questions for the Plan Author
1. **Robustness of Submission:** Is the 200ms delayed `Return` after bracket-paste resilient enough for remote/SSH use cases where network latency is highly variable? Should this delay be configurable?
2. **Multimodal Future-Proofing:** Does the copied `InputTextView` implementation restrict the addition of `NSTextAttachment` later? How difficult will it be to evolve this into a rich-text or multimodal composition area?
3. **Agent Detection Fragility:** Is window title regex the *only* way to detect Claude Code/Codex? Can we leverage the existing `c11mux` socket API to allow these tools to explicitly declare their presence and preferred input routing?
4. **Drag & Drop Collision:** Given the "highest collision risk" in `ContentView.swift`, is the file-path drag-and-drop feature essential for the initial port? Could this be deferred to a follow-up PR to ensure the core text submission lands safely first?
5. **Architectural Coupling:** Why is the TextBox instantiated per-pane rather than as a single global overlay that routes to the active pane? What are the tradeoffs in the current `TerminalPanelView` approach regarding memory and view hierarchy depth?