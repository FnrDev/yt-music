import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.Key.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(AppSettings.Key.showTitleInMenuBar) private var showTitleInMenuBar = false
    @AppStorage(AppSettings.Key.notifyOnTrackChange) private var notifyOnTrackChange = true
    @AppStorage(AppSettings.Key.keepPlayingWhenClosed) private var keepPlayingWhenClosed = true
    @AppStorage(AppSettings.Key.theme) private var theme = ThemeController.Theme.spotifyStyle.rawValue
    @AppStorage(AppSettings.Key.syncedLyrics) private var syncedLyrics = true

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemeController.Theme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }
            }
            Section("Menu Bar") {
                Toggle("Show player controls in the menu bar", isOn: $showMenuBarIcon)
                Toggle("Show current track title next to the icon", isOn: $showTitleInMenuBar)
                    .disabled(!showMenuBarIcon)
            }
            Section {
                Toggle("Synced lyrics from LRCLIB", isOn: $syncedLyrics)
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Looks up time-synced lyrics on lrclib.net, which receives the song's title, artist, album and length. When it has none, YouTube Music's own lyrics are shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Playback") {
                Toggle("Keep playing when the window is closed", isOn: $keepPlayingWhenClosed)
                Toggle("Notify when the track changes", isOn: $notifyOnTrackChange)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
