import AppKit
import SwiftUI

/// Shared SwiftUI rendering for a pane-scoped interaction. Used by every mount layer —
/// AppKit-hosted for terminals and WebView-backed browsers (via NSHostingView), and
/// as a raw SwiftUI ZStack overlay for markdown and empty-browser panels.
///
/// Scrim covers only the panel's bounds. The card grabs first responder via an internal
/// `@FocusState` anchor so Return/Escape/Tab/Cmd+D route through `onKeyPress`.
struct PaneInteractionCardView: View {
    let panelId: UUID
    let interaction: PaneInteraction
    @ObservedObject var runtime: PaneInteractionRuntime

    var body: some View {
        ZStack {
            // Scrim — click does NOT dismiss (plan §2: prevents accidental cancel).
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .allowsHitTesting(true)
                .onTapGesture { /* intentional no-op */ }
                .accessibilityHidden(true)

            card
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    @ViewBuilder
    private var card: some View {
        switch interaction {
        case .confirm(let content):
            ConfirmCard(panelId: panelId, content: content, runtime: runtime)
        case .textInput(let content):
            TextInputCard(panelId: panelId, content: content, runtime: runtime)
        }
    }
}

// MARK: - Confirm variant

private struct ConfirmCard: View {
    let panelId: UUID
    let content: ConfirmContent
    @ObservedObject var runtime: PaneInteractionRuntime

    private enum Field: Hashable { case cancel, confirm }
    @FocusState private var focused: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrandColors.whiteSwiftUI)

            if let message = content.message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(BrandColors.whiteSwiftUI.opacity(0.85))
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button(action: cancel) {
                    Text(content.cancelLabel)
                        .frame(minWidth: 64)
                }
                .keyboardShortcut(.cancelAction)
                .focused($focused, equals: .cancel)
                .focusRing(isActive: focused == .cancel)

                Button(role: content.role == .destructive ? .destructive : nil,
                       action: confirm) {
                    Text(content.confirmLabel)
                        .frame(minWidth: 64)
                }
                .keyboardShortcut(.defaultAction)
                .focused($focused, equals: .confirm)
                .focusRing(isActive: focused == .confirm)
            }
        }
        .padding(24)
        .frame(minWidth: 260, maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BrandColors.surfaceSwiftUI)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(BrandColors.ruleSwiftUI, lineWidth: 1)
                )
        )
        .onAppear { focused = .confirm }
        .onKeyPress(.escape) {
            cancel()
            return .handled
        }
    }

    private func confirm() { runtime.resolveConfirm(panelId: panelId, result: .confirmed) }
    private func cancel() { runtime.resolveConfirm(panelId: panelId, result: .cancelled) }
}

// MARK: - TextInput variant (Phase 1 scaffold; IME-safe NSTextField lands in Phase 6b)

private struct TextInputCard: View {
    let panelId: UUID
    let content: TextInputContent
    @ObservedObject var runtime: PaneInteractionRuntime

    @State private var value: String = ""
    @State private var errorText: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrandColors.whiteSwiftUI)

            if let message = content.message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(BrandColors.whiteSwiftUI.opacity(0.85))
            }

            TextField(content.placeholder ?? "", text: $value)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { submit() }

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button(action: cancel) {
                    Text(content.cancelLabel)
                        .frame(minWidth: 64)
                }
                .keyboardShortcut(.cancelAction)

                Button(action: submit) {
                    Text(content.confirmLabel)
                        .frame(minWidth: 64)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 320, maxWidth: 480, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BrandColors.surfaceSwiftUI)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(BrandColors.ruleSwiftUI, lineWidth: 1)
                )
        )
        .onAppear {
            value = content.defaultValue
            fieldFocused = true
        }
        .onKeyPress(.escape) {
            cancel()
            return .handled
        }
    }

    private func submit() {
        if let error = content.validate(value) {
            errorText = error
            return
        }
        runtime.resolveTextInput(panelId: panelId, result: .submitted(value))
    }

    private func cancel() {
        runtime.resolveTextInput(panelId: panelId, result: .cancelled)
    }
}

// MARK: - Helpers

private extension View {
    @ViewBuilder
    func focusRing(isActive: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(BrandColors.goldSwiftUI, lineWidth: isActive ? 2 : 0)
                .padding(-2)
                .animation(.easeInOut(duration: 0.12), value: isActive)
        )
    }
}

