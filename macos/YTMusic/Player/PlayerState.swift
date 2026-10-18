import Foundation

/// Snapshot of the web player, as reported by `ytm-bridge.js`.
/// Field names mirror shared/PROTOCOL.md.
struct PlayerState: Equatable, Sendable, Decodable {
    enum LikeStatus: String, Sendable, Decodable {
        case like, dislike, indifferent
    }

    var hasTrack = false
    var isAd = false
    var videoId: String?
    var title = ""
    var artist = ""
    var album = ""
    var artworkURL: URL?
    var isPlaying = false
    var position: Double = 0
    var duration: Double = 0
    var likeStatus: LikeStatus = .indifferent
    var volume = 100
    var shuffle = false
    var repeatMode: RepeatMode = .none

    enum RepeatMode: String, Sendable, Decodable {
        case none, all, one
    }

    /// Identifies the track for change detection; falls back to metadata when
    /// the player hasn't exposed a video id yet.
    var trackKey: String {
        videoId ?? "\(title)\u{1F}\(artist)"
    }
}

enum PlayerCommand: Sendable {
    case playPause, play, pause, next, previous
    case seek(Double)
    case setVolume(Int)
    case like, dislike
    case focusSearch
    case search(query: String, params: String?, requestId: Int)
    case library(requestId: Int)
    case queue(requestId: Int)
    case lyrics(requestId: Int)
    case toggleShuffle, cycleRepeat
    case queueResult(id: String, playNext: Bool)
    case playQueueItem(index: Int, videoId: String)
    case playPlaylist(String)
    case playItem(videoId: String, playlistId: String?)
    case openItem(browseId: String, pageType: String?)
    case openSearch(String)

    /// JS evaluated in the page to run this command.
    var javaScript: String {
        let (name, arg): (String, String) = switch self {
        case .playPause: ("playPause", "undefined")
        case .play: ("play", "undefined")
        case .pause: ("pause", "undefined")
        case .next: ("next", "undefined")
        case .previous: ("previous", "undefined")
        case .seek(let seconds): ("seek", String(seconds))
        case .setVolume(let volume): ("setVolume", String(volume))
        case .like: ("like", "undefined")
        case .dislike: ("dislike", "undefined")
        case .focusSearch: ("focusSearch", "undefined")
        case .search(let query, let params, let requestId):
            ("search", Self.json(["query": query, "params": params.map { $0 as Any } ?? NSNull(), "requestId": requestId]))
        case .library(let requestId): ("library", Self.json(["requestId": requestId]))
        case .queue(let requestId): ("queue", Self.json(["requestId": requestId]))
        case .lyrics(let requestId): ("lyrics", Self.json(["requestId": requestId]))
        case .toggleShuffle: ("toggleShuffle", "undefined")
        case .cycleRepeat: ("cycleRepeat", "undefined")
        case .queueResult(let id, let playNext):
            ("queueResult", Self.json(["id": id, "position": playNext ? "next" : "end"]))
        case .playQueueItem(let index, let videoId):
            ("playQueueItem", Self.json(["index": index, "videoId": videoId]))
        case .playPlaylist(let playlistId):
            ("playPlaylist", Self.json(["playlistId": playlistId]))
        case .playItem(let videoId, let playlistId):
            ("playItem", Self.json(["videoId": videoId, "playlistId": playlistId.map { $0 as Any } ?? NSNull()]))
        case .openItem(let browseId, let pageType):
            ("openItem", Self.json(["browseId": browseId, "pageType": pageType.map { $0 as Any } ?? NSNull()]))
        case .openSearch(let query):
            ("openSearch", Self.json(query))
        }
        return "window.__ytmBridge && window.__ytmBridge.command('\(name)', \(arg));"
    }

    /// Encodes a command argument as a JS literal (JSON is valid JS). Missing
    /// values must be passed as NSNull; JSONSerialization rejects optionals.
    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return "undefined" }
        return text
    }
}

/// One search result, as reported by the bridge (see shared/PROTOCOL.md).
struct SearchResult: Identifiable, Equatable, Sendable, Decodable {
    enum Kind: String, Sendable, Decodable {
        case artist, album, playlist, song, video, podcast, episode, page
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
    let videoId: String?
    let playlistId: String?
    let browseId: String?
    let pageType: String?
    /// YT Music offers "Play next" / "Add to queue" for this result.
    let canQueue: Bool

    /// Songs, videos and episodes play directly.
    var isTrack: Bool { videoId != nil && browseId == nil }
    /// Tracks, and albums/playlists that can be played as a whole.
    var canPlay: Bool { isTrack || (playlistId != nil && kind != .artist) }
    /// Artists, albums and playlists have a page to open.
    var canOpen: Bool { browseId != nil }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle, thumbnailURL, videoId, playlistId, browseId, pageType, canQueue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .page // tolerate new kinds
        title = try c.decode(String.self, forKey: .title)
        subtitle = (try? c.decode(String.self, forKey: .subtitle)) ?? ""
        thumbnailURL = try? c.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        videoId = try? c.decodeIfPresent(String.self, forKey: .videoId)
        playlistId = try? c.decodeIfPresent(String.self, forKey: .playlistId)
        browseId = try? c.decodeIfPresent(String.self, forKey: .browseId)
        pageType = try? c.decodeIfPresent(String.self, forKey: .pageType)
        canQueue = (try? c.decodeIfPresent(Bool.self, forKey: .canQueue)) ?? false
    }
}

/// A YT Music search filter chip (Songs, Artists, Albums…).
struct SearchFilter: Identifiable, Equatable, Sendable, Decodable {
    let title: String
    let params: String
    let isSelected: Bool
    var id: String { params }
}

/// One entry in the play queue ("Up next").
struct QueueItem: Identifiable, Equatable, Sendable, Decodable {
    let index: Int
    let videoId: String
    let title: String
    let subtitle: String
    let duration: String
    let thumbnailURL: URL?
    let isCurrent: Bool
    var id: String { "\(index)-\(videoId)" }
}
