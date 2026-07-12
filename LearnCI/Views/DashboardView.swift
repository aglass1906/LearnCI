import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(SyncManager.self) private var syncManager
    
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    @Query private var allProfiles: [UserProfile]
    @Query(sort: \CoachingCheckIn.date, order: .reverse) private var coachingHistory: [CoachingCheckIn]
    @Query private var allStories: [Story]

    @Environment(NextSessionPlanManager.self) private var planManager
    @Environment(StoryPathProgressStore.self) private var pathProgressStore
    
    var activities: [UserActivity] {
        allActivities.filter { $0.userID == authManager.currentUser }
    }
    
    var profiles: [UserProfile] {
        allProfiles.filter { $0.userID == authManager.currentUser }
    }
    
    @Environment(AudioManager.self) private var audioManager
    @State private var wordOfDay: LearningCard?
    @State private var wordOfDayFolder: String?
    @State private var wordOfDayDeckTitle: String?
    @State private var wordOfDayDeckDescription: String?
    @State private var isLoadingWordOfDay = false

    
    var userProfile: UserProfile? {
        profiles.first
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
                GeometryReader { geometry in
                    ScrollView {
                        dashboardContent(size: geometry.size)
                    }
                }

                .task(id: authManager.currentUser) {
                    if let profile = profiles.first, wordOfDay == nil {
                        isLoadingWordOfDay = true
                        if let result = await dataManager.fetchWordOfDay(language: profile.currentLanguage, level: profile.currentLevel) {
                            wordOfDay = result.card
                            wordOfDayFolder = result.folder
                            wordOfDayDeckTitle = result.deckTitle
                            wordOfDayDeckDescription = result.deckDescription
                        }
                        isLoadingWordOfDay = false
                    }
                    
                    // Trigger Data Sync
                    await syncManager.syncNow(modelContext: modelContext)
                }
                .onChange(of: userProfile?.currentLanguage) { _, newLanguage in
                    if let language = newLanguage, let profile = userProfile {
                        Task {
                            print("DEBUG: Language changed to \(language). Refetching Word of Day.")
                            isLoadingWordOfDay = true
                            wordOfDay = nil // Show loading state
                            
                            if let result = await dataManager.fetchWordOfDay(language: language, level: profile.currentLevel) {
                                wordOfDay = result.card
                                wordOfDayFolder = result.folder
                                wordOfDayDeckTitle = result.deckTitle
                                wordOfDayDeckDescription = result.deckDescription
                            }
                            isLoadingWordOfDay = false
                        }
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

    @ViewBuilder
    private func dashboardContent(size: CGSize) -> some View {
        let usesTwoColumns = AdaptiveLayoutPolicy.usesDashboardTwoColumns(for: size)

        VStack(spacing: 20) {
            greetingSection

            todaysPlanSection

            LearningStatsCard(stats: learningStats, appliesHorizontalPadding: false)

            DashboardCardGrid(usesTwoColumns: usesTwoColumns) {
                storiesSection
                wordOfDaySection
                coachingSection
                roadmapSection
                breakdownSection
                leaderboardSection
            }
        }
        .frame(maxWidth: AdaptiveLayoutPolicy.dashboardMaxContentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 32)
    }

    @ViewBuilder
    private var todaysPlanSection: some View {
        let plan = planManager.todaysPlan(for: authManager.currentUser, in: modelContext)
        let studyStates = pathProgressStore.activeStudyStates(
            for: authManager.currentUser,
            in: modelContext,
            limit: 3
        )
        if plan != nil || !studyStates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let plan {
                    todaysPlanCard(plan: plan)
                }
                ForEach(studyStates.filter { plan?.sourceID != $0.storyID }, id: \.id) { state in
                    studyStateCard(state: state)
                }
            }
        }
    }

    @ViewBuilder
    private func todaysPlanCard(plan: NextSessionPlan) -> some View {
        let story = allStories.first { $0.id.uuidString == plan.sourceID }
        Group {
            if let story {
                NavigationLink {
                    StoryPathContainerView(story: story)
                } label: {
                    todaysPlanCardBody(plan: plan)
                }
                .buttonStyle(.plain)
            } else {
                todaysPlanCardBody(plan: plan)
            }
        }
    }

    @ViewBuilder
    private func todaysPlanCardBody(plan: NextSessionPlan) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                Image(systemName: "sunrise.fill")
                    .foregroundStyle(.white)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Today's Plan")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(plan.sourceTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(planDetailLine(plan: plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func planDetailLine(plan: NextSessionPlan) -> String {
        var parts: [String] = []
        if let chap = plan.chapterNumber { parts.append("Ch. \(chap)") }
        parts.append("\(plan.targetMinutes) min")
        if plan.wordReviewCount > 0 { parts.append("\(plan.wordReviewCount) words") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func studyStateCard(state: StoryStudyState) -> some View {
        let story = allStories.first { $0.id.uuidString == state.storyID }
        Group {
            if let story {
                NavigationLink {
                    StoryPathContainerView(story: story)
                } label: {
                    studyStateBody(state: state)
                }
                .buttonStyle(.plain)
            } else {
                studyStateBody(state: state)
            }
        }
    }

    @ViewBuilder
    private func studyStateBody(state: StoryStudyState) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "book.pages.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Studying")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(state.storyTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Scene \(state.currentOrdinal + 1) of \(max(1, state.totalChunks))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var greetingSection: some View {
        if let profile = userProfile {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(profile.currentLanguage.greetingPrefix) \(profile.name.isEmpty ? "" : profile.name)")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Language Learning with Comprehensible Input")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            destination: CoachingProgressView().navigationTitle("Milestones"),
            appliesHorizontalPadding: false
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
            icon: "map.fill",
            appliesHorizontalPadding: false
        ) {
            if userProfile != nil {
                RoadmapView(totalMinutes: totalMinutes)
            }
        }
    }
    
    private var breakdownSection: some View {
        LayoutCardView(
            title: "Today's Breakdown",
            subTitle: "Activity Summary",
            accentColor: .blue,
            icon: "chart.bar.xaxis",
            destination: CoachingProgressDetailView(),
            appliesHorizontalPadding: false
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
            destination: LeaderboardView(),
            appliesHorizontalPadding: false
        ) {
             Text("Compete with learners worldwide.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var wordOfDaySection: some View {
        LayoutCardView(
            title: "Word of the Day",
            subTitle: "Learn vocabulary in a fun way",
            accentColor: .orange,
            icon: "sparkles",
            destination: FlashcardDeckBrowserView(),
            appliesHorizontalPadding: false
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
                                        voiceGender: userProfile?.ttsVoiceGender,
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
                        HStack(alignment: .top) {
                            Text(word.sentenceTarget)
                                .font(.subheadline.italic())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button(action: {
                                audioManager.playAudio(
                                    named: word.audioSentenceFile ?? "",
                                    folderName: wordOfDayFolder,
                                    text: word.sentenceTarget,
                                    language: userProfile?.currentLanguage ?? .spanish,
                                    voiceGender: userProfile?.ttsVoiceGender,
                                    useFallback: true
                                )
                            }) {
                                Image(systemName: "speaker.wave.2.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.blue.opacity(0.8))
                            }
                        }
                        
                        Text(word.sentenceNative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                                                    
                    if let deckTitle = wordOfDayDeckTitle {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("From deck: \(deckTitle)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                            
                            if let deckDesc = wordOfDayDeckDescription, !deckDesc.isEmpty {
                                Text(deckDesc)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                            }
                        }
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
    
    private var storiesSection: some View {
        LayoutCardView(
            title: " Story Learning",
            subTitle: "Generate, Read, & Listen",
            accentColor: .purple,
            icon: "book.closed.fill",
            destination: StoryListView(),
            appliesHorizontalPadding: false
        ) {
             Text("Create custom stories with AI-generated audio.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DashboardCardGrid<Content: View>: View {
    let usesTwoColumns: Bool
    @ViewBuilder let content: Content

    private var columns: [GridItem] {
        if usesTwoColumns {
            return [
                GridItem(.flexible(), spacing: 16, alignment: .top),
                GridItem(.flexible(), spacing: 16, alignment: .top)
            ]
        }

        return [GridItem(.flexible(), spacing: 16, alignment: .top)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
            content
        }
        .animation(.easeInOut(duration: 0.2), value: usesTwoColumns)
    }
}

#Preview {
    DashboardView()
        .environment(DataManager())
        .environment(YouTubeManager())
        .environment(AuthManager())
}
