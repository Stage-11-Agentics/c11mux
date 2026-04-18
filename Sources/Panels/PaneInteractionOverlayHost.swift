import AppKit
import Combine
import SwiftUI

/// AppKit host for the pane-interaction SwiftUI card. Used by every mount layer
/// where SwiftUI-only overlays can't sit above the content (terminal portal,
/// WebView-backed browser portal) because those contents are AppKit-hosted on
/// top of the SwiftUI view tree.
///
/// The host:
/// - Wraps `PaneInteractionCardView` inside an `NSHostingView` sized to fill its bounds.
/// - Becomes first responder while visible so terminal / WebView key routing stops
///   (their surface views lose first-responder status) — the plan's focus-choke-point
///   contract (§3.3, §4.7) leans on this.
/// - Blocks hit-testing everywhere inside its bounds, preventing scrim-through clicks
///   while still letting the card's buttons work.
/// - Subscribes to the provided `PaneInteractionRuntime.$active` stream and shows /
///   hides / rebuilds the root view automatically for a given `panelId`.
@MainActor
final class PaneInteractionOverlayHost: NSView {

    let panelId: UUID
    let runtime: PaneInteractionRuntime
    private var hostingView: NSHostingView<PaneInteractionCardView>?
    private var cancellable: AnyCancellable?
    /// Responder to restore when the overlay hides. Captured on show so the
    /// terminal / browser view that had focus before the dialog regains it
    /// without requiring a manual click (synthesis-critical §2.10).
    private weak var priorFirstResponder: NSResponder?

    init(panelId: UUID, runtime: PaneInteractionRuntime) {
        self.panelId = panelId
        self.runtime = runtime
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        isHidden = true

        cancellable = runtime.$active
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                self?.apply(interaction: active[panelId])
            }
        apply(interaction: runtime.active[panelId])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Hit testing / focus

    override func hitTest(_ point: NSPoint) -> NSView? {
        // While hidden, pass through entirely so the underlying terminal / WebView
        // receives mouse events normally.
        guard !isHidden else { return nil }
        // While visible, swallow all clicks in our bounds so the scrim acts as a
        // modal barrier. The NSHostingView's own hit testing delivers button
        // presses correctly when they land inside the card.
        return super.hitTest(point) ?? self
    }

    override var acceptsFirstResponder: Bool { !isHidden }

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
    }

    // Prevent background mouseDown (on the scrim) from stealing focus back from
    // whatever child view currently needs it — the card manages its own focus.
    override func mouseDown(with event: NSEvent) { /* swallow */ }
    override func mouseUp(with event: NSEvent) { /* swallow */ }
    override func rightMouseDown(with event: NSEvent) { /* swallow */ }

    // MARK: - Content

    private func apply(interaction: PaneInteraction?) {
        if let interaction {
            let rootView = PaneInteractionCardView(
                panelId: panelId,
                interaction: interaction,
                runtime: runtime
            )
            if let hostingView {
                hostingView.rootView = rootView
            } else {
                let hv = NSHostingView(rootView: rootView)
                hv.frame = bounds
                hv.autoresizingMask = [.width, .height]
                addSubview(hv)
                hostingView = hv
            }
            let wasHidden = isHidden
            isHidden = false
            if let window {
                // Capture the prior first responder on first show so we can
                // restore it when the overlay hides. Don't overwrite on
                // subsequent `apply` calls (queue advance) — we want the
                // responder from before the FIRST card appeared.
                if wasHidden, priorFirstResponder == nil,
                   let prior = window.firstResponder, prior !== self {
                    priorFirstResponder = prior
                }
                window.makeFirstResponder(self)
            }
        } else {
            isHidden = true
            hostingView?.removeFromSuperview()
            hostingView = nil
            // Restore whoever had focus before we took it. If the responder
            // has since been torn down (panel close during dialog), fall
            // back to nil so the window's next-responder chain can resolve.
            if let window {
                if let prior = priorFirstResponder, prior.acceptsFirstResponder {
                    window.makeFirstResponder(prior)
                } else {
                    window.makeFirstResponder(nil)
                }
            }
            priorFirstResponder = nil
        }
    }

    // MARK: - Lifecycle

    deinit {
        cancellable?.cancel()
    }
}
