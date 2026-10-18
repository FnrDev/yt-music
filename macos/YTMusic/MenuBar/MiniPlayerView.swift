import SwiftUI

/// The popover shown from the menu bar icon.
struct MiniPlayerView: View {
    let model: PlayerModel
    var onShowWindow: () -> Void
    var onShowSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if model.state.hasTrack {
                NowPlayingSection(model: model)
            } else {
                EmptyStateSection(onShowWindow: onShowWindow)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
    }

    private var footer: some View {
        HStack {
            Button("Open YT Music", action: onShowWindow)
            Spacer()
            Button(action: onShowSettings) {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .help("Quit YT Music")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

private struct NowPlayingSection: View {
    let model: PlayerModel

    var body: some View {
        let state = model.state
        VStack(spacing: 12) {
            Artwork(url: state.artworkURL)
                .frame(width: 268, height: 268)

            VStack(spacing: 2) {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                Text([state.artist, state.album].filter { !$0.isEmpty }.joined(separator: " — "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            ProgressSection(model: model)
            TransportControls(model: model)
            VolumeSlider(model: model)
        }
    }
}

private struct Artwork: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(radius: 4, y: 2)
    }
}

private struct ProgressSection: View {
    let model: PlayerModel
    @State private var scrubPosition: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = max(model.state.duration, 1)
            let position = scrubPosition ?? model.position(at: context.date)
            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { min(position, duration) },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...duration
                ) { editing in
                    if !editing, let target = scrubPosition {
                        model.send(.seek(target))
                        // Hold the scrubbed value until the page reports the jump.
                        Task {
                            try? await Task.sleep(for: .milliseconds(600))
                            scrubPosition = nil
                        }
                    }
                }
                .controlSize(.mini)
                HStack {
                    Text(formatTime(position))
                    Spacer()
                    Text("-" + formatTime(max(model.state.duration - position, 0)))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TransportControls: View {
    let model: PlayerModel

    var body: some View {
        let state = model.state
        HStack(spacing: 22) {
            Button { model.send(.dislike) } label: {
                Image(systemName: state.likeStatus == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .help("Dislike")

            Button { model.send(.previous) } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            .help("Previous")

            Button { model.send(.playPause) } label: {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
            }
            .help(state.isPlaying ? "Pause" : "Play")

            Button { model.send(.next) } label: {
                Image(systemName: "forward.fill").font(.title2)
            }
            .help("Next")

            Button { model.send(.like) } label: {
                Image(systemName: state.likeStatus == .like ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .help("Like")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
    }
}

private struct VolumeSlider: View {
    let model: PlayerModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
            Slider(
                value: Binding(
                    get: { Double(model.state.volume) },
                    set: { model.send(.setVolume(Int($0))) }
                ),
                in: 0...100
            )
            .controlSize(.mini)
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct EmptyStateSection: View {
    var onShowWindow: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Nothing playing")
                .font(.headline)
            Text("Pick something in YT Music to control it from here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}
