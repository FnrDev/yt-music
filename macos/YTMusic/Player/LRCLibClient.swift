import Foundation
import os

/// Looks up time-synced lyrics on LRCLIB (https://lrclib.net), a free, open
/// database of LRC lyrics. YouTube Music's web client only provides plain
/// lyrics, so this is where synced timings come from.
///
/// Sends the playing track's title, artist, album and duration to lrclib.net;
/// see the "Synced lyrics" setting.
struct LRCLibClient: Sendable {
    struct Match: Sendable {
        let lines: [LyricLine]
        let isInstrumental: Bool
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "YTMusic", category: "lrclib")
    private static let baseURL = URL(string: "https://lrclib.net/api/")!
    /// LRCLIB asks clients to identify themselves.
    private static let userAgent = "YTMusic/0.1 (https://github.com/FnrDev/yt-music)"
    /// A result's duration must be this close to the track's, or its timings
    /// probably belong to a different version (radio edit, live, remaster).
    private static let durationTolerance: Double = 3

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Synced lyrics for a track, or nil when LRCLIB has no matching synced version.
    func syncedLyrics(title: String, artist: String, album: String, duration: Double) async -> Match? {
        let titles = Self.titleVariants(title)
        let artist = Self.primaryArtist(artist)

        // 1. Exact lookup (LRCLIB matches on title, artist, album and duration).
        for candidate in titles {
            var query = [
                URLQueryItem(name: "track_name", value: candidate),
                URLQueryItem(name: "artist_name", value: artist),
                URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
            ]
            if !album.isEmpty { query.append(URLQueryItem(name: "album_name", value: album)) }
            if let record: Record = await fetch("get", query: query), let match = Self.match(record, duration: duration) {
                return match
            }
        }

        // 2. Search, keeping only synced results whose duration fits.
        for candidate in titles {
            let query = [
                URLQueryItem(name: "track_name", value: candidate),
                URLQueryItem(name: "artist_name", value: artist),
            ]
            guard let records: [Record] = await fetch("search", query: query) else { continue }
            let best = records
                .filter { $0.syncedLyrics?.isEmpty == false || $0.instrumental == true }
                .min { abs(($0.duration ?? .infinity) - duration) < abs(($1.duration ?? .infinity) - duration) }
            if let best, let match = Self.match(best, duration: duration) {
                return match
            }
        }
        return nil
    }

    // MARK: - Matching

    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
    }

    private static func match(_ record: Record, duration: Double) -> Match? {
        if let recordDuration = record.duration, duration > 0, abs(recordDuration - duration) > durationTolerance {
            return nil
        }
        if record.instrumental == true {
            return Match(lines: [], isInstrumental: true)
        }
        guard let synced = record.syncedLyrics, !synced.isEmpty else { return nil }
        let lines = LRCParser.parse(synced)
        return lines.isEmpty ? nil : Match(lines: lines, isInstrumental: false)
    }

    /// The title as shown, then without decorations YouTube adds to video
    /// titles: "(Official Video)", "[Lyrics]", "(feat. …)", "- Remastered 2011".
    static func titleVariants(_ title: String) -> [String] {
        var cleaned = title
        let patterns = [
            #"\s*[\(\[][^\)\]]*(official|video|audio|lyric|visuali[sz]er|feat\.?|ft\.?|remaster)[^\)\]]*[\)\]]"#,
            #"\s+-\s+[^-]*(remaster|version|edit|mix)[^-]*$"#,
        ]
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty || cleaned == title ? [title] : [title, cleaned]
    }

    /// YouTube Music joins collaborators ("A & B", "A, B", "A x B"); LRCLIB
    /// usually lists the first.
    static func primaryArtist(_ artist: String) -> String {
        let separators = [" & ", ", ", " x ", " X ", " feat. ", " ft. ", " and "]
        var primary = artist
        for separator in separators {
            if let range = primary.range(of: separator) { primary = String(primary[..<range.lowerBound]) }
        }
        return primary.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Networking

    private func fetch<T: Decodable>(_ endpoint: String, query: [URLQueryItem]) async -> T? {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else { return nil } // 404 = not found
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Self.log.info("LRCLIB \(endpoint, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
