import SwiftUI
import Bonsplit

@MainActor
struct TabBarTrailingAccessory: View {
    let paneId: PaneID
    let chromeSaturation: Double
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 2) {
            ToolbarIconButton(
                systemImage: "terminal",
                tooltip: String(localized: "tabbar.newTerminal", defaultValue: "New Terminal")
            ) {
                _ = workspace.newTerminalSurface(inPane: paneId)
            }
            ToolbarIconButton(
                systemImage: "globe",
                tooltip: String(localized: "tabbar.newBrowser", defaultValue: "New Browser")
            ) {
                _ = workspace.newBrowserSurface(inPane: paneId)
            }
            ToolbarIconButton(
                systemImage: "doc.text",
                tooltip: String(localized: "tabbar.newMarkdown", defaultValue: "New Markdown")
            ) {
                _ = workspace.newMarkdownSurface(inPane: paneId)
            }
            ToolbarSeparator()
            ToolbarIconButton(
                systemImage: "square.split.2x1",
                tooltip: String(localized: "tabbar.splitRight", defaultValue: "Split Right")
            ) {
                _ = workspace.bonsplitController.splitPane(paneId, orientation: .horizontal)
            }
            ToolbarIconButton(
                systemImage: "square.split.1x2",
                tooltip: String(localized: "tabbar.splitDown", defaultValue: "Split Down")
            ) {
                _ = workspace.bonsplitController.splitPane(paneId, orientation: .vertical)
            }
            ToolbarIconButton(
                systemImage: "plus",
                tooltip: String(localized: "tabbar.newTab", defaultValue: "New Tab")
            ) {
                workspace.createNewTabOfFocusedKind(inPane: paneId)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .saturation(chromeSaturation)
        // Minimal-mode hover-fade is still handled by bonsplit's internal splitButtons
        // row during Phase 2 (it renders behind this accessory). Phase 3 will delete
        // the internal row; c11mux will then own the fade via @Environment(\.bonsplitTabBarHover).
    }
}

private struct ToolbarIconButton: View {
    let systemImage: String
    let tooltip: String
    let action: () -> Void
    @State private var isMouseInside = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isMouseInside ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isMouseInside = $0 }
        .help(tooltip)
    }
}

private struct ToolbarSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 8)
    }
}
