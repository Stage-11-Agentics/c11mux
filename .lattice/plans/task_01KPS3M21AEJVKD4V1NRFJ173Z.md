# C11-6 Plan v3 — App chrome UI scale for sidebar and tab text

Implementation plan for ticket C11-6 (`task_01KPS3M21AEJVKD4V1NRFJ173Z`). Authored by `agent:opus-4-7-c11-6` after a triple plan-review of v2 (claude + codex FAIL with overlapping CRITICALs; gemini PASS at architectural level). v3 incorporates the merged review's revisions: two CRITICALs and ten MAJOR/MINORs, all surgical fixes inside the v2 design (KVO spine, pure resolver helper, parameter-seam token, Bonsplit submodule push order). The v1→v2→v3 lineage and review artifacts are preserved at `.lattice/artifacts/payload/art_01KQR{5RPHTX,5RSP8,5RXQZ,5YYN8,72DJV,72FB2,72G8B,77M76}*.md`.

The ticket description is the contract. This plan satisfies it without paying down typing latency, gratuitously diverging from upstream Bonsplit, or violating localization/test/socket policies in `CLAUDE.md`.

## Goal

A persisted "App Chrome UI Scale" preset that scales sidebar workspace card text and the Bonsplit surface tab strip (titles, icons, accessories, bar shell height, item height, padding, close-button glyph, dirty indicator, notification badge, active-tab underbar) without touching Ghostty terminal cells, browser content, or markdown content. Live update on the running app, no relaunch — for any writer to UserDefaults, not only the Settings UI.

## C11-5 hierarchy this plan must preserve

C11-5 (`task_01KPRX53F0GK7RT99S0TM86T88`) made the workspace name the stable anchor of the sidebar card and demoted agent identity/status to a secondary register. In `TabItemView` (Sources/ContentView.swift): top line = `tab.title` at 12.5pt semibold; agent chip / notification subtitle / metadata / log / progress / branch / dir / PRs / ports all in the 9–10pt secondary tier. When chrome scale changes, the *relative ordering of emphasis* must hold: every value flows through one resolver multiplier, so the title stays the largest and semibold, secondary stays smaller. Per-row weight and color stay untouched.

## Code-area survey

### Settings UI and persistence

- `Sources/c11App.swift:34` — `WorkspacePresentationModeSettings` enum: the canonical shape for a small mode-set settings store (key + Mode enum + default + `mode(for:)` + `mode(defaults:)`). Direct precedent for `ChromeScaleSettings`.
- `Sources/c11App.swift:3850` — `AppearanceSettings`: simpler enum-style store, also useful as precedent.
- `Sources/c11App.swift:4323` — `SettingsView`, the page host.
- `Sources/c11App.swift:5032+` — `appearanceSettingsPage`. Natural home for the new picker; sibling of theme / sidebar tint controls.
- `Sources/c11App.swift:5044+` — `SettingsPickerRow` example (`SidebarActiveTabIndicatorStyle`); template for the chrome-scale row.
- `Sources/c11App.swift:6403–6541` — `SettingsCard`, `SettingsCardRow`, `SettingsPickerRow`, `SettingsCardDivider`, `SettingsCardNote` reusable building blocks.

### Sidebar workspace card (typing-latency-sensitive)

All in `Sources/ContentView.swift`:

- `8314` — `VerticalTabsSidebar` builds the list inside a `LazyVStack`, calls `TabItemView(...)` per row, with `.equatable()` on each row. Hot path.
- `10914` — `private struct TabItemView: View, Equatable`. `==` compares 17 stored fields. Body renders title (~11240, 12.5pt semibold), accessories (9–10pt), agent chip row, notification subtitle, log, progress, branch/dir, PRs, ports.
- `12596` — `SidebarMetadataRows` (10pt regular).
- `12648` — `SidebarMetadataEntryRow` (10pt regular, 8–9pt icon).
- `12748` — `SidebarMetadataMarkdownBlocks` (10pt semibold for "Show more details").
- `Sources/AgentChipBadge.swift` — `AgentChipBadge` renders the agent chip; has its own font sizes.

### Bonsplit surface tab strip

- `Sources/Workspace.swift:5326` — `bonsplitAppearance(from:)` overload (no context).
- `Sources/Workspace.swift:5382` — full `bonsplitAppearance(from:backgroundOpacity:context:)` — returns a `BonsplitConfiguration.Appearance`. Today sets only color/animation/divider; leaves `tabBarHeight`/`tabTitleFontSize`/`tabMinWidth`/`tabMaxWidth`/`tabSpacing` at initializer defaults.
- `Sources/Workspace.swift:5404` — `setTabBarVisible(_:)` shows the existing pattern for mutating one appearance field on a live controller.
- `Sources/Workspace.swift:5419` — `applyGhosttyChrome(...)` — the existing live-update path. The chrome-scale change path mirrors this shape: no-op guard, mutate, assign.
- `Sources/Workspace.swift:5500+` — `Workspace.init` wires `BonsplitConfiguration` from the resolved appearance.
- `Sources/Workspace.swift:5071` — `@MainActor final class Workspace: Identifiable, ObservableObject` — **NOT an NSObject subclass.** This forecloses the v2 plan's "Workspace observes UserDefaults via KVO" wording (KVO requires NSObject); v3's MAJOR #4 fix is a separate `ChromeScaleObserver: NSObject` helper held by each Workspace.
- `vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift:138` — `Appearance` declaration. Existing public knobs: `tabBarHeight` (declared default `33`, **but no internal consumer** — verified with `rg "tabBarHeight" vendor/bonsplit/Sources/Bonsplit`), `tabMinWidth`, `tabMaxWidth`, `tabTitleFontSize`, `tabSpacing`. v3 adds 9 new knobs.
- `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabItemView.swift`:
  - `127` — `HStack(spacing: TabBarMetrics.contentSpacing)`.
  - `128` — `let iconSlotSize = TabBarMetrics.iconSize`.
  - `179` — `.font(.system(size: appearance.tabTitleFontSize, ...))`.
  - `223` — `.padding(.horizontal, TabBarMetrics.tabHorizontalPadding)`.
  - `228–229` — `minHeight/maxHeight: TabBarMetrics.tabHeight`.
  - `299–306` — `glyphSize(for:)`. **Currently reads `TabBarMetrics.iconSize`. CRITICAL #2 rewrites it.**
  - `326` — `accessoryFontSize = max(8, appearance.tabTitleFontSize - 2)`. Already scales with title.
  - `329–332` — `accessorySlotSize`. **Currently capped by `TabBarMetrics.tabHeight = 30`. MAJOR #5 rewrites it.**
  - `552` — `.frame(height: TabBarMetrics.activeIndicatorHeight)` (3pt selected-tab underbar).
  - `576` — `TabBarMetrics.notificationBadgeSize` (6pt).
  - `581` — `TabBarMetrics.dirtyIndicatorSize` (8pt). **Explicitly named in AC.**
  - `590, 601` — `TabBarMetrics.closeIconSize` (9pt close glyph).
- `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift`:
  - `475` — `Color.clear.frame(width: 0, height: TabBarMetrics.tabHeight)` (leading anchor cell).
  - `486` — `.padding(.horizontal, TabBarMetrics.barPadding)` (bar padding; **today = 0**).
  - `524` — `Color.clear.frame(width: trailing, height: TabBarMetrics.tabHeight)` (trailing chrome backdrop).
  - `559, 624` — `.frame(height: TabBarMetrics.barHeight)` (the OS bar shell — **today = 30pt**).
  - `890` — `Color.clear.frame(width: 30, height: TabBarMetrics.tabHeight)` (drop indicator/spacer cell).
- `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabDragPreview.swift:9–12` — `TabBarMetrics.contentSpacing` and `iconSize` consumers.
- `vendor/bonsplit/Sources/Bonsplit/Internal/Styling/TabBarMetrics.swift` — internal constants. Stays as the *defaults source* for the new public knobs; embedders that don't override see today's behavior.

### Surface title bar

- `Sources/SurfaceTitleBarView.swift:135` — `headerRow`: title at 12pt semibold, subtitle at 10pt semibold. Trivial, single consumer.

## Token resolver design

New file: `Sources/Chrome/ChromeScale.swift` (matches the existing per-feature single-file convention; `Sources/` already has `Theme/`, `Find/`, `Mailbox/`, `Update/`, `Panels/`, etc.).

```swift
import Foundation
import SwiftUI

enum ChromeScaleSettings {
    static let presetKey = "chromeScalePreset"

    enum Preset: String, CaseIterable, Identifiable {
        case compact, standard, large, extraLarge
        var id: String { rawValue }

        // MINOR #10 — the displayName mapping ships in commit 1 alongside Preset.
        var displayName: String {
            switch self {
            case .compact:    return String(localized: "settings.chromeScale.preset.compact",    defaultValue: "Compact")
            case .standard:   return String(localized: "settings.chromeScale.preset.standard",   defaultValue: "Default")
            case .large:      return String(localized: "settings.chromeScale.preset.large",      defaultValue: "Large")
            case .extraLarge: return String(localized: "settings.chromeScale.preset.extraLarge", defaultValue: "Extra Large")
            }
        }
    }

    static let defaultPreset: Preset = .standard

    static func preset(for rawValue: String?) -> Preset {
        Preset(rawValue: rawValue ?? "") ?? defaultPreset
    }

    /// Parameter-seam overload (mirrors WorkspacePresentationModeSettings.mode(defaults:)).
    static func preset(defaults: UserDefaults) -> Preset {
        preset(for: defaults.string(forKey: presetKey))
    }

    static func multiplier(for preset: Preset) -> CGFloat {
        switch preset {
        case .compact:    return 0.90
        case .standard:   return 1.00
        case .large:      return 1.12
        case .extraLarge: return 1.25
        }
    }

    /// Belt-and-suspenders notification posted by the Settings UI setter for any
    /// future non-Workspace listener. Workspace observes UserDefaults via KVO,
    /// so this is NOT load-bearing.
    static let didChangeNotification = Notification.Name("com.stage11.c11.chromeScaleDidChange")
}

/// Single-stored-property + computed-tokens design. The synthesized `Equatable`
/// reduces to a `multiplier` compare so this type can sit inside `TabItemView`'s
/// `==` (typing-latency hot path) without growing the comparison surface. If you
/// add stored properties, audit that hot path before merging.  (MINOR #11)
struct ChromeScaleTokens: Equatable {
    let multiplier: CGFloat

    // Sidebar tokens.
    var sidebarWorkspaceTitle: CGFloat        { 12.5 * multiplier }
    var sidebarWorkspaceDetail: CGFloat       { 10.0 * multiplier }
    var sidebarWorkspaceMetadata: CGFloat     { 10.0 * multiplier }
    var sidebarWorkspaceAccessory: CGFloat    {  9.0 * multiplier }
    var sidebarWorkspaceProgressLabel: CGFloat {  9.0 * multiplier }
    var sidebarWorkspaceLogIcon: CGFloat      {  8.0 * multiplier }
    var sidebarWorkspaceBranchDot: CGFloat    {  3.0 * multiplier }

    // Surface tab strip tokens (Bonsplit Appearance values).
    // CRITICAL #1: surfaceTabBarHeight scales from 30 (today's TabBarMetrics.barHeight),
    // not 33 (the previous Appearance.tabBarHeight default — corrected to 30 in v3).
    var surfaceTabTitle: CGFloat                { 11.0 * multiplier }
    var surfaceTabIcon: CGFloat                 { 14.0 * multiplier }
    var surfaceTabBarHeight: CGFloat            { 30.0 * multiplier }
    var surfaceTabItemHeight: CGFloat           { 30.0 * multiplier }
    var surfaceTabHorizontalPadding: CGFloat    {  6.0 * multiplier }
    // MINOR #12: drop the floor clamps; the four ship presets never bottom out
    // (0.90 × 112 = 100.8 ≥ 96 trivially). Re-add when a Custom-multiplier follow-up lands.
    var surfaceTabMinWidth: CGFloat             { 112.0 * multiplier }
    var surfaceTabMaxWidth: CGFloat             { 220.0 * multiplier }
    var surfaceTabCloseIconSize: CGFloat        {  9.0 * multiplier }
    var surfaceTabContentSpacing: CGFloat       {  6.0 * multiplier }   // MAJOR #3
    var surfaceTabDirtyIndicatorSize: CGFloat   {  8.0 * multiplier }   // MAJOR #3
    var surfaceTabNotificationBadgeSize: CGFloat {  6.0 * multiplier }  // MAJOR #3
    var surfaceTabActiveIndicatorHeight: CGFloat { max(2.0, 3.0 * multiplier) }   // MAJOR #3 — floor=2 keeps a visible underbar at 0.90×

    // Surface title bar tokens.
    var surfaceTitleBarTitle: CGFloat         { 12.0 * multiplier }
    var surfaceTitleBarAccessory: CGFloat     { 10.0 * multiplier }

    static let standard = ChromeScaleTokens(multiplier: 1.0)

    static func resolved(from defaults: UserDefaults = .standard) -> ChromeScaleTokens {
        ChromeScaleTokens(multiplier: ChromeScaleSettings.multiplier(for: ChromeScaleSettings.preset(defaults: defaults)))
    }
}

extension EnvironmentValues {
    private struct ChromeScaleTokensKey: EnvironmentKey {
        static let defaultValue = ChromeScaleTokens.standard
    }
    var chromeScaleTokens: ChromeScaleTokens {
        get { self[ChromeScaleTokensKey.self] }
        set { self[ChromeScaleTokensKey.self] = newValue }
    }
}

/// MAJOR #4 — Workspace is not NSObject, so KVO via Workspace itself doesn't
/// compile. ChromeScaleObserver is a small NSObject helper held by each
/// Workspace. Lifetime tied to the Workspace.
final class ChromeScaleObserver: NSObject {
    private let onChange: () -> Void
    private static let keyPath = ChromeScaleSettings.presetKey

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        UserDefaults.standard.addObserver(self, forKeyPath: Self.keyPath, options: [.new], context: nil)
    }

    deinit {
        UserDefaults.standard.removeObserver(self, forKeyPath: Self.keyPath)
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == Self.keyPath else { return }
        let onChange = self.onChange
        // KVO callbacks fire on the writer's thread; hop to MainActor for
        // BonsplitController + Workspace mutation.
        Task { @MainActor in onChange() }
    }
}
```

## Settings UI design

New picker in the **Appearance** page (`Sources/c11App.swift:5032+`), placed adjacent to the existing theme/sidebar tint controls. Localized label, four options, default-style `Picker` matching `SettingsPickerRow` shape (precedent: `SidebarActiveTabIndicatorStyle` row at `Sources/c11App.swift:5044+`). Row-level subtitle; no per-preset subtitle strings (default-style Picker dropdown does not render them).

```swift
SettingsPickerRow(
    String(localized: "settings.chromeScale.title", defaultValue: "App Chrome UI Scale"),
    subtitle: String(localized: "settings.chromeScale.subtitle",
        defaultValue: "Scale c11 sidebar text and surface tab strip without changing terminal font size."),
    controlWidth: pickerColumnWidth,
    selection: $chromeScalePresetRaw
) {
    ForEach(ChromeScaleSettings.Preset.allCases) { preset in
        Text(preset.displayName).tag(preset.rawValue)
    }
}
```

When `task_01KPST42GAZSK5BYXFMFR2KG72` (Settings sidebar reorganization) lands, this picker travels with the rest of Appearance. Both PRs touch `SettingsView`'s render tree; the merge is a pane assignment, not a behavior change.

## Persistence design

- **Key:** `chromeScalePreset` (UserDefaults string, namespaced via the enum). Bare-key convention; matches `workspacePresentationMode`, `appearanceMode`, etc.
- **Default:** `"standard"` (= 1.00×).
- **Read path (SwiftUI):** `@AppStorage(ChromeScaleSettings.presetKey)` at the c11App scene root. SwiftUI re-renders subscribers automatically on UserDefaults change.
- **Read path (non-SwiftUI):** `ChromeScaleTokens.resolved(from: .standard)` in `Workspace.bonsplitAppearance(...)` — pure parameter, no hidden global call inside the helper.
- **Live-update spine: UserDefaults KVO via `ChromeScaleObserver`.** Each `Workspace` holds one observer (initialized in `init`, released in `deinit`). KVO fires for every writer: Settings UI, `defaults write`, future migrations. The callback hops to `@MainActor` and calls `applyChromeScale(reason: "userdefaults-change")`.
- **Belt-and-suspenders:** Settings UI setter posts `ChromeScaleSettings.didChangeNotification`. Workspace does NOT subscribe — KVO is canonical.
- **No-op guard inside `applyChromeScale(reason:)`** prevents redundant `bonsplitController.configuration` reassignments.

## Sidebar wiring

| File | View | Tokens used |
| --- | --- | --- |
| `Sources/ContentView.swift` | `TabItemView.body` | sidebarWorkspaceTitle, sidebarWorkspaceDetail, sidebarWorkspaceMetadata, sidebarWorkspaceAccessory, sidebarWorkspaceProgressLabel, sidebarWorkspaceLogIcon, sidebarWorkspaceBranchDot |
| `Sources/ContentView.swift` | `SidebarMetadataRows` (12596) | sidebarWorkspaceMetadata |
| `Sources/ContentView.swift` | `SidebarMetadataEntryRow` (12648) | sidebarWorkspaceMetadata |
| `Sources/ContentView.swift` | `SidebarMetadataMarkdownBlocks` (12748) | sidebarWorkspaceMetadata |
| `Sources/AgentChipBadge.swift` | `AgentChipBadge` | sidebarWorkspaceAccessory |
| `Sources/SurfaceTitleBarView.swift` | `headerRow` | surfaceTitleBarTitle, surfaceTitleBarAccessory |

**Hot-path threading rule for `TabItemView`:** CLAUDE.md prohibits adding `@EnvironmentObject` / `@ObservedObject` / `@Binding` to the hot body without updating `==`. We add ONE new `let` parameter (`chromeTokens: ChromeScaleTokens`, value-typed Equatable), threaded from `VerticalTabsSidebar`, included in `==`. No new `@EnvironmentObject` / `@ObservedObject` / `@Binding`.

Threading steps:
1. Add `@AppStorage(ChromeScaleSettings.presetKey) private var chromeScalePresetRaw: String = ChromeScaleSettings.defaultPreset.rawValue` to `VerticalTabsSidebar`.
2. Compute `let chromeTokens = ChromeScaleTokens(multiplier: ChromeScaleSettings.multiplier(for: ChromeScaleSettings.preset(for: chromeScalePresetRaw)))` once inside `body`.
3. Pass `chromeTokens` as a precomputed `let` parameter on `TabItemView(...)` at the call site.
4. Add `let chromeTokens: ChromeScaleTokens` to `TabItemView`'s stored properties.
5. Append `lhs.chromeTokens == rhs.chromeTokens` to `TabItemView.==`.
6. Keep `.equatable()` on the ForEach call site untouched.

For non-hot-path consumers (`SidebarMetadataRows`, `AgentChipBadge`, `SurfaceTitleBarView`): read from `@Environment(\.chromeScaleTokens)` — installed once at scene root.

## Bonsplit wiring

**No "Phase 1 only" deferral path.** AC requires bar shell + item height + icons + padding + close button + dirty indicator + notification badge + active-tab underbar to scale visibly. Verified `Appearance.tabBarHeight` has zero internal consumers today — repurposing it is needed.

### Bonsplit-internal changes (in `vendor/bonsplit/`)

#### Public knob additions (CRITICAL #1, MAJOR #3)

```swift
// vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift Appearance:
public var tabBarHeight: CGFloat = 30           // CRITICAL #1: lowered from 33 → 30 to match today's
                                                // TabBarMetrics.barHeight; this knob now drives the shell.
public var tabItemHeight: CGFloat = 30          // NEW — per-tab frame (was TabBarMetrics.tabHeight)
public var tabIconSize: CGFloat = 14            // NEW — was TabBarMetrics.iconSize
public var tabHorizontalPadding: CGFloat = 6    // NEW — was TabBarMetrics.tabHorizontalPadding
public var tabCloseIconSize: CGFloat = 9        // NEW — was TabBarMetrics.closeIconSize
public var tabContentSpacing: CGFloat = 6       // NEW — was TabBarMetrics.contentSpacing (MAJOR #3)
public var tabDirtyIndicatorSize: CGFloat = 8   // NEW — was TabBarMetrics.dirtyIndicatorSize (MAJOR #3, AC)
public var tabNotificationBadgeSize: CGFloat = 6 // NEW — was TabBarMetrics.notificationBadgeSize (MAJOR #3, AC)
public var tabActiveIndicatorHeight: CGFloat = 3 // NEW — was TabBarMetrics.activeIndicatorHeight (MAJOR #3)
```

`TabBarMetrics.barPadding = 0` is intentionally NOT promoted to a public knob; it's 0 today and any scaling token would multiply 0. If a future "Custom multiplier" follow-up wants tunable bar padding, add the knob then.

#### Preset adjustments (CRITICAL #1)

`Appearance.compact` and `.spacious` were inert until the bar shell rewires through `appearance.tabBarHeight`. After the rewire, they materially change shell height for any embedder that selects them. Adjust:

```swift
public static let compact = Appearance(
    tabBarHeight: 27,           // was 28, scaled to ~0.90× of new 30 default
    tabMinWidth: 100,
    tabMaxWidth: 160,
    tabTitleFontSize: 11
)

public static let spacious = Appearance(
    tabBarHeight: 35,           // was 38, scaled to ~1.17× of new 30 default
    tabMinWidth: 160,
    tabMaxWidth: 280,
    tabTitleFontSize: 11,
    tabSpacing: 2
)
```

Bonsplit PR body must include a "Behavior change" paragraph listing these constants and that `tabBarHeight` is now load-bearing (MINOR #9).

#### Internal re-routing

```swift
// TabBarView.swift:
// 475 — Color.clear.frame(width: 0, height: appearance.tabItemHeight)
// 486 — .padding(.horizontal, 0)            — barPadding stays 0; no public knob
// 524 — Color.clear.frame(width: trailing, height: appearance.tabItemHeight)
// 559 — .frame(height: appearance.tabBarHeight)
// 624 — .frame(height: appearance.tabBarHeight)
// 890 — Color.clear.frame(width: 30, height: appearance.tabItemHeight)

// TabItemView.swift:
// 127 — HStack(spacing: appearance.tabContentSpacing)
// 128 — let iconSlotSize = appearance.tabIconSize
// 223 — .padding(.horizontal, appearance.tabHorizontalPadding)
// 228–229 — minHeight/maxHeight: appearance.tabItemHeight
// 552 — .frame(height: appearance.tabActiveIndicatorHeight)
// 576 — width/height: appearance.tabNotificationBadgeSize
// 581 — width/height: appearance.tabDirtyIndicatorSize
// 590, 601 — .font(.system(size: appearance.tabCloseIconSize, weight: .semibold))
```

#### CRITICAL #2: `glyphSize(for:)` rewrite

```swift
// TabItemView.swift:299–306 — rewrite:
private func glyphSize(for iconName: String) -> CGFloat {
    if iconName == "terminal.fill" || iconName == "terminal" || iconName == "globe" {
        return max(10, appearance.tabIconSize - 2.5)
    }
    return appearance.tabIconSize
}
```

#### MAJOR #5: `accessorySlotSize` rewrite

```swift
// TabItemView.swift:329–332 — rewrite:
private var accessorySlotSize: CGFloat {
    // Outer cap is item height (was constant tabHeight=30, capped close/zoom/shortcut at 30pt).
    // Inner floor is "close icon + breathing room" (closeIconSize+7 = 9+7 = 16, byte-exact with old closeButtonSize=16 default).
    min(appearance.tabItemHeight, max(appearance.tabCloseIconSize + 7, ceil(accessoryFontSize + 4)))
}
```

#### TabDragPreview.swift

```swift
// 9–12 — read appearance.tabContentSpacing and appearance.tabIconSize
```

#### Bonsplit submodule discipline

Push to `Stage-11-Agentics/bonsplit`, NEVER `manaflow-ai/*` or `almonk/bonsplit`. Verified: `vendor/bonsplit` remote = `https://github.com/Stage-11-Agentics/bonsplit.git`.

```bash
cd vendor/bonsplit
git checkout -b c11-6-chrome-scale-knobs
# edit/add files
git add Sources/
git commit -m "Appearance: route tabBarHeight + add tabItemHeight/tabIconSize/tabHorizontalPadding/tabCloseIconSize/tabContentSpacing/tabDirtyIndicatorSize/tabNotificationBadgeSize/tabActiveIndicatorHeight knobs"
git push origin c11-6-chrome-scale-knobs
gh pr create --base main --title "Appearance: chrome-scale public knobs" --body "..." -R Stage-11-Agentics/bonsplit
```

After Bonsplit PR merges:
```bash
cd vendor/bonsplit
git fetch origin
git checkout main && git pull
cd ..
git -C vendor/bonsplit merge-base --is-ancestor HEAD origin/main || { echo "ABORT: bonsplit HEAD not on origin/main"; exit 1; }
git add vendor/bonsplit
git commit -m "Bump bonsplit submodule for chrome-scale knobs"
```

### c11-side wiring (in `Sources/Workspace.swift`)

Pure helper (MAJOR #5/#6 testability seam):

```swift
extension Workspace {
    /// Pure helper. No GhosttyApp.shared, no UserDefaults, no NotificationCenter — just
    /// in/out value-type mutation. Both the static factory and the live-update path
    /// call this so behavior is identical and testable.
    static func applyChromeScale(_ tokens: ChromeScaleTokens, to appearance: inout BonsplitConfiguration.Appearance) {
        appearance.tabBarHeight              = tokens.surfaceTabBarHeight
        appearance.tabTitleFontSize          = tokens.surfaceTabTitle
        appearance.tabMinWidth               = tokens.surfaceTabMinWidth
        appearance.tabMaxWidth               = tokens.surfaceTabMaxWidth
        appearance.tabIconSize               = tokens.surfaceTabIcon
        appearance.tabItemHeight             = tokens.surfaceTabItemHeight
        appearance.tabHorizontalPadding      = tokens.surfaceTabHorizontalPadding
        appearance.tabCloseIconSize          = tokens.surfaceTabCloseIconSize
        appearance.tabContentSpacing         = tokens.surfaceTabContentSpacing
        appearance.tabDirtyIndicatorSize     = tokens.surfaceTabDirtyIndicatorSize
        appearance.tabNotificationBadgeSize  = tokens.surfaceTabNotificationBadgeSize
        appearance.tabActiveIndicatorHeight  = tokens.surfaceTabActiveIndicatorHeight
    }
}
```

`bonsplitAppearance(...)` calls `Workspace.applyChromeScale(tokens, to: &appearance)` after constructing the existing color/animation/divider state.

`Workspace.init` (MAJOR #6):

```swift
let initialTokens = ChromeScaleTokens.resolved(from: .standard)
var appearance = Self.bonsplitAppearance(
    from: GhosttyApp.shared.defaultBackgroundColor,
    backgroundOpacity: GhosttyApp.shared.defaultBackgroundOpacity,
    context: nil,
    tokens: initialTokens
)
```

Live-update path:

```swift
@MainActor
func applyChromeScale(reason: String) {
    let tokens = ChromeScaleTokens.resolved(from: .standard)
    var next = bonsplitController.configuration.appearance
    Workspace.applyChromeScale(tokens, to: &next)
    let current = bonsplitController.configuration.appearance
    let unchanged =
        current.tabBarHeight              == next.tabBarHeight &&
        current.tabTitleFontSize          == next.tabTitleFontSize &&
        current.tabMinWidth               == next.tabMinWidth &&
        current.tabMaxWidth               == next.tabMaxWidth &&
        current.tabIconSize               == next.tabIconSize &&
        current.tabItemHeight             == next.tabItemHeight &&
        current.tabHorizontalPadding      == next.tabHorizontalPadding &&
        current.tabCloseIconSize          == next.tabCloseIconSize &&
        current.tabContentSpacing         == next.tabContentSpacing &&
        current.tabDirtyIndicatorSize     == next.tabDirtyIndicatorSize &&
        current.tabNotificationBadgeSize  == next.tabNotificationBadgeSize &&
        current.tabActiveIndicatorHeight  == next.tabActiveIndicatorHeight
    if unchanged { return }
    var config = bonsplitController.configuration
    config.appearance = next
    bonsplitController.configuration = config
}
```

`Workspace.init` instantiates a `ChromeScaleObserver` and stores it as a property; `deinit` releases it (the observer's deinit removes the KVO registration). The observer's closure calls `applyChromeScale(reason: "userdefaults-change")`.

## Surface title bar wiring

`Sources/SurfaceTitleBarView.swift:135` — replace literal sizes (12 semibold, 10 semibold) with `tokens.surfaceTitleBarTitle` / `tokens.surfaceTitleBarAccessory`. Read from `@Environment(\.chromeScaleTokens)`. Not in the typing-latency hot path.

## Environment / token propagation

Install once at the top of `c11App.body`'s scene content:

```swift
@AppStorage(ChromeScaleSettings.presetKey) private var chromeScalePresetRaw: String = ChromeScaleSettings.defaultPreset.rawValue

var body: some Scene {
    WindowGroup { ... }
        .environment(\.chromeScaleTokens,
            ChromeScaleTokens(multiplier:
                ChromeScaleSettings.multiplier(for:
                    ChromeScaleSettings.preset(for: chromeScalePresetRaw))))
}
```

Hot-path consumers (`TabItemView`, `SidebarMetadataRows`, `AgentChipBadge`) thread `chromeTokens` explicitly as a precomputed `let`. Non-hot-path consumers (`SurfaceTitleBarView`, etc.) read from environment.

## Commit grouping

> **Lattice-write discipline (every comment, every status, every attach).** All `lattice` *write* operations target the **parent repo** at `/Users/atin/Projects/Stage11/code/c11`, never the worktree's `.lattice/`. Use a subshell so cwd doesn't drift: `(cd /Users/atin/Projects/Stage11/code/c11 && lattice <cmd> C11-6 ... --actor agent:opus-4-7-c11-6)`. Reads OK from either side.

Each commit builds and passes tests independently (commit 4 depends on the bonsplit submodule pointer being on origin/main).

1. **C11-6 commit 1: Add ChromeScale resolver, Settings UI, and environment installation.**
   - New `Sources/Chrome/ChromeScale.swift` (`ChromeScaleSettings`, `Preset` + `displayName`, `multiplier(for:)`, `preset(defaults:)`, `ChromeScaleTokens`, `ChromeScaleTokens.resolved(from:)`, `EnvironmentValues.chromeScaleTokens`, `ChromeScaleObserver`).
   - `SettingsPickerRow` for chrome scale in `appearanceSettingsPage` (`Sources/c11App.swift`).
   - Install the environment at `c11App.body`'s scene root.
   - New localized strings (English values; Translator phase fills locales).
   - Unit tests:
     - `Tests/c11Tests/ChromeScaleSettingsTests.swift`
     - `Tests/c11Tests/ChromeScaleTokensTests.swift`
     - `Tests/c11Tests/ChromeScaleObserverTests.swift`
     - `Tests/c11Tests/WorkspaceApplyChromeScaleTests.swift`
   - `project.pbxproj` (MAJOR #8): add `Sources/Chrome/ChromeScale.swift` to app target; add four test files to the `c11-unit` target. The pbxproj edits are part of this commit (not a separate one) so the commit builds cleanly.
   - Visual: no UI change yet because no consumer reads tokens.

2. **C11-6 commit 2: Wire sidebar workspace card to ChromeScale tokens.**
   - Thread `chromeTokens` precomputed `let` from `VerticalTabsSidebar` into `TabItemView`. Update `==` to include `chromeTokens`.
   - Replace literal sizes in `TabItemView.body` with token reads.
   - Same change to `SidebarMetadataRows`, `SidebarMetadataEntryRow`, `SidebarMetadataMarkdownBlocks`, `AgentChipBadge`.

3. **Bonsplit-internal: route `tabBarHeight` + 8 new public knobs; rewrite `glyphSize(for:)` and `accessorySlotSize`; adjust `Appearance.compact`/`.spacious` (CRITICAL #1).**
   - In `vendor/bonsplit/`, branch `c11-6-chrome-scale-knobs`, push to Stage-11-Agentics/bonsplit, PR against `Stage-11-Agentics/bonsplit:main`.
   - Bonsplit-side test (in `vendor/bonsplit/Tests/`): construct `BonsplitConfiguration.Appearance` with non-default knob values; assert each is wired through to the corresponding view's frame/size. Use Bonsplit's existing test harness (or a small ViewInspector-style harness if needed).
   - PR body documents the `tabBarHeight` 33→30 change, `compact`/`spacious` adjustments, and the eight new public knobs.

4. **C11-6 commit 4: Bump bonsplit submodule pointer; thread tokens through `Workspace.bonsplitAppearance(...)` and `Workspace.init`; install ChromeScaleObserver.**
   - Parent commit verifies `git -C vendor/bonsplit merge-base --is-ancestor HEAD origin/main`; pointer bump.
   - `Workspace.bonsplitAppearance(from:backgroundOpacity:context:tokens:)` accepts a `ChromeScaleTokens` parameter and calls `Workspace.applyChromeScale(_:to:)`.
   - `Workspace.applyChromeScale(reason:)` for live updates.
   - `Workspace.init` resolves initial tokens via `ChromeScaleTokens.resolved(from: .standard)` (MAJOR #6) and installs `ChromeScaleObserver`.
   - `applyGhosttyChrome(...)` is left alone (different concern); the ChromeScale path is parallel to it.
   - `pbxproj`: no new files, but `ChromeScaleObserver` lives in the same `ChromeScale.swift` so no further membership work.

5. **C11-6 commit 5: Wire surface title bar to ChromeScale tokens.**
   - `Sources/SurfaceTitleBarView.swift` — read tokens from `@Environment(\.chromeScaleTokens)`.

6. **(DROPPED — MAJOR #7)** No socket command in v1. Validate the live-update mechanism via Settings UI smoke + `defaults write` regression. If a deterministic oracle is later needed, file a follow-up ticket: `c11 chrome.set-scale <preset>` socket command (off-main, focus-safe, with parser/focus-safety tests, skill update).

7. **C11-6 commit 6: Localization sync (Translator placeholder).**
   - Translator sub-agent populates `ja`, `uk`, `ko`, `zh-Hans`, `zh-Hant`, `ru` for the six new keys in `Resources/Localizable.xcstrings`.

c11 PR depends on Bonsplit PR merging first. If Bonsplit review takes longer than the c11 work, c11-6 waits — there is no partial-ship path that meets the AC.

## Test plan

Permitted, runtime-behavior tests (CLAUDE.md test-quality policy):

1. **`ChromeScaleSettingsTests`** — preset(for: nil) → .standard; preset(for: "compact") → .compact; unknown raw values fall back; preset(defaults:) round-trips through a fresh `UserDefaults(suiteName:)`; multiplier(for:) returns 0.90 / 1.00 / 1.12 / 1.25; Preset.displayName non-empty for every case.
2. **`ChromeScaleTokensTests`** — at .standard, every token equals its literal default within ±0.001; at .large, every token equals literal × 1.12; surfaceTabActiveIndicatorHeight floors at 2.0 at .compact (2.7 → 2.7, but the floor protects 0.66 multipliers); ChromeScaleTokens(multiplier: 1.0) == .standard; resolved(from:) round-trips.
3. **`WorkspaceApplyChromeScaleTests`** (pure-helper, no `GhosttyApp.shared`) — given a default `BonsplitConfiguration.Appearance` and `ChromeScaleTokens(multiplier: 1.12)`, every routed field equals the corresponding token within ±0.001. Repeat for compact/large/extraLarge. `applyChromeScale(.standard, to: &appearance)` is idempotent.
4. **`ChromeScaleObserverTests`** — observer fires onChange when UserDefaults key changes; deinit cleanly removes registration (no crash on subsequent UserDefaults mutations).
5. **Bonsplit knob round-trip** (in `vendor/bonsplit/Tests/`) — set each new public knob on a `BonsplitConfiguration` and verify the rendered view tree honors it via Bonsplit's existing test harness.

Forbidden: source-text grep tests, AST-fragment tests, `.xcstrings` content tests, `pbxproj` content tests.

## Validation plan

Tagged build:

1. `./scripts/reload.sh --tag c11-6-chrome-scale`. Confirm tagged build launches.
2. Settings UI smoke: open Settings → Appearance → "App Chrome UI Scale" picker; verify four options + row subtitle render in localized English.
3. Switch through all four presets (Compact / Default / Large / Extra Large). Verify visible scaling for **all of**:
   - **Sidebar:** workspace card titles, notification subtitle, agent chip, metadata rows, log, progress, branch/dir, PR rows, ports.
   - **Surface tab strip:** tab title font, tab bar shell height, tab item height, tab icon size (on a terminal tab AND a browser tab), close-button glyph, accessory affordances (zoom/dirty/notification), horizontal padding, content spacing.
   - C11-5 hierarchy holds: workspace title remains the largest, semibold element on every card at every preset.
4. Ghostty unchanged: open a terminal surface, type, confirm cell font size matches operator's existing Ghostty setting.
5. Multi-writer KVO check: from a sibling pane run `defaults write com.stage11.c11 chromeScalePreset large` and `defaults write com.stage11.c11 chromeScalePreset compact`. Confirm both sidebar AND tab strip update without relaunch and without focus changes.
6. Runtime live update: with two surfaces open and Settings showing, switch presets via the picker; both update immediately, no relaunch, no focus changes.
7. Localization: switch app language to `ja` (relaunch alert); confirm picker label / four option names / row subtitle render in Japanese.
8. Default-preset byte-exact regression seal: with the picker at Default (1.00×), screenshot the tab bar shell height. Compare against a screenshot from a build before the rerouting (or origin/main) — should be identical (CRITICAL #1 byte-exactness).
9. `c11 tree --no-layout` — confirm validation surface and sub-agent surfaces are still readable; rebalance starved panes.

Screenshot pack at Default + Extra Large for both sidebar and tab strip accompanies the PR body.

## Localization plan

All new user-facing strings via `String(localized: "<key>", defaultValue: "<English>")`. After Impl, Translator sub-agent syncs six locales in `Resources/Localizable.xcstrings`.

| Key | English |
| --- | --- |
| `settings.chromeScale.title` | App Chrome UI Scale |
| `settings.chromeScale.subtitle` | Scale c11 sidebar text and surface tab strip without changing terminal font size. |
| `settings.chromeScale.preset.compact` | Compact |
| `settings.chromeScale.preset.standard` | Default |
| `settings.chromeScale.preset.large` | Large |
| `settings.chromeScale.preset.extraLarge` | Extra Large |

## Do NOT ship list (out of scope)

- Ghostty terminal cells / prompts / scrollback / cursor / terminal zoom.
- Web page content inside browser surfaces.
- Markdown document content sizing.
- Comprehensive sweep of every popover, debug, settings string.
- Freeform slider (presets only for v1).
- Per-workspace overrides (one global preset).
- Sidebar footer feedback composer / dev panel / shortcut hint chrome (only the workspace card cluster scales).
- `c11 chrome.set-scale` socket command (deferred to follow-up — MAJOR #7).
- Custom multiplier (deferred; floor clamps removed per MINOR #12).
- Promoting `TabBarMetrics.barPadding = 0` to a public knob (no scaling effect today).

## Open decisions

All v1 open decisions resolved in v2; v3 review surfaced no new operator-decisions. Resolutions reproduced for the record:

1. `@AppStorage` over custom store. Mirrors `WorkspacePresentationModeSettings`.
2. Value-typed unobserved `ChromeScaleTokens`; precomputed `let` parameters.
3. Picker home: Appearance pane.
4. Settings key: bare `chromeScalePreset`.
5. ~~Defaults floors on min/max width.~~ Dropped (MINOR #12).
6. Surface title bar in v1: yes (commit 5).
7. ~~Optional socket command.~~ Dropped from v1 (MAJOR #7).
8. Bonsplit stays generic; c11 owns the resolver.
9. No animation in v1.
