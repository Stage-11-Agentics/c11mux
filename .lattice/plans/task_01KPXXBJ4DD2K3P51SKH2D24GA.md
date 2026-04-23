# C11-12 Plan — Remove bottom status bar; move Jump-to-Latest-Unread into sidebar footer

**Task:** C11-12
**Supersedes:** CMUX-36 (introduced the bottom bar)
**Priority:** medium
**Status target at end of plan phase:** `planned`

---

## 1. Motivation

The bottom status bar (`BottomStatusBarView`) has sat in the main window since CMUX-36 holding exactly one tenant — the Jump-to-Latest-Unread button. A full-width 32pt chrome strip for one button that already has a keyboard shortcut, a menu-bar entry, and an NSStatusItem is disproportionate, costs vertical terminal real estate, and adds a third competing surface (top tabs, sidebar, bottom bar) for operator attention.

Consolidation into the sidebar footer is the right move:

- The sidebar footer already hosts operator-facing utility buttons (`SidebarHelpMenuButton` at `?`, `UpdatePill`). A bell icon is a natural sibling.
- Footer icon buttons already have a styled home: `SidebarFooterIconButtonStyle` (22pt frame, 11pt SF symbol, hover/press states).
- The bottom bar can go entirely. No other tenants were ever added.
- Reclaims 32pt of window height + a `Divider` for the terminal — the thing the user is actually here for.

**User decision (recorded):** icon-only with tooltip + badge. No text label in the new placement.

---

## 2. Current state — concrete anchors

| Concern | File | Line(s) | Notes |
|---|---|---|---|
| Bottom bar view | `Sources/StatusBar/BottomStatusBarView.swift` | 1–46 | Generic 3-slot container (`Leading/Center/Trailing`), 32pt height, `.bar` background, top `Divider`. Only mount site below. |
| Bottom bar mount | `Sources/ContentView.swift` | 2414 | `BottomStatusBarView(leading: { JumpToUnreadStatusBarButton() })` inside root `VStack(spacing: 0)` of `ContentView.body`. |
| Jump button | `Sources/StatusBar/JumpToUnreadStatusBarButton.swift` | 1–87 | Full bell + text + badge capsule. Reads `TerminalNotificationStore` via `@EnvironmentObject`. Calls `AppDelegate.shared?.jumpToLatestUnread()`. |
| Display model | `Sources/StatusBar/StatusBarButtonDisplay.swift` | 1–26 | Pure value type: `isEnabled`, `badgeText` from `unreadCount`. Keep — it's still useful. |
| Sidebar footer wrapper | `Sources/ContentView.swift` | 9444–9458 (`SidebarFooter`) | DEBUG/RELEASE branch; same 6/10/6 padding in both. |
| Sidebar footer buttons | `Sources/ContentView.swift` | 9460–9471 (`SidebarFooterButtons`) | `HStack(spacing: 4)` → `SidebarHelpMenuButton` + `UpdatePill`. **Insertion point.** |
| Help button (style ref) | `Sources/ContentView.swift` | 10170–10213 (`SidebarHelpMenuButton`) | Canonical footer icon button: 22pt frame, 11pt symbol, `SidebarFooterIconButtonStyle`, `.safeHelp(...)`, a11y label. |
| Dev footer | `Sources/ContentView.swift` | 10565–10586 (`SidebarDevFooter`) | DEBUG wrapper reuses `SidebarFooterButtons` — nothing extra to do. |
| Footer button style | `Sources/ContentView.swift` | 10532–10563 | `SidebarFooterIconButtonStyle` — apply to the new bell button. |
| Localization strings | `Resources/Localizable.xcstrings` | keys `statusBar.jumpToUnread.accessibility` (46416), `statusBar.nextNotification.title` (46463) | Already translated into ja / uk / ko / zh-Hans / zh-Hant / ru. **Keep keys, reuse translations** — see §5. |
| Shortcut wiring | `AppDelegate.swift:9103` (`jumpToLatestUnread()`) etc. | — | No changes. Multiple other callers (menu-bar item, NSStatusItem, `c11App.swift` menu entries, keyboard shortcut handler). The button is one surface among many. |

No other callers of `BottomStatusBarView` or `JumpToUnreadStatusBarButton` exist in the repo (grepped across `Sources`, `Tests`, `tests_v2`, `docs`, `CHANGELOG.md`, `cmux-cli`). Safe to delete both types outright.

---

## 3. Design — the new sidebar-footer bell

A new compact view, `SidebarJumpToUnreadButton`, that matches `SidebarHelpMenuButton`'s visual weight. Placed as a **trailing sibling of `SidebarHelpMenuButton`** inside `SidebarFooterButtons`' HStack, before `UpdatePill`.

### Visual spec

- **Frame:** 22×22pt (same as help button).
- **Icon:** `bell` SF symbol, 11pt, `.medium` weight, `.monochrome` rendering mode, `Color(nsColor: .secondaryLabelColor)` — matches help button's visual treatment exactly.
- **Button style:** `SidebarFooterIconButtonStyle()` — hover/press states come for free.
- **Badge:** small numeric overlay in the top-trailing corner of the 22pt frame when `unreadCount > 0`. Styled to survive on the narrow sidebar background — capsule fill tuned to the sidebar, not the old bar. Same `StatusBarButtonDisplay.badgeText` formatter (two-digit cap, `99+`) so it agrees with the menu-bar and dock surfaces.
- **Disabled state:** when `unreadCount == 0`, button is `.disabled(true)`, opacity ~0.45, no badge. Consistent with the old behavior's intent (can't jump when there's nothing to jump to) but visually quieter since it sits in persistent chrome.
- **Tooltip / a11y:** `.safeHelp(...)` using `KeyboardShortcutSettings.Action.jumpToUnread.tooltip(label)` — identical pattern to the current button — so the keyboard shortcut hint is still surfaced. Accessibility label identical to today.

### Dependency shape

- Reads `TerminalNotificationStore` via `@EnvironmentObject`. The store is already injected at app root and is therefore available where the sidebar renders. Verify with a quick trace during implementation; if it isn't threaded to `VerticalTabsSidebar`, pass it into `SidebarFooter` explicitly rather than adding a new environment injection (minimal surface).
- Calls `AppDelegate.shared?.jumpToLatestUnread()` via `DispatchQueue.main.async` — identical to the current implementation.
- Reuses `StatusBarButtonDisplay`. That type gets a lighter home (see §4 on file organization).

### Placement & ordering

```
SidebarFooterButtons HStack(spacing: 4):
  [ ?  ]  [ bell ]  [ UpdatePill ...               ]
  help    jump-to-  existing
          unread
```

Help first, jump second, `UpdatePill` filling the trailing space. Rationale: help is the most-used footer item; the bell is secondary and should sit next to it rather than competing with the update pill.

---

## 4. File organization

- **Delete** `Sources/StatusBar/BottomStatusBarView.swift`.
- **Delete** `Sources/StatusBar/JumpToUnreadStatusBarButton.swift`.
- **Keep** `Sources/StatusBar/StatusBarButtonDisplay.swift` — still useful. Move it to `Sources/Notifications/StatusBarButtonDisplay.swift` (or rename to `JumpToUnreadDisplay.swift`) since it's no longer a "status bar" concept. Update the type name if it moves (`JumpToUnreadDisplay`) and its call sites (there's one: the new sidebar button). **Optional / nice-to-have — can be a follow-up chore.**
- **Delete** the entire `Sources/StatusBar/` directory if we move `StatusBarButtonDisplay` out, so we don't leave a one-file orphan folder. Otherwise leave it and do the cleanup as a follow-up.
- **Add** `Sources/Sidebar/SidebarJumpToUnreadButton.swift` (or inline into `ContentView.swift` next to `SidebarHelpMenuButton` — see **decision point** below).

**Decision point — inline vs new file:** `SidebarHelpMenuButton` is `private` inside `ContentView.swift`. The new bell button will naturally fit there too, reusing the same `SidebarFooterIconButtonStyle` that's also file-private. Two options:

1. **Inline** as another `private struct SidebarJumpToUnreadButton: View` in `ContentView.swift` next to `SidebarHelpMenuButton`. Matches the existing pattern. Keeps one concern in one file. **Recommended.**
2. **Extract to new file**, which forces `SidebarFooterIconButtonStyle` to become non-private. Extra churn for no clarity win.

**Recommendation: inline.** Match the surrounding pattern.

---

## 5. Localization handling

Two existing xcstrings keys cover this surface:

- `statusBar.jumpToUnread.accessibility` → "Jump to next unread notification"
- `statusBar.nextNotification.title` → "Go To Next Notification"

Both are already translated into all six locales (ja / uk / ko / zh-Hans / zh-Hant / ru). Two options:

1. **Keep keys as-is, reuse translations.** The `statusBar.` prefix is a harmless implementation artifact in a key name. Zero translation work. The tooltip reuses `statusBar.nextNotification.title` as its label base (via `KeyboardShortcutSettings.Action.jumpToUnread.tooltip(...)`), accessibility label reuses `statusBar.jumpToUnread.accessibility`. **Recommended.**
2. **Rename to `sidebar.jumpToUnread.*`.** Semantic key name hygiene, but triggers a full re-translation pass across six locales for no operator-visible change. Not worth it.

**Recommendation: keep keys, reuse translations. No translator sub-agent spawn needed.**

If we later consolidate the string keys during a broader localization cleanup, do it then — not as part of this task.

---

## 6. Step-by-step implementation sequence

Small, reviewable commits. Each step leaves `main` buildable.

1. **Add the new sidebar button.** Introduce `SidebarJumpToUnreadButton` inline in `ContentView.swift` next to `SidebarHelpMenuButton`. Wire it through `SidebarFooterButtons` between `SidebarHelpMenuButton` and `UpdatePill`. At this point, **both surfaces exist** — bell appears in the sidebar footer AND the bottom bar still shows the old button. Build, verify, sanity-check that the environment object injection reaches the sidebar. Commit.
2. **Remove the bottom bar mount.** Delete line 2414 in `ContentView.swift` (`BottomStatusBarView(leading: { JumpToUnreadStatusBarButton() })`) and collapse the enclosing `VStack(spacing: 0)` — now a single child, may be replaceable with the child directly. Verify the window chrome tightens by 32pt. Commit.
3. **Delete dead files.** Remove `Sources/StatusBar/BottomStatusBarView.swift` and `Sources/StatusBar/JumpToUnreadStatusBarButton.swift`. Update `project.pbxproj` references. Commit.
4. **(Optional follow-up, separate commit)** Move `StatusBarButtonDisplay.swift` out of `Sources/StatusBar/` to a saner home, update the single call site, delete the now-empty directory. Defer to follow-up chore if it adds surface to the review.

The three-step sequence exists so the bottom bar's removal is a separately-revertible commit from the sidebar addition, in case any regression surfaces.

---

## 7. Validation

Per project policy, do not run tests locally. Validation plan:

- **Tagged reload build** (`./scripts/reload.sh --tag c11-12-jump-unread`) after each commit; visually confirm in the running tagged instance:
  - Sidebar footer shows: `[?]  [bell]  [UpdatePill]` in order.
  - Bell is disabled & dim when `unreadCount == 0`.
  - Bell is enabled with a numeric badge when terminals post notifications (reproduce by running a command that triggers `TerminalNotificationStore` — e.g., the same flow used to validate CMUX-36).
  - Click jumps to the latest unread, same as before.
  - Keyboard shortcut (cmd+option+n or whatever the user's binding is) still works — confirms the `AppDelegate` code path is untouched.
  - Menu bar → Notifications → Jump to Latest Unread still works — same path, separate surface.
  - Bottom 32pt strip is gone; terminal extends to the window's bottom edge.
  - In DEBUG builds, the dev-build banner below `SidebarFooterButtons` still renders correctly (sanity-check `SidebarDevFooter`).
- **Tooltip + a11y:** hover the bell → tooltip shows "Go To Next Notification" with shortcut hint. VoiceOver (or Accessibility Inspector) reads the a11y label.
- **Tests:** unit target is safe to run via CI if a test for `StatusBarButtonDisplay` exists — if not, no new unit test is required since behavior is unchanged (we're only moving the tenant). E2E via `gh workflow run test-e2e.yml` if any existing test asserted on `accessibilityIdentifier("window.bottomStatusBar")` — grep confirms **no such test exists**, so no E2E triggers needed.

---

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| `TerminalNotificationStore` isn't in the sidebar's environment | Trace during step 1; if missing, pass store explicitly into `SidebarFooter` rather than retrofitting a global injection. |
| Bell badge clutters the already-tight sidebar footer | Numeric badge only when `> 0`. At zero, bell is icon-only at 22pt — identical visual weight to `?`. No layout shift. |
| Operators trained on the bottom-bar location hunt for the button | Mitigated by (a) tooltip on hover, (b) keyboard shortcut and menu-bar entry unchanged — the button itself was never the only way to reach the action, it was an opinionated shortcut. Release note covers the move. |
| `UpdatePill` dynamic width squeezes the new bell when an update is pending | `HStack(spacing: 4)` + `frame(maxWidth: .infinity, alignment: .leading)` means icon buttons stay fixed at 22pt and the pill consumes trailing space. No squeeze. Visually sanity-check with a mock "update available" state during step 1. |
| Upstream cmux also carries `BottomStatusBarView` | c11 brought this in (CMUX-36 predates the c11 rename but was already in the fork). No upstream sync concern — this is c11-specific chrome. |

---

## 9. Out of scope

- Repurposing or reintroducing a bottom bar for a different tenant. Explicitly not doing this. If something ever needs the bottom surface, it's a fresh design conversation, not a revival.
- Rebinding or renaming the keyboard shortcut (`KeyboardShortcutSettings.Action.jumpToUnread`).
- Touching the menu-bar `NSStatusItem` entry, the View menu entry, or the NSStatusItem-driven dock badge.
- Renaming the localization keys (deferred — see §5).
- Moving `StatusBarButtonDisplay.swift` out of `Sources/StatusBar/` (optional follow-up chore).
- Changes to `SidebarHelpMenuButton`, `UpdatePill`, or `SidebarFooterIconButtonStyle`.

---

## 10. Release notes line

> The "Go To Next Notification" button moves from the bottom of the window into the sidebar footer next to the help button, reclaiming 32pt of terminal space. Keyboard shortcut and menu entries are unchanged.

---

## 11. Exit criteria for this plan

- Plan reviewed and approved by the operator.
- Move task to `planned`.
- Implementation can then proceed against this document as the contract.
