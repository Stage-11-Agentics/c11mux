### Executive Summary
This is a strong selective-port plan, but it is **not execution-ready yet**. The biggest blocker is a hard shortcut collision the plan misses: `Cmd+Option+T` is already bound in c11mux to “Close Other Tabs in Pane,” both in menu wiring and app-level handling. If unchanged, the port will either break existing behavior or make TextBox toggle unreachable.

The architecture direction (forward-port + additive hooks) is correct. The execution details need a revision pass to align with current c11mux realities: shortcut ownership, drag lifecycle wiring, test drift in the fork, and localization policy.

### The Plan's Intent vs. Its Execution
**Intent:** Fast, low-risk import of a proven feature from a fork without bringing fork release/branding baggage.

**Where execution drifts from intent:**
- The plan assumes `Cmd+Option+T` is free, but c11mux currently uses it for close-other-tabs.
  - `Sources/cmuxApp.swift:630`
  - `Sources/AppDelegate.swift:9498`
  - Related routing test comment: `cmuxTests/AppDelegateShortcutRoutingTests.swift:1415`
- The plan says copy tests with minimal edits, but the fork test/state combo is internally inconsistent:
  - `TextBoxInputSettings.defaultEnabled = true` in fork source (`/tmp/cmux-tb-inspect/Sources/TextBoxInput.swift:583`)
  - Test expects false (`/tmp/cmux-tb-inspect/cmuxTests/TextBoxInputTests.swift:24`)
  - Fork shortcut defaults to `Cmd+Option+T` (`/tmp/cmux-tb-inspect/Sources/KeyboardShortcutSettings.swift:266`), while test asserts key `b` (`/tmp/cmux-tb-inspect/cmuxTests/TextBoxInputTests.swift:53`)
- The plan recommends English-only strings, but c11mux policy requires English+Japanese for user-facing strings (`CLAUDE.md:145`).

### Architectural Assessment
The high-level decomposition is good: bring in `TextBoxInput.swift`, then wire model/view/shortcut/app-shell/drag in phases. That is the right shape for a fork this far diverged.

Where decomposition should be tightened:
- **Shortcut architecture must be treated as a first-class migration axis**, not a minor additive hook.
- **Drag/drop should include lifecycle parity**, not just `performDragOperation`; fork changes include `prepareForDragOperation`/`concludeDragOperation` and a prepared-webview state path.
- **Theme sync contract should be explicit** for current c11mux: fork `TerminalPanelView` references `GhosttyApp.shared.defaultForegroundColor` (not present in current c11mux), so the source of foreground color must be defined up front.

### Is This the Move?
Yes, with revisions. Reimplementation would likely take longer and still rediscover most of this logic.

What I would change before coding:
1. Add a pre-Phase-1 “decision lock” for shortcut ownership (`Cmd+Option+T` vs alternative).
2. Expand Phase 6 scope to include drag lifecycle methods (not only terminal fallback branch).
3. Replace “copy tests” with “selectively port + reconcile expectations to current shortcut/default decisions.”
4. Change localization plan to include Japanese in same PR (or explicitly accept policy exception first).

### Key Strengths
- Clear selective-port strategy; avoids risky branch merge.
- Good per-file integration map with collision awareness called out for `ContentView.swift`.
- Phased delivery with commit boundaries is review-friendly.
- Validation matrix is pragmatic and behavior-focused.
- Open questions surface product decisions early (default mode/scope/persistence).

### Weaknesses and Gaps
1. **Critical:** Shortcut collision is currently unresolved.
- `Cmd+Option+T` is already wired to close-other-tabs in c11mux menu and AppDelegate.
- Port plan currently assumes this chord is unused.

2. **High:** Fork test file cannot be copied “as-is + import tweak.”
- It contains contradictory expectations vs current fork source and shortcut defaults.
- This will generate churn/failures unrelated to core feature quality.

3. **High:** Localization strategy conflicts with c11mux policy.
- Plan suggests English-only shipping; policy requires translated Japanese for user-facing strings.

4. **High:** Drag plan under-scopes lifecycle.
- Current c11mux overlay path is minimal.
- Fork includes additional `prepare/conclude` plumbing for web drag correctness; ignoring this increases regression risk.

5. **Medium:** Theme-foreground integration seam is unspecified for current c11mux.
- Fork references `defaultForegroundColor`; current c11mux does not expose that property.
- Needs an explicit chosen source (`GhosttyConfig.foregroundColor` or a new runtime accessor).

6. **Medium:** Build steps should follow c11mux tagged-build policy.
- Plan uses generic `xcodebuild … build` language, but local policy requires tagged reloads or tagged derived data paths.

7. **Medium:** Risk level on focus interactions is likely understated.
- `Workspace.swift` focus logic is heavily orchestrated in current c11mux; TextBox focus swaps should be treated as medium risk until validated.

### Alternatives Considered
- **Shortcut default**
  - Option A: Keep `Cmd+Option+T` and rehome close-other-tabs.
  - Option B: Use `Cmd+Option+B` for TextBox (not currently occupied), preserving close-other-tabs.
  - In current c11mux, Option B is the lower-risk integration.

- **Drag integration depth**
  - Option A: Minimal `performDragOperation` patch only.
  - Option B: Port `prepare`/`perform`/`conclude` lifecycle pieces and add tests.
  - Given existing web drop complexity, Option B is safer.

- **Test migration strategy**
  - Option A: Copy fork tests directly.
  - Option B: Port routing/settings tests selectively, rewrite shortcut/default assertions to the final c11mux decisions.
  - Option B avoids importing stale assumptions.

- **Localization rollout**
  - Option A: English now, Japanese later.
  - Option B: Add both now.
  - In this repo’s policy context, Option B is the practical default.

### Readiness Verdict
**Needs revision** before implementation.

I would mark it ready once the plan explicitly resolves:
- Shortcut ownership and migration path for close-other-tabs.
- Drag lifecycle scope (not just terminal fallback branch).
- Test reconciliation strategy (instead of verbatim copy).
- Localization compliance approach aligned with repo policy.

### Questions for the Plan Author
1. Do you want to keep `Cmd+Option+T` for close-other-tabs, or repurpose it for TextBox toggle?
2. If TextBox keeps `Cmd+Option+T`, what is the new shortcut for close-other-tabs and where is that migration specified?
3. Should we default TextBox toggle to `Cmd+Option+B` in c11mux to avoid migration churn?
4. Are we explicitly porting drag lifecycle additions (`prepareForDragOperation` and `concludeDragOperation`) from the fork, or intentionally deviating?
5. What is the canonical foreground-color source for TextBox styling in current c11mux?
6. Should the shortcut work when browser/markdown is focused, and if so, what is expected focus behavior?
7. Is `.all` still the desired default toggle scope for c11mux users, or should `.active` be the safer default?
8. Should submitted text preserve leading/trailing blank lines, or is trimming newlines intentional product behavior?
9. Should “Enable Mode = On” force all existing terminal panels visible immediately, or only new/focused panels?
10. Do you want Japanese translations in the same PR (policy-aligned), or do you want to explicitly approve a policy exception?
11. Should we retain the giant inline test-plan comments in `TextBoxInput.swift`, or slim them down during port for maintainability?
12. Do you want a small pre-port PR that only resolves shortcut ownership + tests baseline before the feature code lands?
