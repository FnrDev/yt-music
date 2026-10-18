import Foundation

/// One timed line of synced lyrics.
struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    /// Seconds from the start of the track.
    let time: Double
    let text: String
}

/// Parses LRC ("[mm:ss.xx] line") synced lyrics, as served by LRCLIB.
///
/// Handles several timestamps on one line (`[00:12.00][01:30.00] chorus`),
/// two- or three-digit fractions, the `[offset:±ms]` tag, and ignores other
/// metadata tags (`[ar:…]`, `[ti:…]`) and untimed lines.
enum LRCParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        var offset: Double = 0
        var timed: [(time: Double, text: String)] = []

        for rawLine in lrc.components(separatedBy: .newlines) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [Double] = []

            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = timestamp(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:"),
                          let milliseconds = Double(tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)) {
                    // Positive offsets make lyrics appear sooner.
                    offset = -milliseconds / 1000
                }
                rest = rest[rest.index(after: close)...]
            }

            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times { timed.append((time, text)) }
        }

        return timed
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { index, line in LyricLine(id: index, time: max(0, line.time + offset), text: line.text) }
    }

    /// "mm:ss", "mm:ss.xx" or "mm:ss.xxx" → seconds; nil for metadata tags.
    private static func timestamp(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let minutes = Double(parts[0]), minutes >= 0,
              let seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")), seconds >= 0, seconds < 60
        else { return nil }
        return minutes * 60 + seconds
    }

    /// Index of the line being sung at `position`, or nil before the first line.
    static func currentIndex(in lines: [LyricLine], at position: Double) -> Int? {
        // Lines are sorted by time; binary search for the last one that has started.
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }
}
