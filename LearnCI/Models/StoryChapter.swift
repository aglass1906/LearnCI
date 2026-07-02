import Foundation

struct ChapterLangEnvelope<T: Codable & Equatable>: Codable, Equatable {
    var byLanguage: [String: T]

    init(byLanguage: [String: T] = [:]) {
        self.byLanguage = Dictionary(uniqueKeysWithValues: byLanguage.map { key, value in
            (key.lowercased(), value)
        })
    }

    func forCode(_ langCode: String) -> T? {
        byLanguage[langCode.lowercased()]
    }

    enum CodingKeys: String, CodingKey {
        case byLanguage

        var stringValue: String {
            switch self {
            case .byLanguage:
                return ["by", "language"].joined(separator: "_")
            }
        }

        init?(stringValue: String) {
            switch stringValue {
            case ["by", "language"].joined(separator: "_"):
                self = .byLanguage
            default:
                return nil
            }
        }

        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container.decode([String: T].self, forKey: .byLanguage)) ?? [:]
        byLanguage = Dictionary(uniqueKeysWithValues: raw.map { key, value in
            (key.lowercased(), value)
        })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !byLanguage.isEmpty {
            try container.encode(byLanguage, forKey: .byLanguage)
        }
    }
}

struct ChapterTitleLang: Codable, Equatable {
    var text: String = ""

    init(text: String = "") {
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
    }
}

struct ChapterIntroLang: Codable, Equatable {
    var text: String = ""
    var audioUrl: String?
    var wordTimings: [WordTiming] = []

    enum CodingKeys: String, CodingKey {
        case text
        case audioUrl
        case wordTimings

        var stringValue: String {
            switch self {
            case .text:
                return "text"
            case .audioUrl:
                return ["audio", "url"].joined(separator: "_")
            case .wordTimings:
                return ["word", "timings"].joined(separator: "_")
            }
        }

        init?(stringValue: String) {
            switch stringValue {
            case "text":
                self = .text
            case ["audio", "url"].joined(separator: "_"):
                self = .audioUrl
            case ["word", "timings"].joined(separator: "_"):
                self = .wordTimings
            default:
                return nil
            }
        }

        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(text: String = "", audioUrl: String? = nil, wordTimings: [WordTiming] = []) {
        self.text = text
        self.audioUrl = audioUrl
        self.wordTimings = wordTimings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
        audioUrl = try? container.decode(String.self, forKey: .audioUrl)
        wordTimings = (try? container.decode([WordTiming].self, forKey: .wordTimings)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(audioUrl, forKey: .audioUrl)
        if !wordTimings.isEmpty {
            try container.encode(wordTimings, forKey: .wordTimings)
        }
    }
}

struct ChapterVocabLang: Codable, Equatable {
    var note: String = ""

    init(note: String = "") {
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        note = (try? container.decode(String.self, forKey: .note)) ?? ""
    }
}

struct ChapterComprehensionLang: Codable, Equatable {
    var questions: [ComprehensionQuestion] = []

    init(questions: [ComprehensionQuestion] = []) {
        self.questions = questions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        questions = (try? container.decode([ComprehensionQuestion].self, forKey: .questions)) ?? []
    }
}

/// Represents a single chapter within a long-form story.
struct StoryChapter: Codable, Identifiable, Equatable {
    var id: String
    var chapterNumber: Int
    var chapterType: String
    var plotSummary: String?
    var setting: String?
    var locations: [String]
    var charactersInvolved: [String]
    var sceneBeats: [String]
    var scenes: [StoryScene]
    var coverUrl: String?
    var title: ChapterLangEnvelope<ChapterTitleLang>
    var intro: ChapterLangEnvelope<ChapterIntroLang>
    var vocabulary: ChapterLangEnvelope<ChapterVocabLang>
    var comprehension: ChapterLangEnvelope<ChapterComprehensionLang>

    var isPrologue: Bool { chapterType == "prologue" }
    var isEpilogue: Bool { chapterType == "epilogue" }

    enum CodingKeys: String, CodingKey {
        case id
        case chapterNumber
        case chapterType
        case plotSummary
        case setting
        case locations
        case charactersInvolved
        case sceneBeats
        case scenes
        case coverUrl
        case title
        case intro
        case vocabulary
        case comprehension

        var stringValue: String {
            switch self {
            case .id:
                return "id"
            case .chapterNumber:
                return ["chapter", "number"].joined(separator: "_")
            case .chapterType:
                return ["chapter", "type"].joined(separator: "_")
            case .plotSummary:
                return ["plot", "summary"].joined(separator: "_")
            case .setting:
                return "setting"
            case .locations:
                return "locations"
            case .charactersInvolved:
                return ["characters", "involved"].joined(separator: "_")
            case .sceneBeats:
                return ["scene", "beats"].joined(separator: "_")
            case .scenes:
                return "scenes"
            case .coverUrl:
                return ["chapter", "cover", "url"].joined(separator: "_")
            case .title:
                return "title"
            case .intro:
                return "intro"
            case .vocabulary:
                return "vocabulary"
            case .comprehension:
                return "comprehension"
            }
        }

        init?(stringValue: String) {
            switch stringValue {
            case "id":
                self = .id
            case ["chapter", "number"].joined(separator: "_"):
                self = .chapterNumber
            case ["chapter", "type"].joined(separator: "_"):
                self = .chapterType
            case ["plot", "summary"].joined(separator: "_"):
                self = .plotSummary
            case "setting":
                self = .setting
            case "locations":
                self = .locations
            case ["characters", "involved"].joined(separator: "_"):
                self = .charactersInvolved
            case ["scene", "beats"].joined(separator: "_"):
                self = .sceneBeats
            case "scenes":
                self = .scenes
            case ["chapter", "cover", "url"].joined(separator: "_"):
                self = .coverUrl
            case "title":
                self = .title
            case "intro":
                self = .intro
            case "vocabulary":
                self = .vocabulary
            case "comprehension":
                self = .comprehension
            default:
                return nil
            }
        }

        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(
        id: String = UUID().uuidString,
        chapterNumber: Int,
        chapterType: String = "chapter",
        plotSummary: String? = nil,
        setting: String? = nil,
        locations: [String] = [],
        charactersInvolved: [String] = [],
        sceneBeats: [String] = [],
        scenes: [StoryScene] = [],
        coverUrl: String? = nil,
        title: ChapterLangEnvelope<ChapterTitleLang> = ChapterLangEnvelope(),
        intro: ChapterLangEnvelope<ChapterIntroLang> = ChapterLangEnvelope(),
        vocabulary: ChapterLangEnvelope<ChapterVocabLang> = ChapterLangEnvelope(),
        comprehension: ChapterLangEnvelope<ChapterComprehensionLang> = ChapterLangEnvelope()
    ) {
        self.id = id
        self.chapterNumber = chapterNumber
        self.chapterType = chapterType
        self.plotSummary = plotSummary
        self.setting = setting
        self.locations = locations
        self.charactersInvolved = charactersInvolved
        self.sceneBeats = sceneBeats
        self.scenes = scenes
        self.coverUrl = coverUrl
        self.title = title
        self.intro = intro
        self.vocabulary = vocabulary
        self.comprehension = comprehension
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        chapterNumber = (try? container.decode(Int.self, forKey: .chapterNumber)) ?? 0
        chapterType = (try? container.decode(String.self, forKey: .chapterType)) ?? "chapter"
        plotSummary = try? container.decode(String.self, forKey: .plotSummary)
        setting = try? container.decode(String.self, forKey: .setting)
        locations = (try? container.decode([String].self, forKey: .locations)) ?? []
        charactersInvolved = (try? container.decode([String].self, forKey: .charactersInvolved)) ?? []
        sceneBeats = (try? container.decode([String].self, forKey: .sceneBeats)) ?? []
        scenes = ((try? container.decode([StoryScene].self, forKey: .scenes)) ?? [])
            .sorted { $0.sceneIndex < $1.sceneIndex }
        coverUrl = try? container.decode(String.self, forKey: .coverUrl)
        title = (try? container.decode(ChapterLangEnvelope<ChapterTitleLang>.self, forKey: .title)) ?? ChapterLangEnvelope()
        intro = (try? container.decode(ChapterLangEnvelope<ChapterIntroLang>.self, forKey: .intro)) ?? ChapterLangEnvelope()
        vocabulary = (try? container.decode(ChapterLangEnvelope<ChapterVocabLang>.self, forKey: .vocabulary)) ?? ChapterLangEnvelope()
        comprehension = (try? container.decode(ChapterLangEnvelope<ChapterComprehensionLang>.self, forKey: .comprehension)) ?? ChapterLangEnvelope()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(chapterNumber, forKey: .chapterNumber)
        try container.encode(chapterType, forKey: .chapterType)
        try container.encodeIfPresent(plotSummary, forKey: .plotSummary)
        try container.encodeIfPresent(setting, forKey: .setting)
        try container.encode(locations, forKey: .locations)
        try container.encode(charactersInvolved, forKey: .charactersInvolved)
        try container.encode(sceneBeats, forKey: .sceneBeats)
        try container.encode(scenes, forKey: .scenes)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        if !title.byLanguage.isEmpty { try container.encode(title, forKey: .title) }
        if !intro.byLanguage.isEmpty { try container.encode(intro, forKey: .intro) }
        if !vocabulary.byLanguage.isEmpty { try container.encode(vocabulary, forKey: .vocabulary) }
        if !comprehension.byLanguage.isEmpty { try container.encode(comprehension, forKey: .comprehension) }
    }

    func titleFor(_ langCode: String) -> String {
        let text = title.forCode(langCode)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "Chapter" : text
    }

    func chapterIntroTextForLanguage(_ langCode: String) -> String {
        intro.forCode(langCode)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func chapterIntroAudioUrlForLanguage(_ langCode: String) -> String? {
        intro.forCode(langCode)?.audioUrl?.trimmedStoryChapterNil
    }

    func chapterIntroWordTimingsForLanguage(_ langCode: String) -> [WordTiming] {
        intro.forCode(langCode)?.wordTimings ?? []
    }

    func vocabularyNoteForLanguage(_ langCode: String) -> String? {
        vocabulary.forCode(langCode)?.note.trimmedStoryChapterNil
    }

    func comprehensionQuestionsForLanguage(_ langCode: String) -> [ComprehensionQuestion] {
        comprehension.forCode(langCode)?.questions ?? []
    }

    func hasChapterQuizContentForLanguage(_ langCode: String) -> Bool {
        !comprehensionQuestionsForLanguage(langCode).isEmpty
    }

    func hasChapterVocabularyContentForLanguage(_ langCode: String) -> Bool {
        vocabularyNoteForLanguage(langCode) != nil
    }

    func hasChapterIntroContentForLanguage(_ langCode: String) -> Bool {
        chapterIntroTextForLanguage(langCode).trimmedStoryChapterNil != nil
            || chapterIntroAudioUrlForLanguage(langCode) != nil
    }

    func displayTitleForLanguage(_ langCode: String) -> String {
        titleFor(langCode)
    }

    func chapterIntroBodyWordTimingsForLanguage(_ langCode: String) -> [WordTiming] {
        WordTiming.bodyTimings(
            fullTimings: chapterIntroWordTimingsForLanguage(langCode),
            skippingLeadingSpokenText: displayTitleForLanguage(langCode)
        )
    }

    func bodyTextForLanguage(_ langCode: String) -> String {
        scenes
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .map { $0.captionFor(langCode).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    func bodyScriptForLanguage(_ langCode: String) -> String {
        scenes
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .compactMap { $0.scriptFor(langCode)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    func bodyScriptOrNarrativeForAlignment(_ langCode: String) -> String {
        let script = bodyScriptForLanguage(langCode).trimmingCharacters(in: .whitespacesAndNewlines)
        return script.isEmpty ? bodyTextForLanguage(langCode) : script
    }

    func bodyWordTimingsForLanguage(_ langCode: String) -> [WordTiming] {
        var offset = 0.0
        var merged: [WordTiming] = []

        for scene in scenes.sorted(by: { $0.sceneIndex < $1.sceneIndex }) {
            let timings = scene.wordTimingsFor(langCode)
            merged.append(contentsOf: timings.map {
                WordTiming(word: $0.word, start: $0.start + offset, end: $0.end + offset)
            })

            let durationMs = scene.audioDurationMsFor(langCode)
            if durationMs > 0 {
                offset += Double(durationMs) / 1000.0
            } else if let last = timings.last {
                offset += last.end
            }
        }

        return merged
    }

    func hasSceneAudioForLanguage(_ langCode: String) -> Bool {
        scenes.contains { $0.audioUrlForLanguage(langCode) != nil }
    }

    func bodyNarrationClipsCompleteForLanguage(_ langCode: String) -> Bool {
        !scenes.isEmpty && scenes.allSatisfy { $0.audioUrlForLanguage(langCode) != nil }
    }

    var tableOfContentsOverview: String? {
        plotSummary?.trimmedStoryChapterNil
    }
}

private extension String {
    var trimmedStoryChapterNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
