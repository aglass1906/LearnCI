import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var name: String
    var currentLanguageRaw: String
    var currentLevelRaw: String
    var dailyGoalMinutes: Int
    var dailyCardGoal: Int?
    
    var currentLanguage: Language {
        get { Language(rawValue: currentLanguageRaw) ?? .spanish }
        set { languageRawUpdate(newValue) }
    }
    
    var currentLevel: LearningLevel {
        get { LearningLevel(rawValue: currentLevelRaw) ?? .superBeginner }
        set { levelRawUpdate(newValue) }
    }
    
    init(name: String = "Learner", currentLanguage: Language = .spanish, currentLevel: LearningLevel = .superBeginner, dailyGoalMinutes: Int = 30, dailyCardGoal: Int = 20) {
        self.id = UUID()
        self.name = name
        self.currentLanguageRaw = currentLanguage.rawValue
        self.currentLevelRaw = currentLevel.rawValue
        self.dailyGoalMinutes = dailyGoalMinutes
        self.dailyCardGoal = dailyCardGoal
    }
    
    private func languageRawUpdate(_ newValue: Language) {
        currentLanguageRaw = newValue.rawValue
    }
    
    private func levelRawUpdate(_ newValue: LearningLevel) {
        currentLevelRaw = newValue.rawValue
    }
}
