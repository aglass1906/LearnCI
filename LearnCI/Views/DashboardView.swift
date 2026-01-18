import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    @Query private var allProfiles: [UserProfile]
    @Query(sort: \CoachingCheckIn.date, order: .reverse) private var coachingHistory: [CoachingCheckIn]
    
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
        // Use Synced Profile Total (Source of Truth) + Pending (Unsynced)
        let baseMinutes = userProfile?.totalMinutes ?? 0
        let pendingMinutes = activities.filter { !$0.isSynced }.reduce(0) { $0 + $1.minutes }
        let startingMinutes = (userProfile?.startingHours ?? 0) * 60
        
        return baseMinutes + pendingMinutes + startingMinutes
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
                        
                        // 1. Coaching Section
                        coachingSection
                        
                        // 2. Input Roadmap
                        roadmapSection
                        
                        // 3. Breakdown
                        breakdownSection
                        
                        // 4. Leaderboard
                        leaderboardSection
                        
                        // 5. Word of the Day
                        wordOfDaySection
                    }
                }

                .task(id: authManager.currentUser) {
                    // Create default profile if missing (Self-healing for fresh app install)
                    // We also ensure we have a valid currentUser value to avoid creating profiles for 'nil' (unauth)
                    // although the query filters by nil if unauth.
                    
                    if userProfile == nil {
                         print("DEBUG: No profile found on Dashboard for user \(authManager.currentUser ?? "nil"). Creating default.")
                         if let userID = authManager.currentUser {
                             let newProfile = UserProfile(userID: userID)
                             // Sync with auth data
                             newProfile.fullName = authManager.currentUserFullName
                             newProfile.email = authManager.currentUserEmail
                             newProfile.avatarUrl = authManager.currentUserAvatar
                             if let googleName = authManager.currentUserFullName {
                                 newProfile.name = googleName
                             }
                             
                             modelContext.insert(newProfile)
                             try? modelContext.save()
                             print("DEBUG: Created new profile for \(userID)")
                         }
                    }

                    // Proceed with Word of Day using the (now potentially created) profile
                    if let profile = profiles.first, wordOfDay == nil {
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
    
    // MARK: - Daily Feedback Logic
    
    @Query(sort: \DailyFeedback.date, order: .reverse) private var feedbackHistory: [DailyFeedback]
    
    var todaysFeedback: DailyFeedback? {
        let calendar = Calendar.current
        return feedbackHistory.first { calendar.isDateInToday($0.date) && $0.userID == authManager.currentUser }
    }
    
    // MARK: - Check-in Logic
    
    private var nextCheckInMilestone: Int {
        guard let profile = userProfile else { return 25 }
        let startingBase = (profile.startingHours / 25) * 25
        let base = max(profile.lastCheckInHours, startingBase)
        return base + 25
    }
    
    var isCheckInDue: Bool {
        guard let _ = userProfile else { return false }
        let currentHours = totalMinutes / 60
        return currentHours >= nextCheckInMilestone
    }
    
    var hoursToNextMilestone: Int {
        guard let _ = userProfile else { return 25 }
        let currentHours = totalMinutes / 60
        return max(0, nextCheckInMilestone - currentHours)
    }
    
    var hasCoachingHistory: Bool {
        !coachingHistory.isEmpty
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
}

// MARK: - Component Views
extension DashboardView {
    
    private var coachingSection: some View {
        LayoutCardView(
            title: "Coaching",
            subTitle: isCheckInDue ? nil : "Next Check-in: \(hoursToNextMilestone)h",
            accentColor: .blue,
            icon: "graduationcap.fill",
            destination: CoachingHistoryView()
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Check-in Banner
                if let profile = userProfile {
                    if !hasCoachingHistory {
                        // Initial Coaching Prompt
                        Button(action: { showCheckInSheet = true }) {
                            HStack {
                                Image(systemName: "flag.checkered.2.crossed")
                                    .font(.title)
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading) {
                                    Text("Start Coaching Journey")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Set your baseline and goals.")
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
                            .shadow(color: .blue.opacity(0.1), radius: 2)
                        }
                        .sheet(isPresented: $showCheckInSheet) {
                            CoachingCheckInView(
                                userProfile: profile,
                                currentHours: totalMinutes / 60,
                                milestone: totalMinutes / 60 // Initial baseline
                            )
                        }
                    } else if isCheckInDue {
                        // Regular Milestone Prompt
                        Button(action: { showCheckInSheet = true }) {
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .font(.title)
                                    .foregroundStyle(.yellow)
                                VStack(alignment: .leading) {
                                    Text("Milestone Reached!")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("It's time for your \(nextCheckInMilestone)h check-in.")
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
                    .sheet(isPresented: $showCheckInSheet) {
                        CoachingCheckInView(
                            userProfile: profile,
                            currentHours: totalMinutes / 60,
                            milestone: nextCheckInMilestone
                        )
                    }
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
                            Image(systemName: DailyFeedback.moodIconName(for: feedback.rating))
                                .foregroundStyle(DailyFeedback.moodColor(for: feedback.rating))
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
                                            Image(systemName: DailyFeedback.moodIconName(for: rating))
                                                .foregroundStyle(DailyFeedback.moodColor(for: rating))
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
            }
        }
    }
    
    private var roadmapSection: some View {
        LayoutCardView(
            title: "Input Roadmap",
            subTitle: userProfile != nil ? "\(totalMinutes / 60)h Total Input" : nil,
            accentColor: .green,
            icon: "map.fill"
        ) {
            if userProfile != nil {
                let currentHoursDouble = Double(totalMinutes) / 60.0
                let levels: [(id: Int, range: ClosedRange<Double>, color: Color)] = [
                    (1, 0...50, .teal),
                    (2, 50...150, .green),
                    (3, 150...300, .blue),
                    (4, 300...600, .orange),
                    (5, 600...1000, .purple),
                    (6, 1000...1500, .pink)
                ]
                
                let maxHours: Double = 1500
                let maxLevelDuration: Double = 500 // Level 6 is 500h (longest)
                let graphHeight: CGFloat = 80
                
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        let rWidth = geo.size.width
                        
                        ZStack(alignment: .leading) {
                            // Background Track
                            HStack(alignment: .bottom, spacing: 1) {
                                ForEach(levels, id: \.id) { level in
                                    let levelDuration = level.range.upperBound - level.range.lowerBound
                                    let widthRatio = levelDuration / maxHours
                                    let heightRatio = 0.2 + (0.8 * (levelDuration / maxLevelDuration))
                                    
                                    Rectangle()
                                        .fill(level.color.opacity(0.3))
                                        .frame(width: rWidth * widthRatio, height: graphHeight * heightRatio)
                                        .overlay(
                                            Text("L\(level.id)")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(level.color)
                                                .opacity(0.8)
                                                .padding(.bottom, 2),
                                            alignment: .bottom
                                        )
                                }
                            }
                            .frame(height: graphHeight, alignment: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            // User Progress Fill
                            HStack(alignment: .bottom, spacing: 1) {
                                ForEach(levels, id: \.id) { level in
                                    let levelDuration = level.range.upperBound - level.range.lowerBound
                                    let widthRatio = levelDuration / maxHours
                                    let segmentWidth = rWidth * widthRatio
                                    let heightRatio = 0.2 + (0.8 * (levelDuration / maxLevelDuration))
                                    let segmentHeight = graphHeight * heightRatio
                                    let hoursInLevel = max(0, min(currentHoursDouble - level.range.lowerBound, levelDuration))
                                    let fillRatio = hoursInLevel / levelDuration
                                    
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .fill(Color.clear)
                                            .frame(width: segmentWidth, height: segmentHeight)
                                        
                                        if fillRatio > 0 {
                                            Rectangle()
                                                .fill(level.color)
                                                .frame(width: segmentWidth * fillRatio, height: segmentHeight)
                                        }
                                    }
                                }
                            }
                            .frame(height: graphHeight, alignment: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            // Current Position Line
                            if currentHoursDouble > 0 && currentHoursDouble < maxHours {
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(width: 2, height: graphHeight)
                                    .offset(x: min(rWidth, rWidth * (currentHoursDouble / maxHours)))
                                    .shadow(radius: 1)
                            }
                        }
                    }
                    .frame(height: graphHeight)
                    
                    // Legend
                    GeometryReader { geo in
                        let rWidth = geo.size.width
                        ZStack(alignment: .leading) {
                            ForEach(levels, id: \.id) { level in
                                Text("\(Int(level.range.upperBound))h")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .position(x: rWidth * (level.range.upperBound / maxHours), y: 10)
                                    .offset(x: -10)
                            }
                        }
                    }
                    .frame(height: 20)
                }
            }
        }
    }
    
    private var breakdownSection: some View {
        LayoutCardView(
            title: "Today's Breakdown",
            subTitle: "Activity Summary",
            accentColor: .blue,
            icon: "chart.bar.xaxis",
            destination: HistoryView()
        ) {
            ActivityBreakdownChart(activityByType: activityByType)
                .padding(.top, 4)
        }
    }
    
    private var leaderboardSection: some View {
        LayoutCardView(
            title: "Global Leaderboard",
            subTitle: "See where you rank!",
            accentColor: .yellow,
            icon: "trophy.fill",
            destination: LeaderboardView()
        ) {
             Text("Compete with learners worldwide.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var wordOfDaySection: some View {
        LayoutCardView(
            title: "Word of the Day",
            accentColor: .orange,
            icon: "sparkles"
        ) {
            if let word = wordOfDay {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(word.wordTarget)
                                .font(.title)
                                .fontWeight(.bold)
                            Text(word.wordNative)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if let file = word.audioWordFile {
                            let canPlay = audioManager.audioExists(named: file, folderName: wordOfDayFolder) || true
                            
                            if canPlay {
                                Button(action: {
                                    audioManager.playAudio(
                                        named: file,
                                        folderName: wordOfDayFolder,
                                        text: word.wordTarget,
                                        language: userProfile?.currentLanguage ?? .spanish,
                                        useFallback: true
                                    )
                                }) {
                                    Image(systemName: "speaker.wave.2.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue)
                                }
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
