import AppKit
import MediaPlayer

/// Publishes the current track to Control Center / Now Playing and routes
/// media keys, AirPods and Touch Bar controls back into the player.
@MainActor
final class NowPlayingController {
    private let model: PlayerModel
    private let artworkLoader: ArtworkLoader
    private let center = MPNowPlayingInfoCenter.default()
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?

    init(model: PlayerModel, artworkLoader: ArtworkLoader) {
        self.model = model
        self.artworkLoader = artworkLoader
        Self.registerRemoteCommands(send: { [weak model] command in
            Task { @MainActor in model?.send(command) }
        })
        model.observe { [weak self] old, new in
            self?.stateChanged(from: old, to: new)
        }
    }

    private func stateChanged(from old: PlayerState, to new: PlayerState) {
        guard new.hasTrack else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }

        // Position is extrapolated by the system from elapsed time + rate, so
        // only republish when something other than the heartbeat changed.
        let drift = abs(new.position - (old.position + 1))
        let significant = old.trackKey != new.trackKey
            || old.isPlaying != new.isPlaying
            || old.title != new.title
            || old.artworkURL != new.artworkURL
            || old.duration != new.duration
            || drift > 2
        guard significant || center.nowPlayingInfo == nil else { return }

        publish(new)
        if new.artworkURL != artworkURL {
            loadArtwork(for: new)
        }
    }

    private func publish(_ state: PlayerState) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.title,
            MPMediaItemPropertyArtist: state.artist,
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.position,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if !state.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = state.album
        }
        if let artwork, state.artworkURL == artworkURL {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        center.nowPlayingInfo = info
        center.playbackState = state.isPlaying ? .playing : .paused
    }

    private func loadArtwork(for state: PlayerState) {
        artworkURL = state.artworkURL
        artwork = nil
        guard let url = state.artworkURL else { return }
        Task {
            guard let image = await artworkLoader.image(for: url),
                  url == artworkURL else { return }
            artwork = Self.makeArtwork(image)
            publish(model.state)
        }
    }

    // MARK: - Nonisolated helpers
    //
    // MediaPlayer invokes these closures off the main thread. Building them in
    // a nonisolated context keeps Swift from inferring main-actor isolation
    // (which would trap at runtime).

    private nonisolated static func makeArtwork(_ image: NSImage) -> MPMediaItemArtwork {
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private nonisolated static func registerRemoteCommands(send: @escaping @Sendable (PlayerCommand) -> Void) {
        let commands = MPRemoteCommandCenter.shared()

        func on(_ command: MPRemoteCommand, _ action: PlayerCommand) {
            command.isEnabled = true
            command.addTarget { _ in
                send(action)
                return .success
            }
        }

        on(commands.togglePlayPauseCommand, .playPause)
        on(commands.playCommand, .play)
        on(commands.pauseCommand, .pause)
        on(commands.nextTrackCommand, .next)
        on(commands.previousTrackCommand, .previous)
        on(commands.likeCommand, .like)
        on(commands.dislikeCommand, .dislike)

        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            send(.seek(event.positionTime))
            return .success
        }
    }
}
