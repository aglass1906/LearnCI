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
    case incompleteSceneText
    case incompleteSceneAudio
    case noVisiblePages
    case incompleteSceneImages
    case missingLayout

    var title: String {
        switch self {
        case .noChapters:
            return "Story Data Missing"
        case .noScenes:
            return "Scene Data Missing"
        case .incompleteSceneText:
            return "Scene Text Missing"
        case .incompleteSceneAudio:
            return "Scene Audio Missing"
        case .noVisiblePages:
            return "Reader Data Missing"
        case .incompleteSceneImages:
            return "Scene Images Missing"
        case .missingLayout:
            return "Layout Missing"
        }
    }

    var message: String {
        switch self {
        case .noChapters:
            return "This story does not have published chapter data yet."
        case .noScenes:
            return "This reader needs chapter scene data before it can render the story."
        case .incompleteSceneText:
            return "This reader needs scene target text before it can render the story."
        case .incompleteSceneAudio:
            return "This reader needs scene-level audio for every scene. Chapter-level audio is no longer used as a fallback."
        case .noVisiblePages:
            return "This reader needs spine, reading matter, or scene data before it can render the story."
        case .incompleteSceneImages:
            return "This reader needs scene images or story/chapter cover images before it can render picture pages."
        case .missingLayout:
            return "This reader needs published layout pages before it can render the story."
        }
    }
}

struct StoryReaderDataAdapter {
    let story: Story

    var spine: StoryReadingSpine {
        StoryReadingSpine.make(for: story)
    }

    func spine(for mode: StoryReadingSpineMode) -> StoryReadingSpine {
        StoryReadingSpine.make(for: story, mode: mode)
    }

    func items(for mode: StoryReadingSpineMode) -> [StoryReadingSpineItem] {
        spine(for: mode).items
    }

    func chapter(for item: StoryReadingSpineItem) -> StoryChapter? {
        guard case .chapter(let index) = item else { return nil }
        return story.chapters[safeReaderData: index]
    }

    func readingMatterPage(for item: StoryReadingSpineItem) -> ReadingMatterPage? {
        guard case .readingMatterPage(let index, let id) = item else { return nil }
        guard let page = story.readingMatterPages[safeReaderData: index] else { return nil }
        return page.id == id ? page : nil
    }

    func scene(for item: StoryReadingSpineItem) -> StoryScene? {
        guard case .scene(let chapterIndex, let sceneIndex) = item else { return nil }
        return story.chapters[safeReaderData: chapterIndex]?.scenes.first { $0.sceneIndex == sceneIndex }
    }

    var requirementIssue: StoryReaderRequirementIssue? {
        requirementIssue(for: .storyBook)
    }

    func requirementIssue(for mode: StoryReadingSpineMode) -> StoryReaderRequirementIssue? {
        let chapters = story.chapters
        guard !chapters.isEmpty else { return .noChapters }
        guard chapters.allSatisfy({ !$0.scenes.isEmpty }) else { return .noScenes }

        switch mode {
        case .storyBook:
            guard chapters.allSatisfy({ !$0.bodyTextTargetForReading.isEmpty }) else { return .incompleteSceneText }
            guard chapters.allSatisfy({ $0.bodyNarrationClipsCompleteForPlayback }) else { return .incompleteSceneAudio }
        case .audioBook:
            guard chapters.allSatisfy({ $0.bodyNarrationClipsCompleteForPlayback }) else { return .incompleteSceneAudio }
        case .dialogStory:
            guard chapters.allSatisfy({ chapter in
                chapter.scenes.allSatisfy { scene in
                    !scene.dialogues.isEmpty
                        || scene.scriptTargetLanguage?.trimmedNilIfEmpty != nil
                        || scene.captionTarget?.trimmedNilIfEmpty != nil
                }
            }) else { return .incompleteSceneText }
        case .pictureBook:
            let visibleItems = items(for: .pictureBook)
            guard visibleItems.contains(.cover) || visibleItems.contains(where: isReadingMatterPage) || visibleItems.contains(where: isScene) else {
                return .noVisiblePages
            }
            guard visibleItems.allSatisfy({ item in
                guard case .scene(let chapterIndex, _) = item else { return true }
                guard let scene = scene(for: item) else { return false }
                return sceneImageURL(scene: scene, chapterIndex: chapterIndex) != nil
            }) else { return .incompleteSceneImages }
        case .comicBook:
            guard let layout = story.storyLayout, !layout.pages.isEmpty else { return .missingLayout }
            guard !spine(for: .comicBook).sceneItems.isEmpty else { return .noScenes }
        }

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
                let publishedDuration = scene.audioDurationMs.map { Double($0) / 1000.0 }
                let timingDuration = scene.wordTimings.last?.end
                let duration = Self.resolvedSceneDuration(published: publishedDuration, timed: timingDuration)
                defer { offset += duration ?? 0 }
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

    func audioClip(for sceneItem: StoryReadingSpineItem) -> StorySceneAudioClip? {
        guard case .scene(let chapterIndex, let sceneIndex) = sceneItem else { return nil }
        return audioClips(forChapter: chapterIndex).first { $0.sceneIndex == sceneIndex }
    }

    func audioClips(for mode: StoryReadingSpineMode) -> [StorySceneAudioClip] {
        var offset = 0.0
        return spine(for: mode).sceneItems.compactMap { item in
            guard var clip = audioClip(for: item) else { return nil }
            clip = StorySceneAudioClip(
                id: clip.id,
                chapterIndex: clip.chapterIndex,
                sceneIndex: clip.sceneIndex,
                sceneOrdinal: clip.sceneOrdinal,
                urlString: clip.urlString,
                duration: clip.duration,
                startOffset: offset,
                title: clip.title,
                caption: clip.caption,
                imageURL: clip.imageURL
            )
            offset += clip.duration ?? 0
            return clip
        }
    }

    private func isReadingMatterPage(_ item: StoryReadingSpineItem) -> Bool {
        if case .readingMatterPage = item { return true }
        return false
    }

    private func isScene(_ item: StoryReadingSpineItem) -> Bool {
        if case .scene = item { return true }
        return false
    }

    func allAudioClips() -> [StorySceneAudioClip] {
        audioClips(for: .audioBook)
    }

    func duration(forChapter chapterIndex: Int, fallback: Double = 0) -> Double {
        let clips = audioClips(forChapter: chapterIndex)
        let known = clips.reduce(0.0) { total, clip in total + (clip.duration ?? 0) }
        return known > 0 ? known : fallback
    }

    func duration(
        forChapter chapterIndex: Int,
        currentClipIndex: Int,
        currentStreamDuration: Double,
        fallback: Double = 0
    ) -> Double {
        let clips = audioClips(forChapter: chapterIndex)
        guard !clips.isEmpty else { return fallback }

        let known = duration(forChapter: chapterIndex, fallback: 0)
        guard clips.indices.contains(currentClipIndex), currentStreamDuration > 0 else {
            return known > 0 ? known : fallback
        }

        let currentClip = clips[currentClipIndex]
        let remainingKnown = clips
            .dropFirst(currentClipIndex + 1)
            .reduce(0.0) { total, clip in total + (clip.duration ?? 0) }
        let actualTimelineDuration = currentClip.startOffset + currentStreamDuration + remainingKnown
        return max(known, actualTimelineDuration, fallback)
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

    func localAudioURL(for clip: StorySceneAudioClip) -> URL {
        Self.localAudioURL(storyID: story.id, clip: clip, storyUpdatedAt: story.updatedAt)
    }

    func cachedAudioURL(for clip: StorySceneAudioClip) -> URL? {
        Self.cachedAudioURL(storyID: story.id, clip: clip, storyUpdatedAt: story.updatedAt)
    }

    static func remoteAudioURL(for path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        let supabaseAudioBase = "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories"
        return URL(string: "\(supabaseAudioBase)/\(path)")
    }

    static func localAudioURL(storyID: UUID, clip: StorySceneAudioClip, storyUpdatedAt: Date? = nil) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ext = (clip.urlString as NSString).pathExtension.trimmedNilIfEmpty ?? "mp3"
        let filename = "\(audioCacheBasename(storyID: storyID, clip: clip, storyUpdatedAt: storyUpdatedAt)).\(ext)"
        return docs.appendingPathComponent(filename)
    }

    static func cachedAudioURL(storyID: UUID, clip: StorySceneAudioClip, storyUpdatedAt: Date? = nil) -> URL? {
        let primaryURL = localAudioURL(storyID: storyID, clip: clip, storyUpdatedAt: storyUpdatedAt)
        let docs = primaryURL.deletingLastPathComponent()
        let basename = primaryURL.deletingPathExtension().lastPathComponent
        let primaryExt = primaryURL.pathExtension.trimmedNilIfEmpty ?? "mp3"
        let extensions = [primaryExt, "mp3", "wav", "m4a", "aac"].uniquedCacheExtensions

        for ext in extensions {
            let candidate = docs.appendingPathComponent("\(basename).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    @discardableResult
    static func deleteCachedStoryAudio(storyID: UUID) -> Int {
        deleteCachedStoryFiles(storyID: storyID) { filename in
            filename.hasPrefix("story_\(storyID.uuidString)_chapter_")
                || filename.hasPrefix("story_\(storyID.uuidString).")
        }
    }

    @discardableResult
    static func deleteCachedStoryMedia(storyID: UUID) -> Int {
        deleteCachedStoryFiles(storyID: storyID) { filename in
            filename.hasPrefix("story_\(storyID.uuidString)_chapter_")
                || filename.hasPrefix("story_\(storyID.uuidString).")
                || filename == "video_\(storyID.uuidString)_remote.mp4"
                || filename == "cover_\(storyID.uuidString).png"
        }
    }

    private static func audioCacheBasename(storyID: UUID, clip: StorySceneAudioClip, storyUpdatedAt: Date?) -> String {
        let updatedAtVersion = storyUpdatedAt.map { String($0.timeIntervalSince1970) } ?? "unversioned"
        let fingerprint = cacheFingerprint("\(updatedAtVersion)|\(clip.urlString)")
        return "story_\(storyID.uuidString)_chapter_\(clip.chapterIndex)_scene_\(clip.sceneIndex)_\(fingerprint)"
    }

    private static func cacheFingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private static func deleteCachedStoryFiles(storyID: UUID, matching shouldDelete: (String) -> Bool) -> Int {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else {
            return 0
        }

        var deletedCount = 0
        for file in files where shouldDelete(file.lastPathComponent) {
            do {
                try FileManager.default.removeItem(at: file)
                deletedCount += 1
            } catch {
                print("[StoryMediaCache] Failed to delete \(file.lastPathComponent): \(error)")
            }
        }
        if deletedCount > 0 {
            print("[StoryMediaCache] Deleted \(deletedCount) cached media files for story \(storyID)")
        }
        return deletedCount
    }

    private static func resolvedSceneDuration(published: Double?, timed: Double?) -> Double? {
        let candidates = [published, timed].compactMap { value -> Double? in
            guard let value, value.isFinite, value > 0 else { return nil }
            return value
        }
        return candidates.max()
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

private extension Array where Element == String {
    var uniquedCacheExtensions: [String] {
        var seen = Set<String>()
        return compactMap { value in
            let normalized = value.lowercased()
            guard seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }
}
