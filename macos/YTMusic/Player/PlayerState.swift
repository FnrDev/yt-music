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
        }
        return "window.__ytmBridge && window.__ytmBridge.command('\(name)', \(arg));"
    }
}
