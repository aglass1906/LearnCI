import Foundation

/// One studiable unit in Study Mode — a single scene. A story is studied as an
/// ordered sequence of these chunks, across chapter boundaries.
struct StoryStudyChunk: Identifiable, Equatable {
    let chapterNumber: Int
    /// Index into `story.chapters` (adapters are array-index based).
    let chapterArrayIndex: Int
    let sceneIndex: Int
    /// 0-based position within the whole story's chunk list.
    let ordinal: Int
    let total: Int

    var id: String { "\(chapterNumber)-\(sceneIndex)" }
    var isLast: Bool { ordinal >= total - 1 }
}

enum StoryStudyChunks {
    /// Flatten a story into an ordered list of study chunks (scenes with target
    /// text), in reading order. Uses `story.chapters` array order so the
    /// `chapterArrayIndex` lines up with `StoryReaderDataAdapter`.
    static func chunks(for story: Story) -> [StoryStudyChunk] {
        let lang = story.targetLanguageCode
        var raw: [(chapterNumber: Int, chapterArrayIndex: Int, sceneIndex: Int)] = []

        for (arrayIndex, chapter) in story.chapters.enumerated() {
            let scenes = chapter.scenes.sorted { $0.sceneIndex < $1.sceneIndex }
            for scene in scenes {
                let caption = scene.captionFor(lang).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !caption.isEmpty else { continue }
                raw.append((chapter.chapterNumber, arrayIndex, scene.sceneIndex))
            }
        }

        let total = raw.count
        return raw.enumerated().map { ordinal, item in
            StoryStudyChunk(
                chapterNumber: item.chapterNumber,
                chapterArrayIndex: item.chapterArrayIndex,
                sceneIndex: item.sceneIndex,
                ordinal: ordinal,
                total: total
            )
        }
    }
}
