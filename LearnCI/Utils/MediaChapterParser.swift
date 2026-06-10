import Foundation

struct MediaTimestampChapter: Equatable, Sendable {
    let startTime: TimeInterval
    let title: String
}

enum MediaChapterParser {
    static func parseChapters(from description: String) -> [MediaTimestampChapter] {
        guard !description.isEmpty else { return [] }

        let pattern = #"^\s*(?:\(?\s*)?((?:\d{1,2}:)?\d{1,2}:\d{2})\s*\)?\s*(?:[-–—|:]\s*)?(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var chapters: [MediaTimestampChapter] = []
        var seenStartTimes: Set<Int> = []

        for line in description.components(separatedBy: .newlines) {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: nsRange),
                  let timestampRange = Range(match.range(at: 1), in: line),
                  let titleRange = Range(match.range(at: 2), in: line) else {
                continue
            }

            let timestamp = String(line[timestampRange])
            let title = String(line[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let startSeconds = timestampToSeconds(timestamp)

            guard !title.isEmpty else { continue }
            guard seenStartTimes.insert(startSeconds).inserted else { continue }

            chapters.append(
                MediaTimestampChapter(
                    startTime: TimeInterval(startSeconds),
                    title: title
                )
            )
        }

        let sortedChapters = chapters.sorted { $0.startTime < $1.startTime }
        return sortedChapters.count >= 2 ? sortedChapters : []
    }

    static func timestampToSeconds(_ timestamp: String) -> Int {
        let components = timestamp
            .split(separator: ":")
            .compactMap { Int($0) }

        guard !components.isEmpty else { return 0 }

        return components.reduce(0) { partialResult, value in
            (partialResult * 60) + value
        }
    }
}

enum PodcastAdSegmentDetector {
    static func adIntervals(
        from description: String,
        episodeDuration: TimeInterval
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        let chapters = MediaChapterParser.parseChapters(from: description)
        guard chapters.count >= 2 else { return [] }

        let sorted = chapters.sorted { $0.startTime < $1.startTime }
        var intervals: [(start: TimeInterval, end: TimeInterval)] = []

        for index in sorted.indices {
            let chapter = sorted[index]
            guard isAdChapterTitle(chapter.title) else { continue }

            let end: TimeInterval
            if index + 1 < sorted.count {
                end = sorted[index + 1].startTime
            } else {
                end = max(episodeDuration, chapter.startTime + 60)
            }

            guard end > chapter.startTime else { continue }
            intervals.append((start: chapter.startTime, end: end))
        }

        return intervals
    }

    static func isAdChapterTitle(_ title: String) -> Bool {
        let normalized = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let tokens = [
            "ad break", "ad-break", "advertisement", "advert", "commercial",
            "sponsor", "sponsored", "sponsorship", "promo", "promotion",
            "house ad", "midroll", "mid-roll", "pre-roll", "preroll",
            "anuncio", "publicidad", "patrocinio", "patrocinado"
        ]

        if tokens.contains(where: { normalized.contains($0) }) {
            return true
        }

        if normalized == "ad" || normalized == "ads" {
            return true
        }

        return false
    }

    static func filterWords(
        _ words: [WordTiming],
        excludingAdIntervals intervals: [(start: TimeInterval, end: TimeInterval)]
    ) -> [WordTiming] {
        guard !intervals.isEmpty else { return words }

        return words.filter { word in
            let midpoint = (word.start + word.end) / 2
            return !intervals.contains { interval in
                midpoint >= interval.start && midpoint < interval.end
            }
        }
    }
}
