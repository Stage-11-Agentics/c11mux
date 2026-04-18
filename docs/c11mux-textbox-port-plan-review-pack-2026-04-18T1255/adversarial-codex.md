# Adversarial Review — c11mux-textbox-port-plan (Codex)

## Executive Summary
High concern. The plan is directionally sensible but not execution-safe in its current form.

The single biggest issue: it treats key assumptions as resolved when they are currently false in `main`.

Most critical example: it declares `Cmd+Option+T` “not currently used” and “collision resolved” (`docs/c11mux-textbox-port-plan.md:132`, `:288`), but c11mux already binds that combo to “Close Other Tabs in Pane” in both menu and global shortcut handling (`Sources/cmuxApp.swift:627-631`, `Sources/AppDelegate.swift:9496-9511`), and has tests explicitly asserting this mapping context (`cmuxTests/AppDelegateShortcutRoutingTests.swift:1415`).

If implemented literally, this plan will either silently remove an existing command path or create ambiguous shortcut behavior.

## How Plans Like This Fail
1. Stale-diff porting. A plan anchored to fork deltas underestimates integration drift in high-churn files.
2. “Mostly additive” framing in focus/drag systems. AppKit/SwiftUI responder and drag routing code is non-local; small hooks can have large side effects.
3. Manual validation optimism. Plans pass smoke checks while shipping regression debt in shortcut routing and focus convergence.
4. Policy mismatch. Team-level constraints (localization, testing norms) are treated as optional velocity decisions.

Where this plan is vulnerable:
- Shortcut routing (`AppDelegate`) and drag overlay routing (`ContentView`) are exactly the places where c11mux has active complexity and behavior contracts.
- The plan repeatedly labels risk “low/none” for areas with dense focus and event plumbing.

## Assumption Audit
1. Assumption: `Cmd+Option+T` is unused.
Load-bearing: Yes.
Reality: False (`Sources/cmuxApp.swift:627-631`, `Sources/AppDelegate.swift:9496-9511`).

2. Assumption: collision is resolved.
Load-bearing: Yes.
Reality: False (`docs/c11mux-textbox-port-plan.md:288`).

3. Assumption: TerminalPanelView integration is a simple VStack insertion.
Load-bearing: Yes.
Reality: Weak. Fork integration depends on APIs not present in current c11mux shape.
- Fork view expects `paneId` and `GhosttyApp.shared.defaultForegroundColor` (`/tmp/cmux-tb-inspect/Sources/Panels/TerminalPanelView.swift:11`, `:41`).
- Current c11mux view has no `paneId` parameter (`Sources/Panels/TerminalPanelView.swift:10-35`).
- Current `GhosttyApp` has no `defaultForegroundColor` (`Sources/GhosttyTerminalView.swift:847-848`, plus no symbol match in current tree).

4. Assumption: fork drag-routing patch maps cleanly to current overlay.
Load-bearing: Yes.
Reality: Weak. Fork TextBox patch relies on `prepareForDragOperation`/`concludeDragOperation` state (`/tmp/cmux-tb-inspect/Sources/ContentView.swift:666-758`). Current c11mux overlay path does not have those hooks (`Sources/ContentView.swift:607-685`).

5. Assumption: English-only localization is acceptable initially.
Load-bearing: Yes (timeline).
Reality: Conflicts with project policy requiring all user-facing strings localized (EN+JA) (`AGENTS.md:145`) while plan recommends English-only (`docs/c11mux-textbox-port-plan.md:187-190`, `:262`, `:304`).

6. Assumption: “copy tests, update import” is enough.
Load-bearing: Medium.
Reality: Internally inconsistent with selected shortcut decision.
- Plan chooses `Cmd+Option+T` (`docs/c11mux-textbox-port-plan.md:132`).
- Copied fork test expects default key `b` (`/tmp/cmux-tb-inspect/cmuxTests/TextBoxInputTests.swift:53-58`).

7. Assumption: submission preserves intended multiline input semantics.
Load-bearing: Medium.
Reality: Text is trimmed of leading/trailing newlines before send (`/tmp/cmux-tb-inspect/Sources/TextBoxInput.swift:689`). That is a behavior choice, not transparent preservation.

## Blind Spots
1. No explicit migration decision for the existing “Close Other Tabs in Pane” shortcut contract.
2. No conflict policy for global shortcuts (priority, remap, coexistence, deprecation messaging).
3. No automation plan for integration regressions in drag/focus/shortcut dispatch. Existing copied tests are mostly unit routing tests.
4. No rollout guardrails beyond “default off”: no kill switch, no telemetry event probes, no fast rollback branch strategy.
5. No hard compatibility matrix for keyboard layout variations (the codebase already has Dvorak-specific tests around this area).
6. No design decision on whether TextBox semantics should preserve exact text including surrounding newlines.
7. No strategy for eventual drift from title-regex app detection (`Claude Code|^[✱✳⠂] ` and `Codex`) if terminal titles change.

## Challenged Decisions
1. Choosing `Cmd+Option+T` by default.
Counterargument: upstream chose `Cmd+Option+B` explicitly to avoid this collision class (see fork note: `/tmp/cmux-tb-inspect/upstream-sync.md:171`).

2. Treating `Workspace.toggleTextBoxMode(_:)` as low-risk/self-contained.
Counterargument: Workspace focus pipeline is complex and heavily coordinated (`Sources/Workspace.swift:7757-7857`), making “self-contained” a weak claim.

3. Recommending English-only localization.
Counterargument: direct policy violation (`AGENTS.md:145`), likely to incur review rework later.

4. Copying a 1246-line monolithic file verbatim as a speed strategy.
Counterargument: this imports fork-specific assumptions/documentation debt and increases future maintenance burden in a latency-sensitive codebase.

5. Declaring low risk for Ghostty focus additions.
Counterargument: focus flows in `GhosttyTerminalView` are highly stateful and race-sensitive (`Sources/GhosttyTerminalView.swift:7591-7818`).

## Hindsight Preview
Two years later, likely regrets:
1. “We should have resolved shortcut ownership up front instead of retrofitting around collisions.”
2. “We should have converted the plan from fork-diff framing to c11mux-contract framing before coding.”
3. “We should have required at least one automated integration test per critical subsystem (focus, drag routing, shortcut routing).”

Early warning signs to watch immediately:
1. Any failing/updated tests around `Cmd+Option+T` in AppDelegate shortcut routing.
2. Focus logs showing repeated `ensureFocus`/`applyFirstResponder` churn after toggling TextBox.
3. Drag operation inconsistencies: cursor shows copy badge but drop result routes incorrectly between web/terminal/TextBox.
4. PR comments requesting localization fixes for Japanese strings.

## Reality Stress Test
Most likely disruptions:
1. Upstream churn continues in `ContentView` and `GhosttyTerminalView` while the port is in flight.
2. Product decision keeps “Close Other Tabs” on `Cmd+Option+T` for continuity.
3. Agent title formats evolve, weakening regex-based app detection.

Combined impact:
- Shortcut behavior becomes ambiguous or split by context.
- Drag and focus regressions appear only under specific pane/window states, making manual QA unreliable.
- AI-specific routing feels flaky (“sometimes `/` opens menu, sometimes inserts text”), undermining the feature’s core user value.

## The Uncomfortable Truths
1. The plan reads more like a confident migration brief than a risk-adjusted execution plan for current c11mux.
2. “Resolved” is used for unresolved facts (shortcut collision).
3. “Low risk” is asserted in exactly the files where c11mux has the highest event-routing complexity.
4. The plan optimizes for speed-to-port but underprices cleanup cost from inconsistency (shortcut defaults, tests, localization policy).

## Hard Questions for the Plan Author
1. Do we keep `Cmd+Option+T` for “Close Other Tabs in Pane” or reassign it? If we reassign, what is the migration UX?
2. Why does the plan claim T is unused when both menu and AppDelegate currently bind it?
3. Should TextBox default to `Cmd+Option+B` (upstream choice) to avoid conflict and reduce migration risk?
4. If we keep T for TextBox, what exact shortcut will replace “Close Other Tabs in Pane,” and where is that rollout documented?
5. Why does Phase 1 say “copy tests” when copied tests currently assert default `b` while plan chooses `t`?
6. Which c11mux-local API contract is the source of truth for TerminalPanelView integration given current signature drift?
7. Where is the explicit adaptation step for `defaultForegroundColor` absence in current `GhosttyApp`?
8. Are we willing to ship a plan that conflicts with `AGENTS.md` localization policy, or do we update the plan now?
9. What is the rollback switch if focus regressions appear after merge besides “turn feature off by default”?
10. What automated test will guard the existing close-other-tabs shortcut behavior during this port?
11. What automated test will guard drag target precedence across web, TextBox, and terminal in the current overlay architecture?
12. Should submission preserve exact input bytes (including leading/trailing newlines), or is trimming intentional product behavior?
13. What is the owner-approved behavior when app detection regex fails or false-positives?
14. Why is this one PR rather than a contract PR (shortcuts/localization/integration scaffolding) plus a behavior PR?
15. What objective “no typing latency regression” threshold are we enforcing beyond manual log eyeballing?
