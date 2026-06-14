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

    var isChapterIntro: Bool { sceneIndex == -1 }
    var isReadingMatter: Bool { sceneIndex == -2 }
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

    func readingMatterAudioClip(
        pageIndex: Int,
        page: ReadingMatterPage,
        preferNative: Bool
    ) -> StorySceneAudioClip? {
        guard let urlString = page.audioUrlForPlayback(preferNative: preferNative) else { return nil }
        let title = StoryReadingSpineTitles.readingMatterTitle(for: page)
        let body = preferNative
            ? (page.bodyNative?.trimmedNilIfEmpty ?? page.bodyTarget?.trimmedNilIfEmpty)
            : page.bodyTarget?.trimmedNilIfEmpty
        let timedDuration = page.wordTimingsForPlayback(preferNative: preferNative).last?.end
        return StorySceneAudioClip(
            id: "matter-\(pageIndex)-\(page.id)",
            chapterIndex: -1,
            sceneIndex: -2,
            sceneOrdinal: pageIndex,
            urlString: urlString,
            duration: timedDuration,
            startOffset: 0,
            title: title,
            caption: body ?? "",
            imageURL: readingMatterImageURL(for: page)
        )
    }

    func readingMatterImageURL(for item: StoryReadingSpineItem) -> URL? {
        guard let page = readingMatterPage(for: item) else { return nil }
        return readingMatterImageURL(for: page)
    }

    func readingMatterImageURL(for page: ReadingMatterPage) -> URL? {
        if let imagePath = page.imageUrl?.trimmedNilIfEmpty,
           let url = AppConfig.chapterCoverURL(imagePath) {
            return url
        }

        guard !story.chapters.isEmpty else { return nil }
        let chapterIndex = page.isBackMatter ? story.chapters.count - 1 : 0
        return chapterImageURL(forChapterAt: chapterIndex)
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
        sceneClips(forChapter: chapterIndex, introBaseOffset: 0)
    }

    /// Chapter timeline clips: optional intro pre-scene, then scene narration (for audio book playback + scrubber).
    func tracklistTitle(for clip: StorySceneAudioClip, chapter: StoryChapter) -> String {
        if clip.isChapterIntro {
            return "Chapter Intro"
        }
        return "Scene \(clip.sceneIndex + 1)"
    }

    func tracklistSubtitle(for clip: StorySceneAudioClip, chapter: StoryChapter) -> String {
        if clip.isChapterIntro {
            let intro = clip.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !intro.isEmpty { return intro }
            return chapter.chapterIntroText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let caption = clip.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty { return caption }

        guard let scene = chapter.scenes.first(where: { $0.sceneIndex == clip.sceneIndex }) else {
            return ""
        }
        return scene.spokenTranscriptText(preferences: story.preferences)
    }

    func chapterPlaybackClips(forChapter chapterIndex: Int) -> [StorySceneAudioClip] {
        guard story.chapters.indices.contains(chapterIndex) else { return [] }
        let chapter = story.chapters[chapterIndex]
        var clips: [StorySceneAudioClip] = []
        var offset = 0.0

        if let introPath = chapter.chapterIntroAudioUrl?.trimmedNilIfEmpty {
            let introDuration = Self.resolvedSceneDuration(
                published: nil,
                timed: chapter.chapterIntroWordTimings?.last?.end
            )
            clips.append(
                StorySceneAudioClip(
                    id: "\(chapterIndex)-intro",
                    chapterIndex: chapterIndex,
                    sceneIndex: -1,
                    sceneOrdinal: -1,
                    urlString: introPath,
                    duration: introDuration,
                    startOffset: offset,
                    title: chapter.titleTargetLanguage.isEmpty ? "Chapter \(chapterIndex + 1)" : chapter.titleTargetLanguage,
                    caption: chapter.chapterIntroText?.trimmedNilIfEmpty ?? "",
                    imageURL: chapterImageURL(forChapterAt: chapterIndex)
                )
            )
            offset += introDuration ?? 0
        }

        clips.append(contentsOf: sceneClips(forChapter: chapterIndex, introBaseOffset: offset))
        return clips
    }

    func audioBookPlaybackClips() -> [StorySceneAudioClip] {
        var result: [StorySceneAudioClip] = []
        var seenChapters = Set<Int>()

        for item in spine(for: .audioBook).items {
            guard case .chapter(let chapterIndex) = item, seenChapters.insert(chapterIndex).inserted else { continue }
            result.append(contentsOf: chapterPlaybackClips(forChapter: chapterIndex))
        }
        return result
    }

    private func sceneClips(forChapter chapterIndex: Int, introBaseOffset: Double) -> [StorySceneAudioClip] {
        guard story.chapters.indices.contains(chapterIndex) else { return [] }
        let chapter = story.chapters[chapterIndex]
        var offset = introBaseOffset

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

    func duration(forChapter chapterIndex: Int, fallback: Double = 0, includeIntro: Bool = false) -> Double {
        let clips = includeIntro ? chapterPlaybackClips(forChapter: chapterIndex) : audioClips(forChapter: chapterIndex)
        let known = clips.reduce(0.0) { total, clip in total + (clip.duration ?? 0) }
        return known > 0 ? known : fallback
    }

    func duration(
        forChapter chapterIndex: Int,
        currentClipIndex: Int,
        currentStreamDuration: Double,
        fallback: Double = 0,
        includeIntro: Bool = false
    ) -> Double {
        let clips = includeIntro ? chapterPlaybackClips(forChapter: chapterIndex) : audioClips(forChapter: chapterIndex)
        guard !clips.isEmpty else { return fallback }

        let known = duration(forChapter: chapterIndex, fallback: 0, includeIntro: includeIntro)
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

    func clipIndex(forChapter chapterIndex: Int, localTime: Double, includeIntro: Bool = false) -> (index: Int, offset: Double)? {
        let clips = includeIntro ? chapterPlaybackClips(forChapter: chapterIndex) : audioClips(forChapter: chapterIndex)
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

    func chapterImageURL(forChapterAt chapterIndex: Int) -> URL? {
        guard story.chapters.indices.contains(chapterIndex) else { return nil }
        let chapter = story.chapters[chapterIndex]

        if let path = Self.assetForgeChapterImagePath(story: story, chapterIndex: chapterIndex),
           let url = AppConfig.chapterCoverURL(path) {
            return url
        }
        if let coverUrl = chapter.coverUrl?.trimmedNilIfEmpty,
           let url = AppConfig.chapterCoverURL(coverUrl) {
            return url
        }
        if let remoteCoverPath = story.remoteCoverPath?.trimmedNilIfEmpty,
           let url = AppConfig.chapterCoverURL(remoteCoverPath) {
            return url
        }
        if let coverArt = story.coverArt?.trimmedNilIfEmpty,
           let url = AppConfig.chapterCoverURL(coverArt) {
            return url
        }
        return nil
    }

    func sceneImageURL(scene: StoryScene, chapterIndex: Int) -> URL? {
        if let imageUrl = scene.imageUrl?.trimmedNilIfEmpty,
           let url = AppConfig.chapterCoverURL(imageUrl) {
            return url
        }
        if let path = Self.breakdownSceneImagePath(
            story: story,
            chapterIndex: chapterIndex,
            sceneIndex: scene.sceneIndex
        ), let url = AppConfig.chapterCoverURL(path) {
            return url
        }
        return chapterImageURL(forChapterAt: chapterIndex)
    }

    private static func breakdownSceneImagePath(
        story: Story,
        chapterIndex: Int,
        sceneIndex: Int
    ) -> String? {
        if let path = breakdownSceneImagePath(
            story: story,
            chapterIndex: chapterIndex,
            sceneIndexOneBased: sceneIndex + 1
        ) {
            return path
        }
        return breakdownSceneImagePath(
            story: story,
            chapterIndex: chapterIndex,
            sceneIndexOneBased: sceneIndex
        )
    }

    private static func breakdownSceneImagePath(
        story: Story,
        chapterIndex: Int,
        sceneIndexOneBased: Int
    ) -> String? {
        if let json = story.sceneBreakdownJSON,
           let data = json.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let chapters = root["chapters"] as? [[String: Any]],
           chapters.indices.contains(chapterIndex),
           let scenes = chapters[chapterIndex]["scenes"] as? [[String: Any]] {
            for sceneRow in scenes {
                let rowIndex = (sceneRow["sceneIndex"] as? NSNumber)?.intValue ?? 0
                guard rowIndex == sceneIndexOneBased else { continue }

                let assetID = [
                    sceneRow["asset_id"] as? String,
                    sceneRow["assetId"] as? String
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                    ?? "af_sc_\(chapterIndex)_\(sceneIndexOneBased)"

                if let path = assetForgeMasterPath(story: story, assetID: assetID) {
                    return path
                }
                if let path = (sceneRow["sceneImagePath"] as? String)?.trimmedNilIfEmpty {
                    return path
                }
            }
        }

        return assetForgeMasterPath(
            story: story,
            assetID: "af_sc_\(chapterIndex)_\(sceneIndexOneBased)"
        )
    }

    private static func assetForgeMasterPath(story: Story, assetID: String) -> String? {
        guard let assetForgeJSON = story.assetForgeJSON,
              let data = assetForgeJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return masterImagePath(in: root, matchingAssetID: assetID)
    }

    private static func assetForgeChapterImagePath(story: Story, chapterIndex: Int) -> String? {
        guard let assetForgeJSON = story.assetForgeJSON,
              let data = assetForgeJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let path = assetForgeMasterPath(story: story, assetID: "af_ch_\(chapterIndex)") {
            return path
        }
        if let chapters = root as? [String: Any],
           let chapterRows = chapters["chapters"] as? [Any],
           chapterIndex < chapterRows.count,
           let path = masterImagePath(in: chapterRows[chapterIndex]) {
            return path
        }
        return nil
    }

    private static func masterImagePath(in value: Any, matchingAssetID: String) -> String? {
        if let dictionary = value as? [String: Any] {
            let assetID = [
                dictionary["asset_id"] as? String,
                dictionary["assetId"] as? String
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first

            if assetID == matchingAssetID, let path = masterImagePath(in: dictionary) {
                return path
            }

            for child in dictionary.values {
                if let path = masterImagePath(in: child, matchingAssetID: matchingAssetID) {
                    return path
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let path = masterImagePath(in: child, matchingAssetID: matchingAssetID) {
                    return path
                }
            }
        }
        return nil
    }

    private static func masterImagePath(in value: Any) -> String? {
        if let path = value as? String {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard let dictionary = value as? [String: Any] else { return nil }

        if let images = dictionary["images"] as? [String: Any] {
            for key in ["master_path", "masterPath"] {
                if let path = images[key] as? String {
                    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }

        for key in [
            "master_path", "masterPath",
            "image_path", "imagePath",
            "image_url", "imageUrl",
            "url", "path"
        ] {
            if let path = dictionary[key] as? String {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        for key in ["images", "master_images", "masterImages", "variations"] {
            if let child = dictionary[key], let path = masterImagePath(in: child) {
                return path
            }
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

    /// Downloads scene audio to the local cache when missing. Safe to call concurrently for the same clip.
    static func downloadAndCacheAudioIfNeeded(
        storyID: UUID,
        clip: StorySceneAudioClip,
        storyUpdatedAt: Date?
    ) async -> URL? {
        if let cached = cachedAudioURL(storyID: storyID, clip: clip, storyUpdatedAt: storyUpdatedAt) {
            return cached
        }
        guard let remoteURL = remoteAudioURL(for: clip.urlString) else { return nil }

        let localURL = localAudioURL(storyID: storyID, clip: clip, storyUpdatedAt: storyUpdatedAt)
        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 else {
                return nil
            }

            let isWAV = data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46])
            let correctURL = localURL.deletingPathExtension().appendingPathExtension(isWAV ? "wav" : "mp3")
            try data.write(to: correctURL, options: .atomic)
            return correctURL
        } catch {
            return nil
        }
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
