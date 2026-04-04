import Foundation

/// Represents a single chapter within a long-form story.
struct StoryChapter: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var chapterNumber: Int
    var chapterType: String = "chapter"
    var titleTargetLanguage: String
    var titleEnglish: String
    var textTargetLanguage: String
    var textEnglish: String
    var scriptTargetLanguage: String?
    var scriptEnglish: String?
    var audioUrl: String?
    var wordTimings: [WordTiming]?
    var plotSummaryTarget: String?
    var plotSummaryEnglish: String?
    var chapterImagePrompt: String?
    var coverUrl: String?
    var chapterIntroText: String?
    var chapterIntroTextEnglish: String?
    var chapterIntroAudioUrl: String?
    var chapterIntroWordTimings: [WordTiming]?

    var isPrologue: Bool { chapterType == "prologue" }
    var isEpilogue: Bool { chapterType == "epilogue" }

    enum CodingKeys: String, CodingKey {
        case id
        case chapterNumber = "chapter_number"
        case chapterType = "chapter_type"
        case titleTargetLanguage = "title_target_language"
        case titleEnglish = "title_english"
        case textTargetLanguage = "text_target_language"
        case textEnglish = "text_english"
        case scriptTargetLanguage = "script_target_language"
        case scriptEnglish = "script_english"
        case audioUrl = "audio_url"
        case wordTimings = "word_timings"
        case plotSummaryTarget = "plot_summary_target"
        case plotSummaryEnglish = "plot_summary_english"
        case plotSummaryLegacy = "plot_summary"  // legacy key
        case chapterImagePrompt = "chapter_image_prompt"
        case coverUrl = "chapter_cover_url"
        case chapterIntroText = "chapter_intro_text"
        case chapterIntroTextEnglish = "chapter_intro_text_english"
        case chapterIntroAudioUrl = "chapter_intro_audio_url"
        case chapterIntroWordTimings = "chapter_intro_word_timings"
        case chapterIntroWordTimingsCamel = "chapterIntroWordTimings" // camelCase variant from pipeline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        chapterNumber = (try? container.decode(Int.self, forKey: .chapterNumber)) ?? 1
        chapterType = (try? container.decode(String.self, forKey: .chapterType)) ?? "chapter"
        titleTargetLanguage = (try? container.decode(String.self, forKey: .titleTargetLanguage)) ?? ""
        titleEnglish = (try? container.decode(String.self, forKey: .titleEnglish)) ?? ""
        textTargetLanguage = (try? container.decode(String.self, forKey: .textTargetLanguage)) ?? ""
        textEnglish = (try? container.decode(String.self, forKey: .textEnglish)) ?? ""
        scriptTargetLanguage = try? container.decode(String.self, forKey: .scriptTargetLanguage)
        scriptEnglish = try? container.decode(String.self, forKey: .scriptEnglish)
        audioUrl = try? container.decode(String.self, forKey: .audioUrl)
        wordTimings = try? container.decode([WordTiming].self, forKey: .wordTimings)
        plotSummaryTarget = try? container.decode(String.self, forKey: .plotSummaryTarget)
        // Fall back to legacy "plot_summary" key if new key is absent
        plotSummaryEnglish = (try? container.decode(String.self, forKey: .plotSummaryEnglish))
            ?? (try? container.decode(String.self, forKey: .plotSummaryLegacy))
        chapterImagePrompt = try? container.decode(String.self, forKey: .chapterImagePrompt)
        coverUrl = try? container.decode(String.self, forKey: .coverUrl)
        chapterIntroText = try? container.decode(String.self, forKey: .chapterIntroText)
        chapterIntroTextEnglish = try? container.decode(String.self, forKey: .chapterIntroTextEnglish)
        chapterIntroAudioUrl = try? container.decode(String.self, forKey: .chapterIntroAudioUrl)
        chapterIntroWordTimings = (try? container.decode([WordTiming].self, forKey: .chapterIntroWordTimings))
            ?? (try? container.decode([WordTiming].self, forKey: .chapterIntroWordTimingsCamel))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(chapterNumber, forKey: .chapterNumber)
        try container.encode(chapterType, forKey: .chapterType)
        try container.encode(titleTargetLanguage, forKey: .titleTargetLanguage)
        try container.encode(titleEnglish, forKey: .titleEnglish)
        try container.encode(textTargetLanguage, forKey: .textTargetLanguage)
        try container.encode(textEnglish, forKey: .textEnglish)
        try container.encodeIfPresent(scriptTargetLanguage, forKey: .scriptTargetLanguage)
        try container.encodeIfPresent(scriptEnglish, forKey: .scriptEnglish)
        try container.encodeIfPresent(audioUrl, forKey: .audioUrl)
        try container.encodeIfPresent(wordTimings, forKey: .wordTimings)
        try container.encodeIfPresent(plotSummaryTarget, forKey: .plotSummaryTarget)
        try container.encodeIfPresent(plotSummaryEnglish, forKey: .plotSummaryEnglish)
        try container.encodeIfPresent(chapterImagePrompt, forKey: .chapterImagePrompt)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(chapterIntroText, forKey: .chapterIntroText)
        try container.encodeIfPresent(chapterIntroTextEnglish, forKey: .chapterIntroTextEnglish)
        try container.encodeIfPresent(chapterIntroAudioUrl, forKey: .chapterIntroAudioUrl)
        try container.encodeIfPresent(chapterIntroWordTimings, forKey: .chapterIntroWordTimings)
    }

    init(id: UUID = UUID(),
         chapterNumber: Int,
         chapterType: String = "chapter",
         titleTargetLanguage: String,
         titleEnglish: String,
         textTargetLanguage: String,
         textEnglish: String,
         scriptTargetLanguage: String? = nil,
         scriptEnglish: String? = nil,
         audioUrl: String? = nil,
         wordTimings: [WordTiming]? = nil,
         plotSummaryTarget: String? = nil,
         plotSummaryEnglish: String? = nil,
         chapterImagePrompt: String? = nil,
         coverUrl: String? = nil,
         chapterIntroText: String? = nil,
         chapterIntroTextEnglish: String? = nil,
         chapterIntroAudioUrl: String? = nil,
         chapterIntroWordTimings: [WordTiming]? = nil) {
        self.id = id
        self.chapterNumber = chapterNumber
        self.chapterType = chapterType
        self.titleTargetLanguage = titleTargetLanguage
        self.titleEnglish = titleEnglish
        self.textTargetLanguage = textTargetLanguage
        self.textEnglish = textEnglish
        self.scriptTargetLanguage = scriptTargetLanguage
        self.scriptEnglish = scriptEnglish
        self.audioUrl = audioUrl
        self.wordTimings = wordTimings
        self.plotSummaryTarget = plotSummaryTarget
        self.plotSummaryEnglish = plotSummaryEnglish
        self.chapterImagePrompt = chapterImagePrompt
        self.coverUrl = coverUrl
        self.chapterIntroText = chapterIntroText
        self.chapterIntroTextEnglish = chapterIntroTextEnglish
        self.chapterIntroAudioUrl = chapterIntroAudioUrl
        self.chapterIntroWordTimings = chapterIntroWordTimings
    }
}

