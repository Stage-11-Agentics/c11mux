# Adversarial Plan Review: c11mux TextBox Input Port

### Executive Summary
This plan underestimates the complexity and risk of porting a monolithic, 1200-line view-bridging file from a significantly diverged fork. The integration strategy relies heavily on "pure additions" and assumes that dropping a complex AppKit-wrapped SwiftUI component into the existing rendering loop won't have cascading effects. The most concerning aspect is the inherent flakiness of the core mechanism (bracketed paste + 200ms delayed synthetic Return) and the brittle heuristic for AI agent detection. This feature, as designed, is highly likely to introduce subtle state bugs, layout thrashing, and timing-dependent failures.

### How Plans Like This Fail
Plans involving "selective forward-ports" of complex UI features typically fail not in compilation, but in state synchronization and edge cases. 
- **The "Drop-In" Fallacy:** The plan assumes `TextBoxInput.swift` can be dropped in verbatim because it's a single file. However, this file is a "god object" bridging SwiftUI, AppKit (`NSTextView` subclass), custom key routing, and event interception. These layers interact poorly with existing complex hierarchies.
- **State Desync:** Bridging `@Published` variables with an `NSViewRepresentable` that intercepts `keyDown` and `insertText` is a classic recipe for state desync, especially during rapid typing, pasting, or IME composition.
- **The "Additive" Illusion:** Adding properties to `TerminalPanel` (an `ObservableObject`) is labeled "Risk: none." But adding published properties that update frequently can trigger widespread, unintended SwiftUI view invalidation and layout passes, degrading typing latency.

### Assumption Audit
- **Assumption:** A 200ms hardcoded delay between the bracketed paste and the synthetic Return is reliable. (Load-bearing). **Critique:** Highly unlikely to hold under heavy system load, network latency (if over SSH), or if the shell/agent is busy. When it fails, the user's input will hang, requiring a manual Enter press, or worse, the Return will be inserted into the text stream incorrectly.
- **Assumption:** `TerminalPanelView` can just mount `TextBoxInputContainer` below the terminal without breaking constraints. **Critique:** How does this auto-growing (2 to 8 lines) text box interact with complex split layouts (Bonsplit) or constrained window sizes? It assumes infinite vertical space.
- **Assumption:** `firstResponder is InputTextView` is a reliable way to manage focus. **Critique:** AppKit focus management is notoriously asynchronous and complex. Relying on synchronous type-checking of `firstResponder` during workspace switches or tab changes will inevitably lead to focus trapping or lost keystrokes.
- **Assumption:** AI agents can be reliably detected via terminal titles matching `Claude Code|^[✱✳⠂] ` or `Codex`. **Critique:** Extremely brittle. If an agent updates its CLI title, the feature silently breaks.

### Blind Spots
- **Accessibility (VoiceOver):** There is absolutely no mention of accessibility. Custom `NSTextView` subclasses that intercept `keyDown` and custom drawing often completely break VoiceOver navigation and readout.
- **Memory Management:** `TerminalPanel` adds a `weak var inputTextView: InputTextView?`. Manual weak references to AppKit views from SwiftUI model objects are a huge red flag for retain cycles and memory leaks if the view lifecycle isn't managed perfectly.
- **Split Pane Thrashing:** What happens when a user has 6 split panes and triggers the `Cmd+Option+T` toggle with `.all` scope? Does the app instantiate 6 custom `NSTextView`s and trigger 6 simultaneous layout animations? The performance impact on complex workspaces is unexamined.
- **Undo/Redo Stack:** How does the custom `InputTextView` handle the macOS undo/redo stack, especially given the custom event interception?

### Challenged Decisions
- **Decision:** Copying the 1246-line file verbatim. **Counterargument:** This is institutionalizing technical debt. A 1200-line file handling UI, bridging, key routing, and app detection is unmaintainable. It should be refactored to fit c11mux's architecture *before* merging.
- **Decision:** Modifying `performDragOperation` in `ContentView` with a recursive `NSView` walker (`findTextBox(in:windowPoint:)`). **Counterargument:** This is a massive collision risk and a performance hazard. Recursive view walking on every drag event is poor practice. Drag handling should be localized to the TextBox view itself using modern SwiftUI `.onDrop` or proper AppKit responder chain integration.
- **Decision:** The 200ms delay. **Counterargument:** This must be a configurable setting, or better yet, replaced with a deterministic prompt-readiness check (if possible via PTY inspection), because the optimal delay will vary wildly between machines and environments.

### Hindsight Preview
- Two years from now, we will regret the `Claude Code` title regex when the feature breaks for users because Anthropic changed a bullet point character in their CLI output.
- We will be overwhelmed by bug reports of "Enter key sometimes doesn't work" because the 200ms delay fired while the user's system was momentarily locked up compiling code.
- We will find that the recursive `NSView` walker in `ContentView` is causing crashes or missed drops when users have deeply nested Bonsplit layouts.

### Reality Stress Test
Imagine these three things happen simultaneously:
1. The user has a complex, 8-pane split layout.
2. The user is on a slow machine under heavy CPU load (compiling).
3. The user pastes a massive 500-line block of text into the TextBox and hits Return.
**Result:** The UI thread stutters animating 8 text boxes. The 200ms delay fires before the PTY finishes processing the massive bracketed paste. The `Return` key is swallowed or appended to the text, and the user is left with a hung prompt and a desynced view state.

### The Uncomfortable Truths
- This feature is a giant, brittle hack. Bracketed paste followed by a timed synthetic Return is fundamentally nondeterministic.
- We are porting a fork's monolithic design because it's "cheaper than reimplementing," but we will pay the cost in maintenance, bug fixes, and typing latency regressions down the line.
- The drag-and-drop integration is poorly designed and risks breaking existing, critical drop functionality for web and terminal panes.

### Hard Questions for the Plan Author
1. How does the system recover if the 200ms delayed `Return` fires before the shell is ready to accept it? Is there a fallback mechanism?
2. What is the memory profile of toggling the TextBox on and off 100 times in a heavily split workspace? Have you profiled for retain cycles with the `weak var inputTextView` pattern?
3. How does this custom `NSTextView` behave with VoiceOver enabled? (If the answer is "we don't know", this is a blocker for merging).
4. Why is drag routing using a recursive `NSView` walker on the main `ContentView` instead of localized drop targets on the `TextBoxInputContainer`? What is the performance penalty of this walk during a drag gesture?
5. What happens to the layout of a terminal pane when the TextBox auto-grows to 8 lines but the pane itself is only 10 lines tall? Does it push the terminal off-screen, or does it overlap?
6. Are we comfortable shipping a feature that relies on hardcoded string matching (`Claude Code|^[✱✳⠂] `) for core functionality, knowing it will silently break upon upstream changes?