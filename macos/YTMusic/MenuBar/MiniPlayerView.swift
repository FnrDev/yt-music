import SwiftUI

/// The popover shown from the menu bar icon: a compact player in the spirit of
/// Control Center's Now Playing module.
struct MiniPlayerView: View {
    let model: PlayerModel
    var onShowWindow: () -> Void
    var onShowSettings: () -> Void

    static let width: CGFloat = 300
    private static let padding: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            // Always lay out the full player so the popover keeps one height.
            // NSPopover grows upward when its content gets taller, which would
            // push it off the top of the screen.
            NowPlayingSection(model: model)
                .opacity(model.state.hasTrack ? 1 : 0)
                .allowsHitTesting(model.state.hasTrack)
                .overlay {
                    if !model.state.hasTrack { EmptyStateSection() }
                }
            Footer(onShowWindow: onShowWindow, onShowSettings: onShowSettings)
                .padding(.top, 10)
        }
        .padding(.horizontal, Self.padding)
        .padding(.top, Self.padding)
        .padding(.bottom, 8)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Backdrop(image: model.state.hasTrack ? model.artwork : nil))
        .environment(\.colorScheme, .dark)
        .focusEffectDisabled()
        .animation(.easeOut(duration: 0.25), value: model.state.trackKey)
    }
}

// MARK: - Sections

private struct NowPlayingSection: View {
    let model: PlayerModel

    var body: some View {
        let state = model.state
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtworkThumbnail(image: model.artwork, isAd: state.isAd)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title.isEmpty ? " " : state.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle(state))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                LikeButtons(model: model)
            }

            ProgressSection(model: model)
                .padding(.top, 12)

            TransportControls(model: model)
                .padding(.top, 4)

            VolumeSection(model: model)
                .padding(.top, 6)
        }
    }

    private func subtitle(_ state: PlayerState) -> String {
        let text = [state.artist, state.album].filter { !$0.isEmpty }.joined(separator: " · ")
        return text.isEmpty ? " " : text
    }
}

private struct EmptyStateSection: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text("Nothing playing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Play something in YT Music to control it here.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Footer: View {
    var onShowWindow: () -> Void
    var onShowSettings: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            IconButton(systemName: "macwindow", help: "Open YT Music", size: 24, action: onShowWindow)
            Spacer()
            IconButton(systemName: "gearshape", help: "Settings", size: 24, action: onShowSettings)
            IconButton(systemName: "power", help: "Quit YT Music", size: 24) { NSApp.terminate(nil) }
        }
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
    }
}

// MARK: - Artwork

private struct ArtworkThumbnail: View {
    let image: NSImage?
    let isAd: Bool

    private static let size: CGFloat = 56

    var body: some View {
        ZStack {
            if let image {
                // Square crop; at this size a centred crop of a 16:9 video frame reads fine.
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.size, height: Self.size)
            } else {
                Rectangle().fill(.white.opacity(0.08))
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            if isAd {
                Text("Ad")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.yellow, in: Capsule())
                    .foregroundStyle(.black)
                    .padding(3)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}

/// Blurred, darkened artwork behind everything, so the popover takes on the
/// colours of whatever is playing.
private struct Backdrop: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            Color(white: 0.08)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60, opaque: true)
                    .saturation(1.6)
                    .opacity(0.9)
                    .transition(.opacity)
            }
            LinearGradient(
                colors: [.black.opacity(0.35), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .animation(.easeInOut(duration: 0.4), value: image)
    }
}

// MARK: - Controls

private struct ProgressSection: View {
    let model: PlayerModel
    @State private var scrubPosition: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = max(model.state.duration, 1)
            let position = scrubPosition ?? model.position(at: context.date)

            VStack(spacing: 6) {
                ScrubBar(
                    value: min(position / duration, 1),
                    onChange: { scrubPosition = $0 * duration },
                    onCommit: { fraction in
                        let target = fraction * duration
                        scrubPosition = target
                        model.send(.seek(target))
                        // Hold the scrubbed value until the page reports the jump.
                        Task {
                            try? await Task.sleep(for: .milliseconds(700))
                            scrubPosition = nil
                        }
                    }
                )
                HStack {
                    Text(formatTime(position))
                    Spacer()
                    Text("-" + formatTime(max(model.state.duration - position, 0)))
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
        .disabled(model.state.isAd)
    }
}

private struct TransportControls: View {
    let model: PlayerModel

    var body: some View {
        let isPlaying = model.state.isPlaying
        HStack(spacing: 30) {
            Button { model.send(.previous) } label: {
                Image(systemName: "backward.fill").font(.system(size: 17))
            }
            .help("Previous")

            Button { model.send(.playPause) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34)
            }
            .help(isPlaying ? "Pause" : "Play")

            Button { model.send(.next) } label: {
                Image(systemName: "forward.fill").font(.system(size: 17))
            }
            .help("Next")
        }
        .buttonStyle(PlayerButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

private struct LikeButtons: View {
    let model: PlayerModel

    var body: some View {
        let status = model.state.likeStatus
        HStack(spacing: 2) {
            IconButton(
                systemName: status == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                help: "Dislike",
                isActive: status == .dislike
            ) { model.send(.dislike) }
            IconButton(
                systemName: status == .like ? "hand.thumbsup.fill" : "hand.thumbsup",
                help: "Like",
                isActive: status == .like
            ) { model.send(.like) }
        }
    }
}

private struct VolumeSection: View {
    let model: PlayerModel
    @State private var pendingVolume: Double?

    var body: some View {
        let volume = pendingVolume ?? Double(model.state.volume)
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
            ScrubBar(
                value: volume / 100,
                onChange: { fraction in
                    pendingVolume = fraction * 100
                    model.send(.setVolume(Int(fraction * 100)))
                },
                onCommit: { fraction in
                    model.send(.setVolume(Int(fraction * 100)))
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        pendingVolume = nil
                    }
                }
            )
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.5))
    }
}

// MARK: - Building blocks

/// Thin capsule slider in the style of the system Now Playing controls:
/// grows and shows a knob while hovered or dragged.
private struct ScrubBar: View {
    let value: Double
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let active = (isHovering || isDragging) && isEnabled
        let trackHeight: CGFloat = active ? 7 : 4

        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = min(max(value, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(.white.opacity(active ? 1 : 0.85))
                    .frame(width: max(trackHeight, width * fraction))
            }
            .frame(height: trackHeight)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        onChange(min(max(drag.location.x / width, 0), 1))
                    }
                    .onEnded { drag in
                        isDragging = false
                        onCommit(min(max(drag.location.x / width, 0), 1))
                    }
            )
        }
        .frame(height: 14)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: active)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct IconButton: View {
    let systemName: String
    let help: String
    var isActive = false
    var size: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .medium))
                .frame(width: size, height: size)
        }
        .buttonStyle(PlayerButtonStyle(restingOpacity: isActive ? 1 : 0.6, showsHoverBackground: true))
        .help(help)
    }
}

/// White glyphs that brighten on hover and shrink slightly when pressed.
private struct PlayerButtonStyle: ButtonStyle {
    var restingOpacity: Double = 0.9
    var showsHoverBackground = false

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(
            configuration: configuration,
            restingOpacity: restingOpacity,
            showsHoverBackground: showsHoverBackground
        )
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let restingOpacity: Double
        let showsHoverBackground: Bool
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .opacity(isHovering || configuration.isPressed ? 1 : restingOpacity)
                .background {
                    if showsHoverBackground {
                        Circle().fill(.white.opacity(isHovering ? 0.1 : 0))
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.88 : 1)
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.spring(duration: 0.2), value: configuration.isPressed)
        }
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
