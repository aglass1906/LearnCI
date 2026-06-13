import Foundation
import SwiftData

@Model
final class UserProfile {
    static let currentOnboardingVersion = 1

    var id: UUID
    var userID: String? // Supabase Auth ID
    var name: String
    var currentLanguageRaw: String
    var currentLevelRaw: String // Legacy, kept for safety
    var proficiencyLevel: Int = 1 // 1-6
    var preferredScaleRaw: String = "Simple"
    
    var dailyGoalMinutes: Int
    var dailyCardGoal: Int?
    var isPublic: Bool = false
    var totalMinutes: Int = 0
    var updatedAt: Date = Date()
    var onboardingVersion: Int = 0
    var onboardingCompletedAt: Date?
    
    // New Profile Fields
    var email: String?
    var fullName: String?
    var location: String?
    var avatarUrl: String?
    
    // Streak & Stats Persistence
    var originalStartDate: Date?
    var longestActivityStreak: Int = 0
    var longestGoalStreak: Int = 0
    
    // Preferences
    var defaultGamePresetRaw: String = GameConfiguration.Preset.inputFocus.rawValue
    var lastGameTypeRaw: String = GameConfiguration.GameType.flashcards.rawValue // Added persistence
    var customGameConfiguration: GameConfiguration? // Persisted custom settings
    private var gameSoundEffectsEnabledRaw: Bool = true
    private var gameHapticsEnabledRaw: Bool = true
    
    // Legacy support or direct access
    // var savedCustomConfig: GameConfiguration? { ... }
    
    var currentLanguage: Language {
        get { 
            if let lang = Language(rawValue: currentLanguageRaw) { return lang }
            // Legacy Fallback
            switch currentLanguageRaw {
            case "Spanish": return .spanish
            case "Japanese": return .japanese
            case "Korean": return .korean
            case "French": return .french
            default: return .spanish
            }
        }
        set { languageRawUpdate(newValue) }
    }
    
    var currentLevel: LearningLevel {
        get { LearningLevel(rawValue: currentLevelRaw) ?? .superBeginner }
        set { levelRawUpdate(newValue) }
    }

    var hasCompletedOnboarding: Bool {
        onboardingVersion >= Self.currentOnboardingVersion
    }
    
    var defaultGamePreset: GameConfiguration.Preset {
        get { GameConfiguration.Preset(rawValue: defaultGamePresetRaw) ?? .inputFocus }
        set { 
            defaultGamePresetRaw = newValue.rawValue
            bumpUpdate()
        }
    }
    
    var preferredScale: ProficiencyScale {
        get { ProficiencyScale(rawValue: preferredScaleRaw) ?? .simple }
        set { 
            preferredScaleRaw = newValue.rawValue
            bumpUpdate()
        }
    }
    
    var currentGameType: GameConfiguration.GameType {
        get { GameConfiguration.GameType(rawValue: lastGameTypeRaw) ?? .flashcards }
        set { 
            lastGameTypeRaw = newValue.rawValue
            bumpUpdate()
        }
    }

    var gameSoundEffectsEnabled: Bool {
        get { gameSoundEffectsEnabledRaw }
        set {
            gameSoundEffectsEnabledRaw = newValue
            bumpUpdate()
        }
    }

    var gameHapticsEnabled: Bool {
        get { gameHapticsEnabledRaw }
        set {
            gameHapticsEnabledRaw = newValue
            bumpUpdate()
        }
    }
    
    private var lastIdRaw: String?
    var lastSelectedDeckId: String? {
        get { lastIdRaw }
        set { 
            lastIdRaw = newValue
            bumpUpdate()
        }
    }
    
    var lastCheckInHours: Int = 0 // Tracks the last milestone (0, 25, 50...)
    var startingHours: Int = 0 // Manual offset for previous experience
    
    private var ttsRateRaw: Float = 0.5
    var ttsRate: Float { // Audio Speed Preference
        get { ttsRateRaw }
        set { 
            ttsRateRaw = newValue
            bumpUpdate()
        }
    }
    
    private var ttsVoiceGenderRaw: String = "female"
    var ttsVoiceGender: String { // "male" or "female"
        get { ttsVoiceGenderRaw }
        set { 
            ttsVoiceGenderRaw = newValue
            bumpUpdate()
        }
    }
    
    init(name: String = "Learner", currentLanguage: Language = .spanish, currentLevel: LearningLevel = .superBeginner, dailyGoalMinutes: Int = 30, dailyCardGoal: Int = 20, userID: String? = nil, totalMinutes: Int = 0, defaultPreset: GameConfiguration.Preset = .inputFocus, lastGameType: GameConfiguration.GameType = .flashcards, lastSelectedDeckId: String? = nil, lastCheckInHours: Int = 0, startingHours: Int = 0, ttsRate: Float = 0.5, ttsVoiceGender: String = "female", gameSoundEffectsEnabled: Bool = true, gameHapticsEnabled: Bool = true) {
        self.id = UUID()
        self.userID = userID
        self.name = name
        self.currentLanguageRaw = currentLanguage.rawValue
        self.currentLevelRaw = currentLevel.rawValue
        
        // Auto-migrate legacy level to int
        self.proficiencyLevel = LevelManager.shared.normalize(currentLevel)
        
        self.dailyGoalMinutes = dailyGoalMinutes
        self.dailyCardGoal = dailyCardGoal
        self.isPublic = false
        self.totalMinutes = totalMinutes
        self.updatedAt = Date()
        self.defaultGamePresetRaw = defaultPreset.rawValue
        self.lastGameTypeRaw = lastGameType.rawValue
        self.lastIdRaw = lastSelectedDeckId
        self.lastCheckInHours = lastCheckInHours
        self.startingHours = startingHours
        self.ttsRateRaw = ttsRate
        self.ttsVoiceGenderRaw = ttsVoiceGender
        self.gameSoundEffectsEnabledRaw = gameSoundEffectsEnabled
        self.gameHapticsEnabledRaw = gameHapticsEnabled
        
        // Initialize new fields with safe defaults if needed
        self.originalStartDate = Date()
        self.longestActivityStreak = 0
        self.longestGoalStreak = 0
    }
    
    private func languageRawUpdate(_ newValue: Language) {
        currentLanguageRaw = newValue.rawValue
        bumpUpdate()
    }
    
    private func levelRawUpdate(_ newValue: LearningLevel) {
        currentLevelRaw = newValue.rawValue
        bumpUpdate()
    }

    func bumpUpdate() {
        updatedAt = Date()
    }

    func completeOnboarding(
        name: String,
        language: Language,
        proficiencyLevel: Int,
        dailyGoalMinutes: Int,
        completedAt: Date = Date()
    ) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        currentLanguageRaw = language.rawValue
        self.proficiencyLevel = min(max(proficiencyLevel, 1), 6)
        currentLevelRaw = Self.learningLevel(for: self.proficiencyLevel).rawValue
        self.dailyGoalMinutes = dailyGoalMinutes
        onboardingVersion = Self.currentOnboardingVersion
        onboardingCompletedAt = completedAt
        updatedAt = completedAt
    }

    static func learningLevel(for proficiencyLevel: Int) -> LearningLevel {
        switch proficiencyLevel {
        case ...1: return .superBeginner
        case 2: return .beginner
        case 3...4: return .intermediate
        default: return .advanced
        }
    }
}
