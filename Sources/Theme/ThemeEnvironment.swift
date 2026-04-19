import SwiftUI

private struct C11muxThemeManagerEnvironmentKey: EnvironmentKey {
    static let defaultValue: ThemeManager? = nil
}

private struct C11muxThemeContextEnvironmentKey: EnvironmentKey {
    static let defaultValue: ThemeContext? = nil
}

extension EnvironmentValues {
    var c11muxThemeManager: ThemeManager? {
        get { self[C11muxThemeManagerEnvironmentKey.self] }
        set { self[C11muxThemeManagerEnvironmentKey.self] = newValue }
    }

    var c11muxThemeContext: ThemeContext? {
        get { self[C11muxThemeContextEnvironmentKey.self] }
        set { self[C11muxThemeContextEnvironmentKey.self] = newValue }
    }
}
