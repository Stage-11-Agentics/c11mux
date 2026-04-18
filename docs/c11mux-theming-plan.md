# c11mux — Custom Theming System Plan

**Date**: 2026-04-18
**Status**: Draft v1.1 — 7 open questions locked with operator on 2026-04-18 (see §12)
**Lattice ticket**: [CMUX-9](../.lattice/tasks/task_01KPHCQNQH2BKT128552QP46RE.json)
**Target branch**: feature branch off `main` (e.g. `theme-engine-foundation`), one PR per milestone
**Scope**: c11mux chrome surfaces (sidebar, top bar, tab bar, dividers, outer workspace frame, pane title bars). Ghostty-owned surfaces (terminal cells, prompts, scrollback, cursor) are out of scope and never touched.

---

## 1. Motivation

c11mux today has **no unified theme engine**. Chrome colors are scattered across at least eight independent systems, each with its own persistence key, resolution logic, and rendering path:

| System | Lives at | Scope |
|---|---|---|
| `CmuxThemeNotifications.reloadConfig` | `Sources/AppDelegate.swift:36` | DistributedNotification trigger only — no store |
| `Workspace.bonsplitAppearance(...)` | `Sources/Workspace.swift:5084-5154` | Pushes Ghostty's background hex into `ChromeColors.backgroundHex`; **`borderHex` is never set** |
| `AppearanceMode` | `Sources/cmuxApp.swift:3534-3583` | light/dark/system only |
| `SidebarTint` | `@AppStorage("sidebarTintHexLight"/"Dark")` + opacity | Sidebar window-glass tint |
| `BrowserThemeSettings` | `Sources/Panels/BrowserPanel.swift:166-196` | browser-surface only |
| `WorkspaceTabColorSettings` | `Sources/TabManager.swift:245-443` | workspace color palette + custom colors |
| `SidebarActiveTabIndicatorSettings` | `Sources/TabManager.swift:155-186` | `.solidFill` vs `.leftRail` sidebar render mode |
| `Resources/ghostty/themes/` + `cmux themes` CLI | Ghostty terminal themes | **not c11mux chrome** — terminal cells only |

Three symptoms follow from the scatter:

1. **Dividers are invisible.** `BonsplitConfiguration.Appearance.ChromeColors` already has a `borderHex` field (`vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift:138-140`) and bonsplit's `TabBarColors.nsColorSeparator(...)` already consumes it (`vendor/bonsplit/Sources/Bonsplit/Internal/Styling/TabBarColors.swift:20-25`). c11mux never sets it — so every divider silently derives from Ghostty's background color. The color seam exists; the wiring doesn't.
2. **Workspace identity is sidebar-only.** `Workspace.customColor` (`Sources/Workspace.swift:4883`) — a fully developed 16-color palette plus user hex strings, persisted per workspace — renders in exactly one place: the sidebar tab for that workspace. The operator's peripheral vision gets no grounding for which workspace they're in once they're looking at the content area.
3. **Every future chrome decision is bespoke.** When an engineer adds a new chrome surface today, they have to decide from scratch: where does its color come from? Hardcode? `@AppStorage` key? System color? Ghostty-derived? There is no shared answer. A theme engine gives every future chrome decision a single well-known seam.

The goal is a **unified theme engine for c11mux chrome** that:

- Leaves Ghostty strictly alone (terminal cells, prompts, scrollback, cursor remain Ghostty-owned).
- Makes the workspace color a first-class theme variable (`$workspaceColor`) that theme authors reference freely — so one theme definition works across every workspace and the color automatically gains prevalence wherever the author placed it.
- Adds a new first-class primitive: an **outer workspace frame** that wraps the right-hand content area (sidebar excluded), colored by the workspace color.
- Replaces the scattered `@AppStorage` keys with TOML theme files, with built-ins shipped in the app bundle and user themes dropped into `~/Library/Application Support/c11mux/themes/`.
- Ships as an overall UI convention — future chrome decisions reference the theme's variables instead of minting new `@AppStorage` keys.

---

## 2. Design principles

Locked from the exploration dialogue:

1. **Theme c11mux chrome only. Never touch Ghostty.** Terminal cells, prompts, scrollback, cursor stay Ghostty-owned. Sidebar, top bar, tab bar, dividers, outer workspace frame, titlebars, sidebar status pills — c11mux-owned, theme-addressable.
2. **Workspace color gains subtle prevalence.** Peripheral-vision grounding, not loud. The operator should feel which workspace they're in without reading anything. Default values favour `$workspaceColor` mixed heavily with the chrome background (e.g. 65% toward neutral), not saturated.
3. **Theme engine becomes an overall UI convention.** Future chrome work references theme variables (`$workspaceColor`, `$background`, `$foreground`, `$surface`) rather than minting fresh `@AppStorage` keys. No new scattered theme systems.
4. **Outer workspace frame is a new first-class primitive.** A thin (1-2pt) border that wraps the **right-hand content area only** (sidebar excluded and stays neutral). Colored by the workspace color. It is the logical representation of the active workspace in the content area.
5. **Horizontal and vertical dividers are first-class theme knobs.** Color, thickness, potentially inset/opacity — all themable.
6. **Theme files, not settings-only.** `~/Library/Application Support/c11mux/themes/*.toml` plus built-ins shipped in `Resources/c11mux-themes/`. Users drop in theme files and select them.
7. **`$workspaceColor` is a first-class schema variable.** Themes reference it with opacity and mix modifiers — never hardcode workspace hexes. One theme works across every workspace.
8. **Additive, not migratory.** Existing `@AppStorage` keys (`sidebarTintHexLight/Dark`, `sidebarActiveTabIndicatorStyleRaw`, `BrowserThemeSettings`) stay as orthogonal controls in v1; the theme engine provides defaults those keys can override. Deprecations are deferred until the engine has bedded in.

---

## 3. Architecture overview

```
┌──────────────────────────────────────────────────────────────┐
│ Discoverability (Settings picker, CLI, debug menu)           │  ← M4
├──────────────────────────────────────────────────────────────┤
│ User themes (~/Library/Application Support/c11mux/themes/)   │  ← M3
│ + file watcher + hot reload                                  │
├──────────────────────────────────────────────────────────────┤
│ Workspace frame primitive (outer content-area border)        │  ← M2
│ + divider color/thickness wired through bonsplit             │
│ + $workspaceColor variable resolved at render                │
├──────────────────────────────────────────────────────────────┤
│ C11muxTheme struct + loader + built-in default               │  ← M1
│ (plumbed through chrome without changing visuals)            │
├──────────────────────────────────────────────────────────────┤
│ Existing chrome surfaces (sidebar, title bar, bonsplit…)     │  ← already built
└──────────────────────────────────────────────────────────────┘
```

Each milestone lands as its own PR, in order. M1 is invisible plumbing; visible change starts with M2.

Runtime model:

```
┌─ ThemeManager (singleton, @MainActor) ──────────────────┐
│  • active: C11muxTheme (selected built-in or user file) │
│  • variables: Map<String, ThemeValue>                   │
│  • resolve(role, context) -> NSColor                    │
│  • reload() on file-watcher fsevents                    │
└─────────────────────────────────────────────────────────┘
          ↓ reads from
┌─ C11muxTheme (Codable, loaded from TOML) ───────────────┐
│  identity: { name, author, version }                    │
│  palette: { ... }       ← raw hexes                     │
│  chrome: {                                              │
│    windowFrame: ThemedValue                             │
│    sidebar: { tint, activeTab, borderLeading }          │
│    dividers: { color, thickness, inset }                │
│    titleBar: { background, foreground, border }         │
│    tabBar: { background, activeFill, divider, ... }     │
│    browserChrome, markdownChrome, statusPills …         │
│  }                                                      │
└─────────────────────────────────────────────────────────┘
          ↓ resolved per surface
┌─ Surface rendering (ContentView, WorkspaceContentView,  │
│   Bonsplit, SurfaceTitleBarView, BrowserPanelView …)    │
│  • reads ThemeManager.color(for: .divider, workspace)   │
│  • subscribes to theme-changed publisher                │
└─────────────────────────────────────────────────────────┘
```

`ThemeManager` is workspace-aware at the *resolution* boundary: the role enum carries a `workspaceColor: String?` context so `$workspaceColor`-referencing values resolve correctly per workspace without duplicating the theme.

---

## 4. Current-state map (audit)

Every chrome surface in c11mux, where its color comes from today, and what M1–M3 turn it into. File:line references are verified against the tree at this repo's current HEAD (`ws-selected-keep-custom-color`, 2026-04-18).

### 4.1 Sidebar

| Surface | Today's source | File:line | M2 target |
|---|---|---|---|
| Sidebar window glass tint | `@AppStorage("sidebarTintHex"/"…Light"/"…Dark")` + `sidebarTintOpacity` (default `#000000` @ 0.18) | `Sources/ContentView.swift:13365-13398`, keys at `:13527-13528` | Stays — but defaults now come from theme (`sidebar.tintOverlay`); @AppStorage keys become overrides. |
| Sidebar active-tab background (`.solidFill`) | `resolvedCustomTabColor` (workspace hex, brightened for dark) OR `BrandColors.black` | `Sources/ContentView.swift:11476-11488`, resolver `:11505-11512` | Theme-driven: `sidebar.activeTab.fill = $workspaceColor` for custom, `sidebar.activeTab.fallback = …` otherwise. |
| Sidebar active-tab left rail (`.leftRail`) | `resolvedCustomTabColor.opacity(0.95)` (custom) or `BrandColors.goldSwiftUI` | `Sources/ContentView.swift:11494-11503` | Theme-driven: `sidebar.activeTab.railColor = $workspaceColor`, `sidebar.activeTab.railFallback = $accent`. Opacity moves into theme. |
| Sidebar inactive-tab tint | `resolvedCustomTabColor.opacity(0.7)` (or 0.35 multi-select) in `.solidFill` only | `Sources/ContentView.swift:11481-11483` | `sidebar.inactiveTab.customTint = $workspaceColor.opacity(…)` with theme-controlled opacity. |
| Sidebar unread-count badge fill | `cmuxAccentColor()` (Brand gold) | `Sources/ContentView.swift:10746-10748` | `sidebar.badge.background = $accent` (theme var). |
| Sidebar status / progress / log text | `.primary` / `.secondary` (system) | `Sources/ContentView.swift:12097-12338` | Stays system-default in v1; add `sidebar.status.foreground` as optional override in M3. |
| Sidebar ↔ content divider | Bonsplit `TabBarColors.nsColorSeparator(for: appearance)` — derived from `chromeColors.backgroundHex` because `borderHex` is unset | `vendor/bonsplit/Sources/Bonsplit/Internal/Views/SplitContainerView.swift:113-128`; resolver `vendor/bonsplit/Sources/Bonsplit/Internal/Styling/TabBarColors.swift:20-25` | Theme-driven via `dividers.color` → writes to `ChromeColors.borderHex`. |

### 4.2 Top bar / window chrome

| Surface | Today's source | File:line | M2 target |
|---|---|---|---|
| Titlebar background (under traffic lights) | `GhosttyApp.shared.defaultBackgroundColor` (Ghostty-derived) at alpha-scaled opacity | `Sources/ContentView.swift:2200-2242` | **Stays Ghostty-derived** — intentional: the titlebar visually continues the terminal surface beneath it. Theme exposes `titleBar.background = $ghosttyBackground` as a variable ref so themes can override if needed but default preserves today's behavior. |
| Titlebar bottom separator | `Color(nsColor: .separatorColor)`, 1pt | `Sources/ContentView.swift:2238-2240` | `titleBar.borderBottom = $separator` (theme var, defaults to system separator). |
| Traffic-light buttons | macOS system-owned | — | **Out of scope.** System never themable. |

### 4.3 Tab bar (bonsplit)

| Surface | Today's source | File:line | M2 target |
|---|---|---|---|
| Tab strip background | `TabBarColors.background(for: appearance)` — reads `chromeColors.backgroundHex` | `vendor/bonsplit/Sources/Bonsplit/Internal/Styling/TabBarColors.swift` | Theme-driven via `tabBar.background`, which *currently* defaults to `$ghosttyBackground` for continuity. |
| Active tab fill | Lightened/darkened from backgroundHex for contrast | `TabBarColors.swift` | `tabBar.activeFill` with default formula preserved. |
| Tab divider | `TabBarColors.separator(...)` — uses `borderHex` if set, else derives from background | `vendor/bonsplit/Sources/Bonsplit/Internal/Styling/TabBarColors.swift:150-160` | Theme-driven via `dividers.color` (shared with pane dividers). |
| Active-tab bottom indicator | `TabBarMetrics.activeIndicatorHeight = 2` + accent color | `vendor/bonsplit/Sources/Bonsplit/Internal/Styling/TabBarMetrics.swift:18` | `tabBar.activeIndicator.color` — optional `$workspaceColor` in opinionated themes. |

### 4.4 Pane dividers (horizontal + vertical)

| Surface | Today's source | File:line | M2 target |
|---|---|---|---|
| Divider color | `splitView.customDividerColor = TabBarColors.nsColorSeparator(for: appearance)` — again derives from `backgroundHex` since `borderHex` unset | `vendor/bonsplit/Sources/Bonsplit/Internal/Views/SplitContainerView.swift:123` | Set via theme's `dividers.color` → written to `ChromeColors.borderHex` at workspace-level bonsplit config. |
| Divider thickness | `splitView.dividerStyle = .thin` (system constant ≈ 1pt) + `TabBarMetrics.dividerThickness = 1` | `SplitContainerView.swift:125`; `TabBarMetrics.swift:39` | **New bonsplit field `dividerThicknessPt: CGFloat?`** on `ChromeColors` (or sibling `DividerStyle` struct). When non-nil, override via `splitView.dividerThickness` (NSSplitView's dynamic property). Defaults preserved. |
| Divider inset / opacity | N/A today | — | Deferred to M5; `dividers.inset` / `.opacity` reserved in schema. |

### 4.5 Pane title bar (`SurfaceTitleBarView`)

| Surface | Today's source | File:line | M2 target |
|---|---|---|---|
| Title bar background | `Color(nsColor: NSColor.windowBackgroundColor).opacity(0.85)` | `Sources/SurfaceTitleBarView.swift:59-62` | `titleBar.background = $surface` (theme var). Keep ~85% opacity modifier. |
| Title bar bottom border | `Color(nsColor: .separatorColor)`, 1pt | `SurfaceTitleBarView.swift:63-67` | `titleBar.borderBottom = $separator`. |
| Title text | `.primary` | `SurfaceTitleBarView.swift:~89` | `titleBar.foreground` — defaults to `$foreground`; themes can override. |
| Description markdown body | Markdown theme (existing) | `SurfaceTitleBarView.swift` | **Out of scope for chrome theming** — markdown typography is content, not chrome. |

### 4.6 Sidebar status / progress / log areas

| Surface | Today's source | File:line | M1–M2 target |
|---|---|---|---|
| Sidebar metadata rows (role, model, task chips) | Hardcoded foreground + subtle background per chip kind | `Sources/ContentView.swift:12097-12338` | Stays in v1; no new theme variables. M3+ could add `sidebar.chip.*` roles. |

### 4.7 Browser surface chrome (not content)

| Surface | Today's source | File:line | M2 target |
|---|---|---|---|
| Browser chrome background (address bar area) | `resolvedBrowserChromeBackgroundColor(...)` — receives Ghostty theme background | `Sources/Panels/BrowserPanelView.swift:205-243` | `browserChrome.background = $ghosttyBackground` (default). Theme can override. |
| Omnibar pill background | Darkened/blended from chrome bg | `BrowserPanelView.swift:228-243` | `browserChrome.omnibarFill = $surface.mix($background, 0.15)` (default formula preserved). |
| `BrowserThemeSettings` (light/dark/system for web content) | `@AppStorage("browserThemeMode")` | `Sources/Panels/BrowserPanel.swift:186-196` | **Stays orthogonal** — governs content rendering (prefers-color-scheme), not chrome. Not absorbed into theme engine. |

### 4.8 Markdown surface chrome (not content)

| Surface | Today's source | File:line | M2 target |
|---|---|---|---|
| Panel background | Hardcoded `NSColor(white: 0.12, alpha: 1.0)` dark / `0.98` light | `Sources/Panels/MarkdownPanelView.swift:270-274` | `markdownChrome.background = $background` (theme-driven default retains 0.12/0.98 fallback). |
| Content dividers | System `Divider()` | `MarkdownPanelView.swift:~61` | `$separator` (system default preserved). |
| Markdown typography theme | `titleBarMarkdownTheme(for: colorScheme)` | `MarkdownPanelView.swift:~114` | **Out of scope** — content typography, not chrome. |

### 4.9 Settings window

| Surface | Today's source | Decision |
|---|---|---|
| Settings window chrome | System background, system rows, system controls | **Out of scope for v1.** Settings window is an OS-native surface; skinning it fights the platform and adds maintenance. The Settings window *shows* theme controls (M4) but is not itself themed. |

### 4.10 Menu bar extra

| Surface | Today's source | Decision |
|---|---|---|
| Menu bar icon / popover | System menu bar owns the rendering | **Out of scope.** System-owned. |

---

## 5. Workspace color audit

### 5.1 Flow today

**Write path**: UI-only, four call sites:

- Context-menu "Workspace Color" submenu (`Sources/ContentView.swift:11348-11378`) → `applyTabColor(hex, targetIds)` → `TabManager.setTabColor` → `Workspace.setCustomColor` (`Sources/Workspace.swift:5757-5763`).
- Context-menu "Choose Custom Color…" → `promptCustomColor(targetIds)` (`ContentView.swift:12032-12059`) → validates/normalizes hex → `WorkspaceTabColorSettings.addCustomColor(...)` → `applyTabColor`.
- Settings pane "Workspace Colors" (`Sources/cmuxApp.swift:4806-4890`) — palette overrides and custom-color management; does **not** itself set a workspace's color (per-workspace color is always via context menu).
- Session restore: `Workspace.setCustomColor(snapshot.customColor)` at `Sources/Workspace.swift:256`.

**Persistence**:

- `@Published var customColor: String?` on `Workspace` (`Sources/Workspace.swift:4883`) — in-memory only; no `@AppStorage`.
- Serialized as `SessionWorkspaceSnapshot.customColor` (`Sources/SessionPersistence.swift:385`) in the autosaved JSON snapshot (`~/.config/com.stage11.c11mux/session-com.stage11.c11mux.json`).
- Palette defaults + overrides + user customs live in `UserDefaults`: `workspaceTabColor.defaultOverrides` (dict) and `workspaceTabColor.customColors` (array), keys at `Sources/TabManager.swift:246-247`, getters/setters at `:399-417`.

**Read / render sites** (exhaustive — only sidebar today):

- `TabItemView` in `Sources/ContentView.swift`:
  - `resolvedCustomTabColor` computed property (`:11505-11512`) — the single read seam.
  - `backgroundColor` computed (`:11471-11488`) — `.solidFill` mode fills active tab; inactive tabs get `.opacity(0.7)` or `.opacity(0.35)`.
  - `explicitRailColor` computed (`:11494-11503`) — `.leftRail` mode fills a thin left edge at `.opacity(0.95)`.
  - `tabColorSwatchColor(for:)` (`:11514-11520`) — renders the swatches in context menu / settings.
- v2 API surface (`Sources/TerminalController.swift:3592`): exposes `custom_color` in `workspace` JSON for CLI inspection — **read-only**, no setter.
- Debug log (`TerminalController.swift:16156`): stringified as `color=<hex|"none">`.

No other SwiftUI view reads `customColor` today. The gain-prevalence work in M2 is the first multi-surface consumption.

### 5.2 Dark-mode brightening

`WorkspaceTabColorSettings.displayNSColor(hex:, colorScheme:, forceBright:)` (`Sources/TabManager.swift:382-397`) is the single entry point. In dark mode (or when `forceBright` is true — `.leftRail` forces it), values pass through `brightenedForDarkAppearance(...)` at `:419-442`:

```
HSB-space adjustment:
  brightness' = min(1, max(b, 0.62) + (1 - b) * 0.28)   // min 62% + 28% of headroom
  saturation' = (s ≤ 0.08) ? s : min(1, s + (1 - s) * 0.12)   // preserve neutral greys
  hue preserved
```

This is per-hex, render-time, stateless. Each palette color is a single hex; there's no separate light/dark pair. M2 preserves this helper verbatim.

### 5.3 Named palette (verified)

16 entries in `Sources/TabManager.swift:250-271` (`originalPRPalette`):

| Name | Hex | Name | Hex | Name | Hex | Name | Hex |
|---|---|---|---|---|---|---|---|
| Red | `#C0392B` | Olive | `#4A5C18` | Blue | `#1565C0` | Magenta | `#AD1457` |
| Crimson | `#922B21` | Green | `#196F3D` | Navy | `#1A5276` | Rose | `#880E4F` |
| Orange | `#A04000` | Teal | `#006B6B` | Indigo | `#283593` | Brown | `#7B3F00` |
| Amber | `#7D6608` | Aqua | `#0E6B8C` | Purple | `#6A1B9A` | Charcoal | `#3E4B5E` |

Plus up to 24 user customs and per-name overrides.

### 5.4 Persistence confirmation

`customColor` survives restart. Verified:

1. `Workspace.init(...)` accepts no `customColor`; the field is set on restore via `setCustomColor(snapshot.customColor)` at `Workspace.swift:256`.
2. `Workspace.snapshot()` (via `SessionWorkspaceSnapshot` build site) emits `customColor: customColor` into the JSON snapshot (`SessionPersistence.swift` builders).
3. `SessionPersistenceStore` writes `session-com.stage11.c11mux.json` every 8s (`defaultSnapshotFileURL`), which round-trips the field.

### 5.5 Proposal — gaining subtle prevalence (M2)

Today the workspace color hits exactly one view. M2 wires it into three more surfaces with conservative defaults so the color feels like ambient grounding, not decoration:

| Target surface | Default formula | Rationale |
|---|---|---|
| Pane dividers (horizontal + vertical) | `$workspaceColor.mix($background, 0.65)` — i.e. 35% toward workspace hue | Subtle but visible in peripheral vision. Holds together even with pale / extreme workspace colors because of the heavy mix. |
| Outer workspace frame | `$workspaceColor` at full opacity, 1.5pt border wrapping the content area | The frame is the explicit logical representation of the workspace; this is the one place the color is allowed to be assertive. |
| Sidebar active-tab tint overlay (`.solidFill`) | `$workspaceColor.opacity(0.08)` layered over sidebar tint | Already close to today's `.solidFill` at reduced opacity. Lets `.solidFill` become the default render mode without overwhelming the sidebar. |
| Top-tab-bar active-indicator (optional, theme-author choice) | `$workspaceColor` | Already a 2pt bar; opt-in accent. |

All four are **default formulas in the built-in Stage 11 theme**. Themes (including a "Minimal" theme that zeroes out dividers and the sidebar tint overlay, leaving just the frame) can change them per-surface. Defaults are deliberately on the quiet side; "High-contrast workspace" built-in theme exists for operators who want the loud version.

### 5.6 CLI / socket surface for workspace color

No first-class command today. `cmux` exposes workspace color **read-only** via the v2 API (`TerminalController.swift:3592`). M4 adds:

```
cmux workspace-color set --workspace <ref> <hex>
cmux workspace-color clear --workspace <ref>
cmux workspace-color get --workspace <ref>
cmux workspace-color list-palette
```

Backed by a new socket method `workspace.set_custom_color`. The CLI is additive — context menu stays the canonical user surface.

---

## 6. `C11muxTheme` schema design

### 6.1 File format decision — TOML

Evaluated concretely against the alternatives:

| Format | Pros | Cons | Verdict |
|---|---|---|---|
| **TOML** | Human-writable, comments supported, obvious types, no indentation hazards, `[table]` maps onto nested schema cleanly, `toml` Swift package widely available. Matches Ghostty's own config ergonomics (operators already recognise it). | Slightly more verbose than JSON for deeply nested structures. | **Adopted.** |
| JSON | Ubiquitous, stdlib support, one obvious parser. | No comments, trailing-comma hostile, theme authors have to remember JSON quoting rules, strings-with-hex-colors get noisy. | Rejected — theme files are authored by humans first, parsed second; comments matter. |
| YAML | Comments, less punctuation. | Indentation-sensitive (easy to break), implicit typing surprises (`#FF0000` would YAML-parse weirdly), no stdlib parser in Swift — requires a yams-style dependency. | Rejected — indentation + implicit-type foot-guns outweigh gains over TOML. |

The file extension is `.toml`. Both built-ins and user themes carry it.

### 6.2 Directory layout

- **Built-ins**: bundled in `Resources/c11mux-themes/<name>.toml`. Read-only. Shipped with the app.
- **User themes**: `~/Library/Application Support/c11mux/themes/<name>.toml`. Writable; file watcher picks up changes. User names that collide with built-ins shadow them.
- **Active theme selection**: `@AppStorage("theme.active")` = `<name>`; empty/missing means the built-in default.
- **Per-workspace override** (stretch in M4): `Workspace` stores an optional `themeOverride: String?` that wins over the global selection if set.

### 6.3 Schema (TOML, annotated)

```toml
# Built-in default theme, shipped at Resources/c11mux-themes/stage11.toml.
# Theme files are TOML. Comments supported. Keys are hierarchical tables.

[identity]
name         = "Stage 11"                 # stable, kebab-case preferred
display_name = "Stage 11"                 # shown in pickers (optional)
author       = "Stage 11 Agentics"
version      = "0.01.001"                 # Stage 11 versioning (X.XX.XXX)
schema       = 1                          # bump only on breaking schema changes

# Raw color palette. Values here are always resolved hex strings — never
# expressions — because other sections can $-reference them.
[palette]
void          = "#0A0C0F"                 # primary background
surface       = "#121519"                 # elevated surfaces (title bars)
gold          = "#C4A561"                 # brand accent
fog           = "#2A2F36"                 # separators / chrome borders
text          = "#E9EAEB"                 # primary foreground
textDim       = "#8A8F96"                 # secondary foreground

# Variables referenceable by chrome sections as `$name`.
# Variables can reference palette entries, other variables, or magic tokens
# ($workspaceColor, $ghosttyBackground).
[variables]
background          = "$palette.void"
surface             = "$palette.surface"
foreground          = "$palette.text"
foregroundSecondary = "$palette.textDim"
accent              = "$palette.gold"
separator           = "$palette.fog"
# Magic: resolved at render time from Workspace.customColor, brightened in dark mode
# via WorkspaceTabColorSettings.brightenedForDarkAppearance.
workspaceColor      = "$workspaceColor"
# Magic: resolved from GhosttyApp.shared.defaultBackgroundColor
ghosttyBackground   = "$ghosttyBackground"

# ---- Chrome sections ----
# Each leaf is a "ThemedValue": either a plain hex string, a variable
# reference ($name), or a variable reference with a chain of modifiers.

[chrome.windowFrame]
color        = "$workspaceColor"
thicknessPt  = 1.5
# Optional per-edge overrides; if absent, `color`/`thicknessPt` applies to all
# four edges. When present the color wraps the content area only (sidebar
# excluded). See §7 for render path.

[chrome.sidebar]
tintOverlay         = "$workspaceColor.opacity(0.08)"      # layered over below
tintBase            = "$background.opacity(0.18)"
tintBaseOpacity     = 0.18
activeTabFill       = "$workspaceColor"                    # .solidFill mode
activeTabFillFallback = "$surface"                         # no workspaceColor
activeTabRail       = "$workspaceColor"                    # .leftRail mode
activeTabRailFallback = "$accent"
activeTabRailOpacity  = 0.95
inactiveTabCustomOpacity = 0.7
inactiveTabMultiSelectOpacity = 0.35
badgeFill           = "$accent"
borderLeading       = "$separator"                         # sidebar↔content

[chrome.dividers]
color        = "$workspaceColor.mix($background, 0.65)"    # 35% toward workspace
thicknessPt  = 1.0
# Reserved for M5:
# insetLeadingPt  = 0
# insetTrailingPt = 0
# opacity         = 1.0

[chrome.titleBar]
background       = "$surface"
backgroundOpacity = 0.85
foreground       = "$foreground"
foregroundSecondary = "$foregroundSecondary"
borderBottom     = "$separator"

[chrome.tabBar]
background       = "$ghosttyBackground"                    # preserve current behaviour
activeFill       = "$ghosttyBackground.lighten(0.04)"
divider          = "$separator"
activeIndicator  = "$workspaceColor"                       # 2pt bottom indicator

[chrome.browserChrome]
background      = "$ghosttyBackground"
omnibarFill     = "$surface.mix($background, 0.15)"

[chrome.markdownChrome]
background      = "$background"

# ---- Optional top-level meta ----
[behavior]
# Whether switching workspaces animates theme-variable crossfades. Default false.
animateWorkspaceCrossfade = false
```

### 6.4 Value grammar

Every leaf under `[chrome.*]` is a `ThemedValue`, parseable as one of:

1. **Hex literal**: `"#RRGGBB"` or `"#RRGGBBAA"`.
2. **Variable reference**: `"$name"`. Resolves via the `[variables]` table (and recursively into `[palette]` or magic tokens).
3. **Modifier chain**: `"$name.mod1(args).mod2(args)…"`. Modifiers:

| Modifier | Arg type | Effect |
|---|---|---|
| `.opacity(N)` | `0.0–1.0` | Multiplies alpha by `N`. |
| `.mix(value, N)` | target `ThemedValue`, `0.0–1.0` | Linear RGB interpolation; `N=0` → self, `N=1` → target. |
| `.darken(N)` | `0.0–1.0` | HSB brightness multiplied by `(1 - N)`. |
| `.lighten(N)` | `0.0–1.0` | HSB brightness moved toward 1.0 by `N` of headroom. |
| `.saturate(N)` | `0.0–1.0` | HSB saturation moved toward 1.0 by `N` of headroom. |
| `.desaturate(N)` | `0.0–1.0` | HSB saturation multiplied by `(1 - N)`. |

All resolution happens at render time against `NSColor` in `sRGB` color space. Rules:

- `$workspaceColor` resolves using `WorkspaceTabColorSettings.displayNSColor(hex:colorScheme:forceBright:)` so dark-mode brightening is reused exactly as today — no re-implementation.
- `$ghosttyBackground` resolves from `GhosttyApp.shared.defaultBackgroundColor` at each call (live-updates via the existing `ghosttyDefaultBackgroundDidChange` notification).
- Numeric leaves (thicknesses, opacities) are floats; all other leaves are `ThemedValue`.

### 6.5 Extensibility — how new surfaces get added without breaking old themes

The schema is **additive-only** within a `schema = 1` major version:

- Missing chrome sections / keys fall back to the built-in default theme's values. A theme authored today continues to load when c11mux ships a new chrome surface next year — the new surface just uses the default theme's value until the theme author opts in.
- The loader emits a single OSLog warning per missing key per theme load (deduped), never a fatal error.
- `schema = 2` is reserved for breaking changes (e.g. removing a key, changing a modifier's semantics). When we bump, we ship a one-time converter.

A *separate* extensibility axis: when a surface needs a brand-new variable name (not a new chrome key), add it to the reference loader's `[variables]` synthesizer — not to user themes. Themes can reference anything in `[variables]`, but the canonical set is owned by c11mux.

### 6.6 Built-in themes (M3 ships three)

1. **`stage11.toml` — Stage 11 (default).** Void-dominant, gold accent, subtle workspace frame, muted workspace-tinted dividers (35% mix). Preserves the feel you get today; introduces the frame primitive.
2. **`high-contrast-workspace.toml` — High-contrast workspace.** Thick (3pt) workspace-colored dividers, 2.5pt frame, strong sidebar tint overlay (`$workspaceColor.opacity(0.22)`), workspace-colored tab-bar active indicator. The "thick black bar" experiment parameterized — the operator who wants to *feel* which workspace they're in.
3. **`minimal.toml` — Minimal.** Everything neutral: dividers at `$separator`, sidebar tint overlay zeroed, tab bar inherits Ghostty background. Workspace color renders **only** on the outer frame. For operators who want the frame's grounding without the ambient saturation.

Example snippets at the end of §6, Appendix A.

---

## 7. Divider + workspace frame primitives

### 7.1 Bonsplit — divider thickness knob

Current state: `splitView.dividerStyle = .thin` at `vendor/bonsplit/Sources/Bonsplit/Internal/Views/SplitContainerView.swift:125`. `TabBarMetrics.dividerThickness = 1` exists but isn't used as an override. `NSSplitView.dividerThickness` is a computed property — on a subclass (e.g. the existing `ThemedSplitView`) we can override `var dividerThickness: CGFloat { get }`.

Change (M2; bonsplit submodule):

1. Add a new field to `ChromeColors` (or a sibling struct to keep the naming clean):

   ```swift
   // vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift
   public struct Appearance: Sendable {
       public struct ChromeColors: Sendable {
           public var backgroundHex: String?
           public var borderHex: String?
           /// Optional override for pane divider thickness in points.
           /// When nil, Bonsplit uses NSSplitView's .thin default (~1pt).
           public var dividerThicknessPt: CGFloat?   // NEW

           public init(
               backgroundHex: String? = nil,
               borderHex: String? = nil,
               dividerThicknessPt: CGFloat? = nil
           ) { … }
       }
   }
   ```

2. In `ThemedSplitView`:

   ```swift
   override var dividerThickness: CGFloat {
       overrideThickness ?? super.dividerThickness
   }
   var overrideThickness: CGFloat?
   ```

3. `SplitContainerView.makeNSView(...)` reads `appearance.chromeColors.dividerThicknessPt` and assigns it to the subclass' override field; the update path in `updateNSView` does the same.

4. Retains the `.thin` dividerStyle as the structural hint (keeps macOS's standard hit-test region reasonable) while letting visible thickness be customized.

**Submodule policy** (`CLAUDE.md` "Submodule safety"): the bonsplit change ships first on `Stage-11-Agentics/bonsplit`'s `main`, then the parent-repo submodule pointer bump lands in a separate commit.

### 7.2 Bonsplit — wire `borderHex` from c11mux

Already supported end-to-end in bonsplit; the c11mux side just hasn't been connected. In `Sources/Workspace.swift:5113-5118`, extend `bonsplitAppearance(...)` to accept theme-resolved divider color and thickness:

```swift
private static func bonsplitAppearance(
    from backgroundColor: NSColor,
    backgroundOpacity: Double,
    theme: C11muxTheme,
    workspaceColor: String?
) -> BonsplitConfiguration.Appearance {
    let dividerColor = theme.resolve(.dividers_color, workspaceColor: workspaceColor)
    let dividerThickness = theme.resolveCGFloat(.dividers_thickness)
    return BonsplitConfiguration.Appearance(
        splitButtonTooltips: Self.currentSplitButtonTooltips(),
        enableAnimations: false,
        chromeColors: .init(
            backgroundHex: Self.bonsplitChromeHex(...),
            borderHex: dividerColor.hexString(includeAlpha: true),
            dividerThicknessPt: dividerThickness
        )
    )
}
```

`applyGhosttyChrome(...)` (`Workspace.swift:5130-5154`) extends its no-op guard to compare divider color and thickness alongside background hex, and updates `chromeColors.borderHex` + `chromeColors.dividerThicknessPt` when they change.

### 7.3 Outer workspace frame — where it inserts

The content area a workspace owns is the SwiftUI subtree returned by `WorkspaceContentView.body` at `Sources/WorkspaceContentView.swift:39-166`. `WorkspaceContentView` is mounted once per workspace inside a ZStack in `ContentView.terminalContent` (`Sources/ContentView.swift:2108-2122`), *already* to the right of the sidebar. That mount point is exactly what the frame should wrap — no splitting "sidebar vs content" logic needed because the ZStack is already content-area-only.

**Insertion approach (SwiftUI overlay, adopted)**:

```swift
// Sources/WorkspaceContentView.swift
var body: some View {
    // … existing bonsplitView composition …

    Group {
        if isMinimalMode {
            bonsplitView.ignoresSafeArea(.container, edges: .top)
        } else {
            bonsplitView
        }
    }
    .overlay(
        WorkspaceFrame(
            workspace: workspace,
            theme: themeManager.active,
            isWorkspaceActive: isWorkspaceInputActive
        )
        .allowsHitTesting(false)
    )
}
```

`WorkspaceFrame` is a new `View` that draws a `RoundedRectangle` or plain `Rectangle` stroke at `theme.chrome.windowFrame.thicknessPt`, coloured from `theme.chrome.windowFrame.color` resolved against `workspace.customColor`. Only the active workspace draws at full opacity; background workspaces drop to ~0.25 opacity (preserves the "which workspace am I in" grounding without flicker as the ZStack transitions).

**Why SwiftUI `.overlay` instead of a CALayer border**:

| Option | Pros | Cons |
|---|---|---|
| SwiftUI `.overlay` with `Rectangle().stroke(...)` | Respects SwiftUI layout, animates naturally, `allowsHitTesting(false)` keeps it event-transparent, no AppKit plumbing. | A hairline on Retina can antialias slightly differently than a 1pt CALayer border; for a subtle frame this is acceptable and actually reads well. |
| CALayer border on the hosting NSView | Pixel-perfect 1pt rendering. | Requires a `NSViewRepresentable` host, breaks the `.ignoresSafeArea` / `.frame` layout flow, doesn't respect SwiftUI animations without extra glue. |
| NSBox / AppKit `NSView.wantsLayer` border | Native. | Still requires a hosting representable and fights SwiftUI's layout engine. |

Adopted: SwiftUI overlay. Thickness rendered in points via `.strokeBorder(lineWidth:)`, which renders on the inside of the rect — avoids bleeding into adjacent views.

**Behavior under motion**:

- **Split animations** (pane open/close): the frame wraps the entire content area, not individual panes, so bonsplit's internal animation is unaffected. Frame doesn't flicker.
- **Window resize**: SwiftUI-driven; the overlay resizes with its container.
- **Full-screen**: the overlay disappears cleanly when `isMinimalMode` applies `.ignoresSafeArea(.container, edges: .top)` — verified behaviour because the overlay attaches to the `Group`, inheriting the same bounds.
- **Workspace switch** (ZStack-swap in `ContentView.terminalContent`): each workspace has its own frame at its own color. No crossfade needed in v1 — M5 evaluates.

### 7.4 Cross-fade on workspace switch

Opinion: **do not animate in v1**. Today the ZStack opacity-transitions workspaces instantly (`opacity(presentation.renderOpacity)` at `ContentView.swift:2123`). The frame inherits that. Animating the frame separately would:

- Risk flashing the wrong color briefly during handoff.
- Add coupling to `retiringWorkspaceId` state.
- Cost complexity for dubious UX gain.

If operators feedback asks, M5 adds `behavior.animateWorkspaceCrossfade = true` as a theme-level opt-in.

---

## 8. Migration story

The theme engine replaces no live setting in v1. Every existing `@AppStorage` key below stays in force — the theme engine provides **defaults** that those keys override. The staged deprecations happen after ≥1 release of measured usage.

| Existing setting | v1 behavior | Deferred deprecation |
|---|---|---|
| `sidebarTintHexLight` / `sidebarTintHexDark` / `sidebarTintHex` / `sidebarTintOpacity` (`Sources/ContentView.swift:13527-13528`) | Override theme's `chrome.sidebar.tintBase` / `tintBaseOpacity`. If either light/dark override is set, it continues to win. | Planned: remove @AppStorage keys and move user values into a "User overrides" theme file on first launch after M4 ships. Not in M1-M4. |
| `sidebarActiveTabIndicatorStyleRaw` (`Sources/TabManager.swift:171-186`) | Orthogonal — governs `.leftRail` vs `.solidFill` structure, not colors. Theme provides colors for whichever mode is active. | **No deprecation planned.** The indicator mode is a structural choice, not a theme choice; stays as a first-class setting. |
| `AppearanceMode` (light/dark/system — `Sources/cmuxApp.swift:3534-3583`) | Orthogonal. Themes read `colorScheme` when resolving `$workspaceColor` (brightening) and should otherwise not assume a scheme. | **No deprecation planned.** Light/dark is OS-level; themes are additive to it. |
| `BrowserThemeSettings` (`Sources/Panels/BrowserPanel.swift:166-196`) | Orthogonal — governs web-content `prefers-color-scheme`, not chrome. | **No deprecation planned.** Content rendering ≠ chrome. |
| `WorkspaceTabColorSettings` (`Sources/TabManager.swift:245-443`) | Stays entirely — the palette, custom colors, and `Workspace.customColor` all feed `$workspaceColor`. | **No deprecation planned.** The theme engine consumes this; it does not replace it. |
| `cmux themes` CLI / `Resources/ghostty/themes/` | Untouched — these govern Ghostty terminal colors, not c11mux chrome. | **No deprecation planned.** Separate ownership (Ghostty) from new engine. |

### 8.1 Default theme selection for existing installs

Automatic and silent: on first launch after M1, `theme.active = "stage11"` (the built-in default). M1 is a visual no-op — the default theme is calibrated to produce the same on-screen output as today. Existing installs see no change until M2 ships the frame + divider wiring.

Opt-out of the theme engine entirely: `CMUX_DISABLE_THEME_ENGINE=1` (environment variable) forces fallback to the pre-M1 code paths. Intended as a debug / rollback safety net; removed two releases after M2 lands cleanly.

### 8.2 Per-workspace color stays unchanged

`Workspace.customColor` is already durable (§5.4). Nothing about the theme engine changes its write path, persistence, or read API. The engine **consumes** it via the `$workspaceColor` variable.

---

## 9. Discoverability + UX

### 9.1 Settings pane (M4)

New "Appearance" section above "Workspace Colors" in `Sources/cmuxApp.swift` settings:

- Theme picker (segmented control or menu): lists built-ins + user themes alphabetically; built-ins tagged with a small "Built-in" badge. Selecting writes `@AppStorage("theme.active")`.
- Live preview pane: a small c11mux-shaped diagram (sidebar stub, workspace frame, divider, title bar) rendered with the selected theme's resolved values against a representative workspace color. Updates in ≤100ms on selection change (resolution is cheap; re-render is SwiftUI cheap).
- "Open Themes Folder" button → `NSWorkspace.shared.open(themesDirURL)` to reveal user themes dir in Finder, creating it on first click if absent.
- "Reload themes" button → manual retrigger of the M3 file watcher.

Leaves the existing "Workspace Colors" section intact (palette + custom colors + indicator style picker).

### 9.2 Context menu — per-workspace theme override

**Out of scope for v1.** Per-workspace `themeOverride` adds coordination surface (what happens when the global theme changes? when the override theme is deleted?) without a clear user ask. Theme designers would likely want per-environment themes (prod vs dev) rather than per-workspace, and that discussion is orthogonal.

Reserved: the `Workspace` model can gain `themeOverride: String?` in M5 if asked; the schema already supports it trivially.

### 9.3 Socket / CLI surface (M4)

```
cmux ui themes list               # built-in + user, one per line, built-ins first
cmux ui themes get                # print the active theme's name
cmux ui themes set <name>         # switch the global active theme
cmux ui themes clear              # revert to built-in default
cmux ui themes reload             # force-rescan user themes dir
cmux ui themes path               # print the absolute path of the user themes dir
cmux ui themes dump --json        # dump the resolved theme as JSON for debugging
cmux workspace-color set --workspace <ref> <hex>      # see §5.6
cmux workspace-color clear --workspace <ref>
cmux workspace-color get --workspace <ref>
```

**CLI namespace** (locked 2026-04-18): `cmux themes` stays Ghostty — Ghostty is the king theme of the main user interface and keeps the short verb. c11mux chrome themes live under `cmux ui themes …`. The top-level `cmux help` should educate:

> `cmux themes` — Ghostty terminal themes (terminal cells, cursor, prompt colors).
> `cmux ui themes` — c11mux chrome themes (sidebar, title bars, dividers, workspace frame around the terminal).

Alternatives considered and rejected: (a) renaming Ghostty to `cmux themes-ghostty` — inverts the principle that Ghostty is the king theme; (b) nesting chrome under `cmux appearance themes` — "appearance" implies a broader namespace we'd need to fill; (c) flag-based routing (`cmux themes --chrome`) — same verb, different semantics via flag is confusing.

### 9.4 Debug menu entries

Per the `skills/cmux-debug-windows` conventions, add to the Debug menu:

- "Debug: Dump Active Theme" → opens a new markdown surface with the resolved theme as JSON.
- "Debug: Toggle Theme Engine" → flips `CMUX_DISABLE_THEME_ENGINE` at runtime (for rollback testing).
- "Debug: Show Theme Folder" → `NSWorkspace.shared.open(themesDirURL)`.
- "Debug: Rotate Through Themes" → cycles active theme across all loaded themes (for quick visual comparison).

All debug entries are `#if DEBUG`-only; no release impact.

### 9.5 Localization

All new user-facing strings use `String(localized: "key.name", defaultValue: "English text")` per CLAUDE.md policy. Keys land in `Resources/Localizable.xcstrings` with English + Japanese translations:

- `settings.section.appearance`
- `settings.appearance.theme`
- `settings.appearance.theme.builtin`
- `settings.appearance.theme.openFolder`
- `settings.appearance.theme.reload`
- `settings.appearance.preview.title`
- `debug.theme.dumpActive`, `debug.theme.toggleEngine`, `debug.theme.showFolder`, `debug.theme.rotate`

---

## 10. Phased rollout

Each milestone is independently mergeable, independently useful, and ships as one PR. Milestones are sized so each is one focused review, not a mega-PR.

### M1 — Foundation (invisible plumbing)

**Deliverable**: `C11muxTheme` struct, TOML loader, built-in default theme bundled, `ThemeManager` singleton. Chrome surfaces are refactored to **read from the manager** but the default theme produces identical on-screen output.

**New files**:

- `Sources/Theme/C11muxTheme.swift` — the `Codable` struct (identity, palette, variables, chrome sections).
- `Sources/Theme/ThemedValue.swift` — value grammar parser (hex / `$ref` / modifier chains).
- `Sources/Theme/ThemeManager.swift` — singleton `@MainActor` class; exposes `active: C11muxTheme`, `color(for role:, workspaceColor:) -> NSColor`, `cgFloat(for role:) -> CGFloat`, and a Combine publisher for change broadcasts.
- `Resources/c11mux-themes/stage11.toml` — built-in default.
- Add a TOML parser dep — evaluate `LebJe/toml` (Swift-first, MIT) vs. hand-written. Lean toward a tight hand-written parser if the built-in default is the only theme in M1 (TOML subset needed is small).
- `cmuxTests/C11muxThemeLoaderTests.swift`, `cmuxTests/ThemedValueResolutionTests.swift`.

**Modified files**:

- `Sources/ContentView.swift` — `TabItemView` reads `sidebar.activeTabFill` / `sidebar.activeTabRail` through the manager instead of inline logic (which today already uses `resolvedCustomTabColor`). Visual result identical.
- `Sources/Workspace.swift:5084-5154` — `bonsplitAppearance` takes a `ThemeManager` parameter; resolves `chromeColors.backgroundHex` through it (default theme resolves `$ghosttyBackground` to exactly today's value).
- `Sources/WorkspaceContentView.swift` — injects `ThemeManager.shared` into the environment (for future M2+ child views).
- `Sources/SurfaceTitleBarView.swift` — background / foreground / border read from manager; defaults preserved.

**Tests (all automated, CI-visible)**:

- Round-trip: load `stage11.toml`, encode as JSON, diff against a golden. Catches schema drift.
- Resolution: a set of fixtures — `$foreground`, `$workspaceColor.opacity(0.08)`, `$background.mix($accent, 0.5)` — each producing a specific `NSColor`.
- Visual no-op guard: run the existing XCUITest visual-diff suite; assert no pixel regressions on the default theme.

**Risks**:

- *TOML parser quality.* Picking a poorly-maintained dep could block the whole line. Mitigation: if no dep feels solid, hand-write a tiny subset parser (~200 lines). The schema uses a closed subset of TOML (strings, numbers, booleans, nested tables — no arrays of tables, no inline arrays, no datetime).
- *Resolution performance.* Theme lookups happen per-render, per-surface. Mitigation: memoize the resolved `NSColor` in `ThemeManager` keyed by `(role, workspaceColor)`; invalidate on theme change. Performance budget: ≤1µs per lookup on the hot path (sidebar tab render during workspace switch).
- *SwiftUI render graph.* Turning hardcoded colors into observed values risks over-invalidation. Mitigation: `ThemeManager` exposes a `@Published var version: UInt64` that views observe; views that don't need to re-render on unrelated theme changes (e.g. the tab bar doesn't care about markdown chrome) read specific sub-publishers.

**Rollback**: `CMUX_DISABLE_THEME_ENGINE=1` restores the pre-M1 inline color paths. Keep the pre-M1 code paths dead-but-present for one release behind the flag.

### M2 — Workspace color prevalence + frame + dividers

**Deliverable**: visible change. The workspace color renders on the outer frame, dividers, and (subtly) the sidebar tint overlay. Divider thickness is themable. `$workspaceColor` resolves live per workspace.

**New files**:

- `Sources/Theme/WorkspaceFrame.swift` — SwiftUI view that draws the outer frame overlay.
- `Sources/Theme/ThemeManager+WorkspaceColor.swift` — live resolution of `$workspaceColor` via the existing `WorkspaceTabColorSettings.displayNSColor` helper; dark-mode brightening delegated (not re-implemented).

**Modified files**:

- `vendor/bonsplit/...` — `ChromeColors.dividerThicknessPt` field; `ThemedSplitView.dividerThickness` override; bonsplit submodule bumped, pushed to `Stage-11-Agentics/bonsplit` `main` **before** the parent-repo pointer bump (submodule safety per CLAUDE.md).
- `Sources/Workspace.swift:5106-5154` — `bonsplitAppearance` and `applyGhosttyChrome` thread theme-resolved divider color/thickness into `ChromeColors.borderHex` + `dividerThicknessPt`. No-op guard extends to those fields.
- `Sources/WorkspaceContentView.swift:39-166` — `.overlay(WorkspaceFrame(...))` on the top-level `Group`.
- `Sources/ContentView.swift` — sidebar tint overlay gains the theme's `chrome.sidebar.tintOverlay` layered atop the existing tint.

**Tests**:

- `cmuxTests/WorkspaceFrameRenderTests.swift` — mounts `WorkspaceFrame` with mock workspace+theme, asserts stroke color and thickness resolve correctly per workspace color; asserts `allowsHitTesting(false)`.
- `tests_v2/test_workspace_color_prevalence.py` — set a workspace color via the (new) `cmux workspace-color set` CLI; read back a snapshot; assert color present. **Test deferred to M4** when the CLI ships; in M2 we rely on visual inspection for the frame and XCUITest-visible divider thickness change.
- `cmuxTests/BonsplitDividerThicknessTests.swift` — construct `BonsplitConfiguration.Appearance` with `dividerThicknessPt: 3`, mount, assert `NSSplitView.dividerThickness == 3`.

**Risks**:

- *Submodule coordination.* Bonsplit changes land first. Mitigation: CLAUDE.md "Submodule safety" steps followed; verify with `git merge-base --is-ancestor HEAD origin/main` on `vendor/bonsplit` before bumping parent pointer.
- *Typing-latency-sensitive paths.* Per CLAUDE.md, `WindowTerminalHostView.hitTest()`, `TabItemView`, and `TerminalSurface.forceRefresh()` cannot take on new allocations or observers. `WorkspaceFrame` attaches to the *container* above `bonsplitView`, not to any terminal view; its stroke is resolved once per theme change, memoized. `TabItemView`'s theme reads are through precomputed `let` parameters, preserving its `Equatable` conformance (which gates the `.equatable()` optimization). Explicit audit in the PR body.
- *Workspace crossfade flicker.* The ZStack swap during workspace switch could briefly show both frames. Mitigation: frame opacity gated on `presentation.renderOpacity` (same gate as workspace content).

**Rollback**: The frame view has a `.opacity(0)` kill switch driven by `@AppStorage("theme.workspaceFrame.enabled", default: true)`. Dividers revert to pre-M2 behavior via `CMUX_DISABLE_THEME_ENGINE=1`.

### M3 — User themes + hot reload

**Deliverable**: Users drop `.toml` files in `~/Library/Application Support/c11mux/themes/` and they load. Three built-ins ship: Stage 11 (default), High-contrast workspace, Minimal. Editing a theme file triggers hot reload within ≤1s.

**New files**:

- `Sources/Theme/ThemeDirectoryWatcher.swift` — `DispatchSource.makeFileSystemObjectSource` watcher on the user themes dir (falls back to polling every 2s if FSEvents unavailable). Debounces to 250ms.
- `Resources/c11mux-themes/high-contrast-workspace.toml`
- `Resources/c11mux-themes/minimal.toml`

**Modified files**:

- `Sources/Theme/ThemeManager.swift` — enumerates built-ins + user themes; handles name shadowing (user wins); emits OSLog warnings for malformed files (doesn't crash).
- `Sources/cmuxApp.swift` — creates the user themes dir on first launch if absent (`FileManager.default.createDirectory(at:withIntermediateDirectories:true)`).

**Tests**:

- `cmuxTests/ThemeDirectoryWatcherTests.swift` — write a theme file, wait for change publisher, assert new theme loads. Use a temp dir via a new `ThemeManager.pathsOverride` seam.
- `cmuxTests/ThemeShadowingTests.swift` — built-in named "stage11", user file named "stage11.toml", assert user wins, assert revert on user file delete.
- `cmuxTests/ThemeMalformedLoadTests.swift` — malformed TOML → OSLog warning, doesn't crash, doesn't swap active theme.

**Risks**:

- *FSEvents latency / unreliability.* Polling fallback mitigates; polling is cheap on ≤10 files.
- *User theme that references missing variables.* Additive fallback (§6.5) → missing keys use default-theme values with warning. Never crashes.

**Rollback**: Built-ins continue to load regardless of user-theme state; deleting a broken user theme file restores prior behavior.

### M4 — Settings UI + CLI

**Deliverable**: Theme picker with live preview in Settings. Full `cmux themes` and `cmux workspace-color` CLI surface.

**New files**:

- `Sources/Settings/AppearanceThemeSection.swift` — picker + preview canvas.
- `Sources/Settings/ThemePreviewCanvas.swift` — the miniature c11mux diagram.
- `CLI/commands/Themes.swift` — new CLI subcommands (or extended existing `themes` command).
- `CLI/commands/WorkspaceColor.swift` — `cmux workspace-color` subcommand family.
- `Sources/SocketAPI/ThemeMethods.swift` — socket method handlers for `theme.*` and `workspace.set_custom_color`.

**Modified files**:

- `Sources/cmuxApp.swift:~4806` — insert new "Appearance" section above "Workspace Colors".
- `Sources/ContentView.swift` — context-menu "Workspace Color" submenu gets a small "Preview in overlay: <theme>" tooltip so operators learn about themes organically.
- Socket API doc `docs/socket-api-reference.md` — document new methods.

**Tests**:

- `tests_v2/test_theme_cli.py` — full CRUD over CLI: list / get / set / clear / reload / dump.
- `tests_v2/test_workspace_color_cli.py` — set workspace color, assert readable via `workspace.list`, assert visible in snapshot file.
- `cmuxTests/AppearanceSettingsTests.swift` — picker change flips `ThemeManager.active`.

**Risks**:

- *Socket focus policy.* `cmux themes set` must not steal focus (CLAUDE.md socket focus policy). The handler runs off-main; only theme application (a no-allocation update of observed state) touches main. Audit explicit in PR.

**Rollback**: The CLI is purely additive. The Settings section can be gated behind `@AppStorage("settings.appearance.themeSectionEnabled", default: true)` if needed.

### M5 — Advanced (stretch)

Re-justify after M4 lands. Candidates:

- **Theme crossfade on workspace switch** (`behavior.animateWorkspaceCrossfade = true`).
- **Per-workspace theme override** (`Workspace.themeOverride: String?`, context menu entry).
- **Community theme format** — versioned spec document + theme-sharing conventions (theme file as single gist, one-click import).
- **Light-theme variant handling** — today themes are mode-agnostic via `colorScheme`-aware resolution; a formal `[light]` / `[dark]` variant pair would let theme authors ship two resolved palettes per theme file.
- **Icon theming** — explicitly out of scope for v1 but would slot in here.

Each lands as its own PR, each re-justifies before work starts. None block M1-M4 landing cleanly.

---

## 11. Non-goals (explicit)

- **Ghostty theme modification.** Terminal cells, cursor, prompt rendering, scrollback — entirely Ghostty-owned. `Resources/ghostty/themes/` and the existing `cmux themes` CLI are separate concerns.
- **Terminal cell / cursor / prompt / scrollback theming.**
- **macOS window chrome** — traffic lights, system titlebar buttons, window drop shadow. System-owned.
- **Browser *content* theming** — `BrowserThemeSettings` controls `prefers-color-scheme` on the rendered web content and stays orthogonal.
- **Markdown *content* rendering** — typography, syntax highlighting, list bullets, etc. Chrome-only.
- **Syntax highlighting** (for terminal ANSI or markdown code blocks).
- **Icon theming** — no app icon, menu item icon, or SF Symbol swapping in v1.
- **Settings window theming** — the window that *shows* theme controls is itself not themed.
- **Menu bar extra theming** — system-owned.
- **Cross-platform themes** — c11mux is macOS-only; themes assume NSColor semantics.
- **Dynamic theming from external sources** (e.g. macOS accent color, desktop wallpaper sampling) — nice-to-have, not v1.
- **Theme marketplace / remote fetch** — users copy files by hand in v1.

---

## 12. Open questions — resolved 2026-04-18

All seven open questions were locked with Atin on 2026-04-18 before the Trident plan review kicked off. The plan has been updated to reflect these decisions; this section records them as provenance.

1. **Built-in default theme identity — LOCKED: Stage 11 brand.** The shipped default matches `company/brand/visual-aesthetic.md`: void-dominant (`#0A0C0F`), gold accent (`#C4A561`). See Appendix A.1. *Rationale*: tight brand coherence across the stack; operators fork from an opinionated baseline.

2. **Workspace frame default thickness — LOCKED: 1.5pt.** Readable on Retina without feeling thick next to `.thin` dividers. See §7.3.

3. **Workspace frame opacity for inactive workspaces — LOCKED: 0.25.** Preserves visual continuity during workspace switches. See §7.3 ("Behavior under motion").

4. **Workspace-colored tab-bar active indicator in default theme — LOCKED: `$workspaceColor`.** The default Stage 11 theme uses workspace color on the 2pt bottom indicator. See Appendix A.1 (`[chrome.tabBar].activeIndicator`). *Rationale*: reinforces workspace identity on a second chrome surface; subtle because the indicator is only 2pt.

5. **`cmux themes` CLI namespace — LOCKED: `cmux ui themes`.** `cmux themes` stays Ghostty (Ghostty is the king theme). c11mux chrome themes live at `cmux ui themes …`. See §9.3. *Rationale*: respects Ghostty's primacy in the terminal experience; `ui` is shorter than `appearance` and doesn't imply a broader namespace we'd need to fill. Help text at top-level educates the distinction.

6. **Per-workspace theme override — LOCKED: deferred past v1.** v1 ships a single global theme. Per-workspace `customColor` already exists and gives per-workspace identity; a per-workspace theme *file* override (workspace A loads `stage11.toml`, workspace B loads `minimal.toml`) is deferred to M5 if operators ask. Schema stays forward-compatible. See §9.2.

7. **TOML parser — LOCKED: hand-written subset parser.** ~200 lines; covers strings, numbers, booleans, nested tables. No arrays-of-tables, no inline arrays, no datetime. Zero third-party deps. See §6.1.

---

## 13. Risks + pitfalls

### 13.1 Typing-latency-sensitive paths

CLAUDE.md flags three paths as typing-latency-sensitive; any theme change must prove it doesn't touch them on hot paths.

| Path | Risk | Mitigation |
|---|---|---|
| `WindowTerminalHostView.hitTest()` (`Sources/TerminalWindowPortal.swift`) | Called on every event including keyboard. Any work outside the `isPointerEvent` guard blocks input. | `WorkspaceFrame` attaches above the terminal view stack; `hitTest` never reaches it due to `.allowsHitTesting(false)`. No new work on this path. Explicit PR audit line. |
| `TabItemView` (`Sources/ContentView.swift`) | Uses `Equatable` + `.equatable()` to skip body re-evaluation during typing. New env/binding properties would break the `==` comparison. | Theme reads are through **pre-computed `let` parameters** passed into `TabItemView`, not via `@EnvironmentObject`/`@ObservedObject` inside the view. The M1 refactor carefully preserves `.equatable()`. Explicit PR audit line. |
| `TerminalSurface.forceRefresh()` (`Sources/GhosttyTerminalView.swift`) | Called on every keystroke. | Not touched by any milestone. The theme engine lives outside terminal surfaces. |

### 13.2 Submodule safety (bonsplit)

M2 modifies `vendor/bonsplit`. Per CLAUDE.md "Submodule safety":

1. Commit the bonsplit change on a branch of `Stage-11-Agentics/bonsplit`.
2. Push the commit to bonsplit's remote `main`.
3. Verify: `cd vendor/bonsplit && git merge-base --is-ancestor HEAD origin/main` — must succeed.
4. Only then bump the parent-repo submodule pointer in a separate commit.

Any divergence — detached HEAD, un-pushed commit, wrong branch — must be caught in the PR checklist.

### 13.3 Localizable strings

Every new user-facing string uses `String(localized: "key.name", defaultValue: "English text")`. Keys are added to `Resources/Localizable.xcstrings` with English + Japanese translations. No bare string literals in `Text()`, `Button()`, or alert titles. Explicit audit per PR.

### 13.4 Build / test policy

- Per CLAUDE.md, never run `xcodebuild test` locally — even `cmux-unit` launches host app instances. Defer all test runs to CI (`gh workflow run test-e2e.yml`).
- Per memory `feedback_cmux_never_run_xcodebuild_test.md`, use `build` action only when verifying compilation locally.
- `tests_v2/` Python socket tests must run against a tagged build's socket (`/tmp/cmux-debug-<tag>.sock`), not an untagged `cmux DEV.app`.

### 13.5 Perf budget

- `ThemeManager.color(for:, workspaceColor:)` hot path: ≤1µs per call (memoized).
- `WorkspaceFrame` re-render: triggered only on theme change or workspace `customColor` change — not on keystrokes or typing.
- Bonsplit divider config churn: guarded by the existing no-op check in `applyGhosttyChrome` (`Workspace.swift:5136`), extended to cover `borderHex` + `dividerThicknessPt`.

### 13.6 Brand / aesthetic drift

`company/brand/visual-aesthetic.md` governs Stage 11 visual identity. The default theme must be explicitly reviewed against it before M1 ships. A mismatch here is hard to unwind after user installs pick up the bundled default.

### 13.7 Schema lock-in

Once users start authoring themes, breaking changes to the schema become expensive. The additive-only guarantee within `schema = 1` is load-bearing. Reviewer should explicitly evaluate each proposed schema change during review for breaking-ness.

### 13.8 User theme supply-chain concerns

`.toml` files are inert (no code execution). A malicious theme can at worst produce unreadable UI — not a security concern, but a usability one. Themes never load from remote URLs in v1.

### 13.9 CI red-build baseline

Per memory `project_c11mux_ci_build_runner_red.md`, the c11mux CI build job is red on every main commit (macos-15-xlarge Larger Runner unavailable — billing). Ignore the red build check and use `gh pr merge --admin` to bypass, per established practice.

### 13.10 Forward-only Lattice

Per memory `project_cmux_lattice_forward_only.md`, the CMUX-9 ticket tracks this plan and its implementation. It is **not** retrospectively decomposed into phase tickets for work-already-done. Each milestone PR references CMUX-9 and optionally a new child ticket per milestone when work starts.

---

## Appendix A — Built-in theme examples

### A.1 `stage11.toml` (default, ships in M3)

```toml
[identity]
name         = "stage11"
display_name = "Stage 11"
author       = "Stage 11 Agentics"
version      = "0.01.001"
schema       = 1

[palette]
void    = "#0A0C0F"
surface = "#121519"
gold    = "#C4A561"
fog     = "#2A2F36"
text    = "#E9EAEB"
textDim = "#8A8F96"

[variables]
background          = "$palette.void"
surface             = "$palette.surface"
foreground          = "$palette.text"
foregroundSecondary = "$palette.textDim"
accent              = "$palette.gold"
separator           = "$palette.fog"
workspaceColor      = "$workspaceColor"
ghosttyBackground   = "$ghosttyBackground"

[chrome.windowFrame]
color        = "$workspaceColor"
thicknessPt  = 1.5

[chrome.sidebar]
tintOverlay           = "$workspaceColor.opacity(0.08)"
tintBase              = "$background"
tintBaseOpacity       = 0.18
activeTabFill         = "$workspaceColor"
activeTabFillFallback = "$surface"
activeTabRail         = "$workspaceColor"
activeTabRailFallback = "$accent"
activeTabRailOpacity  = 0.95
inactiveTabCustomOpacity       = 0.70
inactiveTabMultiSelectOpacity  = 0.35
badgeFill             = "$accent"
borderLeading         = "$separator"

[chrome.dividers]
color       = "$workspaceColor.mix($background, 0.65)"
thicknessPt = 1.0

[chrome.titleBar]
background          = "$surface"
backgroundOpacity   = 0.85
foreground          = "$foreground"
foregroundSecondary = "$foregroundSecondary"
borderBottom        = "$separator"

[chrome.tabBar]
background       = "$ghosttyBackground"
activeFill       = "$ghosttyBackground.lighten(0.04)"
divider          = "$separator"
activeIndicator  = "$workspaceColor"

[chrome.browserChrome]
background   = "$ghosttyBackground"
omnibarFill  = "$surface.mix($background, 0.15)"

[chrome.markdownChrome]
background = "$background"

[behavior]
animateWorkspaceCrossfade = false
```

### A.2 `high-contrast-workspace.toml`

```toml
[identity]
name         = "high-contrast-workspace"
display_name = "High-Contrast Workspace"
author       = "Stage 11 Agentics"
version      = "0.01.001"
schema       = 1

# inherits palette + variables from default via loader's fallback layer

[chrome.windowFrame]
color        = "$workspaceColor"
thicknessPt  = 2.5

[chrome.sidebar]
tintOverlay           = "$workspaceColor.opacity(0.22)"
activeTabFill         = "$workspaceColor"
activeTabRail         = "$workspaceColor"
activeTabRailOpacity  = 1.0

[chrome.dividers]
color       = "$workspaceColor"
thicknessPt = 3.0

[chrome.tabBar]
activeIndicator = "$workspaceColor"
```

### A.3 `minimal.toml`

```toml
[identity]
name         = "minimal"
display_name = "Minimal"
author       = "Stage 11 Agentics"
version      = "0.01.001"
schema       = 1

[chrome.windowFrame]
color        = "$workspaceColor"
thicknessPt  = 1.0

[chrome.sidebar]
tintOverlay = "$background.opacity(0.0)"   # off
activeTabFill = "$surface"
activeTabRail = "$accent"

[chrome.dividers]
color       = "$separator"
thicknessPt = 1.0

[chrome.tabBar]
activeIndicator = "$accent"
```

---

## Appendix B — File & directory summary

### New files (across M1-M4)

| Path | Milestone | Purpose |
|---|---|---|
| `Sources/Theme/C11muxTheme.swift` | M1 | Codable theme struct |
| `Sources/Theme/ThemedValue.swift` | M1 | Value grammar parser |
| `Sources/Theme/ThemeManager.swift` | M1 | Singleton manager + publisher |
| `Sources/Theme/WorkspaceFrame.swift` | M2 | Outer frame SwiftUI view |
| `Sources/Theme/ThemeManager+WorkspaceColor.swift` | M2 | `$workspaceColor` resolution |
| `Sources/Theme/ThemeDirectoryWatcher.swift` | M3 | User-theme file watcher |
| `Sources/Settings/AppearanceThemeSection.swift` | M4 | Settings picker |
| `Sources/Settings/ThemePreviewCanvas.swift` | M4 | Settings preview |
| `Sources/SocketAPI/ThemeMethods.swift` | M4 | Socket handlers |
| `CLI/commands/Themes.swift` | M4 | CLI subcommand |
| `CLI/commands/WorkspaceColor.swift` | M4 | CLI subcommand |
| `Resources/c11mux-themes/stage11.toml` | M1 (loaded); M3 (committed) | Default built-in |
| `Resources/c11mux-themes/high-contrast-workspace.toml` | M3 | Built-in |
| `Resources/c11mux-themes/minimal.toml` | M3 | Built-in |

### Modified files (across M1-M4)

| Path | Milestones | Notes |
|---|---|---|
| `Sources/Workspace.swift` | M1, M2 | `bonsplitAppearance` takes theme; `applyGhosttyChrome` threads divider color+thickness |
| `Sources/WorkspaceContentView.swift` | M1, M2 | `.overlay(WorkspaceFrame(...))` |
| `Sources/ContentView.swift` | M1, M2, M4 | `TabItemView` theme reads; sidebar tint overlay; context-menu tooltip |
| `Sources/SurfaceTitleBarView.swift` | M1 | Background / border / foreground through theme |
| `Sources/Panels/BrowserPanelView.swift` | M2 | Chrome background / omnibar through theme |
| `Sources/Panels/MarkdownPanelView.swift` | M2 | Panel background through theme |
| `Sources/cmuxApp.swift` | M3, M4 | Create themes dir; insert Appearance settings section |
| `vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift` | M2 | `ChromeColors.dividerThicknessPt` field |
| `vendor/bonsplit/Sources/Bonsplit/Internal/Views/SplitContainerView.swift` | M2 | Override `dividerThickness` |
| `docs/socket-api-reference.md` | M4 | Document new `theme.*` and `workspace.set_custom_color` methods |
| `Resources/Localizable.xcstrings` | M3, M4 | New localization keys |

Ship M1. Ship M2. Measure. Then M3, M4. Re-justify M5.
