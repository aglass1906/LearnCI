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
                    
                    // Stats Card
                    VStack {
                        Text("Total Learning Time")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("\(totalMinutes) min")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
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
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(activity.activityType.rawValue)
                                            .font(.headline)
                                        Text(activity.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("\(activity.minutes) min")
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(10)
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
