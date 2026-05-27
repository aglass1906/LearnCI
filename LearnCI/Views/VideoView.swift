import SwiftUI
import SwiftData

struct VideoView: View {
    @Environment(YouTubeManager.self) private var youtubeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allProfiles: [UserProfile]
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    
    enum VideoSourceScope: String, CaseIterable {
        case all = "All"
        case playlists = "Playlists"
        case favorites = "Favorites"
    }
    
    enum FavoritesBrowseMode: String, CaseIterable {
        case feed = "Feed"
        case channels = "Channels"
        case saved = "Saved"
    }
    
    enum VideoTabMode: String, CaseIterable {
        case subscriptions = "New Videos"
        case channels = "Subscriptions"
        case discovery = "Discovery"
    }
    
    enum VideoFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case regular = "Regular"
        case shorts = "Shorts"
        
        var id: String { self.rawValue }
    }
    
    @Query(sort: \Favorite.createdAt, order: .reverse) private var allFavorites: [Favorite]
    
    @State private var sourceScope: VideoSourceScope = .all
    @State private var favoritesBrowseMode: FavoritesBrowseMode = .feed
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
    
    private var youtubeFavorites: [Favorite] {
        guard let userID = authManager.currentUser else { return [] }
        return allFavorites.filter { fav in
            guard fav.userID == userID else { return false }
            switch fav.type {
            case .channel, .youtube:
                return true
            default:
                let url = fav.consumptionUrl
                return url.contains("youtube.com") || url.contains("youtu.be")
            }
        }
    }
    
    private var favoritesIndex: FavoritesManager.YouTubeFavoritesIndex {
        FavoritesManager.YouTubeFavoritesIndex.build(
            from: youtubeFavorites,
            userID: authManager.currentUser ?? ""
        )
    }
    
    private var favoriteChannelList: [YouTubeChannel] {
        let index = favoritesIndex
        var byId: [String: YouTubeChannel] = [:]
        
        for channel in youtubeManager.channels where index.matches(channel: channel) {
            byId[channel.id] = channel
        }
        
        for fav in youtubeFavorites {
            if let playlistId = FavoritesManager.resolvePlaylistId(from: fav.consumptionUrl) {
                if byId[playlistId] == nil {
                    byId[playlistId] = YouTubeChannel(
                        id: playlistId,
                        title: fav.title,
                        thumbnailURL: fav.imageUrl ?? "",
                        isPlaylist: true
                    )
                }
            } else if let channelId = FavoritesManager.resolveChannelId(from: fav.consumptionUrl)
                ?? (fav.type == .channel && fav.consumptionUrl.hasPrefix("UC") ? fav.consumptionUrl : nil) {
                if byId[channelId] == nil {
                    byId[channelId] = YouTubeChannel(
                        id: channelId,
                        title: fav.title,
                        thumbnailURL: fav.imageUrl ?? ""
                    )
                }
            }
        }
        
        return byId.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Source", selection: $sourceScope) {
                ForEach(VideoSourceScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            
            if sourceScope == .all {
                Picker("Tab", selection: $mode) {
                    ForEach(VideoTabMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            } else if sourceScope == .favorites {
                Picker("Favorites", selection: $favoritesBrowseMode) {
                    ForEach(FavoritesBrowseMode.allCases, id: \.self) { browseMode in
                        Text(browseMode.rawValue).tag(browseMode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }
            
            // Count Header
            if selectedChannel == nil {
                HStack {
                    Text(scopeCountLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            
            // Category Scroll
            if sourceScope == .all && mode == .discovery {
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
                } else if sourceScope == .favorites {
                    favoritesContentView
                } else if sourceScope == .playlists {
                    playlistListView
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
        .onChange(of: sourceScope) { _, newScope in
            selectedChannel = nil
            if newScope == .favorites {
                refreshFavoriteSavedVideos()
            } else if newScope == .playlists && youtubeManager.isAuthenticated {
                youtubeManager.fetchUserPlaylists()
            }
        }
        .onChange(of: favoritesBrowseMode) { _, newMode in
            if newMode == .saved {
                refreshFavoriteSavedVideos()
            }
        }
        .onChange(of: mode) { _, _ in
            selectedChannel = nil
            if mode == .discovery && youtubeManager.discoveryVideos.isEmpty {
                refreshDiscovery()
            } else if mode == .subscriptions && youtubeManager.isAuthenticated {
                youtubeManager.refreshVideos()
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            refreshDiscovery()
        }
        .task {
            if sourceScope == .favorites {
                refreshFavoriteSavedVideos()
            }
            if sourceScope == .playlists && youtubeManager.isAuthenticated {
                youtubeManager.fetchUserPlaylists()
            } else if sourceScope == .all {
                if mode == .discovery && youtubeManager.discoveryVideos.isEmpty {
                    refreshDiscovery()
                } else if mode == .subscriptions && youtubeManager.isAuthenticated {
                    youtubeManager.refreshVideos()
                }
            }
        }
        .onChange(of: youtubeFavorites.count) { _, _ in
            if sourceScope == .favorites {
                refreshFavoriteSavedVideos()
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
        .navigationTitle(selectedChannel?.title ?? "YouTube")
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
                        if sourceScope == .favorites {
                            refreshFavoriteSavedVideos()
                            youtubeManager.refreshVideos()
                        } else if sourceScope == .playlists {
                            youtubeManager.fetchUserPlaylists(forceRefresh: true)
                        } else if mode == .discovery {
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
    
    var playlistListView: some View {
        Group {
            if !youtubeManager.isAuthenticated {
                notConnectedView
            } else if youtubeManager.isPlaylistsLoading && youtubeManager.playlists.isEmpty {
                ProgressView("Loading playlists...")
            } else if youtubeManager.playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create playlists on YouTube, or pull to refresh after connecting your account.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(youtubeManager.playlists) { playlist in
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .bottomTrailing) {
                                    AsyncImage(url: URL(string: playlist.thumbnailURL)) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(16/9, contentMode: .fill)
                                    } placeholder: {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.15))
                                            .aspectRatio(16/9, contentMode: .fit)
                                            .overlay {
                                                Image(systemName: "list.bullet.rectangle")
                                                    .font(.title)
                                                    .foregroundStyle(.secondary)
                                            }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    
                                    Image(systemName: "list.bullet")
                                        .font(.caption2.bold())
                                        .padding(5)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                        .padding(6)
                                }
                                
                                Text(playlist.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                if let count = playlist.itemCount {
                                    Text("\(count) videos")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onTapGesture {
                                selectedChannel = playlist
                                youtubeManager.fetchVideosForPlaylist(playlist.id)
                            }
                        }
                    }
                    .padding()
                }
                .refreshable {
                    youtubeManager.fetchUserPlaylists(forceRefresh: true)
                }
            }
        }
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
            HStack {
                Picker("Filter", selection: $shortsFilter) {
                    ForEach(VideoFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                Button(action: { youtubeManager.refreshVideos() }) {
                    if youtubeManager.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(youtubeManager.isLoading)
            }
            .padding()
            
            let svideos = feedVideosForCurrentScope()
            
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
                    sourceScope == .favorites ? "No Favorite Videos" : (shortsFilter == .all ? "No videos found" : "No \(shortsFilter.rawValue.lowercased()) found"),
                    systemImage: sourceScope == .favorites ? "heart.slash" : (shortsFilter == .shorts ? "play.rectangle.on.rectangle.slash" : "video.slash"),
                    description: Text(sourceScope == .favorites
                        ? "Favorite channels or individual videos from subscriptions, or use the heart on a channel."
                        : "Try changing the filter or scrolling down.")
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
    
    var favoritesContentView: some View {
        Group {
            switch favoritesBrowseMode {
            case .feed:
                subscriptionContentView
            case .channels:
                favoriteChannelsView
            case .saved:
                savedFavoritesView
            }
        }
    }
    
    var favoriteChannelsView: some View {
        Group {
            if favoriteChannelList.isEmpty {
                ContentUnavailableView(
                    "No Favorite Channels",
                    systemImage: "heart.slash",
                    description: Text("Tap the heart on a subscription or channel to add it here.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        ForEach(favoriteChannelList) { channel in
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
                                
                                if channel.isPlaylist {
                                    Text("Playlist")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onTapGesture {
                                selectedChannel = channel
                                if channel.isPlaylist {
                                    youtubeManager.fetchVideosForPlaylist(channel.id)
                                } else {
                                    youtubeManager.fetchVideosForChannel(channel.id)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    var savedFavoritesView: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filter", selection: $shortsFilter) {
                    ForEach(VideoFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                
                Button(action: { refreshFavoriteSavedVideos() }) {
                    if youtubeManager.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .padding()
            
            let saved = videosMatchingShortsFilter(youtubeManager.savedFavoriteVideos)
            
            if favoritesIndex.videoIds.isEmpty {
                ContentUnavailableView(
                    "No Saved Videos",
                    systemImage: "play.circle",
                    description: Text("Favorite a specific YouTube video to see it here.")
                )
            } else if saved.isEmpty && youtubeManager.isLoading {
                ProgressView("Loading saved videos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if saved.isEmpty {
                ContentUnavailableView(
                    "Could Not Load Videos",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Check your connection and try again.")
                )
            } else {
                VideoGridView(
                    videos: saved,
                    isLoading: youtubeManager.isLoading,
                    onLoadMore: nil,
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
    
    private var scopeCountLabel: String {
        if sourceScope == .favorites {
            switch favoritesBrowseMode {
            case .feed:
                return "\(feedVideosForCurrentScope().count) Favorite Videos"
            case .channels:
                return "\(favoriteChannelList.count) Favorite Channels"
            case .saved:
                return "\(videosMatchingShortsFilter(youtubeManager.savedFavoriteVideos).count) Saved Videos"
            }
        }
        if sourceScope == .playlists {
            return "\(youtubeManager.playlists.count) Playlists"
        }
        if mode == .subscriptions {
            return "\(feedVideosForCurrentScope().count) Videos"
        }
        if mode == .channels {
            return "\(countForMode(mode)) Subscriptions"
        }
        return "\(countForMode(mode)) Videos Found"
    }
    
    private func videosMatchingShortsFilter(_ videos: [YouTubeVideo]) -> [YouTubeVideo] {
        videos.filter { video in
            switch shortsFilter {
            case .all: return true
            case .regular: return !video.isShort
            case .shorts: return video.isShort
            }
        }
    }
    
    private func feedVideosForCurrentScope() -> [YouTubeVideo] {
        let fromFeed = videosMatchingShortsFilter(youtubeManager.videos)
        let index = favoritesIndex
        
        if sourceScope == .favorites {
            let fromSubscriptions = fromFeed.filter { index.matches(video: $0) }
            let saved = videosMatchingShortsFilter(youtubeManager.savedFavoriteVideos)
            var byId: [String: YouTubeVideo] = [:]
            for video in fromSubscriptions + saved {
                byId[video.id] = video
            }
            return byId.values.sorted {
                ($0.addedToFeedAt ?? $0.publishedAt) > ($1.addedToFeedAt ?? $1.publishedAt)
            }
        }
        
        // All Videos on New Videos: show subscription feed excluding favorited items.
        if mode == .subscriptions {
            return fromFeed.filter { !index.matches(video: $0) }
        }
        return fromFeed
    }
    
    private func refreshFavoriteSavedVideos() {
        youtubeManager.fetchSavedFavoriteVideos(videoIds: Array(favoritesIndex.videoIds))
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
