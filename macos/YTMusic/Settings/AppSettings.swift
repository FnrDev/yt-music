import Foundation

/// UserDefaults-backed preferences. SwiftUI reads them with `@AppStorage(Key.x)`;
/// AppKit code reads the static accessors and listens for `didChange`.
enum AppSettings {
    enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showTitleInMenuBar = "showTitleInMenuBar"
        static let notifyOnTrackChange = "notifyOnTrackChange"
        static let keepPlayingWhenClosed = "keepPlayingWhenClosed"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.showMenuBarIcon: true,
            Key.showTitleInMenuBar: false,
            Key.notifyOnTrackChange: true,
            Key.keepPlayingWhenClosed: true,
        ])
    }

    static var showMenuBarIcon: Bool { UserDefaults.standard.bool(forKey: Key.showMenuBarIcon) }
    static var showTitleInMenuBar: Bool { UserDefaults.standard.bool(forKey: Key.showTitleInMenuBar) }
    static var notifyOnTrackChange: Bool { UserDefaults.standard.bool(forKey: Key.notifyOnTrackChange) }
    static var keepPlayingWhenClosed: Bool { UserDefaults.standard.bool(forKey: Key.keepPlayingWhenClosed) }
}
