# Settings Reorganization Research

Status: first inventory pass.

Scope: visible controls in the public Settings window implemented by `SettingsView` in `Sources/c11App.swift`, plus the dynamic `AgentSkillsSettingsSection`. Debug-only windows and hidden developer controls are intentionally out of scope unless they are affected by Reset All.

Primary sources:
- `Sources/c11App.swift` (`SettingsView`, reset behavior, app-level settings)
- `Sources/TabManager.swift` (workspace/sidebar defaults)
- `Sources/Panels/BrowserPanel.swift` (browser defaults)
- `Sources/TerminalNotificationStore.swift` (notification defaults)
- `Sources/KeyboardShortcutSettings.swift` (shortcut matrix)
- `Sources/TextBoxInput.swift` (TextBox Input defaults)
- `Sources/SocketControlSettings.swift` (automation socket modes)
- `Sources/AgentSkillsView.swift` and `Sources/SkillInstaller.swift` (Agent Skills settings)

## First-Pass Page Model

The current Settings window is a single long scroll with these visible sections:

- App
- Workspace Colors
- Sidebar Appearance
- Automation
- Browser
- TextBox Input
- Keyboard Shortcuts
- Agent Skills
- Reset

For reorganization, the inventory below groups every visible control into a more user-centered page model:

1. General
2. Workspace & Sidebar
3. Appearance
4. Notifications
5. Browser
6. Agents & Automation
7. Input & Shortcuts
8. Data & Reset

## General

| Setting | Current section | Control | Stored state / default | Notes |
| --- | --- | --- | --- | --- |
| Language | App | Picker | `appLanguage`, default `system`; also writes `AppleLanguages` | Change requires restart prompt. |
| Theme, Light slot | App | Theme picker | `theme.active.light`, default `stage11` in `ThemeAppStorage` | Chooses chrome theme for light appearance. |
| Theme, Dark slot | App | Theme picker | `theme.active.dark`, default `stage11` in `ThemeAppStorage` | Chooses chrome theme for dark appearance. |
| Open themes folder | App | Icon button | No preference | Reveals user themes directory. |
| Reload themes | App | Icon button | No preference | Reloads user themes. |
| Send anonymous telemetry | App | Toggle | `sendAnonymousTelemetry`, default `true` | Takes effect next launch. |
| Warn Before Quit | App | Toggle | `warnBeforeQuitShortcut`, default `true` | Controls Cmd+Q confirmation. |

## Workspace & Sidebar

| Setting | Current section | Control | Stored state / default | Notes |
| --- | --- | --- | --- | --- |
| New Workspace Placement | App | Picker | `newWorkspacePlacement`, default `afterCurrent` | Options: top, after current, end. |
| Minimal Mode | App | Toggle | `workspacePresentationMode`, default `standard` | Toggle maps to `minimal` vs `standard`. |
| Keep Workspace Open When Closing Last Surface | App | Toggle | Inverted binding to `closeWorkspaceOnLastSurfaceShortcut`, default `true` | UI default is off because stored default means closing last surface also closes workspace. |
| Reorder on Notification | App | Toggle | `workspaceAutoReorderOnNotification`, default `true` | Moves workspaces on notification; affects shortcut stability. |
| Hide All Sidebar Details | App | Toggle | `sidebarHideAllDetails`, default `false` | Disables most detail toggles. |
| Sidebar Branch Layout | App | Picker | `sidebarBranchVerticalLayout`, default `true` | Options: vertical, inline. Disabled by Hide All Sidebar Details. |
| Show Notification Message in Sidebar | App | Toggle | `sidebarShowNotificationMessage`, default `true` | Disabled by Hide All Sidebar Details. |
| Show Branch + Directory in Sidebar | App | Toggle | `sidebarShowBranchDirectory`, default `true` | Disabled by Hide All Sidebar Details. |
| Show Pull Requests in Sidebar | App | Toggle | `sidebarShowPullRequest`, default `true` | Disabled by Hide All Sidebar Details. |
| Open Sidebar PR Links in c11 Browser | App | Toggle | `browserOpenSidebarPullRequestLinksInCmuxBrowser`, default `true` | Disabled by Hide All Sidebar Details. This is browser routing surfaced in sidebar settings. |
| Show SSH in Sidebar | App | Toggle | `sidebarShowSSH`, default `true` | Not currently disabled by Hide All Sidebar Details. |
| Show Listening Ports in Sidebar | App | Toggle | `sidebarShowPorts`, default `true` | Disabled by Hide All Sidebar Details. |
| Show Latest Log in Sidebar | App | Toggle | `sidebarShowLog`, default `true` | Disabled by Hide All Sidebar Details. |
| Show Progress in Sidebar | App | Toggle | `sidebarShowProgress`, default `true` | Disabled by Hide All Sidebar Details. |
| Show Custom Metadata in Sidebar | App | Toggle | `sidebarShowStatusPills`, default `true` | Disabled by Hide All Sidebar Details. |

## Appearance

| Setting | Current section | Control | Stored state / default | Notes |
| --- | --- | --- | --- | --- |
| Workspace Color Indicator | Workspace Colors | Picker | `sidebarActiveTabIndicatorStyle`, default `leftRail` | Options: Left Rail, Solid Fill. |
| Workspace palette: Red | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#C0392B` | Stored only when changed from base. |
| Workspace palette: Crimson | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#922B21` | Stored only when changed from base. |
| Workspace palette: Orange | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#A04000` | Stored only when changed from base. |
| Workspace palette: Amber | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#7D6608` | Stored only when changed from base. |
| Workspace palette: Olive | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#4A5C18` | Stored only when changed from base. |
| Workspace palette: Green | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#196F3D` | Stored only when changed from base. |
| Workspace palette: Teal | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#006B6B` | Stored only when changed from base. |
| Workspace palette: Aqua | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#0E6B8C` | Stored only when changed from base. |
| Workspace palette: Blue | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#1565C0` | Stored only when changed from base. |
| Workspace palette: Navy | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#1A5276` | Stored only when changed from base. |
| Workspace palette: Indigo | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#283593` | Stored only when changed from base. |
| Workspace palette: Purple | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#6A1B9A` | Stored only when changed from base. |
| Workspace palette: Magenta | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#AD1457` | Stored only when changed from base. |
| Workspace palette: Rose | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#880E4F` | Stored only when changed from base. |
| Workspace palette: Brown | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#7B3F00` | Stored only when changed from base. |
| Workspace palette: Charcoal | Workspace Colors | Color picker | `workspaceTabColor.defaultOverrides`; base `#3E4B5E` | Stored only when changed from base. |
| Custom workspace colors | Workspace Colors | List with Remove buttons | `workspaceTabColor.customColors`, default empty, max 24 | Added from workspace context menu, managed here. |
| Reset Palette | Workspace Colors | Button | Clears `workspaceTabColor.defaultOverrides` and `workspaceTabColor.customColors` | Restores built-in workspace color palette. |
| Light Mode Tint | Sidebar Appearance | Color picker | `sidebarTintHexLight`, default nil; falls back to `sidebarTintHex` | Current fallback default is black. |
| Dark Mode Tint | Sidebar Appearance | Color picker | `sidebarTintHexDark`, default nil; falls back to `sidebarTintHex` | Current fallback default is black. |
| Tint Opacity | Sidebar Appearance | Slider | `sidebarTintOpacity`, default `0.18` | 0-100 percent UI. |
| Reset Sidebar Tint | Sidebar Appearance | Button | Resets `sidebarTintHexLight`, `sidebarTintHexDark`, `sidebarTintHex`, `sidebarTintOpacity` | Restores default sidebar tint. |

## Notifications

| Setting | Current section | Control | Stored state / default | Notes |
| --- | --- | --- | --- | --- |
| Dock Badge | App | Toggle | `notificationDockBadgeEnabled`, default `true` | Shows unread count on Dock/Cmd+Tab icon. |
| Show in Menu Bar | App | Toggle | `showMenuBarExtra`, default `true` | Enables menu bar extra for notifications and quick actions. |
| Unread Pane Ring | App | Toggle | `notificationPaneRingEnabled`, default `true` | Blue ring around panes with unread notifications. |
| Pane Flash | App | Toggle | `notificationPaneFlashEnabled`, default `true` | Brief blue outline when c11 highlights a pane. |
| Desktop Notifications | App | Status + action button | macOS notification authorization, no app preference | Button enables notifications or opens System Settings. |
| Send Test notification | App | Button | No preference | Sends a settings test notification. |
| Notification Sound | App | Picker + preview | `notificationSound`, default `Bottle` | Options include Default, system sounds, Custom File, None. |
| Custom notification sound file | App | Choose/Clear buttons | `notificationSoundCustomFilePath`, default empty | Conditional when Notification Sound is Custom File. |
| Notification Command | App | Text field | `notificationCustomCommand`, default empty | Runs via `/bin/sh -c` with notification env vars. |

## Browser

| Setting | Current section | Control | Stored state / default | Notes |
| --- | --- | --- | --- | --- |
| Default Search Engine | Browser | Picker | `browserSearchEngine`, default `google` | Options: Google, DuckDuckGo, Bing, Kagi, Startpage. |
| Show Search Suggestions | Browser | Toggle | `browserSearchSuggestionsEnabled`, default `true` | Applies to browser address bar suggestions. |
| Browser Theme | Browser | Picker | `browserThemeMode`, default `system` | Options: system, light, dark. Migrates legacy `browserForcedDarkModeEnabled`. |
| Open Terminal Links in c11 Browser | Browser | Toggle | `browserOpenTerminalLinksInCmuxBrowser`, default `true` | Terminal output link clicks use embedded browser when enabled. |
| Intercept `open http(s)` in Terminal | Browser | Toggle | `browserInterceptTerminalOpenCommandInCmuxBrowser`, default `true` | Intercepts terminal `open` calls for web URLs. |
| Hosts to Open in Embedded Browser | Browser | Text editor | `browserHostWhitelist`, default empty | Conditional when link/open interception is enabled. Empty means allow all hosts in c11. |
| URLs to Always Open Externally | Browser | Text editor | `browserExternalOpenPatterns`, default empty | Conditional when link/open interception is enabled. Supports plain substring or `re:` regex. |
| HTTP Hosts Allowed in Embedded Browser | Browser | Text editor + Save | `browserInsecureHTTPAllowlist`, default `localhost`, `127.0.0.1`, `::1`, `0.0.0.0`, `*.localtest.me` | Non-HTTPS allowlist; draft only persists when Save is clicked. |
| Import Browser Data | Browser | Choose button | No simple preference | Opens browser data import dialog. |
| Refresh detected browsers | Browser | Refresh button | No preference | Re-runs installed browser detection. |
| Show import hint on blank browser tabs | Browser | Toggle | `browserImportHintShowOnBlankTabs`, default `true` | Turning back on clears `browserImportHintDismissed`. |
| Browsing History | Browser | Clear History button | Browser history store, not UserDefaults | Button disabled when no saved pages exist. |

Associated browser import state touched by reset but not directly exposed as a setting:

| State | Stored state / default | Notes |
| --- | --- | --- |
| Import hint variant | `browserImportHintVariant`, default `toolbarChip` | Current Settings UI does not expose variant selection. |
| Import hint dismissed | `browserImportHintDismissed`, default `false` | Blank-tab dismissal state. |

## Agents & Automation

| Setting | Current section | Control | Stored state / default | Notes |
| --- | --- | --- | --- | --- |
| Socket Control Mode | Automation | Picker | `socketControlMode`, default `cmuxOnly` | Options: off, c11 processes only, automation mode, password mode, full open access. |
| Socket Password | Automation | Secure field + Set/Change/Clear | Password file in Application Support; env override `CMUX_SOCKET_PASSWORD` | Conditional when Socket Control Mode is password. Reset All does not clear the saved password file. |
| Full open access confirmation | Automation | Confirmation dialog | No preference beyond `socketControlMode` | Required before selecting `allowAll`. |
| Claude Code Integration | Automation | Toggle | `claudeCodeHooksEnabled`, default `true` | Controls c11's grandfathered Claude command wrapper integration. |
| Port Base | Automation | Number field | `cmuxPortBase`, default `9100` | Starting `CMUX_PORT` for workspace port ranges. |
| Port Range Size | Automation | Number field | `cmuxPortRange`, default `10` | Size of each workspace's port range. |
| Agent Skills: Claude Code | Agent Skills | Dynamic row | Filesystem state under `~/.claude/skills` | Actions vary by state: Install, Refresh, Update, Remove, Reveal Folder, Reveal Skill. |
| Agent Skills: Codex | Agent Skills | Dynamic row | Filesystem state under `~/.codex/skills` | Same action model as Claude Code. |
| Agent Skills: Kimi | Agent Skills | Dynamic row | Filesystem state under `~/.kimi/skills` | Same action model as Claude Code. |
| Agent Skills: OpenCode | Agent Skills | Dynamic row | Filesystem state under `~/.opencode/skills` | Same action model as Claude Code. |
| Run Onboarding Wizard | Agent Skills | Button | No preference in this view | Opens the first-run skill installation wizard. |

## Input & Shortcuts

| Setting | Current section | Control | Stored state / default | Notes |
| --- | --- | --- | --- | --- |
| Rename Selects Existing Name | App | Toggle | `commandPalette.renameSelectAllOnFocus`, default `true` | Command Palette rename starts with existing text selected. |
| Command Palette Searches All Surfaces | App | Toggle | `commandPalette.switcherSearchAllSurfaces`, default `false` | Cmd+P can include terminal, browser, and markdown surfaces across workspaces. |
| Send on Return | TextBox Input | Picker | `textBoxEnterToSend`, default `true` | Options: Return = Send, Return = Newline. |
| Escape Key | TextBox Input | Picker | `textBoxEscapeBehavior`, default `sendEscape` | Options: Send ESC Key, Focus Terminal. |
| Keyboard Shortcut behavior | TextBox Input | Picker | `textBoxShortcutBehavior`, default `toggleDisplay` | Options: Toggle Display, Toggle Focus. Shortcut itself is configured in Keyboard Shortcuts. |
| Show Cmd/Ctrl-Hold Shortcut Hints | Keyboard Shortcuts | Toggle | `shortcutHintShowOnCommandHold`, default `true` | Shows hint pills while modifier keys are held. |

### Keyboard Shortcut Matrix

Each row is a visible setting backed by the action's `shortcut.*` UserDefaults key. Clicking the displayed shortcut records a replacement. Reset All removes all custom shortcut values.

| Action label | Key | Default shortcut | Proposed subgroup |
| --- | --- | --- | --- |
| Toggle Sidebar | `shortcut.toggleSidebar` | Cmd+B | Window & chrome |
| New Workspace | `shortcut.newTab` | Cmd+N | Window & chrome |
| New Window | `shortcut.newWindow` | Cmd+Shift+N | Window & chrome |
| Close Window | `shortcut.closeWindow` | Ctrl+Cmd+W | Window & chrome |
| Open Folder | `shortcut.openFolder` | Cmd+O | Window & chrome |
| Send Feedback | `shortcut.sendFeedback` | Cmd+Opt+F | Help |
| Show Notifications | `shortcut.showNotifications` | Cmd+I | Notifications |
| Jump to Latest Unread | `shortcut.jumpToUnread` | Cmd+Shift+U | Notifications |
| Flash Focused Panel | `shortcut.triggerFlash` | Cmd+Shift+H | Notifications |
| Next Surface | `shortcut.nextSurface` | Cmd+Shift+] | Navigation |
| Previous Surface | `shortcut.prevSurface` | Cmd+Shift+[ | Navigation |
| Next Workspace | `shortcut.nextSidebarTab` | Ctrl+Cmd+] | Navigation |
| Previous Workspace | `shortcut.prevSidebarTab` | Ctrl+Cmd+[ | Navigation |
| Rename Tab | `shortcut.renameTab` | Cmd+R | Navigation |
| Rename Workspace | `shortcut.renameWorkspace` | Cmd+Shift+R | Navigation |
| Close Workspace | `shortcut.closeWorkspace` | Cmd+Shift+W | Navigation |
| New Surface | `shortcut.newSurface` | Cmd+T | Navigation |
| Toggle Terminal Copy Mode | `shortcut.toggleTerminalCopyMode` | Cmd+Shift+M | Terminal |
| Focus Pane Left | `shortcut.focusLeft` | Cmd+Opt+Left | Panes |
| Focus Pane Right | `shortcut.focusRight` | Cmd+Opt+Right | Panes |
| Focus Pane Up | `shortcut.focusUp` | Cmd+Opt+Up | Panes |
| Focus Pane Down | `shortcut.focusDown` | Cmd+Opt+Down | Panes |
| Split Right | `shortcut.splitRight` | Cmd+D | Panes |
| Split Down | `shortcut.splitDown` | Cmd+Shift+D | Panes |
| Toggle Pane Zoom | `shortcut.toggleSplitZoom` | Cmd+Shift+Return | Panes |
| Split Browser Right | `shortcut.splitBrowserRight` | Cmd+Opt+D | Panes & browser |
| Split Browser Down | `shortcut.splitBrowserDown` | Cmd+Opt+Shift+D | Panes & browser |
| Open Browser | `shortcut.openBrowser` | Cmd+Shift+L | Browser |
| Toggle Browser Developer Tools | `shortcut.toggleBrowserDeveloperTools` | Cmd+Opt+I | Browser |
| Show Browser JavaScript Console | `shortcut.showBrowserJavaScriptConsole` | Cmd+Opt+C | Browser |
| Toggle TextBox Input | `shortcut.toggleTextBoxInput` | Cmd+Opt+B | TextBox |

## Data & Reset

| Setting | Current section | Control | Stored state / default | Notes |
| --- | --- | --- | --- | --- |
| Clear browser history | Browser | Button | Browser history store | Data action, currently located in Browser. |
| Reset All Settings | Reset | Button | Imperative reset in `SettingsView.resetAllSettings()` | Resets many visible preferences, but not all visible controls and not external/system state. |

### Reset All Coverage Notes

`resetAllSettings()` currently resets:

- Language and `AppleLanguages`
- Socket control mode
- Claude Code integration toggle
- Telemetry toggle
- Browser search/theme/link routing/import hint settings and HTTP allowlist
- Notification sound, custom sound path, notification command, Dock badge, pane ring, pane flash, menu bar extra
- Quit warning
- Command Palette rename/search settings
- Shortcut hint visibility defaults
- Workspace placement, presentation mode, last-surface close behavior, notification reorder
- Sidebar detail toggles and sidebar tint
- Keyboard shortcuts
- TextBox Input settings
- Workspace color palette and custom colors

Visible controls that Reset All does not currently reset:

- Theme light/dark slots (`theme.active.light`, `theme.active.dark`)
- Port Base (`cmuxPortBase`)
- Port Range Size (`cmuxPortRange`)
- Saved socket password file
- Browser history
- Agent skill install/remove state
- macOS desktop notification permission

Hidden or legacy state touched by Reset All:

- `workspaceTitlebarVisible`
- `workspaceButtonsFadeMode`
- `titlebarControlsVisibilityMode`
- `paneTabBarControlsVisibilityMode`
- `shortcutHintAlwaysShow`

## Early Reorganization Observations

- The current App section is doing too much: language, themes, workspace behavior, notifications, telemetry, command palette, and sidebar detail controls all live together.
- Sidebar settings are split between App, Workspace Colors, and Sidebar Appearance, while one sidebar link-routing setting is backed by Browser state.
- Notification behavior is mixed with general app behavior and sidebar workspace behavior.
- Browser includes routine search/theme preferences, security allowlists, import flows, and destructive history actions in one long section.
- Agent-facing settings are split between Automation and Agent Skills, even though both are about external control and agent enablement.
- Keyboard shortcuts are a single long flat list; subgrouping by navigation, panes, browser, notifications, and input would make scanning easier.
- Reset All's name overpromises today because several visible controls and external states are not reset.
