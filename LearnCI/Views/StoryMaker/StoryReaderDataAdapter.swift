import Foundation

struct StorySceneAudioClip: Identifiable, Equatable {
    let id: String
    let chapterIndex: Int
    let sceneIndex: Int
    let sceneOrdinal: Int
    let urlString: String
    let duration: Double?
    let startOffset: Double
    let title: String
    let caption: String
    let imageURL: URL?
}

enum StoryReaderRequirementIssue: Equatable {
    case noChapters
    case noScenes
    case incompleteSceneAudio

    var title: String {
        switch self {
        case .noChapters:
            return "Story Data Missing"
        case .noScenes:
            return "Scene Data Missing"
        case .incompleteSceneAudio:
            return "Scene Audio Missing"
        }
    }

    var message: String {
        switch self {
        case .noChapters:
            return "This story does not have published chapter data yet."
        case .noScenes:
            return "This reader needs chapter scene data before it can render the story."
        case .incompleteSceneAudio:
            return "This reader needs scene-level audio for every scene. Chapter-level audio is no longer used as a fallback."
        }
    }
}

struct StoryReaderDataAdapter {
    let story: Story

    var spine: StoryReadingSpine {
        StoryReadingSpine.make(for: story)
    }

    var requirementIssue: StoryReaderRequirementIssue? {
        let chapters = story.chapters
        guard !chapters.isEmpty else { return .noChapters }
        guard chapters.allSatisfy({ !$0.scenes.isEmpty }) else { return .noScenes }
        guard chapters.allSatisfy({ $0.bodyNarrationClipsCompleteForPlayback }) else { return .incompleteSceneAudio }
        return nil
    }

    func text(for chapter: StoryChapter, language: StorySessionView.DisplayLanguage) -> String {
        switch language {
        case .target:
            return chapter.bodyTextTargetForReading
        case .native:
            return chapter.bodyTextEnglishForReading
        }
    }

    func audioClips(forChapter chapterIndex: Int) -> [StorySceneAudioClip] {
        guard story.chapters.indices.contains(chapterIndex) else { return [] }
        let chapter = story.chapters[chapterIndex]
        var offset = 0.0

        return chapter.scenes
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .enumerated()
            .compactMap { ordinal, scene in
                guard let audioUrl = scene.audioUrl?.trimmedNilIfEmpty else { return nil }
                let duration = scene.audioDurationMs.map { Double($0) / 1000.0 }
                defer { offset += duration ?? scene.wordTimings.last?.end ?? 0 }
                return StorySceneAudioClip(
                    id: "\(chapterIndex)-\(scene.sceneIndex)-\(ordinal)",
                    chapterIndex: chapterIndex,
                    sceneIndex: scene.sceneIndex,
                    sceneOrdinal: ordinal,
                    urlString: audioUrl,
                    duration: duration,
                    startOffset: offset,
                    title: chapter.titleTargetLanguage.isEmpty ? "Scene \(scene.sceneIndex + 1)" : chapter.titleTargetLanguage,
                    caption: scene.captionTarget?.trimmedNilIfEmpty ?? scene.scriptTargetLanguage?.trimmedNilIfEmpty ?? "",
                    imageURL: sceneImageURL(scene: scene, chapterIndex: chapterIndex)
                )
            }
    }

    func allAudioClips() -> [StorySceneAudioClip] {
        spine.chapterIndices.flatMap { audioClips(forChapter: $0) }
    }

    func duration(forChapter chapterIndex: Int, fallback: Double = 0) -> Double {
        let clips = audioClips(forChapter: chapterIndex)
        let known = clips.reduce(0.0) { total, clip in total + (clip.duration ?? 0) }
        return known > 0 ? known : fallback
    }

    func clipIndex(forChapter chapterIndex: Int, localTime: Double) -> (index: Int, offset: Double)? {
        let clips = audioClips(forChapter: chapterIndex)
        guard !clips.isEmpty else { return nil }

        for (index, clip) in clips.enumerated() {
            let nextStart = index + 1 < clips.count ? clips[index + 1].startOffset : Double.greatestFiniteMagnitude
            if localTime >= clip.startOffset && localTime < nextStart {
                return (index, max(0, localTime - clip.startOffset))
            }
        }

        let lastIndex = clips.count - 1
        return (lastIndex, max(0, localTime - clips[lastIndex].startOffset))
    }

    func sceneImageURL(scene: StoryScene, chapterIndex: Int) -> URL? {
        if let imageUrl = scene.imageUrl?.trimmedNilIfEmpty {
            return AppConfig.chapterCoverURL(imageUrl)
        }
        if let coverUrl = story.chapters[safeReaderData: chapterIndex]?.coverUrl?.trimmedNilIfEmpty {
            return AppConfig.chapterCoverURL(coverUrl)
        }
        if let remoteCoverPath = story.remoteCoverPath?.trimmedNilIfEmpty {
            return AppConfig.chapterCoverURL(remoteCoverPath)
        }
        if let coverArt = story.coverArt?.trimmedNilIfEmpty {
            return AppConfig.chapterCoverURL(coverArt)
        }
        return nil
    }

    static func remoteAudioURL(for path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        let supabaseAudioBase = "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories"
        return URL(string: "\(supabaseAudioBase)/\(path)")
    }

    static func localAudioURL(storyID: UUID, clip: StorySceneAudioClip) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ext = (clip.urlString as NSString).pathExtension.trimmedNilIfEmpty ?? "mp3"
        let filename = "story_\(storyID.uuidString)_chapter_\(clip.chapterIndex)_scene_\(clip.sceneIndex).\(ext)"
        return docs.appendingPathComponent(filename)
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Collection {
    subscript(safeReaderData index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
