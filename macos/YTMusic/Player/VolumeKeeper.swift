import Foundation

/// Remembers the volume across launches.
///
/// YT Music saves its slider level in the `PREF` cookie, but WebKit writes
/// cookies to disk lazily, so a change made shortly before quitting can be
/// lost. We keep our own copy and re-apply it once the player is up.
@MainActor
final class VolumeKeeper {
    private static let key = "lastVolume"
    private let model: PlayerModel
    /// True from a page load until we've reconciled the page's volume with ours.
    private var restoring = true

    init(model: PlayerModel) {
        self.model = model
        model.observe { [weak self] old, new in
            self?.stateChanged(from: old, to: new)
        }
    }

    private var savedVolume: Int? {
        get { UserDefaults.standard.object(forKey: Self.key) as? Int }
        set { UserDefaults.standard.set(newValue, forKey: Self.key) }
    }

    private func stateChanged(from old: PlayerState, to new: PlayerState) {
        if new == PlayerState() {
            restoring = true // page (re)loaded
            return
        }
        // The player bar's slider is only reliable once a track is loaded.
        guard new.hasTrack else { return }

        if restoring {
            restoring = false
            if let saved = savedVolume, saved != new.volume {
                model.send(.setVolume(saved))
            } else {
                savedVolume = new.volume
            }
        } else if new.volume != old.volume {
            savedVolume = new.volume
        }
    }
}
