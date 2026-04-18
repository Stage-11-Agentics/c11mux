# TP-c11mux-textbox-port-plan-Claude-Evolutionary-20260418-1255

**Reviewer:** Claude (Opus 4.7)
**Plan:** `docs/c11mux-textbox-port-plan.md`
**Mode:** Evolutionary — what this *becomes*, not whether it ships.

---

## Executive Summary

The stated plan is a utility port: lift a feature from a sibling fork and bolt it underneath each terminal pane. That framing undersells what's actually being built. The TextBox Input is c11mux's first **in-process input surface**: a structured, observable, styleable region that sits *between* the user and the PTY and understands semantics the PTY never will. Everything interesting that c11mux could do in the next 12 months — agent-aware composition, context attachments, multimodal prompts, paste-before-send confirmation, pre-flight redaction, cross-pane broadcast — uses this surface as its substrate. The right move is not "port and move on," it is "port as Phase 0 of a Composition Surface roadmap."

The single biggest evolutionary risk in the current plan is framing: if this ships as "TextBox Input" and lives in `TextBoxInput.swift` with `[TextBox]` tags everywhere (it already does in the fork), it will forever read as an accessory feature rather than core infrastructure, and future work will feel like it's "extending the TextBox" rather than "using the composition surface c11mux owns." Rename and rescope now — cheap — or pay compounding renaming cost later.

A secondary opportunity: c11mux already has *the hard piece the fork doesn't* — socket-based agent detection via `AgentDetector` and surface-level metadata. The fork's regex-on-title agent detection (`Claude Code|^[✱✳⠂] `) is the weakest link in the whole design and is exactly what c11mux can replace natively. Porting the fork's detection as-is would be a missed free win.

---

## What's Really Being Built

Three layered capabilities, only the top one is named in the plan.

### Layer 1 (named): a native text field below the terminal
Multi-line input, IME, drag-drop, Cmd+Option+T toggle. The plan treats this as the deliverable.

### Layer 2 (implicit): an input intercept seam
An observable AppKit view where c11mux sees user intent *before* it becomes bytes. This is a substantial architectural shift: c11mux transitions from "dumb pipe with chrome" to "smart proxy with a PTY backend." Every keystroke now passes through Swift code that can inspect, transform, redirect, or augment it. The plan calls this out tangentially ("/" and "@" forwarding) but doesn't name the capability.

### Layer 3 (latent): a structured submission channel
Bracket-paste + delayed Return is a reliable-enough hack for today's agents. But the real underlying capability is: **c11mux now knows exactly what text was submitted, at what wall-clock moment, to what surface, associated with what agent.** That is the first piece of ground truth for a large family of future features — prompt history, session replay, redaction, cost tracking, cross-pane broadcast, "undo send," pre-flight approval.

The plan is correct that it's cheap to port. What it doesn't say is that it's also strategically heavy: it creates a seam that doesn't exist elsewhere in the app today.

### Naming, while it's still cheap

`TextBoxInput` is the fork's name and it's wrong for c11mux. Suggested rename candidates, in order:

1. **`ComposeSurface`** — aligns with the mental model (compose vs. emit) and leaves headroom for non-text composition.
2. **`InputLane`** — if we want to stay concrete and spatially obvious (there's a lane below each pane).
3. **`PromptBar`** — fine if we commit to the agent-first framing; weaker if we care about shell use.

Rename the file, the setting keys (`UserDefaults`), the class prefixes, and the `[TextBox]` comment tags. All of this costs maybe 30 minutes during the port and is irrecoverable after ship because `UserDefaults` keys and AppStorage bindings will have real user state. The plan should either do this rename now or explicitly decide not to with eyes open.

---

## How It Could Be Better

### 1. Replace title-regex agent detection with c11mux's AgentDetector

The fork's detection (`TextBoxAppDetection` — regex on `panel.title`) is the single most fragile piece of the feature. It will break the moment Anthropic or OpenAI touches their terminal UI, it creates a detection loop every time the title updates, and it gives the user no visibility into whether detection is working.

c11mux already has `Sources/AgentDetector.swift` and `SurfaceMetadataStore` carrying `terminal_type` from M1. The port should wire TextBox key-routing rules (Rules 3–5: `/`, `@`, `?` forwarding) against that instead of the fork's regex. This is almost certainly a net-negative LOC change — delete the fork's detector, read a property.

This is the single highest-leverage evolutionary improvement available in the port and it requires no design work, just wiring.

### 2. Make the 200ms paste-delay configurable (and observed)

The plan notes 200ms is "empirically the minimum reliable value." It is — for local zsh and local Claude CLI on modern Macs. For SSH, for Codespaces, for slow PTYs, for users on battery-saver, it will silently truncate submissions. The symptom is "my long prompt got cut off." Mitigations:

- Expose `TextBoxInputSettings.returnDelayMs` (or new name) as a setting with a "recommended: 200" default.
- Better: emit a debug log on every submission with timing info so we can diagnose failures later.
- Best: handshake with detected agents via c11mux socket → structured payload, fallback to bracket-paste for plain shells.

### 3. Own the rename to match c11mux conventions

Every hook the fork labels `[TextBox]` or `[cmux-tb]` should be scrubbed. The `[cmux-tb]` tags are literally fork metadata and must not ship. `[TextBox]` is fine internal shorthand but prefer a more semantic marker tied to the surface concept (e.g. `// compose:` or no tag at all — we have git blame).

### 4. Resist the settings sprawl

The fork ships four settings *in the first release of the feature*. That's already a yellow flag: every setting is a combinatorial cost, documentation cost, and support cost forever. Review each:

| Setting | Real user need? |
|---|---|
| Enable Mode | Yes — kill switch for the feature. |
| Send on Return | Probably — but the fork default (Enter=send) matches every chat app since 2010, and "inverse" is an edge case. Consider shipping with fork default and no setting; add setting later only if users ask. |
| Escape key behavior | Debatable — `.sendEscape` is correct for vim users, `.focusTerminal` is correct for agent users. Default should probably flip based on agent detection, not be a global setting. |
| Toggle shortcut behavior | Debatable — `.toggleFocus` is the more useful mode and `.toggleDisplay` is a power-user preference. Ship focus-only for v1. |

Ship with 1–2 settings, not 4. Add more only when a user asks for them in a GitHub issue. Every settings row you don't ship is settings UI you don't have to maintain across 18 locales (see Concrete Suggestions §6).

### 5. Redesign the key-routing table as data, not an enum switch

`TextBoxKeyRouting`'s 10 rules are defined as a type inside the file, evaluated top-down. This is fine for 10 rules. It becomes a maintenance tax at 20, and agent-specific routing at scale will get there. A `KeyRoutingRule` struct with `(predicate, action)` pairs and an explicit priority field would make the rules composable and testable in isolation. Not a blocker; worth noting while the code is being handled anyway.

---

## Mutations and Wild Ideas

Listed in rough order of "how cheap is the first working version."

### M1. Broadcast submission (cheap, immediate value)
Multi-pane broadcast: submit from one TextBox, send the same text to every terminal in the workspace (or a marked subset). This is ~40 lines on top of the plan, enormously useful for agent fleet operation ("apply this fix across all 4 agent panes"), and it's the obvious extension of the fork's `.all` toggle scope. Ship with the port or as the first follow-up.

### M2. "Undo send" window (cheap, defensive)
The delayed Return (200ms) is already a window. Extend it to a configurable 500–1000ms "cooling" period where pressing Escape aborts submission. Makes the feature *safer* than in-terminal editing for destructive commands. One check before the `asyncAfter` fires.

### M3. Context pins (medium)
Let users "pin" a block of context at the top of the TextBox that persists across submissions. ("You are in directory X. The failing test is Y."). Invisible to the shell between submits but prepended on send. Solves a real problem for agent workflows where context gets forgotten.

### M4. Image / attachment drop (medium, high ceiling)
Drag-drop a PNG → c11mux writes to `/tmp`, inserts the path *and* associates the attachment with the next submission. For agents with vision, c11mux can use the agent socket (once it exists) to forward the image content directly. This is one of the few ways c11mux can beat a web UI for agents.

### M5. Structured prompt templates (medium)
Named, parameterized templates stored per-surface: `/template reviewer` expands to `"Review the following diff for security issues: ..."`. Lives in `SurfaceMetadataStore`. Makes the composition surface a template system, not a text box.

### M6. Pre-flight command inspection (large, defensive)
Before submission, scan text for obvious-bad patterns (`rm -rf /`, `curl | sudo bash`) and require explicit confirmation. Only possible because we have an intercept seam.

### M7. Composition-surface-as-canvas (wild)
The `NSTextView` doesn't have to only hold text. It can hold `NSTextAttachment`s. Once attachments are in play, the surface can render inline widgets — a collapsed diff, an image thumbnail, a model selector dropdown, a cost preview for the next prompt. The terminal stays a character grid; the composition surface becomes a rich canvas. This is the "multimodal chat client that happens to have a shell" endgame. Don't build it now; don't architect away from it either.

### M8. Reverse channel: populate from terminal output (wild)
When a command fails, c11mux recognizes the failure (it already scans output) and *populates the TextBox* with a fix suggestion. Goes from "you type and we send" to "we converse." This is a big leap but the intercept seam is the prerequisite.

### M9. Composition surface for the browser pane (wild)
c11mux has a browser pane. A browser pane also benefits from a native composition area (think: form fill, URL bar, search). The same surface can be reused, turning "TextBox Input" from a terminal-only feature into c11mux's generalized input substrate. This is the clearest path to maximum leverage for the minimum incremental effort.

---

## What It Unlocks

Direct consequences of shipping, in order of distance from the plan:

1. **Agent-friendly workflow.** AI users get the stated UX win. Measurable via usage of the feature in telemetry.
2. **IME baseline.** Japanese/Chinese/Korean users get a usable composition experience for any agent, permanently. This is a marketing win in the en-JP-ZH market where c11mux already localizes heavily.
3. **A settings surface for "compose" behavior.** The fork's four settings become the seed of a whole "Composition" section — prompt history, templates, broadcast targets, pre-flight rules.
4. **A testable input layer.** `TextBoxInputTests.swift` is 360 lines of behavioral tests on user-facing logic. This is rare in c11mux's codebase (most tests are low-level). The port inherits a testing discipline that can propagate.
5. **A place to hang agent-specific features.** The fork's `/`, `@`, `?` routing is the first of many agent-specific interactions. Everything further (model selection, cost preview, slash-command menu) has a home.
6. **A UI seam for multimodal.** The moment attachments land (M4), c11mux is in the multimodal game. This is otherwise a 6-month rearchitecture.
7. **A marketing beat.** "Native macOS input for AI agents" is the kind of specific, honest, differentiating capability the Stage 11 brand-voice doc asks for. It's a page on the website, a screencast, a thread.

---

## Sequencing and Compounding

The plan sequences the port phases correctly at the *mechanical* level (1 standalone file → 2 model/shortcut → 3 terminal bridge → ...). The sequencing I'd change is at the *strategic* level, between "what to do in this PR" and "what to do right after."

### Within the port PR

- **Phase 0 (new, before Phase 1):** Rename decision. `TextBoxInput` vs. `ComposeSurface` vs. other. Lock it in before the first commit because `UserDefaults` key names are permanent once users upgrade.
- **Phase 3 (terminal bridge):** Add the `defaultForegroundColor` property on `GhosttyApp` that the fork assumes exists but c11mux doesn't have. The plan currently misses this — see Concrete Suggestions §1.
- **Phase 5 (shortcut + toggle):** Swap `Cmd+Option+T` for `Cmd+Option+B` to match the fork's README and its test file's hardcoded expectation (`shortcut.key == "b"`). Or leave as `T` and fix the broken test. Either way, the fork ships with this inconsistency; don't inherit it.
- **Phase 6 (drag routing):** Audit c11mux's existing `activeDragWebView` / `preparedDragWebView` / portal-based hit testing. The fork uses a simpler `webViewUnderPoint` approach that c11mux has already evolved past. A naive merge loses c11mux's hit-testing logic; a clean one inserts TextBox as a new branch in the existing `updateDragTarget` / `performDragOperation` without touching the browser plumbing.
- **Phase 8 (validation):** Add one step — launch c11mux with an agent in a surface, confirm `AgentDetector` picks it up, confirm TextBox sees the detection. This is the evolutionary replacement for the fork's title regex; without this, we've silently ported the wrong thing.

### After the port

The port ships with the feature off by default. The *next PR* after that should be exactly one of: (a) swap title-regex detection for c11mux's AgentDetector (biggest win, lowest risk, best compounding), or (b) ship broadcast submission (biggest user-visible win). Pick one and make it the explicit "M9.1" followup, so the port doesn't ship in isolation and then sit untouched.

### What compounds

Each of these is a compounding move because the *next* feature is cheaper once it's done:

- Replacing title-regex detection with `AgentDetector` (unlocks all agent-aware features cleanly).
- Attachment support in `InputTextView` (unlocks M3/M4/M7).
- Structured agent socket handshake (unlocks cost preview, structured prompts, session replay).
- Single composition surface vs. per-pane container (unlocks cross-pane broadcast, workspace-level palette, browser-pane reuse).

If I had to pick one, it's `AgentDetector` — it's an unambiguous quality improvement over the fork's approach, it's a small diff, and it makes every future agent-aware feature legible and testable.

---

## The Flywheel

There are two flywheels latent here. Both are real but one is bigger.

### Flywheel A: UX-driven agent adoption
Plan-author's implicit thesis. Users with AI agents get a nicer input experience → they use c11mux for agent work → agent tool authors notice → they integrate more deeply → more users come. This is real but not unique to c11mux (Warp has been executing on this flywheel for years). It's a "me too" flywheel.

### Flywheel B: Composition surface → data → differentiation
If c11mux owns the composition surface, it owns data the PTY can't see: (a) what was about to be sent, (b) what the user edited away before sending, (c) which agent context the submission targeted, (d) how long composition took. Nobody else has this data. Features that compound on it — session replay, prompt libraries, cost estimation, cross-agent context migration — are all defensible because they require the surface. This flywheel is *unique* to c11mux and much stronger than A.

The plan as written spins flywheel A by default. To spin flywheel B, two small moves are enough:

1. **Log structured submission events** from day one. Even if unused, the data starts accumulating. Cost: ~20 lines in `TextBoxSubmit.send`.
2. **Name and surface the abstraction.** Call it a composition surface, in code, in settings, in the changelog. Users who see "Composition" in settings understand a bigger idea than users who see "TextBox."

---

## Concrete Suggestions

### 1. Fix plan omission: add `GhosttyApp.defaultForegroundColor`
The fork's `Panels/TerminalPanelView.swift:41` reads `GhosttyApp.shared.defaultForegroundColor` and the fork's `GhosttyTerminalView.swift:1205 / 2459` defines it. **c11mux's `GhosttyApp` does not have this property.** The plan's §4.3 and §4.8 both miss this dependency. Add a new bullet under §4.8: "Add `defaultForegroundColor: NSColor` to `GhosttyApp`, populated alongside `defaultBackgroundColor` in the existing `applyDefaultBackground` / config-extraction path." Without this the integration doesn't compile.

### 2. Fix the fork's broken test before porting it
The fork's `TextBoxInputTests.swift:54` asserts `shortcut.key == "b"` but the fork's `KeyboardShortcutSettings.swift:267` returns `"t"`. One of them is wrong. Decide which (recommend: fix the test to match the actual binding) before copying to c11mux, so we don't inherit a failing test we have to fix under time pressure during Phase 8.

### 3. Use `AgentDetector` / `SurfaceMetadataStore`, not title regex
Delete `TextBoxAppDetection` during the port and rewrite the relevant call sites to consult `AgentDetector` / `terminal_type` metadata. This is a ~50-line change inside `TextBoxInput.swift` and the single highest-ROI deviation from the fork.

### 4. Rename before first commit
If renaming, do it first. The mechanical changes are:
- File: `Sources/TextBoxInput.swift` → `Sources/ComposeSurface.swift`
- Type: `TextBoxInputContainer` → `ComposeSurfaceContainer`, etc.
- `UserDefaults` keys: prefix `textbox.*` → `compose.*`
- Settings section: `settings.textBoxInput.*` → `settings.compose.*`
- Shortcut: `toggleTextBoxInput` → `toggleComposeSurface`
- `[TextBox]` tags → remove entirely (or unify to `// compose:`)

Irreversible once users run it; trivial now.

### 5. Ship 2 settings, not 4
Start with `enabled` and `sendOnReturn`. Defer `escapeBehavior` and `shortcutBehavior` until a user asks. (`escapeBehavior` can be made a function of agent detection; `shortcutBehavior` can ship as `.toggleFocus` only.)

### 6. Japanese/Chinese translation is a real blocker, not a nice-to-have
The plan §4.10 treats localization as optional ("ship English-only"). c11mux has 18 locales, not 2. Shipping English-only means 17 `stubbed` entries in `Localizable.xcstrings`, which c11mux's existing localization culture pushes against (per CLAUDE.md: "All user-facing strings must be localized"). The honest options are:

- **Option A:** Translate at port time using the existing patterns in the file (~18 strings × 17 locales = 306 entries; most are structural/obvious and an LLM can draft all of them in one pass).
- **Option B:** Land English-only but file a blocking follow-up issue and get translation done before enabling the setting for production users.
- **Option C:** Gate the feature behind a feature-flag that's off for all non-English locales until translated.

Recommend A — it's a one-shot task, c11mux has done it before, and the fork's string set is small and mostly technical.

### 7. Add structured submission telemetry from day one
In `TextBoxSubmit.send`, emit a `dlog`:
```swift
dlog("compose.submit length=\(trimmed.count) lines=\(trimmed.split...) surface=\(surface.id.uuidString.prefix(8)) agent=\(...)")
```
Costs nothing; unlocks every Flywheel B feature (cost estimation, replay, debugging).

### 8. Declare the Input Intercept Layer explicitly
Add a 10-line doc comment at the top of the renamed file that says: *"This file hosts c11mux's composition surface — the seam between user intent and the PTY byte stream. Features that want to inspect, modify, or redirect user input before submission live here or hook into submission events from here."* Future agents and humans reading the code know what this file is *for*, not just what it does.

### 9. Feature flag tied to c11mux's welcome experience
c11mux already has a welcome sequence (recent commit `3ee342e0` launches a 2x2 quad layout). Consider making "Enable Composition Surface" an explicit opt-in checkbox in the onboarding flow for new users, rather than a settings-panel toggle that nobody finds. Free marketing of a key differentiating feature.

### 10. Decide the M9 naming deliberately
The plan's open question §8.8 asks whether this is M9. If we commit to the composition-surface framing, this is not a terminal module (M1–M8 are mostly terminal-centric). Call it something that signals the architectural shift: `CS1` (Composition Surface), or `M9: Compose`. Naming is cheap now and sets expectations for follow-ups (`M9.1: Broadcast`, `M9.2: Attachments`).

---

## Questions for the Plan Author

1. **Rename or not?** Is `TextBoxInput` the name users and future agents will see in settings, docs, and source for the life of the feature? If not, decide the rename before Phase 1. (Recommend: `ComposeSurface`.) This is the single most-irreversible decision in the port.

2. **Agent detection strategy.** Will the port use the fork's title-regex (`TextBoxAppDetection`) or c11mux's native `AgentDetector`/`SurfaceMetadataStore`? Strongly recommend the latter — it's the best available evolutionary upgrade and costs less code.

3. **`GhosttyApp.defaultForegroundColor` — add during port or defer?** The fork assumes it; c11mux doesn't have it. Missing from the current plan. Does this land in Phase 3, or is there a simpler substitute (e.g. reading from the terminal surface directly)?

4. **Settings count.** Is the plan committed to porting all four fork settings, or will it start with a subset (suggested: `enabled` + `sendOnReturn` only)? The smaller surface is cheaper now and extensible later; the wider surface locks in decisions (and 18-locale translations) we may regret.

5. **Localization strategy.** The plan says "English-only." c11mux has 18 locales. Is the real answer to translate now (one-shot LLM pass, review by native speakers where available), or gate the feature off in non-English locales until translations land? "Ship stubs and file a ticket" is the worst option.

6. **Settings key naming forever-ness.** `TextBoxInputSettings.enabledKey` stores a `UserDefaults` key that persists across app upgrades. If we rename later, existing users' settings are silently reset unless a migration is written. Does the plan commit to a migration strategy or does renaming happen now?

7. **Cross-pane broadcast.** The fork's `.all` toggle scope is the seed of cross-pane broadcast submission. Is this the follow-up PR after the port lands (M9.1: Broadcast) or deferred indefinitely? If indefinite, consider collapsing `.all` into `.active` for v1 to reduce surface area.

8. **Structured submission API.** Longer-term: should c11mux define a socket command (`agent.submit_prompt`) that bypasses bracket-paste entirely for agents that opt in? This eliminates the 200ms delay fragility and is the missing piece for multimodal (M4) and cost preview (M7). Worth a note in the plan even if deferred.

9. **Module numbering.** M9 keeps c11mux's convention but signals "terminal module." If this is the first Composition Surface module, is it named that way, and does it have a distinct letter namespace (CS1, CS2, ...) so the broadcast / attachment / template follow-ups nest cleanly?

10. **Telemetry baseline.** Will Phase 1 include a submission event log (`dlog` or equivalent)? If not in the port, when? Every day without this log is a day of missing diagnostic data for the 200ms-delay fragility and usage analytics.

11. **Browser pane reuse.** Has anyone looked at whether c11mux's browser pane would benefit from the same composition surface (URL bar, form fill, search)? If yes, the abstraction should accommodate non-terminal targets from day one; if no, that's a deliberate scope decision to document.

12. **Two-PR split.** The plan's §7 suggests splitting into a scaffolding PR (phases 1–3) and integration PR (phases 4–8). Strong recommend yes — the scaffolding PR is low-risk and reviewable in isolation; the integration PR concentrates the actual risk (`ContentView.swift`, drag routing, focus guards) in a PR whose scope reviewers can actually hold in their heads. Single-PR merges of 135-commit worth of change are expensive to review.

13. **"Off by default" for how long?** The plan says the feature ships opt-in via settings. What's the criterion for flipping the default to on? Usage-based? Time-based? User-requested? Without a criterion, opt-in features often stay opt-in forever, which kills Flywheel B.
