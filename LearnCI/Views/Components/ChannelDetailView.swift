import SwiftUI
import SwiftData

struct ChannelDetailView: View {
    let channel: YouTubeChannel
    @Environment(YouTubeManager.self) private var youtubeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    
    // Internal State for Video Sheet
    @State private var selectedVideo: YouTubeVideo?
    @State private var showWatchTimePrompt = false
    @State private var watchMinutes: Double = 10
    @State private var watchComment: String = ""
    
    // Helper to check profile for language defaults
    @Query private var allProfiles: [UserProfile]
    var userProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }
    
    let isVideoWatched: (String) -> Bool
    // var isPlaylist: Bool = false // Removed, using channel.isPlaylist
    
    var body: some View {
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
                    Text(channel.isPlaylist ? "Playlist Videos (\(youtubeManager.channelVideos.count))" : "Latest Videos (\(youtubeManager.channelVideos.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Favorite Button
                FavoriteButton(
                    consumptionUrl: channel.id,
                    type: channel.isPlaylist ? .youtube : .channel, 
                    title: channel.title,
                    author: channel.title,
                    imageUrl: channel.thumbnailURL
                )
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            
            if youtubeManager.isChannelLoading && youtubeManager.channelVideos.isEmpty {
                Spacer()
                ProgressView("Loading videos...")
                Spacer()
            } else {
                VideoGridView(
                    videos: youtubeManager.channelVideos,
                    isLoading: youtubeManager.isChannelLoading,
                    onLoadMore: youtubeManager.loadMoreChannelVideos,
                    selectedVideo: $selectedVideo, // Internal State
                    isVideoWatched: isVideoWatched
                )
            }
        }
        .task {
            // Load videos if needed when this view appears
             Logger.debug("ChannelDetailView .task called. Channel: \(channel.title), ID: \(channel.id), isPlaylist: \(channel.isPlaylist)", category: .ui)
             
             if youtubeManager.channelVideos.isEmpty || youtubeManager.channelVideos.first?.id != channel.id {
                 if channel.isPlaylist {
                     Logger.debug("Calling fetchVideosForPlaylist for \(channel.id)", category: .youtube)
                     youtubeManager.fetchVideosForPlaylist(channel.id)
                 } else {
                     Logger.debug("Calling fetchVideosForChannel for \(channel.id)", category: .youtube)
                     youtubeManager.fetchVideosForChannel(channel.id)
                 }
             } else {
                 Logger.debug("Videos already loaded for this channel/playlist.", category: .ui)
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
    
    // MARK: - Actions
    
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
        
        // Use profile language or default to Spanish if not found.
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
