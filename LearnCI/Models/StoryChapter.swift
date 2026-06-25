import Foundation

/// Represents a single chapter within a long-form story.
struct StoryChapter: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var chapterNumber: Int
    var chapterType: String = "chapter"
    var titleTargetLanguage: String
    var titleEnglish: String
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
    var scenes: [StoryScene] = []
    var nativeAudioUrl: String?
    var nativeWordTimings: [WordTiming]?
    var comprehensionQuestions: [ComprehensionQuestion]?
    var vocabularyNote: String?

    var hasChapterQuizContent: Bool {
        !(comprehensionQuestions?.isEmpty ?? true)
    }

    var hasChapterVocabularyContent: Bool {
        !(vocabularyNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var isPrologue: Bool { chapterType == "prologue" }
    var isEpilogue: Bool { chapterType == "epilogue" }

    var spokenChapterReferenceTitle: String {
        if isPrologue { return "Prologue" }
        if isEpilogue { return "Epilogue" }
        return "Chapter \(chapterNumber)"
    }

    func spokenPlaybackMarker(isIntro: Bool) -> String {
        let title = titleTargetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        let section = isIntro ? "\(spokenChapterReferenceTitle) intro" : "\(spokenChapterReferenceTitle) main story"
        return title.isEmpty ? section : "\(section): \(title)"
    }

    var hasChapterIntroContent: Bool {
        let hasAudio = !(chapterIntroAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasText = !(chapterIntroText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasAudio || hasText
    }

    func displayTitleForPlayback(preferNative: Bool) -> String {
        if preferNative {
            let english = titleEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
            return english.isEmpty ? titleTargetLanguage : english
        }
        return titleTargetLanguage
    }

    func chapterIntroBodyWordTimings(preferNative: Bool) -> [WordTiming] {
        WordTiming.bodyTimings(
            fullTimings: chapterIntroWordTimings ?? [],
            skippingLeadingSpokenText: displayTitleForPlayback(preferNative: preferNative)
        )
    }

    var bodyTextTargetForReading: String {
        return scenes
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .compactMap { $0.targetTextForReading }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    var bodyTextEnglishForReading: String {
        let sceneText = scenes
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .compactMap { $0.nativeTextForReading }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        if !sceneText.isEmpty {
            return sceneText
        }

        return scriptEnglish?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Short synopsis for preview / table-of-contents rows (plot summary, not intro or body).
    var tableOfContentsOverview: String? {
        let target = plotSummaryTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !target.isEmpty { return target }
        let english = plotSummaryEnglish?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return english.isEmpty ? nil : english
    }

    var bodyScriptOrNarrativeForAlignment: String {
        let script = scriptTargetLanguage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return script.isEmpty ? bodyTextTargetForReading : script
    }

    var bodyWordTimingsForPlayback: [WordTiming] {
        guard !scenes.isEmpty else { return wordTimings ?? [] }
        var offset = 0.0
        var merged: [WordTiming] = []

        for scene in scenes.sorted(by: { $0.sceneIndex < $1.sceneIndex }) {
            merged.append(contentsOf: scene.wordTimings.map {
                WordTiming(word: $0.word, start: $0.start + offset, end: $0.end + offset)
            })

            if let durationMs = scene.audioDurationMs {
                offset += Double(durationMs) / 1000.0
            } else if let last = scene.wordTimings.last {
                offset += last.end
            }
        }

        return merged
    }

    var hasAnyBodyNarrationAudio: Bool {
        scenes.contains { !($0.audioUrl ?? "").isEmpty }
    }

    var bodyNarrationClipsCompleteForPlayback: Bool {
        !scenes.isEmpty && scenes.allSatisfy { !($0.audioUrl ?? "").isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case chapterNumber = "chapter_number"
        case chapterType = "chapter_type"
        case titleTargetLanguage = "title_target_language"
        case titleEnglish = "title_english"
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
        case scenes
        case nativeAudioUrl = "native_audio_url"
        case nativeAudioUrlCamel = "nativeAudioUrl"
        case nativeWordTimings = "native_word_timings"
        case nativeWordTimingsCamel = "nativeWordTimings"
        case comprehensionQuestions = "comprehension_questions"
        case vocabularyNote = "vocabulary_note"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        chapterNumber = (try? container.decode(Int.self, forKey: .chapterNumber)) ?? 1
        chapterType = (try? container.decode(String.self, forKey: .chapterType)) ?? "chapter"
        titleTargetLanguage = (try? container.decode(String.self, forKey: .titleTargetLanguage)) ?? ""
        titleEnglish = (try? container.decode(String.self, forKey: .titleEnglish)) ?? ""
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
        scenes = (try? container.decode([StoryScene].self, forKey: .scenes)) ?? []
        nativeAudioUrl = (try? container.decode(String.self, forKey: .nativeAudioUrl))
            ?? (try? container.decode(String.self, forKey: .nativeAudioUrlCamel))
        nativeWordTimings = (try? container.decode([WordTiming].self, forKey: .nativeWordTimings))
            ?? (try? container.decode([WordTiming].self, forKey: .nativeWordTimingsCamel))
        comprehensionQuestions = try? container.decode([ComprehensionQuestion].self, forKey: .comprehensionQuestions)
        vocabularyNote = try? container.decode(String.self, forKey: .vocabularyNote)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(chapterNumber, forKey: .chapterNumber)
        try container.encode(chapterType, forKey: .chapterType)
        try container.encode(titleTargetLanguage, forKey: .titleTargetLanguage)
        try container.encode(titleEnglish, forKey: .titleEnglish)
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
        try container.encode(scenes, forKey: .scenes)
        try container.encodeIfPresent(nativeAudioUrl, forKey: .nativeAudioUrl)
        try container.encodeIfPresent(nativeWordTimings, forKey: .nativeWordTimings)
        try container.encodeIfPresent(comprehensionQuestions, forKey: .comprehensionQuestions)
        try container.encodeIfPresent(vocabularyNote, forKey: .vocabularyNote)
    }

    init(id: UUID = UUID(),
         chapterNumber: Int,
         chapterType: String = "chapter",
         titleTargetLanguage: String,
         titleEnglish: String,
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
         chapterIntroWordTimings: [WordTiming]? = nil,
         scenes: [StoryScene] = [],
         nativeAudioUrl: String? = nil,
         nativeWordTimings: [WordTiming]? = nil,
         comprehensionQuestions: [ComprehensionQuestion]? = nil,
         vocabularyNote: String? = nil) {
        self.id = id
        self.chapterNumber = chapterNumber
        self.chapterType = chapterType
        self.titleTargetLanguage = titleTargetLanguage
        self.titleEnglish = titleEnglish
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
        self.scenes = scenes
        self.nativeAudioUrl = nativeAudioUrl
        self.nativeWordTimings = nativeWordTimings
        self.comprehensionQuestions = comprehensionQuestions
        self.vocabularyNote = vocabularyNote
    }
}
