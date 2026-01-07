import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var userID: String? // Supabase Auth ID
    var name: String
    var currentLanguageRaw: String
    var currentLevelRaw: String
    var dailyGoalMinutes: Int
    var dailyCardGoal: Int?
    var isPublic: Bool = false
    var totalMinutes: Int = 0
    var updatedAt: Date = Date()
    
    // New Profile Fields
    var email: String?
    var fullName: String?
    var location: String?
    var avatarUrl: String?
    
    // Preferences
    var defaultGamePresetRaw: String = GameConfiguration.Preset.inputFocus.rawValue
    var customGameConfiguration: GameConfiguration? // Persisted custom settings
    
    // Legacy support or direct access
    // var savedCustomConfig: GameConfiguration? { ... }
    
    var currentLanguage: Language {
        get { Language(rawValue: currentLanguageRaw) ?? .spanish }
        set { languageRawUpdate(newValue) }
    }
    
    var currentLevel: LearningLevel {
        get { LearningLevel(rawValue: currentLevelRaw) ?? .superBeginner }
        set { levelRawUpdate(newValue) }
    }
    
    var defaultGamePreset: GameConfiguration.Preset {
        get { GameConfiguration.Preset(rawValue: defaultGamePresetRaw) ?? .inputFocus }
        set { defaultGamePresetRaw = newValue.rawValue }
    }
    
    var lastSelectedDeckId: String?
    var lastCheckInHours: Int = 0 // Tracks the last milestone (0, 25, 50...)
    var startingHours: Int = 0 // Manual offset for previous experience
    var ttsRate: Float = 0.5 // Audio Speed Preference
    
    init(name: String = "Learner", currentLanguage: Language = .spanish, currentLevel: LearningLevel = .superBeginner, dailyGoalMinutes: Int = 30, dailyCardGoal: Int = 20, userID: String? = nil, totalMinutes: Int = 0, defaultPreset: GameConfiguration.Preset = .inputFocus, lastSelectedDeckId: String? = nil, lastCheckInHours: Int = 0, startingHours: Int = 0, ttsRate: Float = 0.5) {
        self.id = UUID()
        self.userID = userID
        self.name = name
        self.currentLanguageRaw = currentLanguage.rawValue
        self.currentLevelRaw = currentLevel.rawValue
        self.dailyGoalMinutes = dailyGoalMinutes
        self.dailyCardGoal = dailyCardGoal
        self.isPublic = false
        self.totalMinutes = totalMinutes
        self.updatedAt = Date()
        self.defaultGamePresetRaw = defaultPreset.rawValue
        self.lastSelectedDeckId = lastSelectedDeckId
        self.lastCheckInHours = lastCheckInHours
        self.startingHours = startingHours
        self.ttsRate = ttsRate
    }
    
    private func languageRawUpdate(_ newValue: Language) {
        currentLanguageRaw = newValue.rawValue
    }
    
    private func levelRawUpdate(_ newValue: LearningLevel) {
        currentLevelRaw = newValue.rawValue
    }
}
