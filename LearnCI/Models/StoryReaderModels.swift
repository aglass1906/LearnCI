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

    enum CodingKeys: String, CodingKey {
        case id, placement
        case titleTarget
        case titleNative
        case bodyTarget
        case bodyNative
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
        case .audioBook, .dialogStory:
            items.append(contentsOf: story.chapters.indices.map { .chapter(index: $0) })
            items.append(contentsOf: sceneItems(for: story, useLayoutOrder: false))
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
        if useLayoutOrder {
            let panels = story.storyLayout?.flatSequence ?? []
            let layoutItems = panels.map {
                StoryReadingSpineItem.scene(chapterIndex: $0.chapterIndex, sceneIndex: $0.sceneIndex)
            }
            if !layoutItems.isEmpty {
                return uniqueSceneItems(layoutItems)
            }
        }

        let chapterOrderedItems = story.chapters.indices.flatMap { chapterIndex in
            story.chapters[chapterIndex].scenes
                .sorted { $0.sceneIndex < $1.sceneIndex }
                .map { StoryReadingSpineItem.scene(chapterIndex: chapterIndex, sceneIndex: $0.sceneIndex) }
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

private extension ReadingMatterPage {
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
}

private extension String {
    var readingMatterPlacementKey: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
