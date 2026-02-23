import SwiftUI
import SwiftData

struct VideoView: View {
    @Environment(YouTubeManager.self) private var youtubeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allProfiles: [UserProfile]
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    
    enum VideoTabMode: String, CaseIterable {
        case subscriptions = "New Videos"
        case channels = "Channels"
        case discovery = "Discovery"
    }
    
    enum VideoFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case regular = "Regular"
        case shorts = "Shorts"
        
        var id: String { self.rawValue }
    }
    
    @State private var mode: VideoTabMode = .subscriptions
    @State private var selectedCategory: String = "All"
    @State private var selectedVideo: YouTubeVideo?
    @State private var showWatchTimePrompt = false
    @State private var watchMinutes: Double = 10
    @State private var watchComment: String = ""
    @State private var isShowingLogSheet = false
    @State private var shortsFilter: VideoFilter = .all
    @State private var selectedChannel: YouTubeChannel?
    
    let categories = ["All", "Vlogs", "Grammar", "Music", "Input"]
    
    var userProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Mode Toggle
            Picker("Tab", selection: $mode) {
                ForEach(VideoTabMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Count Header
            if selectedChannel == nil {
                HStack {
                    Text("\(countForMode(mode)) \(mode == .channels ? "Channels" : "Videos") Found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            
            // Category Scroll
            if mode == .discovery {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(categories, id: \.self) { category in
                            Button(action: { selectedCategory = category }) {
                                Text(category)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .frame(minHeight: 44)
                                    .background(selectedCategory == category ? Color.red : Color.gray.opacity(0.1))
                                    .foregroundColor(selectedCategory == category ? .white : .primary)
                                    .cornerRadius(22)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
            }
            
            Group {
                if let channel = selectedChannel {
                    ChannelDetailView(
                        channel: channel,
                        isVideoWatched: isVideoWatched
                    )
                } else {
                    switch mode {
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
            if mode == .discovery && youtubeManager.discoveryVideos.isEmpty {
                refreshDiscovery()
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            refreshDiscovery()
        }
        .task {
            // Initial load
            if mode == .discovery && youtubeManager.discoveryVideos.isEmpty {
                refreshDiscovery()
            }
        }
        .onChange(of: userProfile?.currentLanguage) { _, _ in
            youtubeManager.discoveryVideos = [] // Invalidate old data
            if mode == .discovery {
                refreshDiscovery()
            }
        }
        .onChange(of: userProfile?.currentLevel) { _, _ in
            youtubeManager.discoveryVideos = [] // Invalidate old data
            if mode == .discovery {
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
                    Button(action: {
                        if mode == .discovery {
                            refreshDiscovery()
                        } else {
                            youtubeManager.refreshVideos()
                        }
                    }) {
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
                onLogTime: { minutes in
                    selectedVideo = video
                    // Auto-log the activity
                    watchComment = "\(video.channelTitle) - \(video.title) (Auto-Tracked)"
                    logWatchTime(minutes)
                    
                    // We do NOT show the prompt, effectively auto-saving.
                    // Reset simple state
                    selectedVideo = nil
                }
            )
        }
        .sheet(isPresented: $showWatchTimePrompt) {
            LogActivitySheet(
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
    
    // channelDetailView helper removed - replaced by ChannelDetailView struct
    
    var subscriptionContentView: some View {
        VStack(spacing: 0) {
            // Filter Picker
            Picker("Filter", selection: $shortsFilter) {
                ForEach(VideoFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Filtered List
            let svideos = youtubeManager.videos.filter { video in // Changed from channelVideos to videos
                switch shortsFilter {
                case .all: return true
                case .regular: return !video.isShort
                case .shorts: return video.isShort
                }
            }
            
            if svideos.isEmpty && youtubeManager.isLoading && youtubeManager.videos.isEmpty {
                ProgressView("Loading subscriptions...")
            } else if youtubeManager.videos.isEmpty {
                ContentUnavailableView(
                    "No Subscriptions",
                    systemImage: "play.rectangle",
                    description: Text("Connect your YouTube account to see your subscriptions")
                )
            } else if svideos.isEmpty {
                 ContentUnavailableView(
                    shortsFilter == .all ? "No videos found" : "No \(shortsFilter.rawValue.lowercased()) found",
                    systemImage: shortsFilter == .shorts ? "play.rectangle.on.rectangle.slash" : "video.slash",
                    description: Text("Try changing the filter or scrolling down.")
                )
            } else {
                VideoGridView(
                    videos: svideos,
                    isLoading: youtubeManager.isLoading,
                    onLoadMore: youtubeManager.loadMoreFeedVideos,
                    selectedVideo: $selectedVideo,
                    isVideoWatched: isVideoWatched
                )
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
                    .controlSize(.large)
                }
            } else {
                VideoGridView(
                    videos: youtubeManager.discoveryVideos,
                    isLoading: youtubeManager.isDiscoveryLoading,
                    onLoadMore: youtubeManager.loadMoreDiscoveryVideos,
                    selectedVideo: $selectedVideo,
                    isVideoWatched: isVideoWatched
                )
            }
        }
    }
    
    // videoGridView helper removed - replaced by VideoGridView struct
    
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
        // ... (existing implementation)
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
    
    func countForMode(_ mode: VideoTabMode) -> Int {
        switch mode {
        case .subscriptions:
            return youtubeManager.videos.count
        case .channels:
            return youtubeManager.channels.count
        case .discovery:
            return youtubeManager.discoveryVideos.count
        }
    }
}

// MARK: - Previews
// Components moved to separate files to avoid redundancy.


#Preview {
    VideoView()
        .environment(YouTubeManager())
        .environment(DataManager())
        .environment(AuthManager())
}
