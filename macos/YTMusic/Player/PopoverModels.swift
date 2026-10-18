import Foundation
import Observation

/// Request/reply bookkeeping shared by the popover's models: each request gets
/// a fresh id, and only the reply to the latest one is accepted.
@MainActor
struct RequestTracker {
    private(set) var latest = 0
    mutating func next() -> Int { latest += 1; return latest }
    func isLatest(_ id: Int) -> Bool { id == latest }
}

/// "Recently played" and "Your playlists", shown when the search is empty.
@MainActor
@Observable
final class LibraryModel {
    private(set) var recent: [SearchResult] = []
    private(set) var playlists: [SearchResult] = []
    private(set) var isLoading = false

    @ObservationIgnored private let player: PlayerModel
    @ObservationIgnored private var requests = RequestTracker()
    @ObservationIgnored private var loadedAt: Date?

    private static let maxAge: TimeInterval = 120

    init(player: PlayerModel) {
        self.player = player
    }

    func refreshIfStale() {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < Self.maxAge { return }
        refresh()
    }

    func refresh() {
        isLoading = recent.isEmpty && playlists.isEmpty
        player.send(.library(requestId: requests.next()))
    }

    func receive(requestId: Int, recent: [SearchResult], playlists: [SearchResult]) {
        guard requests.isLatest(requestId) else { return }
        self.recent = recent
        self.playlists = playlists
        isLoading = false
        loadedAt = Date()
    }
}

/// The play queue ("Up next"), refreshed while it's on screen.
@MainActor
@Observable
final class QueueModel {
    private(set) var items: [QueueItem] = []
    private(set) var hasLoaded = false
    /// Set by the view while the queue is visible.
    var isVisible = false {
        didSet { if isVisible && !oldValue { refresh() } }
    }

    @ObservationIgnored private let player: PlayerModel
    @ObservationIgnored private var requests = RequestTracker()

    init(player: PlayerModel) {
        self.player = player
        player.observe { [weak self] old, new in
            guard let self, isVisible, old.trackKey != new.trackKey || old.shuffle != new.shuffle else { return }
            // Give the page a moment to update its queue after a track change.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                self.refresh()
            }
        }
    }

    func refresh() {
        player.send(.queue(requestId: requests.next()))
    }

    func play(_ item: QueueItem) {
        player.send(.playQueueItem(index: item.index, videoId: item.videoId))
    }

    func receive(requestId: Int, items: [QueueItem]) {
        guard requests.isLatest(requestId) else { return }
        self.items = items
        hasLoaded = true
    }
}

/// Lyrics for the current track, fetched while the lyrics view is on screen.
/// Synced lyrics come from LRCLIB when it has the song (and the setting is on);
/// otherwise YouTube Music's own plain lyrics, through the bridge.
@MainActor
@Observable
final class LyricsModel {
    enum Content: Equatable {
        case loading
        case synced(lines: [LyricLine], source: String)
        case plain(text: String, source: String?)
        case instrumental
        case unavailable(String)
    }

    private(set) var content: Content = .loading
    /// Set by the view while lyrics are visible.
    var isVisible = false {
        didSet { if isVisible && !oldValue { refreshIfNeeded() } }
    }

    @ObservationIgnored private let player: PlayerModel
    @ObservationIgnored private let lrclib = LRCLibClient()
    @ObservationIgnored private var requests = RequestTracker()
    @ObservationIgnored private var loadedTrack: String?
    @ObservationIgnored private var lookup: Task<Void, Never>?
    /// Recent results by track, so returning to a song doesn't fetch again.
    @ObservationIgnored private var cache: [String: Content] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []

    private static let cacheLimit = 50

    init(player: PlayerModel) {
        self.player = player
        player.observe { [weak self] old, new in
            guard let self, isVisible else { return }
            // LRCLIB matches on duration, which arrives shortly after the track.
            if old.trackKey != new.trackKey || (old.duration == 0 && new.duration > 0) {
                refreshIfNeeded()
            }
        }
    }

    func refreshIfNeeded() {
        let state = player.state
        guard state.hasTrack, !state.isAd else {
            lookup?.cancel()
            loadedTrack = nil
            content = state.isAd ? .unavailable("Lyrics will show after the ad") : .unavailable("Nothing is playing")
            return
        }
        let track = state.trackKey
        guard track != loadedTrack else { return }

        if let cached = cache[track] {
            loadedTrack = track
            content = cached
            return
        }
        content = .loading
        guard state.duration > 0 else { return } // wait for the duration; see init
        loadedTrack = track
        lookup?.cancel()

        guard AppSettings.syncedLyrics else {
            requestPlainLyrics()
            return
        }
        lookup = Task { [weak self, lrclib] in
            let match = await lrclib.syncedLyrics(
                title: state.title, artist: state.artist, album: state.album, duration: state.duration)
            guard let self, !Task.isCancelled, loadedTrack == track else { return }
            if let match {
                finish(match.isInstrumental ? .instrumental : .synced(lines: match.lines, source: "LRCLIB"), for: track)
            } else {
                requestPlainLyrics()
            }
        }
    }

    /// Called by the bridge with YouTube Music's plain lyrics.
    func receive(requestId: Int, text: String?, source: String?, error: String?) {
        guard requests.isLatest(requestId), let track = loadedTrack else { return }
        if let text, !text.isEmpty {
            finish(.plain(text: text, source: source), for: track)
        } else {
            // Not cached: a failed request (e.g. while loading) is worth retrying.
            content = .unavailable(error ?? "Lyrics aren't available for this song")
        }
    }

    private func requestPlainLyrics() {
        player.send(.lyrics(requestId: requests.next()))
    }

    private func finish(_ result: Content, for track: String) {
        cache[track] = result
        cacheOrder.removeAll { $0 == track }
        cacheOrder.append(track)
        if cacheOrder.count > Self.cacheLimit { cache[cacheOrder.removeFirst()] = nil }
        if loadedTrack == track { content = result }
    }
}

/// Everything the menu bar popover shows besides the player itself.
@MainActor
struct PopoverPanels {
    let search: SearchModel
    let library: LibraryModel
    let queue: QueueModel
    let lyrics: LyricsModel
}
