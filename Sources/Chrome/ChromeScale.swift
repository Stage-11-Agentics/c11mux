import Foundation
import SwiftUI

// MARK: - ChromeScaleSettings

/// Persisted "App Chrome UI Scale" preset (C11-6). Scales c11-owned chrome —
/// sidebar workspace card text and the surface tab strip — without changing
/// Ghostty terminal cells or web/markdown content.
///
/// Mirrors the `WorkspacePresentationModeSettings` shape (key + Mode enum +
/// `mode(for:)` + `mode(defaults:)`) so the codebase looks coherent and the
/// resolver stays parameter-pure for non-SwiftUI consumers.
enum ChromeScaleSettings {
    static let presetKey = "chromeScalePreset"

    enum Preset: String, CaseIterable, Identifiable {
        case compact, standard, large, extraLarge
        var id: String { rawValue }

        /// Localized display name for the Settings picker.
        var displayName: String {
            switch self {
            case .compact:
                return String(
                    localized: "settings.chromeScale.preset.compact",
                    defaultValue: "Compact"
                )
            case .standard:
                return String(
                    localized: "settings.chromeScale.preset.standard",
                    defaultValue: "Default"
                )
            case .large:
                return String(
                    localized: "settings.chromeScale.preset.large",
                    defaultValue: "Large"
                )
            case .extraLarge:
                return String(
                    localized: "settings.chromeScale.preset.extraLarge",
                    defaultValue: "Extra Large"
                )
            }
        }
    }

    static let defaultPreset: Preset = .standard

    static func preset(for rawValue: String?) -> Preset {
        Preset(rawValue: rawValue ?? "") ?? defaultPreset
    }

    /// Parameter-seam overload for non-SwiftUI consumers (e.g. `Workspace.bonsplitAppearance(...)`).
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

    /// Belt-and-suspenders notification for any future non-Workspace listener.
    /// Workspace observes UserDefaults via KVO (`ChromeScaleObserver`), so this
    /// notification is NOT load-bearing for the live-update path.
    static let didChangeNotification = Notification.Name("com.stage11.c11.chromeScaleDidChange")
}

// MARK: - ChromeScaleTokens

/// Single-stored-property + computed-tokens design. The synthesized `Equatable`
/// reduces to a `multiplier` compare so this type can sit inside `TabItemView`'s
/// `==` (typing-latency hot path) without growing the comparison surface. If you
/// add stored properties, audit that hot path before merging.
struct ChromeScaleTokens: Equatable {
    let multiplier: CGFloat

    // MARK: Sidebar tokens

    var sidebarWorkspaceTitle: CGFloat         { 12.5 * multiplier }
    var sidebarWorkspaceDetail: CGFloat        { 10.0 * multiplier }
    var sidebarWorkspaceMetadata: CGFloat      { 10.0 * multiplier }
    var sidebarWorkspaceAccessory: CGFloat     {  9.0 * multiplier }
    var sidebarWorkspaceProgressLabel: CGFloat {  9.0 * multiplier }
    var sidebarWorkspaceLogIcon: CGFloat       {  8.0 * multiplier }
    var sidebarWorkspaceBranchDot: CGFloat     {  3.0 * multiplier }

    // MARK: Surface tab strip tokens (Bonsplit Appearance values)

    var surfaceTabTitle: CGFloat                  { 11.0 * multiplier }
    var surfaceTabIcon: CGFloat                   { 14.0 * multiplier }
    var surfaceTabBarHeight: CGFloat              { 30.0 * multiplier }
    var surfaceTabItemHeight: CGFloat             { 30.0 * multiplier }
    var surfaceTabHorizontalPadding: CGFloat      {  6.0 * multiplier }
    var surfaceTabMinWidth: CGFloat               { 112.0 * multiplier }
    var surfaceTabMaxWidth: CGFloat               { 220.0 * multiplier }
    var surfaceTabCloseIconSize: CGFloat          {  9.0 * multiplier }
    var surfaceTabContentSpacing: CGFloat         {  6.0 * multiplier }
    var surfaceTabDirtyIndicatorSize: CGFloat     {  8.0 * multiplier }
    var surfaceTabNotificationBadgeSize: CGFloat  {  6.0 * multiplier }
    /// Floor at 2pt so the selected-tab underbar stays visible at 0.66× and below
    /// in the future Custom-multiplier follow-up. At ship presets (0.90×–1.25×)
    /// the floor is inert (2.7–3.75).
    var surfaceTabActiveIndicatorHeight: CGFloat  { max(2.0, 3.0 * multiplier) }

    // MARK: Surface title bar tokens

    var surfaceTitleBarTitle: CGFloat     { 12.0 * multiplier }
    var surfaceTitleBarAccessory: CGFloat { 10.0 * multiplier }

    static let standard = ChromeScaleTokens(multiplier: 1.0)

    static func resolved(from defaults: UserDefaults = .standard) -> ChromeScaleTokens {
        ChromeScaleTokens(
            multiplier: ChromeScaleSettings.multiplier(
                for: ChromeScaleSettings.preset(defaults: defaults)
            )
        )
    }
}

// MARK: - Environment

extension EnvironmentValues {
    private struct ChromeScaleTokensKey: EnvironmentKey {
        static let defaultValue = ChromeScaleTokens.standard
    }

    var chromeScaleTokens: ChromeScaleTokens {
        get { self[ChromeScaleTokensKey.self] }
        set { self[ChromeScaleTokensKey.self] = newValue }
    }
}

// MARK: - ChromeScaleObserver

/// `Workspace` is `@MainActor final class … : ObservableObject` — not an
/// `NSObject` subclass — so it can't host `UserDefaults.addObserver(...)`
/// directly. `ChromeScaleObserver` is the small `NSObject` helper each
/// `Workspace` holds; lifetime is tied to the Workspace via composition.
///
/// KVO callbacks fire on the writer's thread; the observer hops to the main
/// actor before invoking the callback so the callback can mutate
/// `BonsplitController.configuration` and other main-actor state safely.
final class ChromeScaleObserver: NSObject {
    private let onChange: () -> Void
    private static let keyPath = ChromeScaleSettings.presetKey
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, onChange: @escaping () -> Void) {
        self.defaults = defaults
        self.onChange = onChange
        super.init()
        defaults.addObserver(self, forKeyPath: Self.keyPath, options: [.new], context: nil)
    }

    deinit {
        defaults.removeObserver(self, forKeyPath: Self.keyPath)
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == Self.keyPath else { return }
        let onChange = self.onChange
        Task { @MainActor in onChange() }
    }
}
