import Foundation
import SwiftData

enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case appLearning = "App Learning"
    case watchingVideos = "Watching Videos"
    case listeningPodcasts = "Listening Podcasts"
    case reading = "Reading"
    case crossTalk = "CrossTalk"
    case tutoring = "Language Tutors"
    case speaking = "Speaking"
    case writing = "Writing"
    
    var id: String { self.rawValue }
    
    var isInput: Bool {
        switch self {
        case .speaking, .writing: return false
        default: return true
        }
    }
}

@Model
final class UserActivity {
    var id: UUID
    var date: Date
    var minutes: Int
    var activityTypeRaw: String
    var languageRaw: String
    
    var activityType: ActivityType {
        get { ActivityType(rawValue: activityTypeRaw) ?? .appLearning }
        set { activityTypeRaw = newValue.rawValue }
    }
    
    var language: Language {
        get { Language(rawValue: languageRaw) ?? .spanish }
        set { languageRaw = newValue.rawValue }
    }
    
    init(date: Date = Date(), minutes: Int, activityType: ActivityType, language: Language) {
        self.id = UUID()
        self.date = date
        self.minutes = minutes
        self.activityTypeRaw = activityType.rawValue
        self.languageRaw = language.rawValue
    }
}
