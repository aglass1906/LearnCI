import Foundation
import SwiftData
import Observation

@Observable
class StatsManager {
    static let shared = StatsManager()
    
    struct LearningStats {
        var totalHours: Double = 0
        var totalLearningDays: Int = 0
        var currentActivityStreak: Int = 0
        var currentGoalStreak: Int = 0
        var bestActivityStreak: Int = 0
        var bestGoalStreak: Int = 0
    }
    
    func calculateStats(activities: [UserActivity], profile: UserProfile?) -> LearningStats {
        guard let profile = profile else { return LearningStats() }
        
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        
        // 1. Total Hours
        let baseMinutes = profile.totalMinutes
        let pendingMinutes = activities.filter { !$0.isSynced }.reduce(0) { $0 + $1.minutes }
        let startingMinutes = profile.startingHours * 60
        let totalMinutes = baseMinutes + pendingMinutes + startingMinutes
        let totalHours = Double(totalMinutes) / 60.0
        
        // 2. Total Learning Days
        let startDate = profile.originalStartDate ?? activities.last?.date ?? now
        let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: today)
        let totalLearningDays = (components.day ?? 0) + 1
        
        // 3. Streak Calculations
        // Group activities by start of day
        let activitiesByDay = Dictionary(grouping: activities) { activity in
            calendar.startOfDay(for: activity.date)
        }
        
        // Current Activity Streak
        var activityStreak = 0
        var currentDay = today
        
        // If they haven't learned today, check if they learned yesterday to maintain streak
        if activitiesByDay[today] == nil {
            currentDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }
        
        while let dayActivities = activitiesByDay[currentDay], !dayActivities.isEmpty {
            activityStreak += 1
            guard let prevDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else { break }
            currentDay = prevDay
        }
        
        // Current Goal Streak
        var goalStreak = 0
        let goalMinutes = profile.dailyGoalMinutes
        currentDay = today
        
        // For goal streak, if they haven't met goal today yet, it's not broken until today is over.
        // So we check from yesterday if today's goal isn't met yet.
        let todayMintues = activitiesByDay[today]?.reduce(0) { $0 + $1.minutes } ?? 0
        if todayMintues < goalMinutes {
            currentDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }
        
        while let dayActivities = activitiesByDay[currentDay] {
            let dayMinutes = dayActivities.reduce(0) { $0 + $1.minutes }
            if dayMinutes >= goalMinutes {
                goalStreak += 1
            } else if currentDay == today {
                // Ignore today if goal not met yet, streak not technically broken
            } else {
                break
            }
            guard let prevDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else { break }
            currentDay = prevDay
        }
        
        // 4. Update Best Streaks in Profile if needed
        var bestActivity = profile.longestActivityStreak
        var bestGoal = profile.longestGoalStreak
        
        var needsSave = false
        if activityStreak > bestActivity {
            bestActivity = activityStreak
            profile.longestActivityStreak = activityStreak
            needsSave = true
        }
        if goalStreak > bestGoal {
            bestGoal = goalStreak
            profile.longestGoalStreak = goalStreak
            needsSave = true
        }
        
        // Note: Caller is responsible for saving modelContext if needsSave is true
        // and we will return needsSave info or let the view handle it.
        
        return LearningStats(
            totalHours: totalHours,
            totalLearningDays: totalLearningDays,
            currentActivityStreak: activityStreak,
            currentGoalStreak: goalStreak,
            bestActivityStreak: bestActivity,
            bestGoalStreak: bestGoal
        )
    }
}
