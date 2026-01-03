import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    @Query private var allProfiles: [UserProfile]
    
    var activities: [UserActivity] {
        allActivities.filter { $0.userID == authManager.currentUser }
    }
    
    var profiles: [UserProfile] {
        allProfiles.filter { $0.userID == authManager.currentUser }
    }
    
    @State private var audioManager = AudioManager()
    @State private var wordOfDay: LearningCard?
    @State private var wordOfDayFolder: String?
    @State private var isLoadingWordOfDay = false
    
    var userProfile: UserProfile? {
        profiles.first
    }
    
    var totalMinutes: Int {
        activities.reduce(0) { $0 + $1.minutes }
    }
    
    var todayActivities: [UserActivity] {
        let calendar = Calendar.current
        return activities.filter { calendar.isDateInToday($0.date) }
    }
    
    var todayMinutes: Int {
        todayActivities.reduce(0) { $0 + $1.minutes }
    }
    
    var activityByType: [ActivityTypeData] {
        let grouped = Dictionary(grouping: activities, by: { $0.activityType })
        return grouped.map { type, activities in
            ActivityTypeData(
                type: type,
                minutes: activities.reduce(0) { $0 + $1.minutes }
            )
        }.sorted { $0.minutes > $1.minutes }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    if let profile = userProfile {
                        HStack {
                            Text("Hola, \(profile.name)!")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            Spacer()
                            Text(profile.currentLanguage.flag)
                                .font(.largeTitle)
                        }
                        .padding()
                    }
                    
                    // Today's Stats Card
                    VStack(spacing: 8) {
                        Text("Today's Progress")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(todayMinutes)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                            
                            Text("/ \(userProfile?.dailyGoalMinutes ?? 30)")
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                            
                            Text("min")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            
                            if todayMinutes >= (userProfile?.dailyGoalMinutes ?? 30) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        // Progress bar
                        if let goal = userProfile?.dailyGoalMinutes, goal > 0 {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 8)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(todayMinutes >= goal ? Color.green : Color.blue)
                                        .frame(width: min(CGFloat(todayMinutes) / CGFloat(goal) * geometry.size.width, geometry.size.width), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Leaderboard Entry
                    NavigationLink(destination: LeaderboardView()) {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow)
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text("Global Leaderboard")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("See where you rank!")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Word of the Day
                    wordOfDaySection
                    
                    // Activity Breakdown Chart
                    if !activities.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Activity Breakdown")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .padding(.horizontal)
                            
                            Chart(activityByType) { data in
                                BarMark(
                                    x: .value("Minutes", data.minutes),
                                    y: .value("Type", data.type.rawValue)
                                )
                                .foregroundStyle(data.type.color)
                                .annotation(position: .trailing) {
                                    Text("\(data.minutes) min")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(height: CGFloat(activityByType.count) * 44)
                            .chartXAxis {
                                AxisMarks(position: .bottom)
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Recent Activity
                    HStack {
                        Text("Recent Activity")
                            .font(.title2)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    if activities.isEmpty {
                        Text("No activities recorded yet.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(activities.prefix(5)) { activity in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: activity.activityType.icon)
                                        .font(.title3)
                                        .foregroundStyle(activity.activityType.isInput ? .green : .blue)
                                        .frame(width: 24, height: 24)
                                        .background(activity.activityType.isInput ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(activity.activityType.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        
                                        if let comment = activity.comment, !comment.isEmpty {
                                            Text(comment)
                                                .font(.caption)
                                                .foregroundStyle(.primary.opacity(0.8))
                                                .lineLimit(1)
                                        }
                                        
                                        Text(activity.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(activity.minutes)m")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(activity.activityType.isInput ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
            .task {
                if let profile = userProfile, wordOfDay == nil {
                    isLoadingWordOfDay = true
                    if let result = await dataManager.fetchWordOfDay(language: profile.currentLanguage, level: profile.currentLevel) {
                        wordOfDay = result.card
                        wordOfDayFolder = result.folder
                    }
                    isLoadingWordOfDay = false
                }
            }
        }
    }
    
    private var wordOfDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Word of the Day")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
            }
            .padding(.horizontal)
            
            if let word = wordOfDay {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(word.targetWord)
                                .font(.title)
                                .fontWeight(.bold)
                            Text(word.nativeTranslation)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            if let file = word.audioWordFile {
                                audioManager.playAudio(named: file, folderName: wordOfDayFolder)
                            }
                        }) {
                            Image(systemName: "speaker.wave.2.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text(word.sentenceTarget)
                            .font(.subheadline.italic())
                        Text(word.sentenceNative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(15)
                .padding(.horizontal)
            } else if isLoadingWordOfDay {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("Selecting daily word...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            } else {
                HStack {
                    Spacer()
                    Text("No daily word found for your current level.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            }
        }
    }
}

#Preview {
    DashboardView()
        .environment(DataManager())
        .environment(YouTubeManager())
        .environment(AuthManager())
}

struct ActivityTypeData: Identifiable {
    let id = UUID()
    let type: ActivityType
    let minutes: Int
}

extension ActivityType {
    var color: Color {
        switch self {
        case .appLearning:
            return .blue
        case .flashcards:
            return .teal
        case .watchingVideos:
            return .red
        case .listeningPodcasts:
            return .green
        case .reading:
            return .cyan
        case .crossTalk:
            return .orange
        case .tutoring:
            return .purple
        case .speaking:
            return .pink
        case .writing:
            return .indigo
        }
    }
}
