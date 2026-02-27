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
    
    // Computed property to easy decoding of word timings
    @Transient var wordTimings: [WordTiming] {
        guard let json = wordTimingsJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WordTiming].self, from: data)) ?? []
    }

    @Transient var comprehensionQuestions: [ComprehensionQuestion] {
        guard let json = comprehensionQuestionsJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ComprehensionQuestion].self, from: data)) ?? []
    }
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
         audioFilename: String? = nil,
         remoteAudioPath: String? = nil,
         remoteCoverPath: String? = nil,
         coverArt: String? = nil,
         videoStyle: String? = nil,
         videoGenPrompt: String? = nil,
         remoteVideoPath: String? = nil,
         language: Language, 
         level: Int,
         createdAt: Date = Date()) {
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
        self.audioFilename = audioFilename
        self.remoteAudioPath = remoteAudioPath
        self.remoteCoverPath = remoteCoverPath
        self.coverArt = coverArt
        self.videoStyle = videoStyle
        self.videoGenPrompt = videoGenPrompt
        self.remoteVideoPath = remoteVideoPath
        self.languageRaw = language.rawValue
        self.levelRaw = String(level)
        self.createdAt = createdAt
        self.isFavorite = false
    }
}
