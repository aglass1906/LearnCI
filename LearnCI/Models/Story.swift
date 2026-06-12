import Foundation
import SwiftData

struct ComprehensionQuestion: Codable, Identifiable {
    var id: UUID = UUID()
    let question: String   // In target language
    let choices: [String]  // Exactly 4 choices, in target language
    let correctIndex: Int  // 0–3

    // Exclude `id` so GPT responses (which don't include it) decode cleanly
    enum CodingKeys: String, CodingKey {
        case question, choices, correctIndex
    }
}

@Model
final class Story: Identifiable {
    @Attribute(.unique) var id: UUID
    var userID: String = "" // Required for sync ownership
    var title: String
    var targetLanguageText: String
    var nativeLanguageText: String?
    var audioFilename: String?
    var languageRaw: String
    var levelRaw: String
    var createdAt: Date
    var updatedAt: Date?
    var isFavorite: Bool
    var prompt: String? // New field for the user's topic/prompt
    var preferencesJSON: String? // JSON string of StoryPreferences
    var remoteAudioPath: String? // Path in Supabase Storage
    var remoteCoverPath: String? // Path to cover image in Supabase Storage
    var coverArt: String? // URL or path to cover image
    var textGenPrompt: String? // The exact prompt used for text generation
    var imageGenPrompt: String? // The exact prompt used for image generation
    var videoStyle: String? // Visual style chosen by user (e.g. "Pixar 3D Animation")
    var videoGenPrompt: String? // The cinematic prompt sent to Veo
    var remoteVideoPath: String? // Path to generated video in Supabase Storage
    var wordTimingsJSON: String? // JSON string of [WordTiming]
    var comprehensionQuestionsJSON: String? // JSON string of [ComprehensionQuestion]
    var speakerVoicesJSON: String? // JSON dict of speaker name → OpenAI voice, e.g. {"NARRATOR":"onyx","ELENA":"nova"}
    var taggedTargetText: String? // Original speaker-tagged text (dramatized mode); nil for single-voice stories
    var ambientSoundId: String? // AmbientSound.id, e.g. "rain_night" or "none"
    var ambientVolume: Float = 0.15 // 0.0–1.0 mix level for ambient audio
    var chaptersJSON: String? // JSON string of [StoryChapter]
    var layoutJSON: String? // JSON string of StoryLayout
    var readingMatterPagesJSON: String? // JSON string of [ReadingMatterPage]
    var assetForgeJSON: String? // JSON string of visual asset registry
    var ciProfileJSON: String? // JSON string of CiProfile (pipeline PROFILE stage)
    var bibleJSON: String? // JSON string of Story Bible (pipeline LORE stage)
    var sceneBreakdownJSON: String? // JSON string of scene breakdown (pipeline SCENES stage)

    // Computed property to easy decoding of word timings
    @Transient var wordTimings: [WordTiming] {
        guard let json = wordTimingsJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WordTiming].self, from: data)) ?? []
    }

    @Transient var comprehensionQuestions: [ComprehensionQuestion] {
        guard let json = comprehensionQuestionsJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ComprehensionQuestion].self, from: data)) ?? []
    }

    @Transient var chapters: [StoryChapter] {
        guard let json = chaptersJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([StoryChapter].self, from: data)) ?? []
    }

    @Transient var preferences: StoryPreferences {
        guard let json = preferencesJSON, let data = json.data(using: .utf8) else { return StoryPreferences() }
        return (try? JSONDecoder().decode(StoryPreferences.self, from: data)) ?? StoryPreferences()
    }

    @Transient var storyLayout: StoryLayout? {
        guard let json = layoutJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StoryLayout.self, from: data)
    }

    @Transient var readingMatterPages: [ReadingMatterPage] {
        guard let json = readingMatterPagesJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ReadingMatterPage].self, from: data)) ?? []
    }

    @Transient var ciProfile: CiProfile? {
        guard let json = ciProfileJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CiProfile.self, from: data)
    }

    @Transient var storyBible: StoryBible? {
        guard let json = bibleJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StoryBible.self, from: data)
    }

    /// Narrative synopsis for the preview page — bible overview, then logline, then prompt.
    var storyOverviewText: String? {
        if let overview = storyBible?.storyOverview?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !overview.isEmpty {
            return overview
        }
        if let logline = storyBible?.logline?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !logline.isEmpty {
            return logline
        }
        if let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            return prompt
        }
        return nil
    }

    var isDramatized: Bool { taggedTargetText != nil }
    // Computed properties for type safety, matching existing app patterns
    var language: Language {
        get { Language(rawValue: languageRaw) ?? .spanish }
        set { languageRaw = newValue.rawValue }
    }
    
    // Using Int for level to match existing systems (1-6) or strict enum if preferred
    var level: Int {
        get { Int(levelRaw) ?? 1 }
        set { levelRaw = String(newValue) }
    }
    
    init(id: UUID = UUID(),
         userID: String,
         title: String,
         targetLanguageText: String,
         nativeLanguageText: String? = nil,
         prompt: String? = nil,
         textGenPrompt: String? = nil,
         imageGenPrompt: String? = nil,
         preferencesJSON: String? = nil,
         wordTimingsJSON: String? = nil,
         speakerVoicesJSON: String? = nil,
         taggedTargetText: String? = nil,
         audioFilename: String? = nil,
         remoteAudioPath: String? = nil,
         remoteCoverPath: String? = nil,
         coverArt: String? = nil,
         videoStyle: String? = nil,
         videoGenPrompt: String? = nil,
         remoteVideoPath: String? = nil,
         ambientSoundId: String? = nil,
         ambientVolume: Float = 0.15,
         chaptersJSON: String? = nil,
         layoutJSON: String? = nil,
         readingMatterPagesJSON: String? = nil,
         assetForgeJSON: String? = nil,
         ciProfileJSON: String? = nil,
         bibleJSON: String? = nil,
         sceneBreakdownJSON: String? = nil,
         language: Language,
         level: Int,
         createdAt: Date = Date(),
         updatedAt: Date? = nil) {
        self.id = id
        self.userID = userID
        self.title = title
        self.targetLanguageText = targetLanguageText
        self.nativeLanguageText = nativeLanguageText
        self.prompt = prompt
        self.textGenPrompt = textGenPrompt
        self.imageGenPrompt = imageGenPrompt
        self.preferencesJSON = preferencesJSON
        self.wordTimingsJSON = wordTimingsJSON
        self.speakerVoicesJSON = speakerVoicesJSON
        self.taggedTargetText = taggedTargetText
        self.audioFilename = audioFilename
        self.remoteAudioPath = remoteAudioPath
        self.remoteCoverPath = remoteCoverPath
        self.coverArt = coverArt
        self.videoStyle = videoStyle
        self.videoGenPrompt = videoGenPrompt
        self.remoteVideoPath = remoteVideoPath
        self.ambientSoundId = ambientSoundId
        self.ambientVolume = ambientVolume
        self.chaptersJSON = chaptersJSON
        self.layoutJSON = layoutJSON
        self.readingMatterPagesJSON = readingMatterPagesJSON
        self.assetForgeJSON = assetForgeJSON
        self.ciProfileJSON = ciProfileJSON
        self.bibleJSON = bibleJSON
        self.sceneBreakdownJSON = sceneBreakdownJSON
        self.languageRaw = language.rawValue
        self.levelRaw = String(level)
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isFavorite = false
    }
}
