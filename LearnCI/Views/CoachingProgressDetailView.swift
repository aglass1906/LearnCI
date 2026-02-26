import SwiftUI
import SwiftData

struct CoachingProgressDetailView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    @Query private var allProfiles: [UserProfile]
    
    var activities: [UserActivity] {
        allActivities.filter { $0.userID == authManager.currentUser }
    }
    
    var userProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }
    
    var learningStats: StatsManager.LearningStats {
        StatsManager.shared.calculateStats(activities: activities, profile: userProfile)
    }
    
    var totalMinutes: Int {
        Int(learningStats.totalHours * 60)
    }
    
    var todayActivities: [UserActivity] {
        let calendar = Calendar.current
        return activities.filter { calendar.isDateInToday($0.date) }
    }
    
    var activityByType: [ActivityTypeData] {
        let grouped = Dictionary(grouping: todayActivities, by: { $0.activityType })
        return grouped.map { type, activities in
            ActivityTypeData(
                type: type,
                minutes: activities.reduce(0) { $0 + $1.minutes }
            )
        }.sorted { $0.minutes > $1.minutes }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Learning Stats Card (Reused from Dashboard)
                LearningStatsCard(stats: learningStats)
                    .padding(.top, 10)
                
                // 2. Roadmap Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundStyle(.green)
                        Text("Input Roadmap")
                            .font(.headline)
                        Spacer()
                        Text("\(totalMinutes / 60)h Total")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    RoadmapView(totalMinutes: totalMinutes)
                }
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                .padding(.horizontal)
                
                // 3. Today's Breakdown
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundStyle(.blue)
                        Text("Today's Breakdown")
                            .font(.headline)
                    }
                    
                    ActivityBreakdownChart(activityByType: activityByType)
                        .frame(height: 200)
                }
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Progress Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CoachingProgressDetailView()
            .environment(DataManager())
            .environment(AuthManager())
            .modelContainer(for: [UserActivity.self, UserProfile.self], inMemory: true)
    }
}
