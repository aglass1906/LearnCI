import Foundation
import SwiftData
import SwiftUI

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
        case 1: return "Bad"
        case 2: return "Struggling"
        case 3: return "Good"
        case 4: return "Great"
        case 5: return "Amazing"
        default: return "Unknown"
        }
    }
    
    static func moodIconName(for rating: Int) -> String {
        switch rating {
        case 1: return "cloud.rain.fill"
        case 2: return "cloud.fill"
        case 3: return "cloud.sun.fill"
        case 4: return "sun.max.fill"
        case 5: return "sparkles"
        default: return "questionmark.circle"
        }
    }
    
    static func moodColor(for rating: Int) -> Color {
        switch rating {
        case 1: return .gray
        case 2: return .blue.opacity(0.6)
        case 3: return .orange.opacity(0.7)
        case 4: return .yellow
        case 5: return .yellow
        default: return .gray
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
