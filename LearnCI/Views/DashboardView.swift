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
    
    @Environment(AudioManager.self) private var audioManager
    @State private var wordOfDay: LearningCard?
    @State private var wordOfDayFolder: String?
    @State private var isLoadingWordOfDay = false
    @State private var inspirationalQuote: InspirationalQuote?
    
    var userProfile: UserProfile? {
        profiles.first
    }
    
    var totalMinutes: Int {
        let activityMinutes = activities.reduce(0) { $0 + $1.minutes }
        let startingMinutes = (userProfile?.startingHours ?? 0) * 60
        return activityMinutes + startingMinutes
    }
    
    var todayActivities: [UserActivity] {
        let calendar = Calendar.current
        return activities.filter { calendar.isDateInToday($0.date) }
    }
    
    var todayMinutes: Int {
        todayActivities.reduce(0) { $0 + $1.minutes }
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
        ZStack {
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
                        } else {
                            // Invisible placeholder to prevent layout jumps
                            HStack {
                                Text("Hola!")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .opacity(0)
                                Spacer()
                            }
                            .padding()
                        }
                        
                        // Daily Feedback (Coaching)
                        dailyFeedbackCard
                        
                        // Roadmap (Coaching)
                        roadmapSection
                        
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
                        
                        // Inspirational Quote
                        if let quote = inspirationalQuote {
                            VStack(spacing: 8) {
                                Text("\"\(quote.text)\"")
                                    .font(.system(.body, design: .serif))
                                    .italic()
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.primary)
                                
                                Text("- \(quote.author)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue.opacity(0.1), lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal)
                        }
                        
                        // Activity Breakdown Chart
                        ActivityBreakdownChart(activityByType: activityByType)
                        
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
                    // Start minimum loading duration logic if needed here, 
                    // but for now relying on data triggers.
                    
                    if inspirationalQuote == nil {
                        inspirationalQuote = dataManager.getRandomQuote()
                    }
                    
                    // We need to wait for profile to be available (Async in SwiftData can be immediate but safe to check)
                    // If profile is missing, we might need to trigger creation or wait (ProfileView handles creation usually)
                    
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
            
            // Loading Overlay
            if userProfile == nil || (isLoadingWordOfDay && wordOfDay == nil) {
                LoadingView(message: "Loading your progress...")
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .zIndex(1)
            }
        }
    }
    
    @State private var showCheckInSheet = false
    
    // ... (Existing code)
    
    // MARK: - Daily Feedback Logic
    
    @Query(sort: \DailyFeedback.date, order: .reverse) private var feedbackHistory: [DailyFeedback]
    
    var todaysFeedback: DailyFeedback? {
        let calendar = Calendar.current
        return feedbackHistory.first { calendar.isDateInToday($0.date) && $0.userID == authManager.currentUser }
    }
    
    // MARK: - Check-in Logic
    
    var isCheckInDue: Bool {
        guard let profile = userProfile else { return false }
        let currentHours = totalMinutes / 60
        // Trigger every 25 hours
        return currentHours >= (profile.lastCheckInHours + 25)
    }
    
    var hoursToNextMilestone: Int {
        guard let profile = userProfile else { return 25 }
        let currentHours = totalMinutes / 60
        let nextMilestone = profile.lastCheckInHours + 25
        return max(0, nextMilestone - currentHours)
    }
    
    // MARK: - Views
    
    private var dailyFeedbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Coaching")
                    .font(.headline)
                
                if !isCheckInDue {
                    Text("• Next Check-in: \(hoursToNextMilestone)h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                NavigationLink(destination: CoachingHistoryView()) {
                    Text("History")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal)
            
            // Check-in Banner
            if isCheckInDue, let profile = userProfile {
                Button(action: { showCheckInSheet = true }) {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .font(.title)
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading) {
                            Text("Milestone Reached!")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("It's time for your \(profile.lastCheckInHours + 25)h check-in.")
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
                    .shadow(color: .yellow.opacity(0.3), radius: 5)
                }
                .padding(.horizontal)
                .sheet(isPresented: $showCheckInSheet) {
                    CoachingCheckInView(
                        userProfile: profile,
                        currentHours: totalMinutes / 60,
                        milestone: profile.lastCheckInHours + 25
                    )
                }
            }
            
            // Daily Feedback Content
            VStack(alignment: .leading, spacing: 12) {
                Text("How are you feeling today?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let feedback = todaysFeedback {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("Thanks for checking in!")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(DailyFeedback.moodLabel(for: feedback.rating))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        Spacer()
                        moodIcon(for: feedback.rating)
                            .font(.title2)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                } else {
                    HStack(spacing: 0) {
                        ForEach(1...5, id: \.self) { rating in
                            Button(action: {
                                saveDailyFeedback(rating: rating)
                            }) {
                                VStack(spacing: 4) {
                                    moodIcon(for: rating)
                                        .font(.title2)
                                    Text(DailyFeedback.moodLabel(for: rating))
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func moodIcon(for rating: Int) -> some View {
        let iconName: String
        let color: Color
        switch rating {
        case 1: iconName = "cloud.rain.fill"; color = .gray
        case 2: iconName = "cloud.fill"; color = .blue.opacity(0.6)
        case 3: iconName = "cloud.sun.fill"; color = .orange.opacity(0.7)
        case 4: iconName = "sun.max.fill"; color = .yellow
        case 5: iconName = "sparkles"; color = .yellow
        default: iconName = "questionmark.circle"; color = .gray
        }
        
        return Image(systemName: iconName)
            .foregroundStyle(color)
    }
    
    private func saveDailyFeedback(rating: Int) {
        print("Saving Daily Feedback: Rating \(rating), User: \(authManager.currentUser ?? "nil")")
        let feedback = DailyFeedback(
            rating: rating,
            userID: authManager.currentUser
        )
        modelContext.insert(feedback)
        do {
            try modelContext.save()
            print("Daily Feedback Saved Successfully!")
        } catch {
            print("Error saving daily feedback: \(error)")
        }
    }

    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input Roadmap")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            if let profile = userProfile {
                let currentHours = totalMinutes / 60
                
                VStack(spacing: 0) {
                    // Level 1: 0-50h
                    roadmapLevel(level: 1, range: 0...50, current: currentHours, color: .teal)
                    // Level 2: 50-150h
                    roadmapLevel(level: 2, range: 50...150, current: currentHours, color: .green)
                    // Level 3: 150-300h
                    roadmapLevel(level: 3, range: 150...300, current: currentHours, color: .blue)
                    // Level 4: 300-600h
                    roadmapLevel(level: 4, range: 300...600, current: currentHours, color: .orange)
                    // Level 5: 600-1000h
                    roadmapLevel(level: 5, range: 600...1000, current: currentHours, color: .purple)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func roadmapLevel(level: Int, range: ClosedRange<Int>, current: Int, color: Color) -> some View {
        let isCompleted = current >= range.upperBound
        let isInProgress = range.contains(current)
        
        // Progress within this specific level
        let levelTotal = range.upperBound - range.lowerBound
        let levelCurrent = max(0, min(current - range.lowerBound, levelTotal))
        let progress = CGFloat(levelCurrent) / CGFloat(levelTotal)
        
        return HStack(spacing: 8) {
            Text("L\(level)")
                .font(.caption.bold())
                .frame(width: 24)
                .foregroundStyle(isCompleted || isInProgress ? color : .secondary)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(UIColor.secondarySystemFill))
                        .frame(height: 8)
                    
                    if isCompleted {
                        Capsule()
                            .fill(color)
                            .frame(height: 8)
                    } else if isInProgress {
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * progress, height: 8)
                    }
                }
            }
            .frame(height: 8)
            
            Text("\(range.upperBound)h")
                .font(.caption)
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity((isCompleted || isInProgress) ? 1.0 : 0.4)
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
                        
                        if let file = word.audioWordFile, audioManager.audioExists(named: file, folderName: wordOfDayFolder) {
                            Button(action: {
                                audioManager.playAudio(named: file, folderName: wordOfDayFolder)
                            }) {
                                Image(systemName: "speaker.wave.2.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.blue)
                            }
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
