import Foundation

struct StoryScene: Codable, Identifiable, Equatable {
    var id: String { "\(sceneIndex)" }
    var sceneIndex: Int
    var title: String?
    var characters: [String]
    var imageUrl: String?
    var contentMode: StorySceneContentMode?
    var cropRegion: CropRegion?
    var byLanguage: [String: SceneLanguageData]

    enum CodingKeys: String, CodingKey {
        case sceneIndex
        case title
        case characters
        case imageUrl
        case contentMode
        case cropRegion
        case byLanguage
    }

    init(
        sceneIndex: Int,
        title: String? = nil,
        characters: [String] = [],
        imageUrl: String? = nil,
        contentMode: StorySceneContentMode? = nil,
        cropRegion: CropRegion? = nil,
        byLanguage: [String: SceneLanguageData] = [:]
    ) {
        self.sceneIndex = sceneIndex
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).spineTrimmedNilIfEmpty
        self.characters = characters
        self.imageUrl = imageUrl
        self.contentMode = contentMode
        self.cropRegion = cropRegion
        self.byLanguage = Dictionary(uniqueKeysWithValues: byLanguage.map { key, value in
            (key.lowercased(), value)
        })
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sceneIndex = (try? c.decode(Int.self, forKey: .sceneIndex)) ?? 0
        title = (try? c.decode(String.self, forKey: .title))?.spineTrimmedNilIfEmpty
        characters = (try? c.decode([String].self, forKey: .characters)) ?? []
        imageUrl = try? c.decode(String.self, forKey: .imageUrl)
        contentMode = try? c.decode(StorySceneContentMode.self, forKey: .contentMode)
        cropRegion = try? c.decode(CropRegion.self, forKey: .cropRegion)
        let raw = (try? c.decode([String: SceneLanguageData].self, forKey: .byLanguage)) ?? [:]
        byLanguage = Dictionary(uniqueKeysWithValues: raw.map { key, value in
            (key.lowercased(), value)
        })
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sceneIndex, forKey: .sceneIndex)
        try c.encodeIfPresent(title, forKey: .title)
        if !characters.isEmpty { try c.encode(characters, forKey: .characters) }
        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try c.encodeIfPresent(contentMode, forKey: .contentMode)
        try c.encodeIfPresent(cropRegion, forKey: .cropRegion)
        if !byLanguage.isEmpty { try c.encode(byLanguage, forKey: .byLanguage) }
    }

    func languageDataFor(_ langCode: String) -> SceneLanguageData? {
        byLanguage[langCode.lowercased()]
    }

    func captionFor(_ langCode: String) -> String {
        languageDataFor(langCode)?.caption ?? ""
    }

    func scriptFor(_ langCode: String) -> String? {
        languageDataFor(langCode)?.script?.canonicalTrimmedNil
    }

    func audioUrlForLanguage(_ langCode: String) -> String? {
        languageDataFor(langCode)?.audioUrl?.canonicalTrimmedNil
    }

    func wordTimingsFor(_ langCode: String) -> [WordTiming] {
        languageDataFor(langCode)?.wordTimings ?? []
    }

    func audioDurationMsFor(_ langCode: String) -> Int {
        languageDataFor(langCode)?.audioDurationMs ?? 0
    }

    func dialoguesFor(_ langCode: String) -> [SceneDialogue] {
        languageDataFor(langCode)?.dialogues ?? []
    }

    func spokenTranscriptText(preferences: StoryPreferences, targetCode: String) -> String {
        if preferences.storyType == .comicBook || contentMode == .panel {
            let transcript = captionAndDialogueTranscript(langCode: targetCode, fallbackScript: true)
            if !transcript.isEmpty { return transcript }
        }

        if preferences.audioStyle == .dramatized,
           let script = scriptFor(targetCode) {
            return script
        }

        let caption = captionFor(targetCode).trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
            return caption
        }

        return captionAndDialogueTranscript(langCode: targetCode, fallbackScript: true)
    }

    func transcriptSegments(preferences: StoryPreferences, targetCode: String) -> [StorySegmentTiming] {
        let text = spokenTranscriptText(preferences: preferences, targetCode: targetCode)
        let timings = wordTimingsFor(targetCode)
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

    private func captionAndDialogueTranscript(langCode: String, fallbackScript: Bool) -> String {
        var lines: [String] = []
        let caption = captionFor(langCode).trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
            lines.append(caption)
        }
        for dialogue in dialoguesFor(langCode) {
            let character = dialogue.character.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = dialogue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !character.isEmpty, !text.isEmpty else { continue }
            lines.append("\(character): \(text)")
        }
        if lines.isEmpty, fallbackScript, let script = scriptFor(langCode) {
            lines.append(script)
        }
        return lines.joined(separator: "\n")
    }
}

struct SceneLanguageData: Codable, Equatable {
    var caption: String = ""
    var script: String?
    var audioUrl: String?
    var wordTimings: [WordTiming] = []
    var audioDurationMs: Int = 0
    var dialogues: [SceneDialogue] = []

    enum CodingKeys: String, CodingKey {
        case caption
        case script
        case audioUrl
        case wordTimings
        case audioDurationMs
        case dialogues
    }

    init(
        caption: String = "",
        script: String? = nil,
        audioUrl: String? = nil,
        wordTimings: [WordTiming] = [],
        audioDurationMs: Int = 0,
        dialogues: [SceneDialogue] = []
    ) {
        self.caption = caption
        self.script = script
        self.audioUrl = audioUrl
        self.wordTimings = wordTimings
        self.audioDurationMs = audioDurationMs
        self.dialogues = dialogues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        caption = (try? container.decode(String.self, forKey: .caption)) ?? ""
        script = try? container.decode(String.self, forKey: .script)
        audioUrl = try? container.decode(String.self, forKey: .audioUrl)
        wordTimings = (try? container.decode([WordTiming].self, forKey: .wordTimings)) ?? []
        audioDurationMs = (try? container.decode(Int.self, forKey: .audioDurationMs)) ?? 0
        dialogues = (try? container.decode([SceneDialogue].self, forKey: .dialogues)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(caption, forKey: .caption)
        try container.encodeIfPresent(script, forKey: .script)
        try container.encodeIfPresent(audioUrl, forKey: .audioUrl)
        if !wordTimings.isEmpty {
            try container.encode(wordTimings, forKey: .wordTimings)
        }
        if audioDurationMs > 0 {
            try container.encode(audioDurationMs, forKey: .audioDurationMs)
        }
        if !dialogues.isEmpty {
            try container.encode(dialogues, forKey: .dialogues)
        }
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
    var audioUrl: String?

    enum CodingKeys: String, CodingKey {
        case character, text
        case audioUrl
    }

    init(character: String, text: String, audioUrl: String? = nil) {
        self.character = character
        self.text = text
        self.audioUrl = audioUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        character = (try? c.decode(String.self, forKey: .character)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        audioUrl = try? c.decode(String.self, forKey: .audioUrl)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(character, forKey: .character)
        try c.encode(text, forKey: .text)
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
    var placement: ReadingMatterPlacement
    var kind: ReadingMatterKind
    var byLanguage: [String: ReadingMatterPageLanguageData]

    enum CodingKeys: String, CodingKey {
        case id, placement, kind, byLanguage

        var stringValue: String {
            switch self {
            case .id:
                return "id"
            case .placement:
                return "placement"
            case .kind:
                return "kind"
            case .byLanguage:
                return ["by", "language"].joined(separator: "_")
            }
        }

        init?(stringValue: String) {
            switch stringValue {
            case "id":
                self = .id
            case "placement":
                self = .placement
            case "kind":
                self = .kind
            case ["by", "language"].joined(separator: "_"):
                self = .byLanguage
            default:
                return nil
            }
        }

        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(
        id: String,
        placement: ReadingMatterPlacement = .beforeChapters,
        kind: ReadingMatterKind = .prose,
        byLanguage: [String: ReadingMatterPageLanguageData] = [:]
    ) {
        self.id = id
        self.placement = placement
        self.kind = kind
        self.byLanguage = Dictionary(uniqueKeysWithValues: byLanguage.map { key, value in
            (key.lowercased(), value)
        })
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        placement = (try? container.decode(ReadingMatterPlacement.self, forKey: .placement)) ?? .beforeChapters
        kind = (try? container.decode(ReadingMatterKind.self, forKey: .kind)) ?? .prose
        let raw = (try? container.decode([String: ReadingMatterPageLanguageData].self, forKey: .byLanguage)) ?? [:]
        byLanguage = Dictionary(uniqueKeysWithValues: raw.map { key, value in
            (key.lowercased(), value)
        })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(placement, forKey: .placement)
        if kind != .prose { try container.encode(kind, forKey: .kind) }
        if !byLanguage.isEmpty { try container.encode(byLanguage, forKey: .byLanguage) }
    }

    func languageDataFor(_ langCode: String) -> ReadingMatterPageLanguageData? {
        byLanguage[langCode.lowercased()]
    }

    func titleFor(_ langCode: String) -> String {
        languageDataFor(langCode)?.title ?? ""
    }

    func bodyFor(_ langCode: String) -> String {
        languageDataFor(langCode)?.body ?? ""
    }

    func audioUrlFor(_ langCode: String) -> String? {
        languageDataFor(langCode)?.audioUrl?.canonicalTrimmedNil
    }

    func wordTimingsFor(_ langCode: String) -> [WordTiming] {
        languageDataFor(langCode)?.wordTimings ?? []
    }

    func audioDurationMsFor(_ langCode: String) -> Int {
        languageDataFor(langCode)?.audioDurationMs ?? 0
    }

    func structuredRowsJsonFor(_ langCode: String) -> String? {
        languageDataFor(langCode)?.structuredRowsJson?.canonicalTrimmedNil
    }

    func hasContentFor(targetCode: String, nativeCode: String) -> Bool {
        !bodyFor(targetCode).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyFor(nativeCode).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func appearsOnReadingSpineFor(targetCode: String, nativeCode: String) -> Bool {
        hasContentFor(targetCode: targetCode, nativeCode: nativeCode)
            || !titleFor(targetCode).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !titleFor(nativeCode).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func bodyWordTimingsFor(_ langCode: String) -> [WordTiming] {
        WordTiming.bodyTimings(
            fullTimings: wordTimingsFor(langCode),
            skippingLeadingSpokenText: titleFor(langCode)
        )
    }

    func characterRowsFor(_ langCode: String) -> [CharacterPageRow] {
        guard kind == .characters else { return [] }
        return Self.decodeRows(from: structuredRowsJsonFor(langCode)).map(CharacterPageRow.init(json:))
    }

    func glossaryRowsFor(_ langCode: String) -> [GlossaryPageRow] {
        guard kind == .glossary else { return [] }
        return Self.decodeRows(from: structuredRowsJsonFor(langCode)).map(GlossaryPageRow.init(json:))
    }

    private static func decodeRows(from raw: String?) -> [[String: Any]] {
        guard let raw, let data = raw.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let envelope = decoded as? [String: Any], let rows = envelope["rows"] as? [[String: Any]] {
            return rows
        }
        return (decoded as? [[String: Any]]) ?? []
    }
}

enum ReadingMatterPlacement: String, Codable, Equatable {
    case beforeChapters
    case afterChapters
}

enum ReadingMatterKind: String, Codable, Equatable {
    case prose
    case characters
    case glossary
}

struct ReadingMatterPageLanguageData: Codable, Equatable {
    var title: String = ""
    var body: String = ""
    var audioUrl: String?
    var wordTimings: [WordTiming] = []
    var audioDurationMs: Int?
    var structuredRowsJson: String?

    enum CodingKeys: String, CodingKey {
        case title, body, audioUrl, wordTimings, audioDurationMs, structuredRowsJson

        var stringValue: String {
            switch self {
            case .title:
                return "title"
            case .body:
                return "body"
            case .audioUrl:
                return ["audio", "url"].joined(separator: "_")
            case .wordTimings:
                return ["word", "timings"].joined(separator: "_")
            case .audioDurationMs:
                return ["audio", "duration", "ms"].joined(separator: "_")
            case .structuredRowsJson:
                return ["structured", "rows"].joined(separator: "_")
            }
        }

        init?(stringValue: String) {
            switch stringValue {
            case "title":
                self = .title
            case "body":
                self = .body
            case ["audio", "url"].joined(separator: "_"):
                self = .audioUrl
            case ["word", "timings"].joined(separator: "_"):
                self = .wordTimings
            case ["audio", "duration", "ms"].joined(separator: "_"):
                self = .audioDurationMs
            case ["structured", "rows"].joined(separator: "_"):
                self = .structuredRowsJson
            default:
                return nil
            }
        }

        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(
        title: String = "",
        body: String = "",
        audioUrl: String? = nil,
        wordTimings: [WordTiming] = [],
        audioDurationMs: Int? = nil,
        structuredRowsJson: String? = nil
    ) {
        self.title = title
        self.body = body
        self.audioUrl = audioUrl
        self.wordTimings = wordTimings
        self.audioDurationMs = audioDurationMs
        self.structuredRowsJson = structuredRowsJson
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        body = (try? container.decode(String.self, forKey: .body)) ?? ""
        audioUrl = try? container.decode(String.self, forKey: .audioUrl)
        wordTimings = (try? container.decode([WordTiming].self, forKey: .wordTimings)) ?? []
        audioDurationMs = try? container.decode(Int.self, forKey: .audioDurationMs)
        if let string = try? container.decode(String.self, forKey: .structuredRowsJson) {
            structuredRowsJson = string
        } else if let value = try? container.decode(StructuredRowsValue.self, forKey: .structuredRowsJson) {
            structuredRowsJson = value.jsonString
        } else {
            structuredRowsJson = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        if !body.isEmpty { try container.encode(body, forKey: .body) }
        try container.encodeIfPresent(audioUrl, forKey: .audioUrl)
        if !wordTimings.isEmpty { try container.encode(wordTimings, forKey: .wordTimings) }
        try container.encodeIfPresent(audioDurationMs, forKey: .audioDurationMs)
        if let structuredRowsJson,
           let data = structuredRowsJson.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object),
           let encoded = try? JSONSerialization.data(withJSONObject: object),
           let value = try? JSONDecoder().decode(StructuredRowsValue.self, from: encoded) {
            try container.encode(value, forKey: .structuredRowsJson)
        }
    }
}

private enum StructuredRowsValue: Codable, Equatable {
    case object([String: StructuredRowsValue])
    case array([StructuredRowsValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var jsonString: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: StructuredRowsValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([StructuredRowsValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct CharacterPageRow: Equatable {
    var name: String
    var role: String
    var bio: String
    var relationships: String

    init(json: [String: Any]) {
        name = json["name"] as? String ?? ""
        role = json["role"] as? String ?? ""
        bio = json["bio"] as? String ?? ""
        relationships = json["relationships"] as? String ?? ""
    }
}

struct GlossaryPageRow: Equatable {
    var targetWord: String
    var nativeGloss: String
    var partOfSpeech: String
    var exampleTarget: String
    var exampleNative: String
    var firstChapterIndex: Int?

    init(json: [String: Any]) {
        targetWord = json["targetWord"] as? String ?? ""
        nativeGloss = json["nativeGloss"] as? String ?? ""
        partOfSpeech = json["partOfSpeech"] as? String ?? ""
        exampleTarget = json["exampleTarget"] as? String ?? ""
        exampleNative = json["exampleNative"] as? String ?? ""
        firstChapterIndex = json["firstChapterIndex"] as? Int
    }
}

enum StoryReadingSpineItem: Identifiable, Equatable {
    case cover
    case readingMatterPage(index: Int, id: String)
    case chapter(index: Int)
    case scene(chapterIndex: Int, sceneIndex: Int)
    case chapterQuiz(index: Int)
    case chapterVocabulary(index: Int)

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
        case .chapterQuiz(let index):
            return "quiz-\(index)"
        case .chapterVocabulary(let index):
            return "vocab-\(index)"
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
        let positionedMatter = story.readingMatterPages.enumerated()
            .filter { _, page in
                page.appearsOnReadingSpineFor(
                    targetCode: story.targetLanguageCode,
                    nativeCode: story.nativeLanguageCode
                )
            }
            .map { index, page in
                PositionedReadingMatter(
                    index: index,
                    page: page,
                    position: readingMatterPosition(for: page)
                )
            }
            .sorted(by: compareReadingMatter)

        var mainItems: [StoryReadingSpineItem] = []
        switch mode {
        case .storyBook:
            for index in story.chapters.indices {
                mainItems.append(.chapter(index: index))
                mainItems.append(contentsOf: chapterSupplementItems(for: story, chapterIndex: index))
            }
        case .audioBook:
            for index in story.chapters.indices {
                mainItems.append(.chapter(index: index))
                mainItems.append(contentsOf: chapterSupplementItems(for: story, chapterIndex: index))
            }
            mainItems.append(contentsOf: sceneItems(for: story, useLayoutOrder: false))
        case .dialogStory:
            for chapterIndex in story.chapters.indices {
                mainItems.append(.chapter(index: chapterIndex))
                mainItems.append(contentsOf: sceneItems(
                    for: story,
                    chapterIndex: chapterIndex,
                    useLayoutOrder: false
                ))
                mainItems.append(contentsOf: chapterSupplementItems(for: story, chapterIndex: chapterIndex))
            }
        case .pictureBook, .comicBook:
            mainItems.append(contentsOf: panelStoryItemsWithSupplements(for: story, useLayoutOrder: true))
        }

        for matter in positionedMatter.reversed() {
            switch matter.position {
            case .beforeChapter(let chapterIndex):
                let insertionIndex = insertionIndexBeforeChapter(chapterIndex, in: mainItems)
                mainItems.insert(.readingMatterPage(index: matter.index, id: matter.page.id), at: insertionIndex)
            case .afterChapter(let chapterIndex):
                let insertionIndex = insertionIndexAfterChapter(chapterIndex, in: mainItems)
                mainItems.insert(.readingMatterPage(index: matter.index, id: matter.page.id), at: insertionIndex)
            case .front, .back:
                continue
            }
        }

        var items: [StoryReadingSpineItem] = [.cover]
        items.append(contentsOf: positionedMatter.compactMap { matter in
            guard case .front = matter.position else { return nil }
            return .readingMatterPage(index: matter.index, id: matter.page.id)
        })
        items.append(contentsOf: mainItems)
        items.append(contentsOf: positionedMatter.compactMap { matter in
            guard case .back = matter.position else { return nil }
            return .readingMatterPage(index: matter.index, id: matter.page.id)
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

    private static func sceneItemsWithChapterIntros(
        for story: Story,
        useLayoutOrder: Bool
    ) -> [StoryReadingSpineItem] {
        let scenes = sceneItems(for: story, useLayoutOrder: useLayoutOrder)
        var result: [StoryReadingSpineItem] = []
        var introducedChapters = Set<Int>()

        for item in scenes {
            guard case .scene(let chapterIndex, _) = item else {
                result.append(item)
                continue
            }

            if introducedChapters.insert(chapterIndex).inserted,
               story.chapters.indices.contains(chapterIndex),
               story.chapters[chapterIndex].hasChapterIntroContentForLanguage(story.targetLanguageCode) {
                result.append(.chapter(index: chapterIndex))
            }

            result.append(item)
        }

        return result
    }

    private static func panelStoryItemsWithSupplements(
        for story: Story,
        useLayoutOrder: Bool
    ) -> [StoryReadingSpineItem] {
        let scenes = sceneItems(for: story, useLayoutOrder: useLayoutOrder)
        var result: [StoryReadingSpineItem] = []
        var introducedChapters = Set<Int>()
        var supplementsInserted = Set<Int>()

        for (index, item) in scenes.enumerated() {
            if case .scene(let chapterIndex, _) = item {
                if introducedChapters.insert(chapterIndex).inserted,
                   story.chapters.indices.contains(chapterIndex),
                   story.chapters[chapterIndex].hasChapterIntroContentForLanguage(story.targetLanguageCode) {
                    result.append(.chapter(index: chapterIndex))
                }
            }

            result.append(item)

            guard case .scene(let chapterIndex, _) = item else { continue }
            let hasLaterSceneInChapter = scenes[(index + 1)...].contains {
                if case .scene(let laterChapterIndex, _) = $0 {
                    return laterChapterIndex == chapterIndex
                }
                return false
            }
            guard !hasLaterSceneInChapter,
                  supplementsInserted.insert(chapterIndex).inserted else { continue }
            result.append(contentsOf: chapterSupplementItems(for: story, chapterIndex: chapterIndex))
        }

        return result
    }

    private static func chapterSupplementItems(
        for story: Story,
        chapterIndex: Int
    ) -> [StoryReadingSpineItem] {
        guard story.chapters.indices.contains(chapterIndex) else { return [] }
        let chapter = story.chapters[chapterIndex]
        guard !chapter.isPrologue, !chapter.isEpilogue else { return [] }

        var items: [StoryReadingSpineItem] = []
        if ChapterComprehensionQuizResolver.shouldShowQuiz(for: chapter, in: story, chapterIndex: chapterIndex) {
            items.append(.chapterQuiz(index: chapterIndex))
        }
        if ChapterComprehensionQuizResolver.shouldShowVocabulary(for: chapter, in: story) {
            items.append(.chapterVocabulary(index: chapterIndex))
        }
        return items
    }

    private enum ReadingMatterPosition {
        case front
        case beforeChapter(Int)
        case afterChapter(Int)
        case back
    }

    private struct PositionedReadingMatter {
        let index: Int
        let page: ReadingMatterPage
        let position: ReadingMatterPosition
    }

    nonisolated private static func compareReadingMatter(
        _ lhs: PositionedReadingMatter,
        _ rhs: PositionedReadingMatter
    ) -> Bool {
        lhs.index < rhs.index
    }

    nonisolated private static func readingMatterPosition(for page: ReadingMatterPage) -> ReadingMatterPosition {
        switch page.placement {
        case .beforeChapters:
            return .front
        case .afterChapters:
            return .back
        }
    }

    nonisolated private static func insertionIndexBeforeChapter(
        _ chapterIndex: Int,
        in items: [StoryReadingSpineItem]
    ) -> Int {
        items.firstIndex { item in
            item.belongsToChapter(chapterIndex)
        } ?? items.count
    }

    nonisolated private static func insertionIndexAfterChapter(
        _ chapterIndex: Int,
        in items: [StoryReadingSpineItem]
    ) -> Int {
        guard let lastIndex = items.lastIndex(where: { $0.belongsToChapter(chapterIndex) }) else {
            return items.count
        }
        return items.index(after: lastIndex)
    }
}

private extension StoryReadingSpineItem {
    nonisolated func belongsToChapter(_ chapterIndex: Int) -> Bool {
        switch self {
        case .chapter(let index):
            return index == chapterIndex
        case .scene(let index, _):
            return index == chapterIndex
        case .chapterQuiz(let index), .chapterVocabulary(let index):
            return index == chapterIndex
        case .cover, .readingMatterPage:
            return false
        }
    }
}

enum ChapterComprehensionQuizResolver {
    static func questions(
        for chapter: StoryChapter,
        in story: Story
    ) -> (questions: [ComprehensionQuestion], isStoryWideFallback: Bool) {
        let chapterQuestions = chapter.comprehensionQuestionsForLanguage(story.targetLanguageCode)
        if !chapterQuestions.isEmpty {
            return (chapterQuestions, false)
        }
        let storyQuestions = story.comprehensionQuestions
        return (storyQuestions, !storyQuestions.isEmpty)
    }

    static func shouldShowQuiz(
        for chapter: StoryChapter,
        in story: Story,
        chapterIndex: Int
    ) -> Bool {
        guard !chapter.isPrologue, !chapter.isEpilogue else { return false }
        if chapter.hasChapterQuizContentForLanguage(story.targetLanguageCode) { return true }

        let anyChapterHasOwnedQuiz = story.chapters.contains {
            $0.hasChapterQuizContentForLanguage(story.targetLanguageCode)
        }
        let storyWideQuiz = !story.comprehensionQuestions.isEmpty
        return storyWideQuiz
            && !anyChapterHasOwnedQuiz
            && chapterIndex == story.chapters.count - 1
    }

    static func shouldShowVocabulary(for chapter: StoryChapter, in story: Story) -> Bool {
        guard !chapter.isPrologue, !chapter.isEpilogue else { return false }
        guard chapter.hasChapterVocabularyContentForLanguage(story.targetLanguageCode) else { return false }
        return story.ciProfile?.generateChapterVocabulary ?? true
    }
}

enum StoryReadingSpineTitles {
    static func readingMatterTitle(for page: ReadingMatterPage, targetCode: String, nativeCode: String, preferNative: Bool = true) -> String {
        if preferNative, let title = page.titleFor(nativeCode).spineTrimmedNilIfEmpty {
            return title
        }
        if let title = page.titleFor(targetCode).spineTrimmedNilIfEmpty {
            return title
        }
        return page.id
    }

    static func chapterTitle(for chapter: StoryChapter, index: Int, targetCode: String) -> String {
        let resolved = chapter.titleFor(targetCode)
        if let title = resolved.spineTrimmedNilIfEmpty, title != "Chapter" {
            return title
        }
        if chapter.isPrologue { return "Prologue" }
        if chapter.isEpilogue { return "Epilogue" }
        return "Chapter \(index + 1)"
    }

    static func introSpineTitle(
        for chapter: StoryChapter,
        targetCode: String,
        nativeCode: String,
        preferNative: Bool = true
    ) -> String {
        if preferNative,
           let title = chapter.chapterIntroTitleForLanguage(nativeCode)?.spineTrimmedNilIfEmpty {
            return title
        }
        if let title = chapter.chapterIntroTitleForLanguage(targetCode)?.spineTrimmedNilIfEmpty {
            return title
        }
        return "Intro"
    }

    static func chapterKindLabel(
        for chapter: StoryChapter,
        index: Int,
        regularChapterCount: Int,
        targetCode: String
    ) -> String {
        let resolved = chapter.titleFor(targetCode)
        let titlePart = resolved == "Chapter" ? "" : (resolved.spineTrimmedNilIfEmpty.map { " · \($0)" } ?? "")
        if chapter.isPrologue { return "Prologue\(titlePart)" }
        if chapter.isEpilogue { return "Epilogue\(titlePart)" }
        return "Chapter \(chapter.chapterNumber) of \(regularChapterCount)\(titlePart)"
    }

    static func chapterPrefix(for chapter: StoryChapter, index: Int, targetCode: String) -> String {
        let resolved = chapter.titleFor(targetCode)
        let titlePart = resolved == "Chapter" ? "" : (resolved.spineTrimmedNilIfEmpty.map { " · \($0)" } ?? "")
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
        targetCode: String,
        breakdownTitle: String? = nil
    ) -> String {
        if let persisted = scene.title?.spineTrimmedNilIfEmpty {
            return persisted
        }
        if let breakdownTitle = breakdownTitle?.spineTrimmedNilIfEmpty {
            return breakdownTitle
        }
        if let caption = scene.captionFor(targetCode).spineTrimmedNilIfEmpty, caption.count <= 80 {
            return caption
        }
        if let firstLine = scene.scriptFor(targetCode)?
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
        sceneIndex: Int,
        targetCode: String
    ) -> String {
        guard let chapter else { return "Scene \(sceneIndex + 1)" }
        return "\(chapterPrefix(for: chapter, index: chapterIndex, targetCode: targetCode))Scene \(sceneIndex + 1)"
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
                return readingMatterTitle(for: page, targetCode: story.targetLanguageCode, nativeCode: story.nativeLanguageCode)
            }
            return "Reading Matter"
        case .chapter(let index):
            if let chapter = adapter.chapter(for: item) {
                return introSpineTitle(
                    for: chapter,
                    targetCode: story.targetLanguageCode,
                    nativeCode: story.nativeLanguageCode
                )
            }
            return "Intro"
        case .scene(let chapterIndex, let sceneIndex):
            if let scene = adapter.scene(for: item) {
                let breakdown = sceneTitleFromBreakdown(
                    story: story,
                    chapterIndex: chapterIndex,
                    sceneIndex: sceneIndex
                )
                return sceneTitle(from: scene, sceneIndex: sceneIndex, targetCode: story.targetLanguageCode, breakdownTitle: breakdown)
            }
            return "Scene \(sceneIndex + 1)"
        case .chapterQuiz:
            return "Chapter Quiz"
        case .chapterVocabulary:
            return "Word Focus"
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
            return chapterKindLabel(for: chapter, index: chapterIndex, regularChapterCount: regularCount, targetCode: story.targetLanguageCode)
        case .scene(let chapterIndex, let sceneIndex):
            let chapter = story.chapters[safeSpineTitle: chapterIndex]
            return sceneContextLabel(chapter: chapter, chapterIndex: chapterIndex, sceneIndex: sceneIndex, targetCode: story.targetLanguageCode)
        case .chapterQuiz(let chapterIndex):
            guard let chapter = story.chapters[safeSpineTitle: chapterIndex] else { return "Chapter Quiz" }
            return "\(chapterPrefix(for: chapter, index: chapterIndex, targetCode: story.targetLanguageCode))Quiz"
        case .chapterVocabulary(let chapterIndex):
            guard let chapter = story.chapters[safeSpineTitle: chapterIndex] else { return "Word Focus" }
            return "\(chapterPrefix(for: chapter, index: chapterIndex, targetCode: story.targetLanguageCode))Vocabulary"
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
    var canonicalTrimmedNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated var readingMatterPlacementKey: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }

    nonisolated var readingMatterPlacementTokens: Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        return Set(tokens)
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
