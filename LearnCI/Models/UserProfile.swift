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
    
    var currentLanguage: Language {
        get { Language(rawValue: currentLanguageRaw) ?? .spanish }
        set { languageRawUpdate(newValue) }
    }
    
    var currentLevel: LearningLevel {
        get { LearningLevel(rawValue: currentLevelRaw) ?? .superBeginner }
        set { levelRawUpdate(newValue) }
    }
    
    init(name: String = "Learner", currentLanguage: Language = .spanish, currentLevel: LearningLevel = .superBeginner, dailyGoalMinutes: Int = 30, dailyCardGoal: Int = 20, userID: String? = nil, totalMinutes: Int = 0) {
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
    }
    
    private func languageRawUpdate(_ newValue: Language) {
        currentLanguageRaw = newValue.rawValue
    }
    
    private func levelRawUpdate(_ newValue: LearningLevel) {
        currentLevelRaw = newValue.rawValue
    }
}
