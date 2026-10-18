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
        static let syncedLyrics = "syncedLyrics"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.showMenuBarIcon: true,
            Key.showTitleInMenuBar: false,
            Key.notifyOnTrackChange: true,
            Key.keepPlayingWhenClosed: true,
            Key.theme: ThemeController.Theme.spotifyStyle.rawValue,
            Key.syncedLyrics: true,
        ])
    }

    static var showMenuBarIcon: Bool { UserDefaults.standard.bool(forKey: Key.showMenuBarIcon) }
    static var showTitleInMenuBar: Bool { UserDefaults.standard.bool(forKey: Key.showTitleInMenuBar) }
    static var notifyOnTrackChange: Bool { UserDefaults.standard.bool(forKey: Key.notifyOnTrackChange) }
    static var keepPlayingWhenClosed: Bool { UserDefaults.standard.bool(forKey: Key.keepPlayingWhenClosed) }
    /// Look up time-synced lyrics on LRCLIB (sends the track's title and artist to lrclib.net).
    static var syncedLyrics: Bool { UserDefaults.standard.bool(forKey: Key.syncedLyrics) }

    @MainActor
    static var theme: ThemeController.Theme {
        UserDefaults.standard.string(forKey: Key.theme).flatMap(ThemeController.Theme.init(rawValue:)) ?? .spotifyStyle
    }
}
