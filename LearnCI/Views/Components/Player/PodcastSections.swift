import Foundation

/// Builds navigable sections for a podcast episode from its transcript study blocks.
/// Episodes without a transcript get no sections (the chapter UI stays hidden).
enum PodcastSections {
    /// Groups consecutive blocks into sections of roughly `targetSeconds`.
    static func make(
        from blocks: [StudyBlock],
        episodeDuration: TimeInterval,
        targetSeconds: TimeInterval = 300
    ) -> [PlaybackChapter] {
        let sorted = blocks.sorted { $0.mediaStart < $1.mediaStart }
        guard let first = sorted.first else { return [] }

        var groups: [[StudyBlock]] = []
        var current: [StudyBlock] = []
        var groupStart = first.mediaStart
        for block in sorted {
            if !current.isEmpty, block.mediaStart - groupStart >= targetSeconds {
                groups.append(current)
                current = []
                groupStart = block.mediaStart
            }
            current.append(block)
        }
        if !current.isEmpty { groups.append(current) }
        guard groups.count > 1 else { return [] }

        return groups.enumerated().map { index, group in
            let start = index == 0 ? 0 : group[0].mediaStart
            let end: TimeInterval? = index + 1 < groups.count
                ? groups[index + 1][0].mediaStart
                : (episodeDuration > 0 ? episodeDuration : group.last?.mediaEnd)
            return PlaybackChapter(
                id: "section-\(index)",
                title: title(for: group[0], fallbackIndex: index),
                startTime: start,
                endTime: end
            )
        }
    }

    private static func title(for block: StudyBlock, fallbackIndex: Int) -> String {
        let words = block.targetText
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(6)
            .joined(separator: " ")
        return words.isEmpty ? "Section \(fallbackIndex + 1)" : words + "…"
    }
}
