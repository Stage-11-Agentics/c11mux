import AppKit
import SwiftUI

// CMUX-10: Single seam for flash visuals (color + envelope) used by both the
// pane ring renderer (`GhosttySurfaceScrollView`) and the sidebar workspace row
// fill (`TabItemView`). Lifting these behind one type lets later commits swap
// the default color, accept a per-call override, and unify the temporal
// envelope across surfaces without touching every renderer.
//
// Commit 1 (this file's introduction) is a pure refactor: `FlashAppearance.current()`
// still returns the existing gold accent and the existing two-pattern envelope
// pair (`.paneRing` / `.sidebarFill`). Later commits in CMUX-10 swap the
// default color (#F5C518) and unify the envelope.

enum FlashEnvelope: Equatable {
    /// Two-peak ring envelope used by the pane ring (`FocusFlashPattern`,
    /// 0.9s, peaks at full opacity). Carried forward unchanged from the
    /// pre-CMUX-10 implementation.
    case paneRing

    /// Single-peak low-amplitude envelope used by the sidebar workspace row
    /// (`SidebarFlashPattern`, 0.6s, peak 0.18). Carried forward unchanged for
    /// the refactor commit; commit 3 retires this in favor of `.paneRing` with
    /// a per-channel amplitude scalar.
    case sidebarFill
}

struct FlashAppearance: Equatable {
    let color: NSColor
    let envelope: FlashEnvelope

    /// SwiftUI-compatible projection of `color`. SwiftUI's sidebar fill needs a
    /// `Color`, not an `NSColor`; pane renderer needs the `NSColor` directly.
    var swiftUIColor: Color {
        Color(nsColor: color)
    }

    /// The default flash color used when no per-call override is provided.
    /// Commit 1 keeps the historical gold accent; commit 2 swaps to the
    /// CMUX-10 yellow.
    static var defaultColor: NSColor {
        cmuxAccentNSColor()
    }

    /// Snapshot of the current default appearance for the given envelope.
    /// Call sites that don't yet know which envelope they want pick `.paneRing`
    /// (the historical pane behavior) so the refactor stays a no-op.
    static func current(envelope: FlashEnvelope = .paneRing) -> FlashAppearance {
        FlashAppearance(color: defaultColor, envelope: envelope)
    }
}
