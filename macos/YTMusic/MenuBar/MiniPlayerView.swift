import SwiftUI

/// The popover shown from the menu bar icon: search on top, a panel (search
/// results, or Library / Up Next / Lyrics), then a compact player in the
/// spirit of Control Center's Now Playing module.
struct MiniPlayerView: View {
    let model: PlayerModel
    let panels: PopoverPanels
    var onShowWindow: () -> Void
    var onShowSettings: () -> Void

    static let width: CGFloat = 340
    /// Constant, so the popover never resizes (NSPopover grows upward and
    /// would push itself off the top of the screen).
    static let panelHeight: CGFloat = 300
    private static let padding: CGFloat = 14

    @AppStorage("popoverPanel") private var panel: PopoverPanel = .library

    var body: some View {
        let search = panels.search
        let actions = ResultActions(search: search, onShowWindow: onShowWindow)
        VStack(spacing: 0) {
            SearchField(search: search) {
                if let first = search.results.first { actions.activate(first) }
            }
            .padding(.bottom, 10)

            Group {
                if search.isActive {
                    VStack(spacing: 8) {
                        FilterBar(search: search)
                        SearchResultsView(search: search, actions: actions) {
                            search.showAllResults()
                            onShowWindow()
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        PanelPicker(selection: $panel)
                        switch panel {
                        case .library: LibraryPanel(library: panels.library, actions: actions)
                        case .upNext: QueuePanel(queue: panels.queue)
                        case .lyrics: LyricsPanel(lyrics: panels.lyrics, player: model)
                        }
                    }
                }
            }
            .frame(height: Self.panelHeight, alignment: .top)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 10)

            // Always lay out the full player so the popover keeps one height.
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

enum PopoverPanel: String, CaseIterable, Identifiable {
    case library, upNext, lyrics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .library: "Library"
        case .upNext: "Up Next"
        case .lyrics: "Lyrics"
        }
    }
}

/// What a result row can do, shared by search results and the library.
@MainActor
struct ResultActions {
    let search: SearchModel
    let onShowWindow: () -> Void

    func activate(_ result: SearchResult) {
        if search.activate(result) { onShowWindow() }
    }

    func play(_ result: SearchResult) { search.play(result) }

    func open(_ result: SearchResult) {
        if search.open(result) { onShowWindow() }
    }

    func queue(_ result: SearchResult, playNext: Bool) {
        search.queue(result, playNext: playNext)
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
        let state = model.state
        HStack(spacing: 22) {
            ToggleButton(
                systemName: "shuffle",
                isOn: state.shuffle,
                help: state.shuffle ? "Shuffle on" : "Shuffle off"
            ) { model.send(.toggleShuffle) }

            Button { model.send(.previous) } label: {
                Image(systemName: "backward.fill").font(.system(size: 17))
            }
            .help("Previous")

            Button { model.send(.playPause) } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34)
            }
            .help(state.isPlaying ? "Pause" : "Play")

            Button { model.send(.next) } label: {
                Image(systemName: "forward.fill").font(.system(size: 17))
            }
            .help("Next")

            ToggleButton(
                systemName: state.repeatMode == .one ? "repeat.1" : "repeat",
                isOn: state.repeatMode != .none,
                help: repeatHelp(state.repeatMode)
            ) { model.send(.cycleRepeat) }
        }
        .buttonStyle(PlayerButtonStyle())
        .frame(maxWidth: .infinity)
    }

    private func repeatHelp(_ mode: PlayerState.RepeatMode) -> String {
        switch mode {
        case .none: "Repeat off"
        case .all: "Repeat all"
        case .one: "Repeat one"
        }
    }
}

/// Shuffle / repeat: green with a dot underneath when on, as in Spotify.
private struct ToggleButton: View {
    let systemName: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                Circle()
                    .frame(width: 4, height: 4)
                    .opacity(isOn ? 1 : 0)
            }
            .foregroundStyle(isOn ? Color.spotifyGreen : Color.white.opacity(0.7))
            .frame(width: 24, height: 28)
        }
        .help(help)
    }
}

extension Color {
    /// Spotify's bright accent, matching the Spotify-style theme.
    static let spotifyGreen = Color(red: 0x1E / 255, green: 0xD7 / 255, blue: 0x60 / 255)
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

// MARK: - Search

private struct SearchField: View {
    @Bindable var search: SearchModel
    var onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(focused ? 0.9 : 0.55))
            TextField("Search songs, artists, albums", text: $search.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(onSubmit)
                .onExitCommand { search.clear() }
            if !search.query.isEmpty {
                Button { search.clear() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
                .help("Clear")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Capsule().fill(.white.opacity(focused ? 0.14 : 0.08)))
        .overlay(Capsule().strokeBorder(.white.opacity(focused ? 0.85 : 0), lineWidth: 1.5))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// YT Music's own filter chips for the query, plus "All".
private struct FilterBar: View {
    let search: SearchModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                Pill(title: "All", isSelected: search.filter == nil) { search.select(filter: nil) }
                ForEach(search.filters) { filter in
                    Pill(title: filter.title, isSelected: search.filter == filter.params) {
                        search.select(filter: filter)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: 28)
        .opacity(search.filters.isEmpty ? 0 : 1)
    }
}

private struct PanelPicker: View {
    @Binding var selection: PopoverPanel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PopoverPanel.allCases) { panel in
                Pill(title: panel.title, isSelected: selection == panel) { selection = panel }
            }
            Spacer()
        }
        .frame(height: 28)
    }
}

/// Spotify-style chip: tinted, or white with black text when selected.
private struct Pill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(isSelected ? .white : .white.opacity(isHovering ? 0.16 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct SearchResultsView: View {
    let search: SearchModel
    let actions: ResultActions
    var onShowAll: () -> Void

    var body: some View {
        if search.results.isEmpty {
            PanelMessage(isLoading: search.isSearching, message: search.message)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(search.results.enumerated()), id: \.element.id) { index, result in
                        if search.filter == nil, index == 0 {
                            SectionHeader(title: "Top result")
                        } else if search.filter == nil, index == 1 {
                            SectionHeader(title: "Results").padding(.top, 8)
                        }
                        ResultRow(result: result, actions: actions)
                    }
                    Button(action: onShowAll) {
                        Text("Show all results in YT Music")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
            }
            .scrollIndicators(.never)
            .opacity(search.isSearching ? 0.6 : 1) // refreshing for a newer query
        }
    }
}

// MARK: - Panels

private struct LibraryPanel: View {
    let library: LibraryModel
    let actions: ResultActions

    var body: some View {
        if library.recent.isEmpty && library.playlists.isEmpty {
            PanelMessage(
                isLoading: library.isLoading,
                message: "Nothing here yet. Play something, or sign in to YouTube Music."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !library.recent.isEmpty {
                        SectionHeader(title: "Recently played")
                        ForEach(library.recent) { ResultRow(result: $0, actions: actions) }
                    }
                    if !library.playlists.isEmpty {
                        SectionHeader(title: "Your playlists").padding(.top, 8)
                        ForEach(library.playlists) { ResultRow(result: $0, actions: actions) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct QueuePanel: View {
    let queue: QueueModel

    var body: some View {
        // Show the current track and what follows; earlier tracks are history.
        let current = queue.items.firstIndex(where: \.isCurrent) ?? 0
        let upcoming = Array(queue.items.dropFirst(current))
        Group {
            if upcoming.isEmpty {
                PanelMessage(isLoading: !queue.hasLoaded, message: "Your queue is empty.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { offset, item in
                            if offset == 0 {
                                SectionHeader(title: item.isCurrent ? "Now playing" : "Next")
                            } else if offset == 1 {
                                SectionHeader(title: "Next").padding(.top, 8)
                            }
                            QueueRow(item: item) { queue.play(item) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear { queue.isVisible = true }
        .onDisappear { queue.isVisible = false }
    }
}

private struct LyricsPanel: View {
    let lyrics: LyricsModel
    let player: PlayerModel

    var body: some View {
        Group {
            switch lyrics.content {
            case .loading:
                PanelMessage(isLoading: true, message: nil)
            case .unavailable(let message):
                PanelMessage(isLoading: false, message: message)
            case .instrumental:
                PanelMessage(isLoading: false, message: "♪ Instrumental")
            case .synced(let lines, let source):
                SyncedLyricsView(lines: lines, source: source, player: player)
            case .plain(let text, let source):
                PlainLyricsView(text: text, source: source)
            }
        }
        .onAppear { lyrics.isVisible = true }
        .onDisappear { lyrics.isVisible = false }
    }
}

/// Time-synced lyrics: the current line is highlighted and kept centred;
/// click a line to jump there.
private struct SyncedLyricsView: View {
    let lines: [LyricLine]
    let source: String
    let player: PlayerModel

    /// Highlight slightly early, so a line lights up as it starts being sung.
    private static let lead: Double = 0.15

    var body: some View {
        let rtl = isRightToLeft(lines.map(\.text).joined())
        let alignment: HorizontalAlignment = rtl ? .trailing : .leading
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let current = LRCParser.currentIndex(in: lines, at: player.position(at: context.date) + Self.lead)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: alignment, spacing: 10) {
                        ForEach(lines) { line in
                            Button { player.send(.seek(line.time)) } label: {
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white.opacity(opacity(of: line.id, current: current)))
                                    .multilineTextAlignment(rtl ? .trailing : .leading)
                                    .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(line.id)
                            .animation(.easeOut(duration: 0.25), value: current)
                        }
                        Text("Lyrics from \(source)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 8)
                    // Room above and below so the first and last lines can be centred.
                    .padding(.vertical, MiniPlayerView.panelHeight / 2 - 40)
                }
                .scrollIndicators(.never)
                .onAppear {
                    if let current { proxy.scrollTo(current, anchor: .center) }
                }
                .onChange(of: current) { _, line in
                    guard let line else { return }
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(line, anchor: .center) }
                }
            }
        }
    }

    /// Current line bright, sung lines dimmed, upcoming lines fainter.
    private func opacity(of id: Int, current: Int?) -> Double {
        guard let current else { return 0.35 }
        if id == current { return 1 }
        return id < current ? 0.55 : 0.35
    }
}

private struct PlainLyricsView: View {
    let text: String
    let source: String?

    var body: some View {
        // Right-to-left scripts (Arabic, Hebrew…) read from the right.
        let rtl = isRightToLeft(text)
        ScrollView {
            VStack(alignment: rtl ? .trailing : .leading, spacing: 12) {
                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .lineSpacing(5)
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(rtl ? .trailing : .leading)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
                if let source {
                    Text(source)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never)
    }
}

/// True when most letters are from a right-to-left script.
private func isRightToLeft(_ text: String) -> Bool {
    var rtl = 0, ltr = 0
    for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: rtl += 1
        default: ltr += 1
        }
    }
    return rtl > ltr
}

private struct PanelMessage: View {
    let isLoading: Bool
    let message: String?

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }
}

// MARK: - Rows

private struct ResultRow: View {
    let result: SearchResult
    let actions: ResultActions
    @State private var isHovering = false

    var body: some View {
        Button { actions.activate(result) } label: {
            HStack(spacing: 10) {
                Thumbnail(url: result.thumbnailURL, round: result.kind == .artist)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                    Text(result.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                if isHovering && (result.canQueue || result.canOpen) {
                    Menu { menuItems } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More")
                }
                Image(systemName: result.canPlay ? "play.fill" : "chevron.right")
                    .font(.system(size: result.canPlay ? 11 : 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(isHovering ? 0.9 : 0.4))
                    .frame(width: 14)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .background(RowHighlight(isOn: isHovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu { menuItems }
    }

    @ViewBuilder private var menuItems: some View {
        if result.canPlay {
            Button("Play") { actions.play(result) }
        }
        if result.canQueue {
            Button("Play Next") { actions.queue(result, playNext: true) }
            Button("Add to Queue") { actions.queue(result, playNext: false) }
        }
        if result.canOpen {
            Divider()
            Button(openTitle) { actions.open(result) }
        }
    }

    private var openTitle: String {
        switch result.kind {
        case .artist: "Go to Artist"
        case .album: "Go to Album"
        case .playlist: "Go to Playlist"
        default: "Open in YT Music"
        }
    }
}

private struct QueueRow: View {
    let item: QueueItem
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Thumbnail(url: item.thumbnailURL, round: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundStyle(item.isCurrent ? Color.spotifyGreen : .white)
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.duration)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .background(RowHighlight(isOn: isHovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.isCurrent ? "Now playing" : "Play")
    }
}

private struct RowHighlight: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.white.opacity(isOn ? 0.08 : 0))
    }
}

private struct Thumbnail: View {
    let url: URL?
    let round: Bool

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.08))
            }
        }
        .frame(width: 40, height: 40)
        // Artists get round photos, everything else rounded squares.
        .clipShape(round
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)))
    }
}
