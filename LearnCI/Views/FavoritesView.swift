import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(YouTubeManager.self) private var youtubeManager
    @Environment(SyncManager.self) private var syncManager
    @Environment(DataManager.self) private var dataManager // For finding resources if needed, though we store URL.
    
    // We need user profile for language/level if we want to filter, but favorites are user-specific anyway.
    @Query private var allActivities: [UserActivity]
    
    @Query(sort: \Favorite.createdAt, order: .reverse) private var favorites: [Favorite]
    
    // Filter State
    @State private var typeFilter: FavoriteType? = nil // nil = All
    @State private var authorFilter: String? = nil // nil = All
    
    // Navigation State
    // Navigation State
    @State private var selectedChannel: YouTubeChannel?
    @State private var selectedResourceLink: Favorite? // For opening links
    // @State private var showBrowser = false // Removed in favor of item-based sheet
    @State private var browserUrl: URL?
    
    // Derived Filters
    var filteredFavorites: [Favorite] {
        favorites.filter { fav in
            // Type Filter
            if let type = typeFilter {
                if type == .other {
                    // encompass anything not channel/website/podcast?
                    // For now strict match
                   if fav.type != type { return false }
                } else {
                     if fav.type != type { return false }
                }
            }
            
            // Author Filter
            if let author = authorFilter {
                if fav.author != author { return false }
            }
            
            return true
        }
    }
    
    var availableAuthors: [String] {
        let authors = favorites.compactMap { $0.author }
        return Array(Set(authors)).sorted()
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Filters
                VStack(spacing: 12) {
                    // Type Filter Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            FilterPill(title: "All", isSelected: typeFilter == nil) { typeFilter = nil }
                            
                            FilterPill(title: "Channels", isSelected: typeFilter == .channel) { typeFilter = .channel }
                            FilterPill(title: "YouTube", isSelected: typeFilter == .youtube) { typeFilter = .youtube }
                            FilterPill(title: "Websites", isSelected: typeFilter == .website) { typeFilter = .website }
                            FilterPill(title: "Podcasts", isSelected: typeFilter == .podcast) { typeFilter = .podcast }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Author Filter Chips
                    if !availableAuthors.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterPill(title: "All Creators", isSelected: authorFilter == nil, color: .gray) { authorFilter = nil }
                                
                                ForEach(availableAuthors, id: \.self) { author in
                                    FilterPill(title: author, isSelected: authorFilter == author, color: .gray) { authorFilter = author }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
                .background(Color(UIColor.systemBackground))
                
                // MARK: - Content
                if filteredFavorites.isEmpty {
                    ContentUnavailableView(
                        "No Favorites Found",
                        systemImage: "heart.slash",
                        description: Text("Try changing your filters or add some favorites from the Library or Videos tab.")
                    )
                } else {
                    List {
                        ForEach(filteredFavorites) { fav in
                             FavoriteRow(favorite: fav) {
                                 handleTap(fav)
                             }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("My Favorites")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await syncManager.syncNow(modelContext: modelContext)
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .symbolEffect(.bounce, value: syncManager.isSyncing)
                    }
                    .disabled(syncManager.isSyncing)
                }
            }
            .navigationDestination(item: $selectedChannel) { channel in
                ChannelDetailView(
                    channel: channel,
                    isVideoWatched: isVideoWatched
                    // isPlaylist is now part of channel model
                )
            }
            .sheet(item: $browserUrl) { url in
                InAppBrowserView(url: url) {
                    browserUrl = nil
                }
                .ignoresSafeArea()
            }
            .alert("Debug Info", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Actions
    
    func handleTap(_ fav: Favorite) {
        Logger.debug("handleTap called for \(fav.title) | Type: \(fav.type) | URL: \(fav.consumptionUrl)", category: .ui)
        
        // Check if it's explicitly a channel OR if we can resolve it to one (Runtime Fix)
        if fav.type == .channel {
            openChannel(id: fav.consumptionUrl, title: fav.title, thumbnail: fav.imageUrl)
        } else if let resolvedId = FavoritesManager.resolveChannelId(from: fav.consumptionUrl) {
            // Static/Hardcoded resolution (Fast)
            Logger.debug("Auto-resolving legacy favorite '\(fav.title)' to Channel ID: \(resolvedId)", category: .favorites)
            openChannel(id: resolvedId, title: fav.title, thumbnail: fav.imageUrl)
        } else if let playlistId = FavoritesManager.resolvePlaylistId(from: fav.consumptionUrl) {
             Logger.debug("Detected Playlist ID: \(playlistId)", category: .favorites)
             
             // ... rest of the code ...
             openChannel(id: playlistId, title: fav.title, thumbnail: fav.imageUrl, isPlaylist: true)
             
        } else if fav.consumptionUrl.contains("@") && (fav.type == .website || fav.type == .youtube) {
            // Async Dynamic Resolution (Slow - requires API)
            Task {
                // Extract handle from URL
                // Supports: youtube.com/@handle, mobile versions, etc.
                var handle: String? = nil
                
                if let atRange = fav.consumptionUrl.range(of: "@") {
                    let substring = fav.consumptionUrl[atRange.lowerBound...] // "@handle/..."
                    // Split by / to get component, then by ? to remove query params
                    let pathComponent = substring.components(separatedBy: "/").first ?? String(substring)
                    let cleanHandle = pathComponent.components(separatedBy: "?").first ?? pathComponent
                    handle = cleanHandle
                }
                
                if let handle = handle {
                    print("DEBUG: Attempting to resolve handle: \(handle)")
                    if let channelId = await youtubeManager.resolveChannelFromHandle(handle) {
                        print("DEBUG: Resolved \(handle) -> \(channelId)")
                        await MainActor.run {
                            openChannel(id: channelId, title: fav.title, thumbnail: fav.imageUrl)
                        }
                    } else {
                        print("DEBUG: Resolution failed for \(handle), fallback to browser")
                        await MainActor.run {
                             // DEBUG: Show why resolution failed
                             errorMessage = "DEBUG: Failed to resolve handle: \(handle). fallback to browser."
                             showError = true
                             
                             if let url = URL(string: fav.consumptionUrl) {
                                browserUrl = url
                            }
                        }
                    }
                } else {
                      await MainActor.run {
                            if let url = URL(string: fav.consumptionUrl) {
                                browserUrl = url
                            }
                        }
                }
            }
        } else {
            // Open Link
            if let url = URL(string: fav.consumptionUrl) {
                browserUrl = url
            }
        }
    }
    
    // Debug helper
    @State private var showError = false
    @State private var errorMessage = ""
    
    func openChannel(id: String, title: String, thumbnail: String?, isPlaylist: Bool = false) {
        let channel = YouTubeChannel(
            id: id,
            title: title,
            thumbnailURL: thumbnail ?? "",
            isPlaylist: isPlaylist // Set directly on model
        )
        // self.isPlaylistNavigation = isPlaylist // Removed state
        selectedChannel = channel
    }
    
    // ... helpers ...
    
    // @State private var isPlaylistNavigation = false // Removed State

    // MARK: - Helpers (Duplicated from VideoView - should be extracted if exact match needed)
    
    private func isVideoWatched(_ videoId: String) -> Bool {
        allActivities.contains { activity in
            activity.activityType == .watchingVideos && 
            (activity.comment?.contains(videoId) ?? false)
        }
    }
}

// MARK: - Components

struct FilterPill: View {
    let title: String
    let isSelected: Bool
    var color: Color = .blue
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? color : Color.gray.opacity(0.1))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

struct FavoriteRow: View {
    let favorite: Favorite
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon / Image
                if let imageUrl = favorite.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: favorite.type == .youtube ? 89 : 50, height: 50) // 16:9 for videos, 1:1 for others
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: favorite.type.icon)
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .offset(x: 4, y: 4) // Slight overhang or sticking to corner
                    }
                } else {
                    Image(systemName: favorite.type.icon)
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(favorite.title)
                        .font(.headline)
                    
                    if let subtitle = favorite.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let author = favorite.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            FavoriteButton(
                 consumptionUrl: favorite.consumptionUrl,
                 type: favorite.type,
                 title: favorite.title
            )
            .tint(.red)
        }
    }
}
