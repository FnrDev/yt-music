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
@MainActor
@Observable
final class LyricsModel {
    enum Content: Equatable {
        case loading
        case lyrics(text: String, source: String?)
        case unavailable(String)
    }

    private(set) var content: Content = .loading
    /// Set by the view while lyrics are visible.
    var isVisible = false {
        didSet { if isVisible && !oldValue { refreshIfNeeded() } }
    }

    @ObservationIgnored private let player: PlayerModel
    @ObservationIgnored private var requests = RequestTracker()
    @ObservationIgnored private var loadedTrack: String?

    init(player: PlayerModel) {
        self.player = player
        player.observe { [weak self] old, new in
            guard let self, isVisible, old.trackKey != new.trackKey else { return }
            refreshIfNeeded()
        }
    }

    func refreshIfNeeded() {
        let track = player.state.trackKey
        guard player.state.hasTrack else {
            content = .unavailable("Nothing is playing")
            loadedTrack = nil
            return
        }
        guard track != loadedTrack else { return }
        loadedTrack = track
        content = .loading
        player.send(.lyrics(requestId: requests.next()))
    }

    func receive(requestId: Int, text: String?, source: String?, error: String?) {
        guard requests.isLatest(requestId) else { return }
        if let text, !text.isEmpty {
            content = .lyrics(text: text, source: source)
        } else {
            content = .unavailable(error ?? "Lyrics aren't available for this song")
        }
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
