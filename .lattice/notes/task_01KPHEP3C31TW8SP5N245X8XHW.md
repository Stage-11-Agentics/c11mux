# CMUX-12 — Pane title bar chrome & theming (Plan)

**Author:** `agent:claude-opus-4-7-cmux-12-plan` (Plan sub-agent in worktree pane).
**Date:** 2026-05-06.
**Lineage:** CMUX-12 Delegator (`agent:claude-opus-4-7-cmux-12`) → CMUX-12 Plan (this note).
**Branch / worktree:** `cmux-12-pane-title-bar` at `/Users/atin/Projects/Stage11/code/c11-worktrees/cmux-12-pane-title-bar`.
**Plan supersedes:** the pre-scope-alignment brief that previously occupied this file (kept in git history). `docs/c11-pane-title-bar-plan.md` survives but its Phase split + decisions 1, 6, 7 are now stale; this note is the source of truth and the Impl sub-agent should read it first.

CMUX-11 fully shipped (Phases 1–4 merged via #22, #25, #27). `PaneMetadataStore` exposes `setMetadata` / `getMetadata` / `clearMetadata` / `currentRevision`, and pane RPCs `pane.set_metadata` / `pane.get_metadata` / `pane.clear_metadata` are live. The view has data to read.

---

## 1. Confirmed scope (operator approved 2026-05-06: "Go" → all 8 stand)

1. **Phase 1 + Phase 2 absorbed into one PR.** Visible strip + chevron + collapse/expand + right-click menu (Rename, Hide, Expand/Collapse) + inline rename ship together.
2. **Mount point: in-surface.** Inside `Sources/Panels/PanelContentView.swift`, in the same `VStack`, mounted *above* `SurfaceTitleBarView`. Not the bonsplit pane-header builder route. Decision 8 holds.
3. **Title is left-aligned**, mirroring the actual `SurfaceTitleBarView` (which uses `Spacer(minLength: 0)` + leading text). Original Decision 1 (centered) is stale.
4. **Visual differentiation** between pane and surface bars uses the same `titleBar_*` theme roles, with weight/opacity to distinguish: pane bar = `titleBar_foreground` at full weight (semibold); surface bar = `titleBar_foregroundSecondary` (or 0.85 opacity on `titleBar_foreground`) when a pane bar is rendered above it. No new theme roles minted.
5. **Decision 8 strict for this PR.** No edits to `vendor/bonsplit/`. The pane title bar is NOT mounted above the bonsplit tab bar; it lives inside the active surface's chrome stack. This is the documented degraded form of Decision 7 — same paneId across all sibling tabs in the pane, so the title is consistent regardless of which tab is active, but it visually appears below the bonsplit tab bar instead of above the whole pane.
6. **Coordinate with CMUX-10's flash work.** Both touch `Sources/Panels/PanelContentView.swift`. No file-level lock; default to lower-merge-conflict ordering at runtime. Surface in §8.
7. **No separate Phase-3 ticket for theming.** Existing `titleBar_*` roles are sufficient; theming polish lands in this PR.
8. **Stale `cmux→c11` references** in the ticket description and the now-renamed plan doc reference (`c11mux-pane-title-bar-plan.md` → `c11-pane-title-bar-plan.md`) are cleaned up as part of this work.

---

## 2. Architecture

### Mount tree (after this PR)

```
PanelContentView (per active tab in a Bonsplit pane)
  VStack(spacing: 0) {
    PaneTitleBarView                ← NEW. Renders only when:
                                       paneTitle is non-empty AND
                                       !workspace.paneTitleBarHidden.contains(paneId)
    SurfaceTitleBarView             ← existing, becomes secondary-emphasis
                                       when PaneTitleBarView renders above
    contentView (terminal/browser/markdown)
  }
```

Bonsplit tab bar sits *above* `PanelContentView` and is unchanged. The pane title bar therefore appears once per active tab, below the tab bar, above the surface title bar. In a multi-surface pane the visible title bar reads "this pane's identity stays, the active surface changes" — acceptable degraded form of Decision 7.

### State on `Workspace` (in `Sources/Workspace.swift`)

Three new published collections, parallel to the existing surface-side trio (`titleBarCollapsed`, `titleBarUserCollapsed`, `titleBarVisible`), all keyed by the underlying `paneId.id: UUID` (Bonsplit's `PaneID` wraps a UUID at `vendor/bonsplit/Sources/Bonsplit/Public/Types/PaneID.swift`):

```swift
@Published var paneTitleBarCollapsed: [UUID: Bool] = [:]      // chevron state, default true (collapsed)
@Published var paneTitleBarUserCollapsed: Set<UUID> = []      // user toggled — suppresses auto-expand
@Published var paneTitleBarHidden: Set<UUID> = []             // right-click → Hide; ephemeral
```

Plus two published mirrors so SwiftUI re-renders on metadata writes without subscribing to `PaneMetadataStore` directly:

```swift
@Published var paneTitles: [UUID: String] = [:]        // empty / unset → no key
@Published var paneDescriptions: [UUID: String] = [:]
```

These mirrors are written from the same code path that handles `pane.set_metadata` / `pane.clear_metadata` socket commands (see §3 file anchors). The store remains source of truth; the mirrors exist purely so the SwiftUI body sees a `@Published` change.

### Workspace-level helpers

```swift
func paneTitleBarState(paneId: UUID) -> PaneTitleBarState
func togglePaneTitleBarCollapsed(paneId: UUID)
func hidePaneTitleBar(paneId: UUID)
func setPaneTitle(paneId: UUID, title: String?) throws        // wraps PaneMetadataStore.setMetadata
func maybeAutoExpandPaneTitleBar(paneId: UUID)                // mirror of surface auto-expand
```

`PaneTitleBarState` is a new `Equatable` value struct in the same file as `PaneTitleBarView`:

```swift
struct PaneTitleBarState: Equatable {
    var title: String?
    var description: String?
    var titleSource: MetadataSource?
    var descriptionSource: MetadataSource?
    var visible: Bool         // false when hidden or title is nil/empty
    var collapsed: Bool       // chevron state
}
```

Rendering rule in `PanelContentView`:
- `PaneTitleBarView` renders iff `state.visible && (state.title?.isEmpty == false)`.
- When `PaneTitleBarView` renders, `SurfaceTitleBarView` receives `secondaryEmphasis: true` so its header drops to `titleBar_foregroundSecondary`.

### Dual-bar emphasis

The smallest change to `SurfaceTitleBarView` that satisfies decision 4:

- Add `var secondaryEmphasis: Bool = false` to `SurfaceTitleBarState`.
- In `headerRow` (`Sources/SurfaceTitleBarView.swift:136`), pick foreground via `state.secondaryEmphasis ? resolvedSecondaryForegroundColor : resolvedForegroundColor`.
- `PanelContentView` computes `secondaryEmphasis` as `paneTitleBarState.visible && paneTitleBarState.title?.isEmpty == false`.

No font-weight change: weight stays `.semibold` for both bars. Differentiation is colour role only, which is exactly what `titleBar_foreground` vs `titleBar_foregroundSecondary` exists for.

### Reactivity

Today, `surfaceTitleBarState(panelId:)` reads `SurfaceMetadataStore.shared.getMetadata` directly inside the SwiftUI body and gets re-evaluated whenever any `@Published` on `Workspace` changes. We follow the same model for panes — but the published `paneTitles` / `paneDescriptions` mirrors mean we don't have to touch `PaneMetadataStore` from the body at all. The body becomes a pure read of `Workspace`'s published collections, which is cheap and matches the `TabItemView` precomputed-let pattern in spirit.

---

## 3. Affected code paths (file:line anchors)

### Add (new files)

- **`Sources/Panels/PaneTitleBarView.swift`** — new. Mirrors `SurfaceTitleBarView` structurally: `headerRow` (left-aligned title + chevron), `descriptionRow` with the same Markdown subset, `chromeScaleTokens` consumption, `titleBar_*` theme role adoption. ~250 LoC; smaller than `SurfaceTitleBarView` because there is no `m1bSurfaceTitleBarMigrated` legacy fallback to thread through (we ship adopted from day one).

### Modify

- **`Sources/Panels/PanelContentView.swift:21–32`** — extend the existing `VStack` to add `PaneTitleBarView` above `SurfaceTitleBarView`. Pass `paneTitleBarState` from `workspace.paneTitleBarState(paneId: paneId.id)`. Compute `secondaryEmphasis` for the surface bar. Update `drawsPortalTopFrameEdge` (line 42) so the frame edge is suppressed when *either* bar is visible.
- **`Sources/SurfaceTitleBarView.swift:16–24, 136–158`** — add `secondaryEmphasis: Bool = false` to `SurfaceTitleBarState`. Switch the title `Text` foreground in `headerRow` to honour it. No-op on existing call sites (default false).
- **`Sources/Workspace.swift`**:
  - **5236–5247** — declare the three new `@Published` collections and the two mirrors next to the existing surface-side trio.
  - **6892–6927** — add the pane analogues: `maybeAutoExpandPaneTitleBar`, `paneTitleBarState`, `togglePaneTitleBarCollapsed`, `hidePaneTitleBar`, `setPaneTitle`. Mirror the pattern used by `maybeAutoExpandTitleBar` / `surfaceTitleBarState` / `toggleSurfaceTitleBarCollapsed`.
  - **~6929–6955** — add `paneTitleBarStatePayload(paneId:)` (socket-ready dict, parallels `titleBarStatePayload`). Used by any future socket query. Optional this PR; ship if cheap.
  - **7040–7057** (`pruneSurfaceMetadata`) — extend pruning to drop `paneTitleBarCollapsed`, `paneTitleBarUserCollapsed`, `paneTitleBarHidden`, `paneTitles`, `paneDescriptions` for paneIds not in `bonsplitController.allPaneIds`. Add a sibling `prunePaneMetadata(validPaneIds:)` if the surface-prune signature doesn't already pass pane state.
  - **socket handler for `pane.set_metadata` / `pane.clear_metadata`** (search `PaneMetadataStore.shared.setMetadata` / `.clearMetadata` call sites in the socket dispatcher) — after the store write, update `paneTitles[paneId.id]` / `paneDescriptions[paneId.id]` so the view re-renders. The existing surface analogue does the same thing for `panelTitles`.
- **`Sources/WorkspaceContentView.swift:76–119`** — no change needed. `PanelContentView` already receives `paneId` here; the new view consumes it through `workspace.paneTitleBarState(paneId: paneId.id)`.
- **`Resources/Localizable.xcstrings`** — add new keys (English only this PR, six-locale translator pass spawned post-impl per CLAUDE.md):
  - `paneTitleBar.chevron.expand` → "Expand pane title bar"
  - `paneTitleBar.chevron.collapse` → "Collapse pane title bar"
  - `paneTitleBar.empty_title` → "Untitled pane"
  - `paneTitleBar.contextMenu.rename` → "Rename…"
  - `paneTitleBar.contextMenu.hide` → "Hide title bar"
  - `paneTitleBar.contextMenu.expand` → "Expand"
  - `paneTitleBar.contextMenu.collapse` → "Collapse"
  - `paneTitleBar.rename.placeholder` → "Pane title"
  - `paneTitleBar.rename.error.tooLong` → "Title is too long"
- **`docs/c11-pane-title-bar-plan.md`** — surgical annotation (top banner) noting Phase 1+2 absorbed; decisions 1 (centered → left-aligned), 6 (in-flight theming → existing tokens), 7 (above whole pane → above active surface). Don't rewrite the doc; just mark the parts that no longer match shipped reality.
- **CMUX-12 ticket description** — replace `docs/c11mux-pane-title-bar-plan.md` → `docs/c11-pane-title-bar-plan.md`, drop "in-flight c11mux theming plan" phrasing in favor of "existing `titleBar_*` theme roles". Done via `lattice update` from `$REPO_ROOT`.

### Read-only references for the impl agent

- **`Sources/SurfaceTitleBarView.swift:16–353`** — the precedent. Copy-and-adapt for layout, theme adoption, chevron behavior, and the `sanitizeDescriptionMarkdown` + `titleBarMarkdownTheme` helpers (these are file-private; the pane view should reuse them, so either move them to a shared file or call into them via an `internal` exposure).
- **`Sources/PaneMetadataStore.swift:22–238`** — full API. Use `setMetadata` with `mode: .merge`, `source: .explicit` for inline rename. Use `clearMetadata` with `keys: [MetadataKey.title]` to clear (when operator submits empty in the rename field).
- **`Sources/SurfaceMetadataStore.swift:11–32`** — `MetadataKey.title` / `MetadataKey.description` constants are shared (PaneMetadataStore reuses them).
- **`Sources/ContentView.swift:10940–11037`** — `TabItemView` Equatable + precomputed-let precedent. Not directly extended in this PR, but the impl agent must understand the discipline before adding any state to PanelContentView (see §6 hot-path discipline).
- **`Sources/Chrome/ChromeScale.swift:122–187`** — `ChromeScaleTokens.surfaceTitleBarTitle` / `.surfaceTitleBarAccessory` are reused for pane bar sizing (no new tokens minted).
- **`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitView.swift:1–125`** — confirms there is no pane-header slot. Read-only; no edits.

---

## 4. Commit grouping (4 commits, each independently reviewable, build-green)

Each commit subject: `# CMUX-12 commit N: <…>`. Each commit must build and pass `xcodebuild -scheme c11-unit` in CI (per the project testing policy, no local runs).

### Commit 1 — Workspace state + observable mirrors

- Add `paneTitleBarCollapsed`, `paneTitleBarUserCollapsed`, `paneTitleBarHidden`, `paneTitles`, `paneDescriptions` to `Workspace`.
- Add `paneTitleBarState`, `togglePaneTitleBarCollapsed`, `hidePaneTitleBar`, `setPaneTitle`, `maybeAutoExpandPaneTitleBar`.
- Wire `pane.set_metadata` / `pane.clear_metadata` socket handlers to mirror title/description into the published dicts (after the existing `PaneMetadataStore.shared.setMetadata` call).
- Extend pruning to drop pane-id-keyed state when panes close.
- No view changes yet. Build green; nothing user-visible.

### Commit 2 — `PaneTitleBarView` + `PanelContentView` mount + dual-bar emphasis

- Add `Sources/Panels/PaneTitleBarView.swift` with `headerRow` (chevron + left-aligned title) and `descriptionRow` (Markdown subset). Adopts `titleBar_*` theme roles directly; consumes `chromeScaleTokens`.
- Promote `sanitizeDescriptionMarkdown` and `titleBarMarkdownTheme` from file-private in `SurfaceTitleBarView.swift` to file-internal (top-level `internal func`) so `PaneTitleBarView` reuses them.
- Add `secondaryEmphasis: Bool = false` to `SurfaceTitleBarState`; honour it in `SurfaceTitleBarView.headerRow`.
- Edit `Sources/Panels/PanelContentView.swift` to render `PaneTitleBarView` above `SurfaceTitleBarView` in the existing `VStack`. Compute `secondaryEmphasis` for the surface bar from pane-bar visibility. Adjust `drawsPortalTopFrameEdge` so it stays suppressed when *either* bar is visible.
- Localized chevron labels minted for the pane bar (`paneTitleBar.chevron.expand`, `.collapse`, `.empty_title`).
- User-visible milestone: a named pane shows the pane title bar above the surface title bar.

### Commit 3 — Right-click context menu + inline rename

- Add `.contextMenu` to `PaneTitleBarView` with three items: Rename…, Hide title bar, Expand/Collapse (label flips with state).
- Inline rename: `@State private var isRenaming: Bool` + `@State private var draftTitle: String`. While renaming, swap the title `Text` for a `TextField` with `.focused()` binding and `.onSubmit` → `workspace.setPaneTitle(paneId: paneId, title: trimmed)`; Escape (`.onExitCommand`) cancels. Click-away cancels (focused-state observer that drops the field on focus loss).
- Error surface: if `setPaneTitle` throws (cap exceeded, etc.), restore the prior title and show a transient inline banner using `paneTitleBar.rename.error.tooLong`. No alert dialog (per the "trust the operator, it's text" philosophy from the plan doc).
- Localized strings minted for menu items + placeholder + error banner.
- This is the second user-visible milestone: operators can rename, hide, and toggle from the strip without using the CLI.

### Commit 4 — Ticket text + plan doc cleanup

- `lattice update CMUX-12` (from `$REPO_ROOT`): replace `docs/c11mux-pane-title-bar-plan.md` → `docs/c11-pane-title-bar-plan.md`, replace "the in-flight c11mux theming plan" with "the existing `titleBar_*` theme roles". Update via the API the agent has, no manual ticket edits.
- Append a "**2026-05-06 — Phase 1+2 absorbed**" banner to the top of `docs/c11-pane-title-bar-plan.md` with bullet points: (i) Phase 1+2 absorbed; (ii) Decision 1 left-aligned; (iii) Decision 6 uses existing tokens; (iv) Decision 7 degraded to in-surface mount per CMUX-12 plan note. Don't rewrite the body — the banner makes the doc honest without throwing away the Plan-phase prose that's still useful.
- No code changes in this commit. Doc + ticket-text only.

**Why four commits, not six.** Localization strings ride alongside their first-use commits (commits 2 and 3) so the build stays green at every commit; splitting them into a standalone commit would gate the impl commits on a separate review. The Workspace-state commit is a clean foundation that builds-but-does-nothing, which is the cheapest review surface to land first.

---

## 5. Tests

Per the project test-quality policy in CLAUDE.md (Sources/CLAUDE.md "Test quality policy" section): no source-text grep tests, no `Localizable.xcstrings` shape assertions, no AST checks. Tests must verify observable runtime behavior.

### Behavioral seams that already exist (use these)

- **Workspace's `paneTitleBarState(paneId:)` is a pure function over `@Published` state + `paneTitles` / `paneDescriptions` mirrors.** Add a unit test that constructs a Workspace, mutates `paneTitles` / `paneTitleBarCollapsed` / `paneTitleBarHidden` directly, and asserts the returned `PaneTitleBarState` matches expectations across the visibility / collapse / hide truth table.
- **`PaneMetadataStore` has a `currentRevision()` counter and a public API that's already exercised by CMUX-11 unit tests.** Add a unit test that calls `Workspace.setPaneTitle(paneId:title:)` and asserts (a) the store reflects the write at `MetadataKey.title`, (b) `Workspace.paneTitles[paneId]` is the published mirror.

### Behavioral seams to add

- **A test seam on `Workspace` that handles a `pane.set_metadata` socket payload** — refactored out of the existing socket dispatcher into a small `applyPaneMetadataWrite(paneId:partial:)` method (call site: existing socket handler). Test asserts that title and description writes update both the store and the published mirror.

### What we explicitly do NOT test in this PR

- **The chevron-toggle visual.** No SwiftUI snapshot tests — those degrade to source-shape tests in the project's policy. Validate visually in the tagged build during the Validate phase.
- **Inline rename UI flow.** Same reasoning — covered by computer-use validation in a tagged build, not unit tests.
- **Localizable.xcstrings shape.** Covered by the existing translator workflow at the language level; we don't write tests that grep the file.

If the impl agent finds a richer behavioral seam (e.g. one that lets us route a "rename submit" through a non-UI code path and assert the cap-exceeded error case), great — add it. Otherwise the unit-level seams above are the floor.

---

## 6. Hot-path discipline

The view is mounted into `PanelContentView`, which is rebuilt on every `WorkspaceContentView` body re-evaluation. That re-eval runs whenever `workspace` publishes any change. Three concrete rules for the impl agent:

1. **Don't subscribe to `PaneMetadataStore` from the view.** Read pane title/description from `Workspace.paneTitles` / `paneDescriptions` only. The store's `currentRevision()` is *not* a SwiftUI `@Published` and must not be polled in the body.
2. **Don't add `@EnvironmentObject` to `PaneTitleBarView`.** It would subscribe the view to every publish on the injected object. Use the existing `@ObservedObject private var themeManager = ThemeManager.shared` precedent from `SurfaceTitleBarView.swift:33` — that one is OK because it's a singleton with infrequent publishes.
3. **`PanelContentView` is not Equatable.** It re-evaluates on every workspace publish, which is the existing reality (the surface bar already lives there). The new pane bar adds one more `paneTitleBarState(paneId:)` call per re-eval, which is a dictionary lookup over `paneTitles` / `paneDescriptions` plus a `Set` membership check. No allocations, no I/O. Acceptable.

Nothing in `PanelContentView`'s render path is on the keyboard event hot path; that path lives in `WindowTerminalHostView.hitTest` and `TerminalSurface.forceRefresh`, neither of which this PR touches.

---

## 7. Localization

New keys, English only, all minted at the call site via `String(localized: "key", defaultValue: "English")`:

```
paneTitleBar.chevron.expand           — "Expand pane title bar"
paneTitleBar.chevron.collapse         — "Collapse pane title bar"
paneTitleBar.empty_title              — "Untitled pane"
paneTitleBar.contextMenu.rename       — "Rename…"
paneTitleBar.contextMenu.hide         — "Hide title bar"
paneTitleBar.contextMenu.expand       — "Expand"
paneTitleBar.contextMenu.collapse     — "Collapse"
paneTitleBar.rename.placeholder       — "Pane title"
paneTitleBar.rename.error.tooLong     — "Title is too long"
```

After the impl PR is open, spawn one translator sub-agent in a fresh c11 surface with the six-locale instruction (ja, uk, ko, zh-Hans, zh-Hant, ru) per CLAUDE.md. Nine keys total — single-agent pass is fine, no need to parallelize per locale. The translator reads `Resources/Localizable.xcstrings`, syncs the new keys for all six locales, writes back. Land the translation as a separate small commit on the same branch (`# CMUX-12 commit 5: localization translations`) so the impl PR's review surface stays focused on the Swift code.

---

## 8. Risks and conflicts

### CMUX-10 file overlap (medium, mitigatable)

CMUX-10 is `in_progress` as of 2026-05-06T03:47Z, also touching `Sources/Panels/PanelContentView.swift` (flash envelope around pane content + sidebar tab). The two PRs overlap in this file. Two outcomes are possible:

- **CMUX-10 lands first.** This PR rebases on top, adds `PaneTitleBarView` to the `VStack` *inside* the flash envelope so a flashing pane still flashes its title bar coherently. Likely low-friction: insertion point is clear.
- **CMUX-12 lands first.** CMUX-10 rebases on top, wraps the existing `VStack` (now containing both bars + content) in its envelope. Also likely low-friction.

**Mitigation.** Don't lock ordering ahead of time. Whichever PR is first to land green wins; the second rebases. The Impl agent should rebase against `origin/main` immediately before opening the PR and resolve any flash-related diff conservatively. Flag in the PR description so the Trident review takes the merge surface seriously.

### ChromeTokens scaling (low)

`ChromeScaleTokens.surfaceTitleBarTitle` and `.surfaceTitleBarAccessory` are reused for the pane bar. At extreme scale settings two stacked title bars could feel chrome-heavy on a small pane. Acceptable for v1; operators can use Hide on the pane bar (or set no pane title) if it bothers them. No mitigation needed in this PR.

### Cap edge cases (low)

`PaneMetadataStore` enforces a 64 KiB blob cap. A multi-paragraph pane description hits the cap path. The inline rename UI is title-only — no description edit — so the rename code path can't hit the cap by itself. The store throws `WriteError.payloadTooLarge`; `setPaneTitle` propagates that and the view restores the prior title with the inline error banner. Already covered in commit 3.

### Dual-bar visual ergonomics (low; design decision baked in)

When a pane is named *and* the active surface inside it is named, two title bars stack. Operator decision 4 (primary vs secondary foreground) is what makes that stack readable rather than two competing strips. If the visual outcome turns out to be too subtle in the Validate phase, the follow-up is to bump pane-bar font weight to `.bold` (still using shared roles). Don't pre-empt that here — ship the secondary-emphasis baseline, validate visually, iterate only if needed.

### `sanitizeDescriptionMarkdown` and `titleBarMarkdownTheme` promotion (very low)

These are currently file-private in `SurfaceTitleBarView.swift`. Commit 2 promotes them to file-internal so `PaneTitleBarView` can reuse them. No external API change; SwiftUI compiler should accept the visibility bump cleanly. If there's a name collision in the c11 module, prefix with `titleBarShared_` and update both call sites in the same commit.

---

## 9. Open questions for the delegator

None that block Plan → Impl. The four operator-confirmed scope decisions (1+2 absorbed, in-surface mount, left-aligned, secondary-emphasis) cover the load-bearing choices. Three sub-decisions made unilaterally by this plan that the delegator should sanity-check before greenlighting impl:

1. **Three-flag state model** (`paneTitleBarCollapsed` + `paneTitleBarUserCollapsed` + `paneTitleBarHidden`) versus collapsing Hide into `paneTitleBarUserCollapsed`. The plan doc and the operator's Decision 4 phrasing arguably collapse them; this plan keeps Hide separate so right-click → Hide is "fully gone for the session" and chevron-collapse is "compact view." If the delegator wants the simpler two-flag model, swap `paneTitleBarHidden` for "userCollapsed implies fully hidden" in commit 1; small refactor.
2. **Promotion of `sanitizeDescriptionMarkdown` / `titleBarMarkdownTheme`** to file-internal versus duplication into `PaneTitleBarView`. Plan picks promotion. If the delegator prefers strict isolation, duplicate; cost is ~80 LoC and one drift risk.
3. **Banner in `docs/c11-pane-title-bar-plan.md`** versus deleting the plan doc entirely. Plan picks banner. The doc still has useful background prose (motivation, rollout, risks); only specific decisions are stale. If the delegator wants the doc removed, swap commit 4's annotation for a `git rm` and a corresponding update to anything that references it.

If silence, all three stand.

---

## 10. Definition of done for this Plan phase

- [x] Plan note written at this path.
- [ ] TL;DR comment posted to CMUX-12 (next step; goes to `$REPO_ROOT` via `lattice comment`).

After the comment is posted: the Plan phase stops. The delegator transitions status to `planned` and spawns the Impl sub-agent in a separate sibling surface.
