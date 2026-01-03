import Foundation
import SwiftData

enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case appLearning = "App Learning"
    case flashcards = "Flashcards"
    case watchingVideos = "Watching Videos"
    case listeningPodcasts = "Listening Podcasts"
    case reading = "Reading"
    case crossTalk = "CrossTalk"
    case tutoring = "Language Tutors"
    case speaking = "Speaking"
    case writing = "Writing"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .appLearning: return "app.fill"
        case .flashcards: return "rectangle.stack.fill"
        case .watchingVideos: return "play.rectangle.fill"
        case .listeningPodcasts: return "headphones"
        case .reading: return "book.fill"
        case .crossTalk: return "bubble.left.and.bubble.right.fill"
        case .tutoring: return "person.2.fill"
        case .speaking: return "mic.fill"
        case .writing: return "pencil"
        }
    }
    
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
    var userID: String? // Supabase Auth ID
    var isSynced: Bool = false
    var comment: String?
    
    var activityType: ActivityType {
        get { ActivityType(rawValue: activityTypeRaw) ?? .appLearning }
        set { activityTypeRaw = newValue.rawValue }
    }
    
    var language: Language {
        get { Language(rawValue: languageRaw) ?? .spanish }
        set { languageRaw = newValue.rawValue }
    }
    
    init(date: Date = Date(), minutes: Int, activityType: ActivityType, language: Language, userID: String? = nil, comment: String? = nil) {
        self.id = UUID()
        self.date = date
        self.minutes = minutes
        self.activityTypeRaw = activityType.rawValue
        self.languageRaw = language.rawValue
        self.userID = userID
        self.isSynced = false
        self.comment = comment
    }
}
