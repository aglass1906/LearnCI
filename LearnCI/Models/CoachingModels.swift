import Foundation
import SwiftData

@Model
final class DailyFeedback {
    var id: UUID
    var date: Date
    var rating: Int // 1-5
    var note: String?
    var userID: String? // Supabase Auth ID
    var isSynced: Bool = false
    
    init(date: Date = Date(), rating: Int, note: String? = nil, userID: String? = nil) {
        self.id = UUID()
        self.date = date
        self.rating = rating
        self.note = note
        self.userID = userID
        self.isSynced = false
    }

    var moodDescription: String {
        return DailyFeedback.moodLabel(for: rating)
    }
    
    static func moodLabel(for rating: Int) -> String {
        switch rating {
        case 1: return "Frustrated"
        case 2: return "Struggling"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "Great!"
        default: return "Unknown"
        }
    }
}

@Model
final class CoachingCheckIn {
    var id: UUID
    var date: Date
    var hoursMilestone: Int // e.g. 25, 50, 75
    var userID: String?
    
    // Ratings for each activity type (1-5)
    // Stored as a dictionary for flexibility: [ActivityType.rawValue : Rating]
    var activityRatings: [String: Int] 
    
    // Reflections
    var progressSentiment: String // "How do you feel about your progress?"
    var nextCyclePlan: String // "What will you do next?"

    var notes: String?
    var isSynced: Bool = false
    
    init(date: Date = Date(), hoursMilestone: Int, userID: String? = nil, activityRatings: [String: Int] = [:], progressSentiment: String = "", nextCyclePlan: String = "", notes: String? = nil) {
        self.id = UUID()
        self.date = date
        self.hoursMilestone = hoursMilestone
        self.userID = userID
        self.activityRatings = activityRatings
        self.progressSentiment = progressSentiment
        self.nextCyclePlan = nextCyclePlan
        self.notes = notes
        self.isSynced = false
    }
}

// Helper for UI
struct ActivityRatingItem: Identifiable {
    let id = UUID()
    let type: ActivityType
    var rating: Double // Double for Slider binding
}
