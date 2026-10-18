import Foundation

/// UserDefaults-backed preferences. SwiftUI reads them with `@AppStorage(Key.x)`;
/// AppKit code reads the static accessors and listens for `didChange`.
enum AppSettings {
    enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showTitleInMenuBar = "showTitleInMenuBar"
        static let notifyOnTrackChange = "notifyOnTrackChange"
        static let keepPlayingWhenClosed = "keepPlayingWhenClosed"
        static let theme = "theme"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.showMenuBarIcon: true,
            Key.showTitleInMenuBar: false,
            Key.notifyOnTrackChange: true,
            Key.keepPlayingWhenClosed: true,
            Key.theme: ThemeController.Theme.spotifyStyle.rawValue,
        ])
    }

    static var showMenuBarIcon: Bool { UserDefaults.standard.bool(forKey: Key.showMenuBarIcon) }
    static var showTitleInMenuBar: Bool { UserDefaults.standard.bool(forKey: Key.showTitleInMenuBar) }
    static var notifyOnTrackChange: Bool { UserDefaults.standard.bool(forKey: Key.notifyOnTrackChange) }
    static var keepPlayingWhenClosed: Bool { UserDefaults.standard.bool(forKey: Key.keepPlayingWhenClosed) }

    @MainActor
    static var theme: ThemeController.Theme {
        UserDefaults.standard.string(forKey: Key.theme).flatMap(ThemeController.Theme.init(rawValue:)) ?? .spotifyStyle
    }
}
