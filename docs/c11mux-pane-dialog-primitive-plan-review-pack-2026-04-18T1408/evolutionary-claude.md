# Evolutionary Plan Review — c11mux Pane Dialog Primitive

**Plan ID**: `c11mux-pane-dialog-primitive-plan`
**Model**: Claude (Opus)
**Review type**: Evolutionary
**Timestamp**: 20260418-1408
**Reviewer posture**: What could this *become*? Where is the latent infrastructure leverage?

---

## Executive Summary

**The plan is framed as "a nicer close-tab confirmation." The actual asset being built is c11mux's first pane-scoped in-UI dialog primitive — and with one or two design nudges, it becomes the universal per-surface interaction substrate that every future in-app prompt, agent handshake, permission gate, inline form, and notification toast will flow through.**

Every agent-forward multiplexer eventually needs an answer to "how do I ask the user something *about a specific pane* without interrupting the other 15 panes?" Today c11mux uses the OS modal alert, which takes the whole window hostage and can't even say which tab is being discussed in a 4×4 grid. The plan fixes that specific pain — but the *mechanism* it introduces (card + scrim + presenter + FIFO queue, per-panel) is exactly the shape of the primitive c11mux needs for at least a dozen other features already visible on the horizon: rename (§8 Q1), permission prompts, agent `/` command handshakes, inline paste confirmation, cross-agent coordination banners, progress + cancel, undo toasts, first-run onboarding, multi-step wizards, drag-drop confirms, and "this agent wants to do X — approve?" prompts.

**The biggest opportunity**: rename this primitive from `PaneDialog` to something that *invites* the second, third, and fourth consumers — and expand the presenter's contract slightly so it can carry non-modal affordances (banners, toasts, progress) alongside modal dialogs. The per-panel FIFO queue + presenter is already the right shape for this; what's missing is the ambition.

**The second-biggest opportunity**: make the presenter **addressable from the socket**. c11mux's `cmux` CLI + socket is how agents speak to the app. A pane-scoped prompt surface that a clear-codex or a Lattice bot can *trigger* (e.g., `cmux confirm --pane <id> --text "Apply this patch?"`) is not a small feature — it's a protocol. Agents currently have no way to ask a human a structured question tied to a specific pane. This plan is one method signature away from giving them one.

**Risk of under-selling**: if this ships as "tab-close dialog, done," the primitive gets special-cased to close confirmations (APIs narrowed to `ConfirmContent`, focus guards scoped only to the runtime-closing case) and the next three consumers each reinvent 30% of the scaffolding. The plan already reserves `.textInput` — good. Reserving the right *shape* of slots matters more than the exact enum cases.

---

## What's Really Being Built

**Stated:** A pane-scoped replacement for `NSAlert` on tab/surface close.

**Actual:** c11mux's first-class **per-surface dialog and interaction substrate**. Specifically:

1. **A per-panel presenter** — a new mini-MVC that owns "what is this pane currently asking / showing / waiting on the human for?" This is a durable piece of architecture, not a one-off view. Every panel now has an in-band channel for "pane wants to talk to the human."
2. **Panel-bounded modality** — the assertion that modality is a property of a *pane*, not a *window*. In a tiling terminal multiplexer with N concurrent agents, this is a foundational claim. Most tools still ship window-modal prompts because they come from a single-focus UI tradition. c11mux is moving to N-focus (N agents, each with their own context).
3. **An async, queueable handshake primitive** — FIFO queue per panel + async continuation is the shape of *any* interaction with a pane that must wait for a human decision. Not just close: rename, "approve command?", "save unsaved work?", "finish multi-step wizard?". Anything with a "resolve later" contract.
4. **A portal-layering escape hatch** — the plan flags the hazard that the Ghostty portal may z-fight the SwiftUI overlay. Solving this (even via fallback) establishes the *pattern* for ever putting SwiftUI UI on top of a Ghostty surface. This pattern is reusable for toast banners, progress indicators, status badges, agent-ownership chips, etc.
5. **A new piece of the agent-coordination vocabulary.** Today an agent running in a pane cannot cause c11mux to display a structured interactive prompt. It can only write ANSI to stdout. A pane-scoped dialog is the beachhead for "agent says: ask the human this question, tied to this pane."

Name it for what it is. `PaneDialog` is accurate but shy. Candidates in §Concrete Suggestions.

---

## How It Could Be Better

### 1. Widen the primitive's contract from "modal dialog" to "pane interaction surface"

Right now the enum is:

```swift
enum PaneDialog {
    case confirm(ConfirmContent)
    // case textInput(TextInputContent)  // reserved
}
```

This locks the mental model to "modal card." Instead:

```swift
enum PaneInteraction {
    case confirm(ConfirmContent)              // modal Y/N
    case textInput(TextInputContent)          // modal Y/N + field
    case choice(ChoiceContent)                // modal multi-option
    case banner(BannerContent)                // non-modal, dismissible, doesn't block keys
    case progress(ProgressContent)            // non-modal, cancellable
    case toast(ToastContent)                  // auto-dismissing
    case form(FormContent)                    // multi-field, staged
    case agentHandshake(AgentHandshakeContent) // special case: agent requested this
}
```

You don't have to *implement* all of these in v1 — just don't paint yourself into "every case is modal and blocks keystrokes." Concretely: the presenter should distinguish between interactions that capture first responder vs. those that do not. The queue semantics should distinguish between "serialize" (current behavior, appropriate for modal) vs. "coexist" (banner + progress at same time is fine).

Effort to widen the contract now: ~30 LOC of enum plumbing. Effort to widen it in six months after three consumers special-cased modal behavior: multi-day refactor across all consumers. Invest here.

### 2. Make the presenter socket-addressable from day one

The plan's §4.6 adds `confirmCloseInPanel(...) async -> Bool`. That's the Swift-side API. Also add a socket command — even a stub — so that agents and the `cmux` CLI can trigger a pane-scoped confirm:

```
cmux confirm --panel <uuid> \
             --title "Apply diff?" \
             --message "10 files, 340 lines" \
             --confirm-label "Apply" \
             --cancel-label "Cancel" \
             --destructive
# exits 0 on accept, 1 on cancel
```

Why this matters disproportionately: today an agent has *no in-app channel* to ask a structured question tied to a pane. Every agent prompt is ANSI-in-terminal, which competes with the agent's own output and is visually indistinguishable from normal text. A socket-triggerable pane-scoped prompt is the first real surface for agent-to-human structured interaction *inside* c11mux's UI, which is exactly the kind of primitive Stage 11 should own.

Guardrails it needs from day one (crib from existing socket policies):
- Rate limit (one pending dialog per panel, queued after).
- Off-main parsing; main-actor only for the actual `present()` call.
- Focus-steal policy: DOES NOT raise the window or activate the app. The card appears in the target pane but does not steal focus from other windows — aligns with the existing socket focus policy.
- Provenance: tag the `PaneInteraction` with the originating agent identity (`socket.agentId`). Render this in the card ("`claude-code` is asking:"). Critical for the case where multiple agents can trigger dialogs on different panes concurrently.

Effort: ~80 LOC for one new socket command + one CLI subcommand. Huge unlock.

### 3. Separate "modality" from "focus capture" — make them orthogonal

The current design couples two things: "dialog is visible" and "terminal input is suppressed." That's right for close-confirm. It's wrong for:

- A banner that says "Tests failed — click to view" (should not suppress typing).
- A progress indicator for a long operation (should not suppress typing).
- An agent handshake where the agent continues running (should not suppress typing in other surfaces).

Restructure:

```swift
protocol PaneInteraction {
    var capturesFocus: Bool { get }    // true for modal dialog, false for banner/progress
    var blocksInput: Bool { get }      // true for modal dialog, false for banner/progress
    var allowsConcurrent: Bool { get } // true for banner/progress, false for modal dialog
}
```

The existing close-confirm case would set all three to `(true, true, false)`. New cases set them differently. The focus-restore guard (§4.7 of the plan) keys off `blocksInput`, not "presenter.current non-nil."

This is the structural change that future-proofs the primitive for non-modal consumers without a v2 rewrite.

### 4. Card should be addressable by `PanelInteraction.id`, not just "the current one"

The plan's `resolveCurrent(accepted:)` is imperative — the overlay view calls it when the user clicks. That works for modal single-current-item, but breaks the moment you want to show two stacked banners or dismiss a specific toast without touching the current dialog.

Widen the API:

```swift
func resolve(_ id: UUID, result: PaneInteractionResult)
func dismissAll()
```

Trivial change, eliminates a class of future bugs.

### 5. The presenter is a publisher; expose it

The plan has `@Published private(set) var current: PaneDialog?`. Good. Also expose:

- `presenter.activeInteractionsPublisher` (the full queue, not just current) — for telemetry, debug views, "pane is busy" indicators in the tab.
- `presenter.pendingConfirmCount` — so tab chrome can show a "!" badge on panes with pending dialogs the user may have missed when switching tabs.

Tab-level unread/pending-prompt indication is the visual-design complement to the per-pane modality claim. Without it, a user can close the tab and miss the prompt that was queued on another pane.

### 6. Completion semantics: enum, not Bool

`completion: (Bool) -> Void` is fine today but ambiguous tomorrow. Move to:

```swift
enum ConfirmResolution {
    case accepted
    case cancelled
    case dismissed          // window closed, panel removed, etc.
    case superseded         // replaced by a higher-priority dialog
}
```

Consumers can treat `cancelled`/`dismissed`/`superseded` identically today (`accepted == false`), but distinguishing them later doesn't require an API break. This matters for the rename case specifically: `dismissed` during a rename should probably re-show the dialog next tab-switch, `cancelled` should not.

### 7. Don't fall back to NSAlert — fall back to "focused window's focused pane"

The plan says: "Falls back to NSAlert if the panel cannot be resolved (defensive)." That's reasonable for safety, but it's also the point at which the primitive gets special-cased and the NSAlert branch lives forever. Alternative:

- For single-panel cases: if `panelId` unresolvable, present on the window's focused pane. Almost always what the user expects anyway.
- For true bulk cases (§5 — close multiple workspaces) where there's no defensible target pane, **use a different surface**: a window-level bottom-banner or sheet that clearly shows the list of affected workspaces. This *earns* not being a pane dialog by being structurally different, not by being an NSAlert.

Getting out of the NSAlert business entirely is the right long-term move. Keeping two paths indefinitely is worse than committing to one modernization.

### 8. Persistence of in-flight dialogs

If a dialog is up and the app crashes, restarts, or the tab is restored from session persistence, what happens? The plan doesn't say. The coordination note with the tier-1 persistence plan says "ephemeral — no persistence interaction." I'd push on this: consider whether a pending rename or pending "approve agent action" dialog should survive a restart. Probably not for close-confirmation (just re-run the check on relaunch). Definitely yes for multi-step forms and some agent handshakes. Design the `PaneInteraction` so *some cases* can declare `var survivesRestart: Bool { get }` — doesn't need implementation in v1, but don't architect it out.

---

## Mutations and Wild Ideas

### Mutation 1: The primitive becomes the **agent consent surface**

This is the highest-leverage mutation. Today when Claude Code wants to run a tool, it either auto-approves (`--dangerously-skip-permissions`) or blocks in-terminal with a y/n prompt. For long-running agent loops, the in-terminal prompt is a massive friction point: the user has to watch every pane, context-switch in, approve, context-switch out.

With a pane-scoped dialog primitive socket-addressable from day one (§2 above), c11mux can become the **consent arbiter for agent actions**. Workflow:

1. Claude in pane A wants to run `rm -rf foo/`.
2. Claude's hook sends `cmux confirm --panel $CMUX_PANEL_ID --title "Run dangerous command?" --message "rm -rf foo/" --destructive`.
3. c11mux shows the dialog on pane A. User in pane B is typing in Claude-B, untouched.
4. User in pane A approves or denies.
5. `cmux confirm` exits 0/1. Claude's hook acts accordingly.

This turns c11mux from "a multiplexer you run agents in" into "the coordination substrate that every agent routes its consent requests through." That's a category jump. It's also *exactly* the thing that distinguishes c11mux from a terminal with tabs — nothing else can do this because nothing else understands pane identity.

### Mutation 2: The primitive becomes the **cross-agent coordination channel**

Once agents can trigger pane-scoped prompts, they can trigger them on *other panes too*. Claude-A wants to know if Codex-B is free. Send `cmux ask --panel $CODEX_B_PANEL --title "Hand off or continue?" --options "Hand off,Continue"`. Codex-B's driving human sees the prompt, decides, replies, and Claude-A's hook reads the answer.

This is dangerous without ACL. Add one: dialogs can only be addressed to panels within the same workspace by default; cross-workspace requires explicit opt-in. Also add provenance display (which agent triggered this) and throttle (one pending prompt per (source-agent, target-panel) pair).

### Mutation 3: The primitive becomes the **inline form runner**

Reserved `.textInput` in the plan is single-field. Widen to `.form(FormContent)` with N fields, validation, and multi-step. Sudden new consumers:

- Workspace creation wizard ("name, template, git branch")
- "Send to agent" composer (richer than textbox plan's per-pane input box)
- Settings overrides scoped to a pane ("use these env vars for this pane only")
- One-off scripts that need input ("paste token here")

This is where the `.textInput` reservation either pays off or locks you in. Going straight to `.form` with N=1 being a degenerate case costs 50 LOC more and removes the need for a second rewrite.

### Mutation 4: The primitive becomes a **pane-scoped notification center**

Today c11mux has `TerminalNotificationStore` — OSC-52-style pane notifications. Today these render as a ring/badge on the pane. They never surface as an inline interactive card. Let them:

- Short-lived toast (auto-dismiss): "Tests passed ✓" — rendered via PaneInteraction.toast on pane A.
- Persistent banner: "Disk full — claude cannot write" — rendered via PaneInteraction.banner, requires dismissal.
- Interactive notification: "Build failed — view log?" → banner with "View / Dismiss" buttons.

This is the merge point between `TerminalNotificationStore` and `PaneDialogPresenter`. One publisher, one queue, one overlay mount site. The naming matters a lot here (§Concrete Suggestions).

### Mutation 5: The primitive becomes the **inline undo/snooze surface**

Closing tabs is where this plan starts. Closing tabs is where modern design patterns have moved past dialogs entirely — Gmail-style inline "Undone" toast. Mutation: instead of confirming *before* close, close immediately and show a 5-second toast on the pane's *replacement content* ("Tab closed — Undo"). The dialog primitive becomes the toast host.

This is slightly bigger scope than the plan wants, but worth naming: it may be that the *correct* evolution for *this specific use case* is to drop the confirmation entirely in favor of an undo toast. The plan just needs to be designed so that pivot is one consumer-level change, not a primitive rewrite.

### Mutation 6: The primitive becomes the **multiplexer-native prompt shell**

Push this far enough and you end up with: every pane has a structured interactive region *separate from the terminal buffer*. Agents and the app compose to populate it. This is starting to look like the TextBox Input plan (§8 Q1 of that plan), but aimed at a different problem. They will converge. See §Sequencing below.

### Wild idea 1: Cross-pane dialog *chaining*

"Confirm delete on pane A, then on pane B, then on pane C." Useful for batch workflows where the user wants per-item confirmation but can't tolerate N separate window modals. Presenter supports this natively once you have per-panel FIFO + async continuations.

### Wild idea 2: Dialogs render in `cmux tree`

`cmux tree` shows the spatial layout. A pane with a pending prompt shows it right there in the tree output. Agents driving other agents can read the tree and detect pending prompts. Full-loop autonomy: Claude-A sees Codex-B has a pending prompt, answers it for Codex-B. Controversial, but fits Stage 11's direction.

### Wild idea 3: Dialog macros / replay

Record a dialog interaction sequence. Replay it against a different set of panes. "Approve this pattern of command across all 5 panes in this workspace" → one dialog that broadcasts the decision to all matching queued dialogs.

---

## What It Unlocks

Once this ships (even the minimal close-confirm version):

1. **The rename follow-up is trivial.** §8 Q1 of the plan already calls this out. Add `.textInput`, wire rename-tab / rename-workspace callsites, done. 1-day follow-up.

2. **Agent consent requests become possible.** Add the socket command (§2 above) and Stage 11 has a meaningful new axis of differentiation from plain terminals.

3. **Non-modal banner / toast infrastructure is 30% done.** The overlay mount point, the portal-z-order resolution, the publisher, and the queue are all reusable. A "show banner on pane" feature becomes a weekend project, not a week.

4. **Test seams land.** The `confirmCloseInPanelHandler` pattern replicated across future cases gives UI tests deterministic hooks for every interactive prompt in the app. This compounds.

5. **The mental model of "pane as an addressable interaction target" hardens.** Future features (progress, status, notifications, agent badges, consent, rename) all snap into the same primitive. Engineering velocity on anything pane-scoped goes up.

6. **Focus-restore guards become a pattern.** The `if presenter.current != nil { return }` check at every `makeFirstResponder` call site (Phase 5 of the plan) is painful to add once. Once it's there, adding new modal-taking surfaces costs zero additional focus work — you just register the next interaction, the guards already cover it.

7. **VoiceOver and keyboard accessibility for in-app prompts gets a home.** Today every NSAlert is doing its own thing. Moving to a primitive lets you improve a11y in one place and have it apply everywhere.

8. **Screenshot-testing the UI becomes possible.** A pane-scoped dialog with a stable accessibility ID is a golden case for snapshot testing. NSAlert is not.

9. **Close-other-tabs-in-pane eventually gets anchored.** §5 says "no anchor" but that's only true if you insist on anchoring to a tab. You *can* anchor on the pane (the parent container holding the tabs). Once the primitive exists, someone will propose this improvement and it'll be mostly "update `closeOtherTabsInFocusedPaneWithConfirmation` to present on the focused pane with a card that lists the N tabs being closed." Good evolution; no plan change needed now.

---

## Sequencing and Compounding

### The plan's sequencing is mostly right, but the *naming* and *API widening* should move earlier.

**Move earlier:**

1. **Phase 0 (new):** Decide the naming. This is a one-way door. `PaneDialog` vs. `PaneInteraction` vs. `PanelPrompt` vs. `PaneBanner` — whichever wins, it shapes the whole enum and everything that imports it. Changing the name later is a 400-file diff. Change it now, zero cost.

2. **Phase 0 (new):** Decide the enum shape. Even if you only implement `.confirm`, commit to the *shape* (modal/non-modal distinction, `capturesFocus`, `blocksInput`, `allowsConcurrent`) so the next two consumers don't each negotiate their own protocol.

3. **Phase 1.5 (new, insert between current Phase 1 and 2):** Design the socket API surface *on paper*. No implementation yet. Ten lines of command definition in `docs/socket-api-reference.md`. Forces the team to confirm the primitive can serve both in-process callers and external (socket/CLI/agent) callers without a refactor.

**Defer:**

- **Rename follow-up** is correctly deferred (§8 Q1). Good.
- **Bulk close redesign** (§5 out-of-scope items) is correctly deferred. But name the target in the plan: "these will graduate to a window-level banner design, not permanently to NSAlert."

**Compound:**

Each phase should earn a reusable affordance:

- Phase 1 (presenter + enum): vend `ConfirmResolution`, not Bool. Future-proof by default.
- Phase 2 (panel conformance): `dialogPresenter` is the stored property, but mark it `public` and document the socket-addressing plan even if not wired. Future callers have the slot.
- Phase 3 (overlay view): solve portal z-order *generally*. Whatever the solution is, write it so the next SwiftUI-on-terminal overlay (agent chip, progress bar, toast) uses the same mount pattern.
- Phase 4 (TabManager wiring): the `confirmCloseInPanel` method should be the *first* of a family. Name it so. Adopt a method naming convention: `presentConfirm`, `presentTextInput`, `presentBanner`. Suggests the API without requiring implementation.
- Phase 5 (focus guards): grep is good, but also add a `PresenterCoordinator` or similar so future focus paths can subscribe once, not audit every site. Light tax now, heavy saving later.
- Phase 6 (localization): two keys today, but create a localization *prefix* convention: `dialog.pane.confirm.*`, `dialog.pane.text-input.*`, `dialog.pane.banner.*`. Enforces discoverability.
- Phase 8 (validation): include a latency baseline with the presenter *mounted but idle*. This becomes the regression baseline for every future consumer.

### Sequencing relative to the textbox-port plan (m9)

Reading both plans together: **the pane-dialog primitive should finalize first, and the textbox port should adopt it for the `TextBoxInput`'s status / error / confirm surfaces.** Specifically:

- TextBox drag-drop has a "file dropped — accept?" affordance today (it inserts directly, no confirm). If that evolves to confirm (e.g., "10 files, some outside working tree — ok?"), it should use the pane dialog primitive.
- TextBox IME errors, shell-escape warnings, submission failures → banner cases of the primitive.
- TextBox + rename = the second consumer (after close-confirm) of the primitive's `.textInput`. The textbox port reserves the "compose" surface. The pane dialog provides the "ask" surface. Don't conflate them, but make them share palette + keyboard contract + focus discipline.

**Recommended order:**
1. Pane dialog primitive lands (m10).
2. Rename-tab / rename-workspace follow-up uses `.textInput` (m10.1, tiny PR).
3. TextBox port lands (m9).
4. TextBox adopts pane dialog primitive for its error/confirm/banner surfaces (m9.1, small PR).

Note the module numbers: the plan calls itself m10 but open question §8 Q6 asks. The dependency order above argues for m10 being **before** m9 in calendar time, even if the numbering says otherwise. Consider renaming m10 → m8a or leaving both parallel but sync on the shared primitive.

---

## The Flywheel

### Engineered flywheel (starts spinning with this plan)

**Loop 1 — primitive adoption:**
Each new consumer of the primitive (rename, banner, toast, progress) reduces the friction for the *next* consumer. Starts at "close-confirm (1 consumer)" and compounds. Goal: by 3 consumers, the marginal cost of the 4th is near-zero.

*Accelerator:* write the primitive docs to include a consumer checklist ("adding a new interaction type: (1) add enum case, (2) add overlay subview, (3) add test hook"). First consumer after close-confirm produces the doc as a PR artifact.

**Loop 2 — agent substrate:**
If the socket API ships in v1 (per §Concrete Suggestions), the loop is:
- Stage 11 agents use pane-dialog for consent / handshakes.
- Users see it work and ask for more (approve-this-command, rename-from-agent, etc.).
- Agents ship new hooks that use it.
- More agents adopt c11mux as the coordination surface.
- c11mux's agent-forward positioning hardens.

This is the **single highest-leverage loop** in the plan. It's also the one most easily killed by scoping out the socket API. Protect it.

**Loop 3 — pane-scoped UI language:**
As the primitive grows, the pane starts accumulating per-pane UI language (cards, banners, progress, notifications, agent chips, consent gates). The *pane* becomes a richer UI surface — a clear visual differentiation from every other terminal multiplexer, which all treat panes as just a bag of cells. This is visual moat.

*Accelerator:* once 2–3 non-modal affordances exist, commission an internal design doc for the "pane UI language" — what can live on a pane, how it layers, animation rules, palette. This both crystallizes the design and becomes a reference for external contributors.

### Latent flywheel (engineer it in)

**Loop 4 — dialog telemetry:**
Every presented dialog is a datapoint. "Users cancel close-confirm 30% of the time — should we drop the confirm?" "Users take 4s median to respond to agent consent prompts — should we add a snooze?" Presenter publishes interaction events; opt-in telemetry aggregates them.

Effort: ~40 LOC + a clear opt-in toggle + respect for Stage 11 privacy defaults. Reward: informed evolution of every future interaction.

**Loop 5 — screenshot corpus:**
Every dialog case becomes a snapshot test with a gold-master PNG. Over time, c11mux accumulates a visual regression corpus. Future SwiftUI / macOS releases that break styling are caught immediately. No other multiplexer has this.

Effort: fold into Phase 8; one snapshot per case. Reward: durable visual-quality insurance.

### What kills the flywheel

- Naming the primitive too narrowly → each new consumer is a different module.
- Scoping out the socket command → agent substrate never spins up.
- Keeping the NSAlert fallback permanent → always have two paths, flywheel halved.
- Not publishing the queue → no pane-level "pending prompt" badge → users miss prompts → users turn off the whole feature.

---

## Concrete Suggestions

### Suggestion 1: Rename the primitive now.

Candidates, ranked:

1. **`PaneInteraction`** — matches the generalization. Enum cases are all "kinds of interactions." Shows up in code as `panel.interactionPresenter.present(.confirm(...))`. Clear, non-committal on modality.
2. **`PanePrompt`** — cuter, scopes to "asking the user something." Slightly narrower than `PaneInteraction`; excludes pure informational banners/toasts. Defensible if you really only ever want "things the user must respond to."
3. **`PanelOverlay`** — too generic; overlaps with "overlay view."
4. **`PaneSpeak`** — Stage 11-voice, probably too clever.

**Recommended: `PaneInteraction`.**

Rename effort *now*: find-and-replace, ~10 files, one commit.
Rename effort *after shipping two consumers*: multi-day audit, breaking API, risk.

### Suggestion 2: Widen the enum shape before shipping.

```swift
public enum PaneInteraction: Identifiable {
    case confirm(ConfirmContent)
    case textInput(TextInputContent)        // not wired v1, slot reserved
    case choice(ChoiceContent)              // not wired v1, slot reserved
    case banner(BannerContent)              // not wired v1, slot reserved
    case toast(ToastContent)                // not wired v1, slot reserved
    case progress(ProgressContent)          // not wired v1, slot reserved
    case form(FormContent)                  // not wired v1, slot reserved

    public var id: UUID { ... }
    public var capturesFocus: Bool { ... }   // key disambiguator
    public var blocksInput: Bool { ... }
    public var allowsConcurrent: Bool { ... }
}
```

Implement only `.confirm` in v1. Other cases are `switch` exhaustiveness placeholders that do nothing. Cost: ~30 extra LOC, mostly enum boilerplate. Benefit: no case-shape migration later.

### Suggestion 3: Socket command stub in v1.

Add **one** socket command — `pane.confirm` — that vends a confirm dialog on a named panel and returns accepted/cancelled.

```
cmux pane confirm --panel <uuid> \
                  --title "..." \
                  --message "..." \
                  --confirm-label "..." \
                  --cancel-label "..." \
                  --destructive
```

Tests: one Python socket test (you have `tests_v2/` already) that fires the command against a tagged build and asserts the response. This is 80 LOC and opens a new product surface.

### Suggestion 4: Make `PaneInteractionPresenter` a `public` type with documented API, not an implementation detail.

The plan treats it as internal panel machinery. Treat it as c11mux's next public API. Add doc comments with examples. Add it to `docs/` (the existing socket-api-reference is a good pattern). Future authors — including external contributors and agents writing their own c11mux-addressable tools — need this to be findable.

### Suggestion 5: Ship the tab-badge for pending interactions.

When `presenter.current != nil` AND the panel is not currently visible (different tab selected, different pane focused), show a subtle indicator on the tab chrome: a dot, the gold focus ring, or an exclamation. Minimal v1: reuse the existing unread-notification ring mechanism (`hasUnreadNotification` is already in TerminalPanelView).

Effort: ~20 LOC — presenter publishes `hasPendingInteraction`, TabItemView reads it, styling reuses existing patterns.
Benefit: users never miss a queued dialog on a backgrounded pane. Without this, queueing is a footgun.

### Suggestion 6: Add a "close panel kills dialog" test that exercises the full close lifecycle.

The plan mentions `clear()` from `close()`. Validate with an end-to-end: panel has pending dialog; parent workspace closes; continuation resolves `cancelled` (or `dismissed`); no leaks, no hangs, no memory issues. This is the footgun that causes apps to wedge. Unit test against the presenter is insufficient; do an integration test.

### Suggestion 7: One-commit rename-tab follow-up as the canary.

Land this plan. Then immediately land a single-commit PR that adds `.textInput` and wires rename-tab. It proves the primitive extends cleanly, exercises the "second consumer" path, and establishes the pattern for all follow-ups. If the extension is painful, you learn before the third consumer is blocked.

### Suggestion 8: Explicit out-of-scope list for this *primitive*, separate from out-of-scope for this *PR*.

The plan's §5 lists what it doesn't change. Add a §5b listing interactions that are *candidates* for this primitive in follow-ups (rename, permission, progress, toast, agent-consent, etc.). Makes the future-mapping intentional rather than reactive.

### Suggestion 9: Redirect "what if bulk close" to a separate design pass.

§5 keeps NSAlert for bulk close. OK for this PR. But commit to killing NSAlert entirely within some time horizon. The half-migration is worse than either fully-migrated or fully-NSAlert. Schedule the follow-up design now, even if the implementation is deferred.

### Suggestion 10: Consider renaming `PaneDialogOverlay` too.

If the primitive becomes `PaneInteraction`, the overlay view should be `PaneInteractionOverlay` — and more importantly, its *job* widens from "render card + scrim" to "render whatever the current interaction needs." Factor it as a dispatcher:

```swift
struct PaneInteractionOverlay: View {
    @ObservedObject var presenter: PaneInteractionPresenter
    var body: some View {
        if let interaction = presenter.current {
            switch interaction {
            case .confirm(let c): ConfirmCardView(content: c, ...)
            case .textInput(let t): TextInputCardView(content: t, ...)
            case .banner(let b): BannerView(content: b, ...)
            // etc.
            }
        }
    }
}
```

Each case's view lives in its own file. First one ships with `.confirm`. This is the single-responsibility factoring; the plan's current monolithic `PaneDialogOverlay` will bloat the moment it handles two cases.

---

## Questions for the Plan Author

1. **Naming.** Will you commit to a name before Phase 1 that invites the second, third, and fourth consumers? `PaneInteraction`, `PanePrompt`, or staying with `PaneDialog` — whichever is fine, but decide knowing that this is a one-way door. What's the intended family this primitive belongs to?

2. **Socket addressability.** Is it acceptable to add a single socket command (`pane.confirm`) as part of this PR, or do you want to defer it to a follow-up? My strong recommendation: include it. Zero cost now, creates a new agent-coordination surface. If deferred, is there a named follow-up ticket?

3. **Non-modal affordances.** Do you agree the enum should distinguish modal vs. non-modal cases from v1, even if v1 only implements modal? This is the single highest-leverage API-shape decision and it affects §4.7's focus-guard design.

4. **Agent consent positioning.** Is Stage 11 interested in this primitive becoming the agent-consent substrate (Mutation 1), or is that out of scope for c11mux and better hosted elsewhere (Lattice, a separate daemon)? The answer shapes how much infrastructure to build into v1.

5. **Bulk-close follow-up.** The plan keeps NSAlert for two cases. Is there intent to migrate these away too, or is NSAlert the permanent answer for "no single anchor" cases? If migrate, when and into what surface?

6. **Rename timing (re-raising §8 Q1).** My recommendation is even stronger than the plan's: rename as a **1-commit canary PR immediately after this one lands**, not a nebulous follow-up. Does that work?

7. **Persistence contract.** For the three cases most likely to hit a restart mid-interaction (rename, form, agent-consent), should the presenter persist pending interactions, or always drop them? This affects the enum shape (add `survivesRestart: Bool`?) and coordinates with the tier-1 persistence plan.

8. **Unified notifications + dialogs.** `TerminalNotificationStore` already exists. Is the direction to eventually merge it into `PaneInteractionPresenter` (one queue, one mount, unified publisher), or keep them as separate systems? If merge, when?

9. **Tab-pending badge.** Concretely: should this PR include the "panel has pending interaction" tab-chrome badge (§Suggestion 5), or leave it for a follow-up? I recommend including — without it, users miss queued prompts on backgrounded panes.

10. **Module numbering and order (re §8 Q6).** Given the dependency analysis (pane-dialog primitive → rename follow-up → textbox adopts for its error/confirm surfaces), should this land **before** the textbox port on the calendar? If yes, the "m10" numbering conflicts with the intent. Reconsider m8a or some ordering that matches dependency direction.

11. **Per-case overlay dispatch (§Suggestion 10).** Are you open to factoring the overlay as a dispatcher with per-case subviews from v1, even though only `.confirm` ships? Trivial now, essential when the second case lands.

12. **Primitive docs.** Will you publish a short "consumer guide" alongside this PR (e.g., `docs/pane-interaction-guide.md`)? This is the single most-leverage piece of documentation: every future consumer needs the patterns in one place. ~200 lines, pays off by the third consumer.

13. **Telemetry.** Is there interest in emitting telemetry for dialog interactions (opt-in, local-only) to inform future evolution? Aligns with the flywheel (Loop 4 above). If yes, Phase 2 adds a publisher hook; if no, defer.

14. **Focus-guard coordinator (vs. grep).** The plan says "grep every `makeFirstResponder` call site." That works once. A coordinator where new focus paths subscribe once is more robust but costs more scaffolding. Worth it, or grep-per-PR acceptable?

15. **Brand alignment in v1.** §8 Q3-Q4 flag the visual design as a guess. Will you coordinate with the brand doc / visual-aesthetic reference before Phase 3, or treat v1's palette as provisional and revisit after launch?

---

## Closing Thought

This plan is solving a real, immediate, visible problem — the 4×4 workspace confusion. Ship it. But name it and shape it so that six months from now nobody has to write a "pane interaction primitive plan" because they're building on the one already here. The cost of a slightly wider enum, a slightly more public presenter, and a single socket command is trivial relative to the optionality it buys. The most dangerous outcome is shipping a primitive named and scoped so narrowly that the next three consumers all have to negotiate their own thing.

The underlying thesis — "modality is a property of a pane, not a window, and that matters for N-agent workflows" — is correct and under-communicated in the current plan. That thesis, not the close-confirm UI, is what this PR is really delivering. Name it. Claim it. Build on it.
