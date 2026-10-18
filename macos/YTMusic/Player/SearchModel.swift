import Foundation
import Observation

/// Search from the menu bar popover. Queries run in the page through the
/// bridge (`search` command → `searchResults` message); typing is debounced
/// and replies to anything but the latest request are dropped.
@MainActor
@Observable
final class SearchModel {
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }

    private(set) var results: [SearchResult] = []
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

    /// Plays a song/video, or opens an artist/album/playlist page. Returns
    /// true when the result opened a page (so the main window should show).
    @discardableResult
    func activate(_ result: SearchResult) -> Bool {
        if result.isPlayable, let videoId = result.videoId {
            player.send(.playItem(videoId: videoId, playlistId: result.playlistId))
            return false
        }
        if let browseId = result.browseId {
            player.send(.openItem(browseId: browseId, pageType: result.pageType))
            return true
        }
        return false
    }

    /// Shows YT Music's full results page for the current query.
    func showAllResults() {
        guard isActive else { return }
        player.send(.openSearch(trimmedQuery))
    }

    /// Called by the bridge with a `searchResults` reply.
    func receive(requestId: Int, results: [SearchResult], error: String?) {
        guard requestId == latestRequest else { return } // stale reply
        self.results = results
        isSearching = false
        message = results.isEmpty ? (error ?? "No results for “\(trimmedQuery)”") : nil
    }

    private func scheduleSearch() {
        pending?.cancel()
        let query = trimmedQuery
        guard !query.isEmpty else {
            latestRequest += 1 // invalidate in-flight replies
            results = []
            isSearching = false
            message = nil
            return
        }
        isSearching = true
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard let self, !Task.isCancelled else { return }
            latestRequest += 1
            player.send(.search(query: query, requestId: latestRequest))
        }
    }
}
