import Foundation

enum PodcastStudyContentStart {
    /// Extra audio included before the content-start mark so Whisper captures opening words.
    static let whisperLeadInSeconds: TimeInterval = 20

    static func effectiveStart(for episode: PodcastEpisode) -> TimeInterval {
        max(0, episode.studyContentStartSeconds)
    }

    static func whisperExportStart(for episode: PodcastEpisode) -> TimeInterval {
        max(0, effectiveStart(for: episode) - whisperLeadInSeconds)
    }

    /// Parses `MM:SS`, `H:MM:SS`, or plain seconds (e.g. `180`).
    static func parseTimestampEntry(_ raw: String) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.allSatisfy({ $0.isNumber }) {
            guard let seconds = TimeInterval(trimmed), seconds >= 0 else { return nil }
            return seconds
        }

        let parts = trimmed.split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count), parts.allSatisfy({ Int($0) != nil }) else {
            return nil
        }

        let numbers = parts.compactMap { Int($0) }
        switch numbers.count {
        case 2:
            return TimeInterval(numbers[0] * 60 + numbers[1])
        case 3:
            return TimeInterval(numbers[0] * 3600 + numbers[1] * 60 + numbers[2])
        default:
            return nil
        }
    }

    static func offsetWords(_ words: [WordTiming], by start: TimeInterval) -> [WordTiming] {
        guard start > 0 else { return words }
        return words.map { word in
            WordTiming(
                word: word.word,
                start: word.start + start,
                end: word.end + start
            )
        }
    }

    static func transcriptAlreadyAnchoredAtContentStart(
        _ words: [WordTiming],
        contentStart: TimeInterval
    ) -> Bool {
        guard contentStart > 0, let first = words.first else { return false }
        return first.start >= contentStart - 1.0
    }

    static func transcriptAlreadyAnchoredAtContentStart(
        blocks: [StudyBlock],
        contentStart: TimeInterval
    ) -> Bool {
        guard contentStart > 0, let first = blocks.first else { return false }
        return first.mediaStart >= contentStart - 1.0
    }

    static func filterWordsAtOrAfter(_ words: [WordTiming], start: TimeInterval) -> [WordTiming] {
        guard start > 0 else { return words }
        if transcriptAlreadyAnchoredAtContentStart(words, contentStart: start) {
            return words
        }
        return words.filter { word in
            let midpoint = (word.start + word.end) / 2
            return midpoint >= start
        }
    }

    static func filterCuesAtOrAfter(_ cues: [YouTubeCaptionCue], start: TimeInterval) -> [YouTubeCaptionCue] {
        guard start > 0 else { return cues }
        if let first = cues.first, first.startTime >= start - 1.0 {
            return cues
        }
        return cues.filter { $0.startTime >= start - 0.01 }
    }

    static func filterBlocksAtOrAfter(_ blocks: [StudyBlock], start: TimeInterval) -> [StudyBlock] {
        guard start > 0 else { return blocks }
        if transcriptAlreadyAnchoredAtContentStart(blocks: blocks, contentStart: start) {
            return blocks
        }
        return blocks.filter { block in
            block.mediaEnd > start && block.mediaStart >= start - 0.25
        }
    }

    static func formattedTimestampWithSeconds(_ seconds: TimeInterval) -> String {
        let stamp = formattedTimestamp(seconds)
        let raw = Int(max(0, seconds).rounded())
        return "\(stamp) (\(raw)s)"
    }

    static func formattedTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func formattedSignedOffset(_ seconds: TimeInterval) -> String {
        if abs(seconds) < 0.05 {
            return "0s"
        }
        let rounded = Int(seconds.rounded())
        return rounded > 0 ? "+\(rounded)s" : "\(rounded)s"
    }

    /// Parses a signed second value such as `-30`, `+30`, or `30`.
    static func parseSignedSecondsEntry(_ raw: String) -> TimeInterval? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasSuffix("s") || trimmed.hasSuffix("S") {
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        }

        guard let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    static func formattedSignedSecondsEntry(_ seconds: TimeInterval) -> String {
        if abs(seconds) < 0.05 {
            return "0"
        }
        let rounded = Int(seconds.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    static func applyTimingOffset(to blocks: [StudyBlock], offset: TimeInterval) -> [StudyBlock] {
        guard abs(offset) > 0.001 else { return blocks }

        return blocks.compactMap { block in
            let start = block.mediaStart + offset
            let end = block.mediaEnd + offset
            guard end > 0 else { return nil }

            return StudyBlock(
                id: block.id,
                index: block.index,
                targetText: block.targetText,
                nativeText: block.nativeText,
                mediaStart: max(0, start),
                mediaEnd: end,
                cueStartIndex: block.cueStartIndex,
                cueEndIndex: block.cueEndIndex
            )
        }
    }
}
