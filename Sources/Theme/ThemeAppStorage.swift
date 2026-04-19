import Foundation

public enum ThemeAppStorage {
    public enum Keys {
        public static let engineDisabledRuntime = "theme.engine.disabledRuntime"
        public static let workspaceFrameEnabled = "theme.workspaceFrame.enabled"

        public static let m1bSurfaceTitleBarMigrated = "theme.m1b.surfaceTitleBar.migrated"
        public static let m1bBrowserChromeMigrated = "theme.m1b.browserChrome.migrated"
        public static let m1bMarkdownChromeMigrated = "theme.m1b.markdownChrome.migrated"
        public static let m1bBonsplitAppearanceMigrated = "theme.m1b.bonsplitAppearance.migrated"
        public static let m1bSidebarTabItemMigrated = "theme.m1b.sidebarTabItem.migrated"
        public static let m1bCustomTitlebarMigrated = "theme.m1b.customTitlebar.migrated"
        public static let m1bWorkspaceContentViewContextMigrated = "theme.m1b.workspaceContentViewContext.migrated"
    }

    public static var defaults: UserDefaults {
        if let bundleID = Bundle.main.bundleIdentifier,
           let scoped = UserDefaults(suiteName: bundleID) {
            return scoped
        }
        return .standard
    }

    public static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        let store = defaults
        guard store.object(forKey: key) != nil else { return defaultValue }
        return store.bool(forKey: key)
    }

    public static func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
