import Foundation
import Observation

/// One navigable chapter/section. Story chapters, feed chapters and transcript-derived
/// podcast sections all map onto this.
struct PlaybackChapter: Identifiable, Hashable {
    let id: String
    var title: String
    var startTime: TimeInterval
    var endTime: TimeInterval?
    var isCompleted: Bool = false

    var duration: TimeInterval? {
        endTime.map { max(0, $0 - startTime) }
    }
}

extension Array where Element == PlaybackChapter {
    /// Index of the chapter containing `time` (last chapter whose start <= time).
    func chapterIndex(at time: TimeInterval) -> Int? {
        guard !isEmpty else { return nil }
        var result = 0
        for (i, chapter) in enumerated() where chapter.startTime <= time {
            result = i
        }
        return result
    }
}

/// Single source of truth the shared player UI reads from. Adapters (AudioManager,
/// story chapter player, podcast player) push values into it.
@Observable
final class PlaybackState {
    var title: String = ""
    var subtitle: String?
    var isPlaying = false
    var isBuffering = false
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var rate: Float = 1.0
    var chapters: [PlaybackChapter] = []
    var canGoPrevious = true
    var canGoNext = true

    init() {}

    var currentChapterIndex: Int? { chapters.chapterIndex(at: position) }

    var fractionComplete: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Wall-clock time left, accounting for playback speed.
    var timeRemaining: TimeInterval {
        guard rate > 0 else { return max(0, duration - position) }
        return max(0, duration - position) / TimeInterval(rate)
    }

    var currentChapterProgress: Double {
        guard let i = currentChapterIndex else { return 0 }
        let chapter = chapters[i]
        let end = chapter.endTime ?? (i + 1 < chapters.count ? chapters[i + 1].startTime : duration)
        let length = end - chapter.startTime
        guard length > 0 else { return 0 }
        return min(max((position - chapter.startTime) / length, 0), 1)
    }

    /// "Chapter 3 of 12 · The Warren", nil when there is at most one chapter.
    var chapterLabel: String? {
        guard chapters.count > 1, let i = currentChapterIndex else { return nil }
        return "Chapter \(i + 1) of \(chapters.count) · \(chapters[i].title)"
    }
}
