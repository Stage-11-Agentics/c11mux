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

    private var selected: ConfirmSelectionField {
        runtime.confirmSelection[panelId] ?? .confirm
    }

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
                        .foregroundColor(BrandColors.whiteSwiftUI)
                        .frame(minWidth: 64)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .selectionBox(isActive: selected == .cancel)
                .accessibilityAddTraits(selected == .cancel ? .isSelected : [])

                Button(role: content.role == .destructive ? .destructive : nil,
                       action: confirm) {
                    Text(content.confirmLabel)
                        .foregroundColor(content.role == .destructive
                                         ? BrandColors.whiteSwiftUI
                                         : BrandColors.blackSwiftUI)
                        .frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(content.role == .destructive ? .red : BrandColors.goldSwiftUI)
                .selectionBox(isActive: selected == .confirm)
                .accessibilityAddTraits(selected == .confirm ? .isSelected : [])
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
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("PaneInteraction.confirm.card")
    }

    private func confirm() {
        runtime.resolveConfirm(
            panelId: panelId,
            result: .confirmed,
            ifInteractionId: content.id
        )
    }
    private func cancel() {
        runtime.resolveConfirm(
            panelId: panelId,
            result: .cancelled,
            ifInteractionId: content.id
        )
    }
}

// MARK: - TextInput variant

private struct TextInputCard: View {
    let panelId: UUID
    let content: TextInputContent
    @ObservedObject var runtime: PaneInteractionRuntime

    @State private var value: String = ""
    @State private var errorText: String?

    private var selection: TextInputSelectionField {
        runtime.textInputSelection[panelId] ?? .field
    }

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

            IMESafeTextField(
                text: $value,
                placeholder: content.placeholder,
                onSubmit: submit,
                onCancel: cancel,
                onTabOut: { backward in
                    runtime.cycleTextInputSelection(panelId: panelId, backward: backward)
                },
                onBeganEditing: {
                    runtime.setTextInputSelection(panelId: panelId, .field)
                }
            )
            .frame(minHeight: 22)

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                    .accessibilityIdentifier("PaneInteraction.textInput.error")
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button(action: cancel) {
                    Text(content.cancelLabel)
                        .foregroundColor(BrandColors.whiteSwiftUI)
                        .frame(minWidth: 64)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .selectionBox(isActive: selection == .cancel)
                .accessibilityAddTraits(selection == .cancel ? .isSelected : [])

                Button(action: submit) {
                    Text(content.confirmLabel)
                        .foregroundColor(BrandColors.blackSwiftUI)
                        .frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandColors.goldSwiftUI)
                .keyboardShortcut(.defaultAction)
                .selectionBox(isActive: selection != .cancel)
                .accessibilityAddTraits(selection == .confirm ? .isSelected : [])
            }
        }
        .padding(24)
        .frame(minWidth: 320, maxWidth: 480, alignment: .leading)
        .background(
            // Background tap: click on the card chrome (outside the field and
            // buttons) defocuses the field and promotes selection to .confirm
            // so arrow keys start driving the buttons. The Color.clear layer
            // sits behind real content, so taps on the field / buttons hit
            // those first and never reach this gesture.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    runtime.setTextInputSelection(panelId: panelId, .confirm)
                }
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BrandColors.surfaceSwiftUI)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(BrandColors.ruleSwiftUI, lineWidth: 1)
                )
        )
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("PaneInteraction.textInput.card")
        .onAppear {
            value = content.defaultValue
            // Seed the bridge so Cmd+D immediately after present() submits the
            // default value instead of nil — matches the original contract
            // when the user hasn't started typing yet.
            runtime.updatePendingTextInputValue(interactionId: content.id, value: content.defaultValue)
        }
        .onChange(of: value) { _, newValue in
            // Bridge live text back to the runtime so Cmd+D accept submits
            // what the user typed, not the default value.
            runtime.updatePendingTextInputValue(interactionId: content.id, value: newValue)
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
        runtime.resolveTextInput(
            panelId: panelId,
            result: .submitted(value),
            ifInteractionId: content.id
        )
    }

    private func cancel() {
        runtime.resolveTextInput(
            panelId: panelId,
            result: .cancelled,
            ifInteractionId: content.id
        )
    }
}

/// NSTextField-backed text input that respects IME composition. Needed because
/// SwiftUI's `TextField` routes key events in a way that swallows marked-text
/// composition state for CJK input methods — typing Japanese (Kotoeri) or
/// Pinyin into the rename-tab overlay would otherwise lose the composition.
///
/// Pattern mirrors m9's `TextBoxInput.InputTextView` IME guard: skip binding
/// sync and binding writes whenever `currentEditor()?.hasMarkedText()` is true.
private struct IMESafeTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String?
    let onSubmit: () -> Void
    let onCancel: () -> Void
    /// Called when Tab / Shift-Tab is pressed inside the field. `backward`
    /// is true for Shift-Tab. The card uses this to cycle its selection
    /// state off `.field`; the overlay host's selection observer then
    /// transfers first responder from this field to itself.
    var onTabOut: ((_ backward: Bool) -> Void)? = nil
    /// Called when the field begins editing (e.g., user clicked it after
    /// defocusing). Lets the card restore `.field` selection so the outline
    /// on Cancel/Confirm clears.
    var onBeganEditing: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField(string: text)
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.placeholderString = placeholder ?? ""
        tf.delegate = context.coordinator
        tf.isBezeled = true
        tf.bezelStyle = .roundedBezel
        tf.isEditable = true
        tf.isSelectable = true
        tf.usesSingleLineMode = true
        tf.lineBreakMode = .byTruncatingTail
        tf.cell?.sendsActionOnEndEditing = false
        tf.focusRingType = .default
        // Grab first responder on next runloop so the hosting window has
        // settled its responder chain (the AppKit overlay host has already
        // become first responder just before this view appears).
        DispatchQueue.main.async { [weak tf] in
            guard let tf, let window = tf.window else { return }
            window.makeFirstResponder(tf)
            if let editor = tf.currentEditor() {
                editor.selectedRange = NSRange(location: 0, length: (tf.stringValue as NSString).length)
            }
        }
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.placeholderString = placeholder ?? ""
        // Skip committed-text sync during IME composition — the field editor
        // holds uncommitted marked text that stringValue doesn't reflect.
        // Overwriting stringValue here cancels the active composition.
        if let editor = nsView.currentEditor() as? NSTextView, editor.hasMarkedText() {
            return
        }
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: IMESafeTextField
        init(_ parent: IMESafeTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            if let editor = tf.currentEditor() as? NSTextView, editor.hasMarkedText() {
                // Don't push uncommitted composition through to the binding.
                return
            }
            parent.text = tf.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            // User clicked back into the field (or AppKit granted responder) —
            // reset the card's selection so the outline on Cancel/Confirm
            // clears and arrow keys go back to cursor-movement inside the
            // field editor.
            parent.onBeganEditing?()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if textView.hasMarkedText() {
                    // Let the IME commit the composition first; NSTextField
                    // will re-send insertNewline on the next commit.
                    return false
                }
                // Flush the field's committed value to the binding before
                // invoking submit — resignFirstResponder otherwise lags.
                parent.text = control.stringValue
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                if textView.hasMarkedText() { return false }
                parent.text = control.stringValue
                parent.onTabOut?(false)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                if textView.hasMarkedText() { return false }
                parent.text = control.stringValue
                parent.onTabOut?(true)
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Helpers

private extension View {
    /// White rectangular outline around the currently-selected button. Arrow
    /// keys (left/right) and Tab move the selection; Return invokes it. Plain
    /// `@State` drives this overlay rather than `@FocusState` because the
    /// `PaneInteractionOverlayHost` holds AppKit first responder — SwiftUI
    /// focus inside the card is shadowed, so it can't be trusted to render.
    @ViewBuilder
    func selectionBox(isActive: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white, lineWidth: isActive ? 2 : 0)
                .padding(-3)
                .animation(.easeInOut(duration: 0.12), value: isActive)
        )
    }
}

