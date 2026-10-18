import Foundation
import Observation

/// Search from the menu bar popover. Queries run in the page through the
/// bridge (`search` command → `searchResults` message); typing is debounced
/// and replies to anything but the latest request are dropped.
@MainActor
@Observable
final class SearchModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            filter = nil // a new query starts unfiltered
            scheduleSearch()
        }
    }

    private(set) var results: [SearchResult] = []
    /// YT Music's filter chips for the current query (Songs, Artists, …).
    private(set) var filters: [SearchFilter] = []
    /// The selected filter's params, or nil for all results.
    private(set) var filter: String?
    private(set) var isSearching = false
    private(set) var message: String?

    @ObservationIgnored private let player: PlayerModel
    @ObservationIgnored private var latestRequest = 0
    @ObservationIgnored private var pending: Task<Void, Never>?

    private static let debounce: Duration = .milliseconds(250)

    init(player: PlayerModel) {
        self.player = player
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isActive: Bool { !trimmedQuery.isEmpty }

    func clear() {
        query = ""
    }

    func select(filter: SearchFilter?) {
        let params = filter?.isSelected == true ? nil : filter?.params // tapping the active chip clears it
        guard params != self.filter else { return }
        self.filter = params
        scheduleSearch(immediately: true)
    }

    /// Default action for a result: play what can be played (tracks, albums,
    /// playlists), open what can't (artists). Returns true when it opened a
    /// page, so the main window should be shown.
    @discardableResult
    func activate(_ result: SearchResult) -> Bool {
        if result.canPlay {
            play(result)
            return false
        }
        return open(result)
    }

    func play(_ result: SearchResult) {
        if result.isTrack, let videoId = result.videoId {
            player.send(.playItem(videoId: videoId, playlistId: result.playlistId))
        } else if let playlistId = result.playlistId {
            player.send(.playPlaylist(playlistId))
        }
    }

    /// Opens an artist/album/playlist page; returns false if there is none.
    @discardableResult
    func open(_ result: SearchResult) -> Bool {
        guard let browseId = result.browseId else { return false }
        player.send(.openItem(browseId: browseId, pageType: result.pageType))
        return true
    }

    func queue(_ result: SearchResult, playNext: Bool) {
        guard result.canQueue else { return }
        player.send(.queueResult(id: result.id, playNext: playNext))
    }

    /// Shows YT Music's full results page for the current query.
    func showAllResults() {
        guard isActive else { return }
        player.send(.openSearch(trimmedQuery))
    }

    /// Called by the bridge with a `searchResults` reply.
    func receive(requestId: Int, results: [SearchResult], filters: [SearchFilter], error: String?) {
        guard requestId == latestRequest else { return } // stale reply
        self.results = results
        if !filters.isEmpty { self.filters = filters }
        isSearching = false
        message = results.isEmpty ? (error ?? "No results for “\(trimmedQuery)”") : nil
    }

    private func scheduleSearch(immediately: Bool = false) {
        pending?.cancel()
        let query = trimmedQuery
        guard !query.isEmpty else {
            latestRequest += 1 // invalidate in-flight replies
            results = []
            filters = []
            isSearching = false
            message = nil
            return
        }
        if filter == nil && !immediately { filters = [] }
        isSearching = true
        let params = filter
        pending = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: Self.debounce) }
            guard let self, !Task.isCancelled else { return }
            latestRequest += 1
            player.send(.search(query: query, params: params, requestId: latestRequest))
        }
    }
}
