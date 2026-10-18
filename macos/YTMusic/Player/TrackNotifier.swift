import AppKit
import UserNotifications

/// Posts a notification when the track changes while the app is in the background.
@MainActor
final class TrackNotifier {
    private let artworkLoader: ArtworkLoader
    private let center = UNUserNotificationCenter.current()
    private var authorizationRequested = false

    init(model: PlayerModel, artworkLoader: ArtworkLoader) {
        self.artworkLoader = artworkLoader
        model.observe { [weak self] old, new in
            guard new.hasTrack, new.isPlaying, !new.isAd, old.trackKey != new.trackKey || !old.hasTrack else { return }
            self?.notify(new)
        }
    }

    private func notify(_ state: PlayerState) {
        guard AppSettings.notifyOnTrackChange, !NSApp.isActive else { return }

        Task {
            guard await ensureAuthorized() else { return }

            let content = UNMutableNotificationContent()
            content.title = state.title
            content.body = [state.artist, state.album].filter { !$0.isEmpty }.joined(separator: " — ")
            if let url = state.artworkURL,
               let file = await artworkLoader.fileURL(for: url),
               let attachment = try? UNNotificationAttachment(identifier: "artwork", url: file) {
                content.attachments = [attachment]
            }

            // Reuse one identifier so the previous track's notification is replaced.
            let request = UNNotificationRequest(identifier: "now-playing", content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    private func ensureAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined where !authorizationRequested:
            authorizationRequested = true
            return (try? await center.requestAuthorization(options: [.alert])) ?? false
        default:
            return false
        }
    }
}
