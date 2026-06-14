import Foundation

struct StoryScene: Codable, Identifiable, Equatable {
    var id: String { "\(sceneIndex)" }
    var sceneIndex: Int
    var captionTarget: String?
    var captionNative: String?
    var dialogues: [SceneDialogue]
    var imageUrl: String?
    var audioUrl: String?
    var audioDurationMs: Int?
    var wordTimings: [WordTiming]
    var scriptTargetLanguage: String?
    var scriptEnglish: String?
    var contentMode: StorySceneContentMode?
    var cropRegion: CropRegion?

    enum CodingKeys: String, CodingKey {
        case sceneIndex = "scene_index"
        case sceneIndexCamel = "sceneIndex"
        case captionTarget = "caption_target"
        case captionTargetCamel = "captionTarget"
        case captionNative = "caption_native"
        case captionNativeCamel = "captionNative"
        case dialogues
        case imageUrl = "image_url"
        case imageUrlCamel = "imageUrl"
        case audioUrl = "audio_url"
        case audioUrlCamel = "audioUrl"
        case audioDurationMs = "audio_duration_ms"
        case audioDurationMsCamel = "audioDurationMs"
        case wordTimings = "word_timings"
        case wordTimingsCamel = "wordTimings"
        case scriptTargetLanguage = "script_target_language"
        case scriptTargetLanguageCamel = "scriptTargetLanguage"
        case scriptEnglish = "script_english"
        case scriptEnglishCamel = "scriptEnglish"
        case contentMode = "content_mode"
        case contentModeCamel = "contentMode"
        case cropRegion = "crop_region"
        case cropRegionCamel = "cropRegion"
    }

    init(
        sceneIndex: Int,
        captionTarget: String? = nil,
        captionNative: String? = nil,
        dialogues: [SceneDialogue] = [],
        imageUrl: String? = nil,
        audioUrl: String? = nil,
        audioDurationMs: Int? = nil,
        wordTimings: [WordTiming] = [],
        scriptTargetLanguage: String? = nil,
        scriptEnglish: String? = nil,
        contentMode: StorySceneContentMode? = nil,
        cropRegion: CropRegion? = nil
    ) {
        self.sceneIndex = sceneIndex
        self.captionTarget = captionTarget
        self.captionNative = captionNative
        self.dialogues = dialogues
        self.imageUrl = imageUrl
        self.audioUrl = audioUrl
        self.audioDurationMs = audioDurationMs
        self.wordTimings = wordTimings
        self.scriptTargetLanguage = scriptTargetLanguage
        self.scriptEnglish = scriptEnglish
        self.contentMode = contentMode
        self.cropRegion = cropRegion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sceneIndex = (try? c.decode(Int.self, forKey: .sceneIndex))
            ?? (try? c.decode(Int.self, forKey: .sceneIndexCamel))
            ?? 0
        captionTarget = (try? c.decode(String.self, forKey: .captionTarget))
            ?? (try? c.decode(String.self, forKey: .captionTargetCamel))
        captionNative = (try? c.decode(String.self, forKey: .captionNative))
            ?? (try? c.decode(String.self, forKey: .captionNativeCamel))
        dialogues = (try? c.decode([SceneDialogue].self, forKey: .dialogues)) ?? []
        imageUrl = (try? c.decode(String.self, forKey: .imageUrl))
            ?? (try? c.decode(String.self, forKey: .imageUrlCamel))
        audioUrl = (try? c.decode(String.self, forKey: .audioUrl))
            ?? (try? c.decode(String.self, forKey: .audioUrlCamel))
        audioDurationMs = (try? c.decode(Int.self, forKey: .audioDurationMs))
            ?? (try? c.decode(Int.self, forKey: .audioDurationMsCamel))
        wordTimings = (try? c.decode([WordTiming].self, forKey: .wordTimings))
            ?? (try? c.decode([WordTiming].self, forKey: .wordTimingsCamel))
            ?? []
        scriptTargetLanguage = (try? c.decode(String.self, forKey: .scriptTargetLanguage))
            ?? (try? c.decode(String.self, forKey: .scriptTargetLanguageCamel))
        scriptEnglish = (try? c.decode(String.self, forKey: .scriptEnglish))
            ?? (try? c.decode(String.self, forKey: .scriptEnglishCamel))
        contentMode = (try? c.decode(StorySceneContentMode.self, forKey: .contentMode))
            ?? (try? c.decode(StorySceneContentMode.self, forKey: .contentModeCamel))
        cropRegion = (try? c.decode(CropRegion.self, forKey: .cropRegion))
            ?? (try? c.decode(CropRegion.self, forKey: .cropRegionCamel))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sceneIndex, forKey: .sceneIndex)
        try c.encodeIfPresent(captionTarget, forKey: .captionTarget)
        try c.encodeIfPresent(captionNative, forKey: .captionNative)
        try c.encode(dialogues, forKey: .dialogues)
        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try c.encodeIfPresent(audioUrl, forKey: .audioUrl)
        try c.encodeIfPresent(audioDurationMs, forKey: .audioDurationMs)
        try c.encode(wordTimings, forKey: .wordTimings)
        try c.encodeIfPresent(scriptTargetLanguage, forKey: .scriptTargetLanguage)
        try c.encodeIfPresent(scriptEnglish, forKey: .scriptEnglish)
        try c.encodeIfPresent(contentMode, forKey: .contentMode)
        try c.encodeIfPresent(cropRegion, forKey: .cropRegion)
    }

    /// Target-language text that matches per-scene TTS / narration (pipeline parity with Flutter).
    func spokenTranscriptText(preferences: StoryPreferences) -> String {
        if preferences.storyType == .comicBook || contentMode == .panel {
            return captionAndDialogueTranscript(fallbackScript: true)
        }

        if preferences.audioStyle == .dramatized,
           let script = Self.trimmedNonEmpty(scriptTargetLanguage) {
            return script
        }

        if let caption = Self.trimmedNonEmpty(captionTarget) {
            return caption
        }

        return captionAndDialogueTranscript(fallbackScript: true)
    }

    var hasNarrationAudio: Bool {
        !(audioUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Timed segments for transcript highlighting (per-scene word timings).
    func transcriptSegments(preferences: StoryPreferences) -> [StorySegmentTiming] {
        let text = spokenTranscriptText(preferences: preferences)
        let timings = wordTimings
        guard !text.isEmpty, !timings.isEmpty else { return [] }

        if preferences.audioStyle == .dramatized, text.contains("[") {
            let parsed = ScriptParser.parseSegments(scriptText: text, globalTimings: timings)
            if !parsed.isEmpty { return parsed }
        }

        return [
            StorySegmentTiming(
                speaker: "NARRATOR",
                text: text,
                startTime: timings.first?.start ?? 0,
                endTime: timings.last?.end ?? 0,
                timings: timings
            )
        ]
    }

    private func captionAndDialogueTranscript(fallbackScript: Bool) -> String {
        var lines: [String] = []
        if let caption = Self.trimmedNonEmpty(captionTarget) {
            lines.append(caption)
        }
        for dialogue in dialogues {
            let character = dialogue.character.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = dialogue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !character.isEmpty, !text.isEmpty else { continue }
            lines.append("\(character): \(text)")
        }
        if lines.isEmpty, fallbackScript, let script = Self.trimmedNonEmpty(scriptTargetLanguage) {
            lines.append(script)
        }
        return lines.joined(separator: "\n")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum StorySceneContentMode: String, Codable, Equatable {
    case prose
    case panel
}

struct SceneDialogue: Codable, Identifiable, Equatable {
    var id = UUID()
    var character: String
    var text: String
    var textEnglish: String?
    var audioUrl: String?

    enum CodingKeys: String, CodingKey {
        case character, speaker, name, text
        case textEnglish
        case textEnglishSnake = "text_english"
        case audioUrl
        case audioUrlSnake = "audio_url"
    }

    init(character: String, text: String, textEnglish: String? = nil, audioUrl: String? = nil) {
        self.character = character
        self.text = text
        self.textEnglish = textEnglish
        self.audioUrl = audioUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        character = (try? c.decode(String.self, forKey: .character))
            ?? (try? c.decode(String.self, forKey: .speaker))
            ?? (try? c.decode(String.self, forKey: .name))
            ?? "NARRATOR"
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        textEnglish = (try? c.decode(String.self, forKey: .textEnglish))
            ?? (try? c.decode(String.self, forKey: .textEnglishSnake))
        audioUrl = (try? c.decode(String.self, forKey: .audioUrl))
            ?? (try? c.decode(String.self, forKey: .audioUrlSnake))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(character, forKey: .character)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(textEnglish, forKey: .textEnglish)
        try c.encodeIfPresent(audioUrl, forKey: .audioUrl)
    }
}

struct StoryLayout: Codable, Equatable {
    var pages: [StoryPage]
    var flatSequence: [PanelLayout]
    var chapterFlatOffsets: [Int]

    enum CodingKeys: String, CodingKey {
        case pages
        case flatSequence = "flat_sequence"
        case flatSequenceCamel = "flatSequence"
        case chapterFlatOffsets = "chapter_flat_offsets"
        case chapterFlatOffsetsCamel = "chapterFlatOffsets"
    }

    init(pages: [StoryPage] = [], flatSequence: [PanelLayout] = [], chapterFlatOffsets: [Int] = []) {
        self.pages = pages
        self.flatSequence = flatSequence
        self.chapterFlatOffsets = chapterFlatOffsets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pages = (try? c.decode([StoryPage].self, forKey: .pages)) ?? []
        flatSequence = (try? c.decode([PanelLayout].self, forKey: .flatSequence))
            ?? (try? c.decode([PanelLayout].self, forKey: .flatSequenceCamel))
            ?? []
        chapterFlatOffsets = (try? c.decode([Int].self, forKey: .chapterFlatOffsets))
            ?? (try? c.decode([Int].self, forKey: .chapterFlatOffsetsCamel))
            ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pages, forKey: .pages)
        try c.encode(flatSequence, forKey: .flatSequence)
        try c.encode(chapterFlatOffsets, forKey: .chapterFlatOffsets)
    }
}

struct StoryPage: Codable, Identifiable, Equatable {
    var id = UUID()
    var chapterIndex: Int?
    var sceneIndex: Int?
    var canvases: [StoryCanvas]

    enum CodingKeys: String, CodingKey {
        case chapterIndex = "chapter_index"
        case chapterIndexCamel = "chapterIndex"
        case sceneIndex = "scene_index"
        case sceneIndexCamel = "sceneIndex"
        case canvases
    }

    init(chapterIndex: Int? = nil, sceneIndex: Int? = nil, canvases: [StoryCanvas] = []) {
        self.chapterIndex = chapterIndex
        self.sceneIndex = sceneIndex
        self.canvases = canvases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chapterIndex = (try? c.decode(Int.self, forKey: .chapterIndex))
            ?? (try? c.decode(Int.self, forKey: .chapterIndexCamel))
        sceneIndex = (try? c.decode(Int.self, forKey: .sceneIndex))
            ?? (try? c.decode(Int.self, forKey: .sceneIndexCamel))
        canvases = (try? c.decode([StoryCanvas].self, forKey: .canvases)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(chapterIndex, forKey: .chapterIndex)
        try c.encodeIfPresent(sceneIndex, forKey: .sceneIndex)
        try c.encode(canvases, forKey: .canvases)
    }
}

struct StoryCanvas: Codable, Identifiable, Equatable {
    var id = UUID()
    var panels: [PanelLayout]

    enum CodingKeys: String, CodingKey {
        case panels
    }

    init(panels: [PanelLayout] = []) {
        self.panels = panels
    }
}

struct PanelLayout: Codable, Identifiable, Equatable {
    var id: String { "\(chapterIndex)-\(sceneIndex)-\(x)-\(y)-\(width)-\(height)" }
    var chapterIndex: Int
    var sceneIndex: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var cropRegion: CropRegion

    enum CodingKeys: String, CodingKey {
        case chapterIndex = "chapter_index"
        case chapterIndexCamel = "chapterIndex"
        case sceneIndex = "scene_index"
        case sceneIndexCamel = "sceneIndex"
        case x, y, width, height
        case cropRegion = "crop_region"
        case cropRegionCamel = "cropRegion"
    }

    init(
        chapterIndex: Int,
        sceneIndex: Int,
        x: Double = 0,
        y: Double = 0,
        width: Double = 1,
        height: Double = 1,
        cropRegion: CropRegion = .full
    ) {
        self.chapterIndex = chapterIndex
        self.sceneIndex = sceneIndex
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cropRegion = cropRegion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chapterIndex = (try? c.decode(Int.self, forKey: .chapterIndex))
            ?? (try? c.decode(Int.self, forKey: .chapterIndexCamel))
            ?? 0
        sceneIndex = (try? c.decode(Int.self, forKey: .sceneIndex))
            ?? (try? c.decode(Int.self, forKey: .sceneIndexCamel))
            ?? 0
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0
        width = (try? c.decode(Double.self, forKey: .width)) ?? 1
        height = (try? c.decode(Double.self, forKey: .height)) ?? 1
        cropRegion = (try? c.decode(CropRegion.self, forKey: .cropRegion))
            ?? (try? c.decode(CropRegion.self, forKey: .cropRegionCamel))
            ?? .full
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chapterIndex, forKey: .chapterIndex)
        try c.encode(sceneIndex, forKey: .sceneIndex)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(cropRegion, forKey: .cropRegion)
    }
}

enum CropRegion: String, Codable, Equatable {
    case full
    case center
    case centre
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case topHalf
    case bottomHalf
}

struct ReadingMatterPage: Codable, Identifiable, Equatable {
    var id: String
    var placement: String?
    var titleTarget: String?
    var titleNative: String?
    var bodyTarget: String?
    var bodyNative: String?
    var imageUrl: String?
    var audioUrl: String?
    var nativeAudioUrl: String?
    var wordTimings: [WordTiming]?
    var nativeWordTimings: [WordTiming]?

    enum CodingKeys: String, CodingKey {
        case id, placement
        case titleTarget
        case titleNative
        case bodyTarget
        case bodyNative
        case imageUrl = "image_url"
        case imageUrlCamel = "imageUrl"
        case coverUrl = "cover_url"
        case coverUrlCamel = "coverUrl"
        case audioUrl = "audio_url"
        case audioUrlCamel = "audioUrl"
        case targetAudioUrl = "target_audio_url"
        case targetAudioUrlCamel = "targetAudioUrl"
        case nativeAudioUrl = "native_audio_url"
        case nativeAudioUrlCamel = "nativeAudioUrl"
        case wordTimings = "word_timings"
        case wordTimingsCamel = "wordTimings"
        case nativeWordTimings = "native_word_timings"
        case nativeWordTimingsCamel = "nativeWordTimings"
    }

    init(
        id: String,
        placement: String? = nil,
        titleTarget: String? = nil,
        titleNative: String? = nil,
        bodyTarget: String? = nil,
        bodyNative: String? = nil,
        imageUrl: String? = nil,
        audioUrl: String? = nil,
        nativeAudioUrl: String? = nil,
        wordTimings: [WordTiming]? = nil,
        nativeWordTimings: [WordTiming]? = nil
    ) {
        self.id = id
        self.placement = placement
        self.titleTarget = titleTarget
        self.titleNative = titleNative
        self.bodyTarget = bodyTarget
        self.bodyNative = bodyNative
        self.imageUrl = imageUrl
        self.audioUrl = audioUrl
        self.nativeAudioUrl = nativeAudioUrl
        self.wordTimings = wordTimings
        self.nativeWordTimings = nativeWordTimings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        placement = try? container.decode(String.self, forKey: .placement)
        titleTarget = try? container.decode(String.self, forKey: .titleTarget)
        titleNative = try? container.decode(String.self, forKey: .titleNative)
        bodyTarget = try? container.decode(String.self, forKey: .bodyTarget)
        bodyNative = try? container.decode(String.self, forKey: .bodyNative)
        imageUrl = (try? container.decode(String.self, forKey: .imageUrl))
            ?? (try? container.decode(String.self, forKey: .imageUrlCamel))
            ?? (try? container.decode(String.self, forKey: .coverUrl))
            ?? (try? container.decode(String.self, forKey: .coverUrlCamel))
        audioUrl = (try? container.decode(String.self, forKey: .audioUrl))
            ?? (try? container.decode(String.self, forKey: .audioUrlCamel))
            ?? (try? container.decode(String.self, forKey: .targetAudioUrl))
            ?? (try? container.decode(String.self, forKey: .targetAudioUrlCamel))
        nativeAudioUrl = (try? container.decode(String.self, forKey: .nativeAudioUrl))
            ?? (try? container.decode(String.self, forKey: .nativeAudioUrlCamel))
        wordTimings = (try? container.decode([WordTiming].self, forKey: .wordTimings))
            ?? (try? container.decode([WordTiming].self, forKey: .wordTimingsCamel))
        nativeWordTimings = (try? container.decode([WordTiming].self, forKey: .nativeWordTimings))
            ?? (try? container.decode([WordTiming].self, forKey: .nativeWordTimingsCamel))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(placement, forKey: .placement)
        try container.encodeIfPresent(titleTarget, forKey: .titleTarget)
        try container.encodeIfPresent(titleNative, forKey: .titleNative)
        try container.encodeIfPresent(bodyTarget, forKey: .bodyTarget)
        try container.encodeIfPresent(bodyNative, forKey: .bodyNative)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(audioUrl, forKey: .audioUrl)
        try container.encodeIfPresent(nativeAudioUrl, forKey: .nativeAudioUrl)
        try container.encodeIfPresent(wordTimings, forKey: .wordTimings)
        try container.encodeIfPresent(nativeWordTimings, forKey: .nativeWordTimings)
    }

    func audioUrlForPlayback(preferNative: Bool) -> String? {
        let preferred = preferNative ? nativeAudioUrl : audioUrl
        let fallback = preferNative ? audioUrl : nativeAudioUrl
        return Self.trimmedNonEmpty(preferred) ?? Self.trimmedNonEmpty(fallback)
    }

    func wordTimingsForPlayback(preferNative: Bool) -> [WordTiming] {
        let preferred = preferNative ? nativeWordTimings : wordTimings
        let fallback = preferNative ? wordTimings : nativeWordTimings
        return preferred ?? fallback ?? []
    }

    func hasGeneratedAudio(preferNative: Bool) -> Bool {
        audioUrlForPlayback(preferNative: preferNative) != nil
    }

    var isBackMatter: Bool {
        let placementKey = placement?.readingMatterPlacementKey ?? ""
        if placementKey.contains("front") || placementKey.contains("about") || placementKey.contains("intro") {
            return false
        }
        if placementKey.contains("back")
            || placementKey.contains("appendix")
            || placementKey.contains("after")
            || placementKey.contains("end")
            || placementKey.contains("post")
            || placementKey.contains("credit") {
            return true
        }

        let identityKey = [
            id,
            titleTarget,
            titleNative
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .readingMatterPlacementKey

        return identityKey.contains("back")
            || identityKey.contains("appendix")
            || identityKey.contains("credit")
            || identityKey.contains("afterword")
            || identityKey.contains("glossary")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum StoryReadingSpineItem: Identifiable, Equatable {
    case cover
    case readingMatterPage(index: Int, id: String)
    case chapter(index: Int)
    case scene(chapterIndex: Int, sceneIndex: Int)

    var id: String {
        switch self {
        case .cover:
            return "cover"
        case .readingMatterPage(let index, let id):
            return "matter-\(index)-\(id)"
        case .chapter(let index):
            return "chapter-\(index)"
        case .scene(let chapterIndex, let sceneIndex):
            return "scene-\(chapterIndex)-\(sceneIndex)"
        }
    }
}

enum StoryReadingSpineMode {
    case storyBook
    case audioBook
    case pictureBook
    case comicBook
    case dialogStory
}

struct StoryReadingSpine {
    var items: [StoryReadingSpineItem]

    static func make(for story: Story, mode: StoryReadingSpineMode = .storyBook) -> StoryReadingSpine {
        var items: [StoryReadingSpineItem] = [.cover]
        let matterPages = story.readingMatterPages.enumerated().map { index, page in
            (index: index, page: page)
        }
        let frontMatter = matterPages.filter { !$0.page.isBackMatter }
        let backMatter = matterPages.filter { $0.page.isBackMatter }

        items.append(contentsOf: frontMatter.map { index, page in
            .readingMatterPage(index: index, id: page.id)
        })

        switch mode {
        case .storyBook:
            items.append(contentsOf: story.chapters.indices.map { .chapter(index: $0) })
        case .audioBook:
            items.append(contentsOf: story.chapters.indices.map { .chapter(index: $0) })
            items.append(contentsOf: sceneItems(for: story, useLayoutOrder: false))
        case .dialogStory:
            for chapterIndex in story.chapters.indices {
                items.append(.chapter(index: chapterIndex))
                items.append(contentsOf: sceneItems(
                    for: story,
                    chapterIndex: chapterIndex,
                    useLayoutOrder: false
                ))
            }
        case .pictureBook, .comicBook:
            items.append(contentsOf: sceneItems(for: story, useLayoutOrder: true))
        }

        items.append(contentsOf: backMatter.map { index, page in
            .readingMatterPage(index: index, id: page.id)
        })

        return StoryReadingSpine(items: items)
    }

    var chapterIndices: [Int] {
        items.compactMap {
            if case .chapter(let index) = $0 { return index }
            return nil
        }
    }

    var sceneItems: [StoryReadingSpineItem] {
        items.filter {
            if case .scene = $0 { return true }
            return false
        }
    }

    private static func sceneItems(for story: Story, useLayoutOrder: Bool) -> [StoryReadingSpineItem] {
        sceneItems(for: story, chapterIndex: nil, useLayoutOrder: useLayoutOrder)
    }

    private static func sceneItems(
        for story: Story,
        chapterIndex: Int?,
        useLayoutOrder: Bool
    ) -> [StoryReadingSpineItem] {
        if useLayoutOrder {
            let panels = story.storyLayout?.flatSequence ?? []
            let layoutItems = panels
                .filter { chapterIndex == nil || $0.chapterIndex == chapterIndex }
                .map {
                    StoryReadingSpineItem.scene(chapterIndex: $0.chapterIndex, sceneIndex: $0.sceneIndex)
                }
            if !layoutItems.isEmpty {
                return uniqueSceneItems(layoutItems)
            }
        }

        let chapterIndices = chapterIndex.map { [$0] } ?? Array(story.chapters.indices)
        let chapterOrderedItems = chapterIndices.flatMap { index in
            story.chapters[index].scenes
                .sorted { $0.sceneIndex < $1.sceneIndex }
                .map { StoryReadingSpineItem.scene(chapterIndex: index, sceneIndex: $0.sceneIndex) }
        }
        return uniqueSceneItems(chapterOrderedItems)
    }

    private static func uniqueSceneItems(_ items: [StoryReadingSpineItem]) -> [StoryReadingSpineItem] {
        var seen = Set<String>()
        return items.filter { item in
            guard !seen.contains(item.id) else { return false }
            seen.insert(item.id)
            return true
        }
    }
}

enum StoryReadingSpineTitles {
    static func readingMatterTitle(for page: ReadingMatterPage, preferNative: Bool = true) -> String {
        if preferNative, let title = page.titleNative?.spineTrimmedNilIfEmpty {
            return title
        }
        if let title = page.titleTarget?.spineTrimmedNilIfEmpty {
            return title
        }
        return page.id
    }

    static func chapterTitle(for chapter: StoryChapter, index: Int) -> String {
        if let title = chapter.titleTargetLanguage.spineTrimmedNilIfEmpty {
            return title
        }
        if chapter.isPrologue { return "Prologue" }
        if chapter.isEpilogue { return "Epilogue" }
        return "Chapter \(index + 1)"
    }

    static func chapterKindLabel(
        for chapter: StoryChapter,
        index: Int,
        regularChapterCount: Int
    ) -> String {
        let titlePart = chapter.titleTargetLanguage.spineTrimmedNilIfEmpty.map { " · \($0)" } ?? ""
        if chapter.isPrologue { return "Prologue\(titlePart)" }
        if chapter.isEpilogue { return "Epilogue\(titlePart)" }
        return "Chapter \(chapter.chapterNumber) of \(regularChapterCount)\(titlePart)"
    }

    static func chapterPrefix(for chapter: StoryChapter, index: Int) -> String {
        let titlePart = chapter.titleTargetLanguage.spineTrimmedNilIfEmpty.map { " · \($0)" } ?? ""
        if chapter.isPrologue { return "Prologue\(titlePart) · " }
        if chapter.isEpilogue { return "Epilogue\(titlePart) · " }
        return "Ch \(index + 1)\(titlePart) · "
    }

    static func sceneTitleFromBreakdown(story: Story, chapterIndex: Int, sceneIndex: Int) -> String? {
        guard let json = story.sceneBreakdownJSON,
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chapters = root["chapters"] as? [[String: Any]],
              chapters.indices.contains(chapterIndex),
              let scenes = chapters[chapterIndex]["scenes"] as? [[String: Any]],
              scenes.indices.contains(sceneIndex) else {
            return nil
        }

        let scene = scenes[sceneIndex]
        if let title = scene["title"] as? String, let trimmed = title.spineTrimmedNilIfEmpty {
            return trimmed
        }
        if let purpose = scene["purpose"] as? String, let trimmed = purpose.spineTrimmedNilIfEmpty {
            return trimmed
        }
        if let beats = scene["beats"] as? [Any], let first = beats.first {
            let beat = "\(first)".spineTrimmedNilIfEmpty
            if let beat { return beat }
        }
        return nil
    }

    static func sceneTitle(
        from scene: StoryScene,
        sceneIndex: Int,
        breakdownTitle: String? = nil
    ) -> String {
        if let breakdownTitle = breakdownTitle?.spineTrimmedNilIfEmpty {
            return breakdownTitle
        }
        if let caption = scene.captionTarget?.spineTrimmedNilIfEmpty, caption.count <= 80 {
            return caption
        }
        if let firstLine = scene.scriptTargetLanguage?
            .components(separatedBy: .newlines)
            .first?
            .spineTrimmedNilIfEmpty {
            return truncate(firstLine, maxLength: 80)
        }
        return "Scene \(sceneIndex + 1)"
    }

    static func sceneContextLabel(
        chapter: StoryChapter?,
        chapterIndex: Int,
        sceneIndex: Int
    ) -> String {
        guard let chapter else { return "Scene \(sceneIndex + 1)" }
        return "\(chapterPrefix(for: chapter, index: chapterIndex))Scene \(sceneIndex + 1)"
    }

    static func spinePrimaryTitle(
        for item: StoryReadingSpineItem,
        story: Story,
        adapter: StoryReaderDataAdapter
    ) -> String {
        switch item {
        case .cover:
            return story.title
        case .readingMatterPage:
            if let page = adapter.readingMatterPage(for: item) {
                return readingMatterTitle(for: page)
            }
            return "Reading Matter"
        case .chapter(let index):
            if let chapter = adapter.chapter(for: item) {
                return chapterTitle(for: chapter, index: index)
            }
            return "Chapter \(index + 1)"
        case .scene(let chapterIndex, let sceneIndex):
            if let scene = adapter.scene(for: item) {
                let breakdown = sceneTitleFromBreakdown(
                    story: story,
                    chapterIndex: chapterIndex,
                    sceneIndex: sceneIndex
                )
                return sceneTitle(from: scene, sceneIndex: sceneIndex, breakdownTitle: breakdown)
            }
            return "Scene \(sceneIndex + 1)"
        }
    }

    static func spineContextLabel(
        for item: StoryReadingSpineItem,
        story: Story,
        adapter: StoryReaderDataAdapter
    ) -> String {
        switch item {
        case .cover:
            return "Cover"
        case .readingMatterPage:
            return "Reading Matter"
        case .chapter(let chapterIndex):
            guard let chapter = adapter.chapter(for: item) else { return "Chapter" }
            let regularCount = story.chapters.filter { !$0.isPrologue && !$0.isEpilogue }.count
            return chapterKindLabel(for: chapter, index: chapterIndex, regularChapterCount: regularCount)
        case .scene(let chapterIndex, let sceneIndex):
            let chapter = story.chapters[safeSpineTitle: chapterIndex]
            return sceneContextLabel(chapter: chapter, chapterIndex: chapterIndex, sceneIndex: sceneIndex)
        }
    }

    static func spinePositionLabel(index: Int, total: Int, context: String) -> String {
        "\(index + 1) of \(total) · \(context)"
    }

    private static func truncate(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        let end = value.index(value.startIndex, offsetBy: max(0, maxLength - 1))
        return String(value[..<end]) + "…"
    }
}

private extension String {
    var readingMatterPlacementKey: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }

    var spineTrimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Collection {
    subscript(safeSpineTitle index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
