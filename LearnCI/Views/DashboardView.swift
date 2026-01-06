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
                        NavigationLink(destination: HistoryView()) {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Today's Progress")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
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
                                
                                // Activity Breakdown Chart
                                if !activityByType.isEmpty {
                                    Divider()
                                        .padding(.vertical, 4)
                                    ActivityBreakdownChart(activityByType: activityByType)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                        
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
                        

                        

                    }
                }

                .task {
                    // Start minimum loading duration logic if needed here, 
                    // but for now relying on data triggers.
                    

                    
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
                Text("How are you feeling today about your language learning?")
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
                    VStack(spacing: 8) {
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
                        
                        HStack {
                            Text("Rough")
                            Spacer()
                            Text("Great")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Input Roadmap")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                if let profile = userProfile {
                    let currentHours = totalMinutes / 60
                    Text("\(currentHours)h Total Input")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(UIColor.secondarySystemFill))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            
            if let profile = userProfile {
                let currentHours = Double(totalMinutes) / 60.0
                let levels: [(id: Int, range: ClosedRange<Double>, color: Color)] = [
                    (1, 0...50, .teal),
                    (2, 50...150, .green),
                    (3, 150...300, .blue),
                    (4, 300...600, .orange),
                    (5, 600...1000, .purple),
                    (6, 1000...1500, .pink)
                ]
                
                let maxHours: Double = 1500
                
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        let rWidth = geo.size.width
                        
                        ZStack(alignment: .leading) {
                            // Background Track (Segments)
                            HStack(spacing: 1) {
                                ForEach(levels, id: \.id) { level in
                                    let levelDuration = level.range.upperBound - level.range.lowerBound
                                    let widthRatio = levelDuration / maxHours
                                    
                                    Rectangle()
                                        .fill(level.color.opacity(0.3))
                                        .frame(width: rWidth * widthRatio)
                                        .overlay(
                                            Text("L\(level.id)")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(level.color)
                                                .opacity(0.8)
                                        )
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            // User Progress Fill (Cumulative)
                            // We need to mask this or build it similarly
                            HStack(spacing: 1) {
                                ForEach(levels, id: \.id) { level in
                                    let levelDuration = level.range.upperBound - level.range.lowerBound
                                    let widthRatio = levelDuration / maxHours
                                    let segmentWidth = rWidth * widthRatio
                                    
                                    // Calculate fill for this specific segment
                                    let hoursInLevel = max(0, min(currentHours - level.range.lowerBound, levelDuration))
                                    let fillRatio = hoursInLevel / levelDuration
                                    
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .fill(Color.clear) // Placeholder for spacing
                                            .frame(width: segmentWidth)
                                        
                                        if fillRatio > 0 {
                                            Rectangle()
                                                .fill(level.color)
                                                .frame(width: segmentWidth * fillRatio)
                                        }
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            // Current Position Indicator (Line)
                            if currentHours > 0 && currentHours < maxHours {
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(width: 2, height: 24)
                                    .offset(x: min(rWidth, rWidth * (currentHours / maxHours)))
                                    .shadow(radius: 1)
                            }
                        }
                    }
                    .frame(height: 24)
                    
                    // Legend / Labels for milestones
                    GeometryReader { geo in
                        let rWidth = geo.size.width
                        ZStack(alignment: .leading) {
                            ForEach(levels, id: \.id) { level in
                                let positionRatio = level.range.upperBound / maxHours
                                Text("\(Int(level.range.upperBound))h")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .position(x: rWidth * positionRatio, y: 10)
                                    // Offset slightly left to center on the break, unless it's the end
                                    .offset(x: -10) 
                            }
                        }
                    }
                    .frame(height: 20)
                }
                .padding(.horizontal)
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
