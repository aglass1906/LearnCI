import SwiftUI
import SwiftData

struct VideoView: View {
    @Environment(YouTubeManager.self) private var youtubeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allProfiles: [UserProfile]
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    
    @State private var selectedVideo: YouTubeVideo?
    @State private var showWatchTimePrompt = false
    @State private var watchMinutes: Double = 10
    @State private var watchComment: String = ""
    
    enum VideoTabMode: String, CaseIterable {
        case recommended = "Recs"
        case subscriptions = "My Subs"
        case channels = "Channels"
        case discovery = "Discovery"
    }
    
    @State private var mode: VideoTabMode = .recommended
    @State private var selectedCategory: String = "All"
    @State private var selectedChannel: YouTubeChannel?
    
    let categories = ["All", "Vlogs", "Grammar", "Music", "Input"]
    
    var userProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode Toggle
                Picker("Tab", selection: $mode) {
                    ForEach(VideoTabMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Category Scroll
                if mode == .discovery {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(categories, id: \.self) { category in
                                Button(action: { selectedCategory = category }) {
                                    Text(category)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedCategory == category ? Color.red : Color.gray.opacity(0.1))
                                        .foregroundColor(selectedCategory == category ? .white : .primary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                }
                
                Group {
                    if let channel = selectedChannel {
                        channelDetailView(channel)
                    } else {
                        switch mode {
                        case .recommended:
                            recommendedContentView
                        case .subscriptions:
                            subscriptionContentView
                        case .channels:
                            channelListView
                        case .discovery:
                            discoveryContentView
                        }
                    }
                }
            }
            .onChange(of: mode) { _, _ in
                selectedChannel = nil // Reset drill-down when switching modes
                if mode == .recommended && youtubeManager.recommendedVideos.isEmpty {
                    youtubeManager.fetchRecommendedVideos()
                }
                if mode == .discovery && youtubeManager.discoveryVideos.isEmpty {
                    refreshDiscovery()
                }
            }
            .onChange(of: selectedCategory) { _, _ in
                refreshDiscovery()
            }
            .task {
                // Initial load
                if mode == .recommended && youtubeManager.recommendedVideos.isEmpty {
                    youtubeManager.fetchRecommendedVideos()
                }
                if mode == .discovery && youtubeManager.discoveryVideos.isEmpty {
                    refreshDiscovery()
                }
            }
            .navigationTitle(selectedChannel?.title ?? "Videos")
            .toolbar {
                if selectedChannel != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { selectedChannel = nil }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    }
                }
                
                if youtubeManager.isAuthenticated {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { youtubeManager.loadVideos() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(item: $selectedVideo) { video in
                VideoDetailSheet(
                    video: video,
                    onWatch: {
                        openInYouTube(video)
                        selectedVideo = nil
                        // Pre-fill comment with video context
                        watchComment = "\(video.channelTitle) - \(video.title)"
                        showWatchTimePrompt = true
                    },
                    onLogTime: {
                        selectedVideo = video
                        // Pre-fill comment with video context
                        watchComment = "\(video.channelTitle) - \(video.title)"
                        showWatchTimePrompt = true
                    }
                )
            }
            .sheet(isPresented: $showWatchTimePrompt) {
                LogWatchTimeSheet(
                    minutes: $watchMinutes,
                    comment: $watchComment,
                    onSave: {
                        logWatchTime(Int(watchMinutes))
                        showWatchTimePrompt = false
                        watchMinutes = 10
                        watchComment = ""
                    }
                )
            }
        }
    }
    
    var notConnectedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Connect YouTube")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Go to Profile to connect your YouTube account")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            NavigationLink(destination: ProfileView()) {
                Label("Go to Profile", systemImage: "person.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 300)
                    .background(Color.red)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
    
    var channelListView: some View {
        Group {
            if !youtubeManager.isAuthenticated {
                notConnectedView
            } else if youtubeManager.isLoading && youtubeManager.channels.isEmpty {
                ProgressView("Loading channels...")
            } else if youtubeManager.channels.isEmpty {
                ContentUnavailableView(
                    "No Channels",
                    systemImage: "person.2",
                    description: Text("Connect your YouTube account to see your channels")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        ForEach(youtubeManager.channels) { channel in
                            VStack {
                                AsyncImage(url: URL(string: channel.thumbnailURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle().fill(Color.gray.opacity(0.1))
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                
                                Text(channel.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(height: 35)
                            }
                            .onTapGesture {
                                selectedChannel = channel
                                youtubeManager.fetchVideosForChannel(channel.id)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    func channelDetailView(_ channel: YouTubeChannel) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                AsyncImage(url: URL(string: channel.thumbnailURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.1))
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                
                VStack(alignment: .leading) {
                    Text(channel.title)
                        .font(.headline)
                    Text("Latest Videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            
            if youtubeManager.isLoading {
                Spacer()
                ProgressView("Loading videos...")
                Spacer()
            } else {
                videoGridView(videos: youtubeManager.videos)
            }
        }
    }
    
    var subscriptionContentView: some View {
        Group {
            if !youtubeManager.isAuthenticated {
                notConnectedView
            } else if youtubeManager.isLoading {
                ProgressView("Loading subscriptions...")
            } else if youtubeManager.videos.isEmpty {
                ContentUnavailableView(
                    "No Subscriptions",
                    systemImage: "play.rectangle",
                    description: Text("Connect your YouTube account to see your subscriptions")
                )
            } else {
                videoGridView(videos: youtubeManager.videos)
            }
        }
    }
    
    var recommendedContentView: some View {
        Group {
            if youtubeManager.isRecommendedLoading && youtubeManager.recommendedVideos.isEmpty {
                ProgressView("Fetching recommendations...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !youtubeManager.isAuthenticated && !(ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] ?? "").contains("1") {
                // Not authenticated, show guest version or login prompt
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        "Sign in for Personal Recs",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Connect your YouTube account to see your personal homepage recommendations.")
                    )
                    Button("Sign In") {
                        youtubeManager.signInWithGoogle()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else if youtubeManager.recommendedVideos.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "No Recommendations",
                        systemImage: "video.badge.plus",
                        description: Text("Try watching more videos or subcribing to channels.")
                    )
                    Button("Refresh") {
                        youtubeManager.fetchRecommendedVideos()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                videoGridView(videos: youtubeManager.recommendedVideos)
            }
        }
    }
    
    var discoveryContentView: some View {
        Group {
            if youtubeManager.isDiscoveryLoading {
                ProgressView("Finding learning content...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if youtubeManager.discoveryVideos.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "No Content Found",
                        systemImage: "sparkles",
                        description: Text("Try changing your language or level in Profile")
                    )
                    Button("Retry Discovery") {
                        refreshDiscovery()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                videoGridView(videos: youtubeManager.discoveryVideos)
            }
        }
    }
    
    func videoGridView(videos: [YouTubeVideo]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(videos) { video in
                    VideoCard(
                        video: video, 
                        isWatched: isVideoWatched(video.id)
                    )
                    .onTapGesture {
                        selectedVideo = video
                    }
                }
            }
            .padding()
        }
    }
    
    private func isVideoWatched(_ videoId: String) -> Bool {
        // Check if any activity comment contains the video ID
        allActivities.contains { activity in
            activity.activityType == .watchingVideos && 
            (activity.comment?.contains(videoId) ?? false)
        }
    }
    
    private func refreshDiscovery() {
        let language = userProfile?.currentLanguage ?? .spanish
        let level = userProfile?.currentLevel ?? .beginner
        
        youtubeManager.searchVideos(
            for: language, 
            level: level,
            category: selectedCategory
        )
    }
    
    func openInYouTube(_ video: YouTubeVideo) {
        if let url = URL(string: "youtube://\(video.id)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else if let webURL = URL(string: "https://www.youtube.com/watch?v=\(video.id)") {
                UIApplication.shared.open(webURL)
            }
        }
    }
    
    func logWatchTime(_ minutes: Int) {
        guard minutes > 0 else { return }
        
        let language = userProfile?.currentLanguage ?? .spanish
        
        // Use the comment edited by user (or auto-generated default)
        // Store video ID in comment for tracking
        var finalComment = watchComment
        if let video = selectedVideo, !finalComment.contains(video.id) {
            finalComment += " [ID:\(video.id)]"
        }
        
        let activity = UserActivity(
            date: Date(),
            minutes: minutes,
            activityType: .watchingVideos,
            language: language,
            userID: authManager.currentUser,
            comment: finalComment.isEmpty ? nil : finalComment
        )
        modelContext.insert(activity)
    }
}

// MARK: - Enhanced VideoCard

struct VideoCard: View {
    let video: YouTubeVideo
    let isWatched: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Thumbnail with Overlays
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .aspectRatio(16/9, contentMode: .fill)
                            .overlay { ProgressView().scaleEffect(0.8) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    Text("\(video.durationInMinutes)m")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .padding(6)
                }
                
                if isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .background(Circle().fill(.white))
                        .font(.title3)
                        .padding(4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Channel info
                HStack {
                    Text(video.channelTitle)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let level = video.level {
                        Text(level.rawValue)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct VideoDetailSheet: View {
    let video: YouTubeVideo
    let onWatch: () -> Void
    let onLogTime: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(16/9, contentMode: .fill)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    Text(video.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text(video.channelTitle)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Duration: \(video.durationInMinutes) min")
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                    
                    Text(video.description)
                        .font(.body)
                    
                    VStack(spacing: 12) {
                        Button(action: onWatch) {
                            Label("Watch on YouTube", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(10)
                        }
                        
                        Button(action: onLogTime) {
                            Label("Log Watch Time", systemImage: "clock.fill")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.top)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LogWatchTimeSheet: View {
    @Binding var minutes: Double
    @Binding var comment: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Watch Duration")) {
                    VStack(alignment: .leading) {
                        Text("Minutes: \(Int(minutes))")
                            .foregroundStyle(.secondary)
                        Slider(value: $minutes, in: 1...120, step: 1)
                    }
                }
                
                Section(header: Text("Notes (Optional)")) {
                    TextField("Add or edit comment...", text: $comment, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Log Watch Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    VideoView()
        .environment(YouTubeManager())
        .environment(DataManager())
        .environment(AuthManager())
}
