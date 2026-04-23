import SwiftUI
import SwiftData

extension URL: Identifiable {
    public var id: String { absoluteString }
}

struct ResourceDetailView: View {
    let resource: LearningResource
    
    var body: some View {
        content
    }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    
    // @State private var showBrowser = false // Removed in favor of item-based sheet
    @State private var startTime: Date?
    
    @State private var browserUrl: URL?
    @State private var podcastManager = PodcastManager()
    @State private var selectedPodcastShow: PodcastShow?
    @State private var isSubscribing = false
    @Query(sort: \PodcastShow.addedAt) private var podcastShows: [PodcastShow]

    @Environment(YouTubeManager.self) private var youtubeManager
    @State private var selectedYouTubeChannel: YouTubeChannel?
    @State private var isResolvingChannel = false
    @Query private var allActivities: [UserActivity]
    
    func openUrl(_ url: URL) {
        browserUrl = url
        startTime = Date()
        // showBrowser = true // No longer needed with sheet(item:)
    }

    func openPodcast(feedUrl: String) {
        if let show = podcastShows.first(where: { $0.feedUrl == feedUrl }) {
            selectedPodcastShow = show
        } else {
            isSubscribing = true
            Task {
                await podcastManager.addPodcast(feedUrl: feedUrl, modelContext: modelContext, userID: authManager.currentUser)
                isSubscribing = false
                let descriptor = FetchDescriptor<PodcastShow>(predicate: #Predicate { $0.feedUrl == feedUrl })
                if let show = try? modelContext.fetch(descriptor).first {
                    selectedPodcastShow = show
                }
            }
        }
    }
    
    func openYouTubeChannel(url: String, title: String, thumbnail: String?) {
        if let channelId = FavoritesManager.resolveChannelId(from: url) {
            selectedYouTubeChannel = YouTubeChannel(id: channelId, title: title, thumbnailURL: thumbnail ?? "")
        } else if let playlistId = FavoritesManager.resolvePlaylistId(from: url) {
            selectedYouTubeChannel = YouTubeChannel(id: playlistId, title: title, thumbnailURL: thumbnail ?? "", isPlaylist: true)
        } else if url.contains("@") {
            isResolvingChannel = true
            Task {
                var handle: String?
                if let atRange = url.range(of: "@") {
                    let substring = url[atRange.lowerBound...]
                    let pathComponent = substring.components(separatedBy: "/").first ?? String(substring)
                    handle = pathComponent.components(separatedBy: "?").first ?? pathComponent
                }
                if let handle, let channelId = await youtubeManager.resolveChannelFromHandle(handle) {
                    await MainActor.run {
                        selectedYouTubeChannel = YouTubeChannel(id: channelId, title: title, thumbnailURL: thumbnail ?? "")
                    }
                } else {
                    await MainActor.run {
                        if let url = URL(string: url) { openUrl(url) }
                    }
                }
                await MainActor.run { isResolvingChannel = false }
            }
        } else {
            if let url = URL(string: url) { openUrl(url) }
        }
    }

    func isVideoWatched(_ videoId: String) -> Bool {
        allActivities.contains { activity in
            activity.activityType == .watchingVideos &&
            (activity.comment?.contains(videoId) ?? false)
        }
    }

    /// Finds the best YouTube URL for this resource — mainUrl if it's YouTube, otherwise the first YouTube resource link.
    func bestYouTubeUrl() -> String? {
        let main = resource.mainUrl
        if main.contains("youtube.com") || main.contains("youtu.be") {
            return main
        }
        if let links = resource.resourceLinks {
            if let ytLink = links.first(where: { $0.type.lowercased() == "youtube" && ($0.isActive ?? true) }) {
                return ytLink.url
            }
        }
        return nil
    }

    func getLinkIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "youtube": return "play.rectangle.fill"
        case "spotify", "podcast", "apple_podcasts": return "headphones"
        case "pdf": return "doc.text.fill"
        case "website": return "globe"
        default: return "link"
        }
    }
    
    func handleBrowserDismiss() {
        browserUrl = nil
        if let start = startTime {
            let minutes = Int(Date().timeIntervalSince(start) / 60)
            if minutes > 0 {
                let activity = UserActivity(
                    date: start,
                    minutes: minutes,
                    activityType: mapResourceTypeToActivity(resource.type),
                    language: Language(rawValue: resource.language) ?? .spanish,
                    userID: authManager.currentUser,
                    comment: "\(resource.title)"
                )
                modelContext.insert(activity)
                try? modelContext.save()
            }
            startTime = nil
        }
    }
    
    func mapResourceTypeToActivity(_ type: ResourceType) -> ActivityType {
        switch type {
        case .book, .website, .webScan: return .reading
        case .youtube: return .watchingVideos
        case .podcast: return .podcasts
        }
    }
    
    // Helper to determine the correct favorite type and ID (Channel ID vs URL)
    func resolveFavoriteTypeAndId(_ resource: LearningResource) -> (FavoriteType, String) {
        // Default to website/url
        var type: FavoriteType = .website
        var id: String = resource.mainUrl
        
        switch resource.type {
        case .youtube:
            // Use Central Helper
            if let resolvedId = FavoritesManager.resolveChannelId(from: resource.mainUrl) {
                type = .channel
                id = resolvedId
            } else {
                 type = .website
            }
            
        case .podcast:
            type = .podcast
            if let feedUrl = resource.feedUrl, !feedUrl.isEmpty {
                id = feedUrl
            }
        case .webScan:
            type = .webScan
        default:
            type = .website
        }
        
        return (type, id)
    }
}

extension ResourceDetailView {
    // ... existing view ...
}

// Add sheets to main body
extension ResourceDetailView {
    // This wrapper is needed because `body` is computed
    // We will inject the sheet modifiers into the main details view below
}

// Re-structure struct for cleaner modifiers
extension ResourceDetailView {
    
    @ViewBuilder
    var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero Image
                ZStack {
                    Color(UIColor.secondarySystemBackground) // Clean neutral background
                    
                    AsyncImage(url: URL(string: resource.coverImageUrl ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(20) // Extra padding for the large detail view
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    } placeholder: {
                        Image(systemName: resource.type.icon)
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.3))
                    }
                }
                .frame(height: 250)
                .clipped()
                
                VStack(alignment: .leading, spacing: 16) {
                    // Title Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(resource.type.displayName.uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        
                        Text(resource.title)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        Text(resource.author)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Metadata Badges
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Badge(text: resource.difficulty, color: .blue)
                            Badge(text: resource.language.uppercased(), color: .orange)
                            
                            ForEach(resource.tags, id: \.self) { tag in
                                Badge(text: tag, color: .gray)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.headline)
                        
                        Text(resource.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    
                    // Curator Notes
                    if let notes = resource.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Curator's Note", systemImage: "quote.opening")
                                .font(.headline)
                                .foregroundStyle(.indigo)
                            
                            Text(notes)
                                .font(.body)
                                .italic()
                                .foregroundStyle(.primary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.indigo.opacity(0.05))
                                .cornerRadius(12)
                        }
                    }
                    
                    Spacer(minLength: 20)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        // Podcast "Listen in App" Button
                        if resource.type == .podcast, let feedUrl = resource.feedUrl, !feedUrl.isEmpty {
                            HStack {
                                Button(action: {
                                    openPodcast(feedUrl: feedUrl)
                                }) {
                                    HStack {
                                        if isSubscribing {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "headphones")
                                        }
                                        Text(podcastShows.contains(where: { $0.feedUrl == feedUrl }) ? "View Episodes" : "Listen in App")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                    }
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding()
                                    .background(Color.purple)
                                    .cornerRadius(16)
                                }
                                .disabled(isSubscribing)

                                // Favorite (use feedUrl for podcast routing)
                                let (favType, favId) = resolveFavoriteTypeAndId(resource)

                                FavoriteButton(
                                    consumptionUrl: favId,
                                    type: favType,
                                    title: resource.title,
                                    author: resource.author,
                                    imageUrl: resource.coverImageUrl,
                                    sourceResourceId: resource.id.uuidString
                                )
                                .font(.title2)
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(16)
                            }
                        }

                        // Main URL Button (secondary when native action exists, primary for others)
                        if let url = URL(string: resource.mainUrl), !resource.mainUrl.isEmpty {
                            let hasNativeAction = resource.type == .podcast && resource.feedUrl != nil && !resource.feedUrl!.isEmpty
                            HStack {
                                Button(action: {
                                    openUrl(url)
                                }) {
                                    HStack {
                                        Image(systemName: "safari")
                                        Text(hasNativeAction ? "Visit Website" : "Open Creator Page")
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .font(.headline)
                                    .foregroundStyle(hasNativeAction ? Color.primary : .white)
                                    .padding()
                                    .background(hasNativeAction ? Color(UIColor.secondarySystemBackground) : Color.blue)
                                    .cornerRadius(16)
                                }

                                if !hasNativeAction {
                                    // Favorite Main Resource Link (only for non-podcast primary buttons)
                                    let (favType, favId) = resolveFavoriteTypeAndId(resource)

                                    FavoriteButton(
                                        consumptionUrl: favId,
                                        type: favType,
                                        title: resource.title,
                                        author: resource.author,
                                        imageUrl: resource.coverImageUrl,
                                        sourceResourceId: resource.id.uuidString
                                    )
                                    .font(.title2)
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(16)
                                }
                            }
                        }
                        
                        // Additional Resource Links
                        if let links = resource.resourceLinks {
                            ForEach(links.filter { $0.isActive ?? true }.sorted { ($0.order ?? 0) < ($1.order ?? 0) }) { link in
                                if let url = URL(string: link.url) {
                                    let isPodcastLink = ["podcast", "apple_podcasts"].contains(link.type.lowercased())
                                    let isYouTubeLink = link.type.lowercased() == "youtube"
                                    let isNativeLink = isPodcastLink || isYouTubeLink
                                    HStack {
                                        Button(action: {
                                            if isPodcastLink {
                                                openPodcast(feedUrl: link.url)
                                            } else if isYouTubeLink {
                                                openYouTubeChannel(url: link.url, title: link.label.isEmpty ? resource.title : link.label, thumbnail: resource.coverImageUrl)
                                            } else {
                                                openUrl(url)
                                            }
                                        }) {
                                            HStack(spacing: 12) {
                                                Image(systemName: getLinkIcon(link.type))
                                                    .foregroundStyle(.secondary)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(link.label.isEmpty ? resource.title : link.label)
                                                        .lineLimit(1)
                                                    Text(isPodcastLink ? "Podcast Feed" : isYouTubeLink ? "YouTube" : link.type.capitalized.replacingOccurrences(of: "_", with: " "))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                if (isPodcastLink && isSubscribing) || (isYouTubeLink && isResolvingChannel) {
                                                    ProgressView()
                                                } else {
                                                    Image(systemName: isNativeLink ? "chevron.right" : "arrow.up.right")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(Color.primary)
                                            .padding()
                                            .background(Color(UIColor.secondarySystemBackground))
                                            .cornerRadius(16)
                                        }

                                        // Favorite Link
                                        FavoriteButton(
                                            consumptionUrl: link.url,
                                            type: isPodcastLink ? .podcast : isYouTubeLink ? .youtube : .other,
                                            title: link.label.isEmpty ? resource.title : link.label,
                                            author: resource.author,
                                            subtitle: resource.title,
                                            imageUrl: resource.coverImageUrl,
                                            sourceResourceId: resource.id.uuidString
                                        )
                                        .padding()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedPodcastShow) { show in
            PodcastShowView(show: show)
        }
        .navigationDestination(item: $selectedYouTubeChannel) { channel in
            ChannelDetailView(
                channel: channel,
                isVideoWatched: isVideoWatched
            )
        }
        .sheet(item: $browserUrl) { url in
            InAppBrowserView(url: url, onDismiss: handleBrowserDismiss)
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
