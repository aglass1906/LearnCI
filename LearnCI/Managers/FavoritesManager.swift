import Foundation
import SwiftData
import SwiftUI

@Observable
class FavoritesManager {
    // No local state needed if we use @Query in views, 
    // but this manager can provide helper methods for toggling.
    
    // Helper to check if item is favorited
    func isFavorited(url: String, in context: ModelContext, userID: String) -> Bool {
        // We'll perform a fetch
        let descriptor = FetchDescriptor<Favorite>(
            predicate: #Predicate { $0.consumptionUrl == url && $0.userID == userID }
        )
        do {
            let count = try context.fetchCount(descriptor)
            return count > 0
        } catch {
            print("Error checking favorite status: \(error)")
            return false
        }
    }
    
    func toggleFavorite(
        context: ModelContext,
        userID: String,
        consumptionUrl: String,
        type: FavoriteType,
        title: String,
        author: String?,
        subtitle: String?,
        imageUrl: String?,
        sourceResourceId: String?
    ) {
        // ... implementation ...
        // Check if exists
        let descriptor = FetchDescriptor<Favorite>(
            predicate: #Predicate { $0.consumptionUrl == consumptionUrl && $0.userID == userID }
        )
        
        do {
            let existing = try context.fetch(descriptor)
            if let match = existing.first {
                // Remove
                Logger.debug("Removing favorite for \(consumptionUrl)", category: .favorites)
                context.delete(match)
            } else {
                // Add
                Logger.debug("Adding favorite for \(consumptionUrl)", category: .favorites)
                
                // Auto-detect YouTube type if not explicitly set
                var finalType = type
                if (consumptionUrl.contains("youtube.com") || consumptionUrl.contains("youtu.be")) && type != .channel {
                    finalType = .youtube
                }
                
                let newFavorite = Favorite(
                    userID: userID,
                    consumptionUrl: consumptionUrl,
                    type: finalType,
                    title: title,
                    author: author,
                    subtitle: subtitle,
                    imageUrl: imageUrl,
                    sourceResourceId: sourceResourceId
                )
                context.insert(newFavorite)
            }
            try context.save()
            Logger.info("Favorites saved successfully.", category: .favorites)
        } catch {
            Logger.error("Error toggling favorite: \(error)", category: .favorites)
        }
    }
    
    // MARK: - Static Helpers
    
    static func resolveChannelId(from url: String) -> String? {
        // 1. Check for standard Channel URL
        if url.contains("channel/") {
            // Extract ID: .../channel/UCxyz... -> UCxyz
            // Split by "channel/" and take the part after
            if let fragment = url.components(separatedBy: "channel/").last {
                // Take the first component if there are trailing slashes or query params
                let id = fragment.components(separatedBy: "/").first ?? fragment
                // Basic validation: Channel IDs usually start with UC
                 if id.starts(with: "UC") {
                     return id
                 }
            }
        }
        return nil
    }
    
    static func resolveVideoId(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 11,
           trimmed.range(of: #"^[a-zA-Z0-9_-]{11}$"#, options: .regularExpression) != nil {
            return trimmed
        }
        guard let url = URL(string: trimmed),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if url.host?.contains("youtu.be") == true {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.count == 11 ? id : nil
        }
        if let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value, videoId.count == 11 {
            return videoId
        }
        if trimmed.contains("/shorts/"),
           let id = trimmed.components(separatedBy: "/shorts/").last?.components(separatedBy: "?").first,
           id.count == 11 {
            return id
        }
        return nil
    }
    
    /// Normalized YouTube favorite keys for filtering subscription feeds and channel grids.
    struct YouTubeFavoritesIndex {
        var channelIds: Set<String> = []
        var videoIds: Set<String> = []
        var playlistIds: Set<String> = []
        
        static func build(from favorites: [Favorite], userID: String) -> YouTubeFavoritesIndex {
            var index = YouTubeFavoritesIndex()
            for fav in favorites where fav.userID == userID {
                switch fav.type {
                case .channel:
                    if let channelId = normalizedChannelId(fav.consumptionUrl) {
                        index.channelIds.insert(channelId)
                    }
                case .youtube:
                    if let videoId = resolveVideoId(from: fav.consumptionUrl) {
                        index.videoIds.insert(videoId)
                    } else if let channelId = resolveChannelId(from: fav.consumptionUrl) {
                        index.channelIds.insert(channelId)
                    } else if let playlistId = resolvePlaylistId(from: fav.consumptionUrl) {
                        index.playlistIds.insert(playlistId)
                    } else if let channelId = normalizedChannelId(fav.consumptionUrl) {
                        index.channelIds.insert(channelId)
                    }
                default:
                    let url = fav.consumptionUrl
                    guard url.contains("youtube.com") || url.contains("youtu.be") else { continue }
                    if let videoId = resolveVideoId(from: url) {
                        index.videoIds.insert(videoId)
                    } else if let channelId = resolveChannelId(from: url) {
                        index.channelIds.insert(channelId)
                    } else if let playlistId = resolvePlaylistId(from: url) {
                        index.playlistIds.insert(playlistId)
                    } else if let channelId = normalizedChannelId(url) {
                        index.channelIds.insert(channelId)
                    }
                }
            }
            return index
        }
        
        func matches(video: YouTubeVideo) -> Bool {
            if videoIds.contains(video.id) { return true }
            if let channelId = video.channelId, channelIds.contains(channelId) { return true }
            return false
        }
        
        func matches(channel: YouTubeChannel) -> Bool {
            if channelIds.contains(channel.id) { return true }
            if channel.isPlaylist, playlistIds.contains(channel.id) { return true }
            return false
        }
        
        private static func normalizedChannelId(_ value: String) -> String? {
            if let resolved = resolveChannelId(from: value) { return resolved }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("UC"), trimmed.count >= 20 {
                return String(trimmed.prefix(24))
            }
            return nil
        }
    }
    
    static func resolvePlaylistId(from urlString: String) -> String? {
        // Logging for debugging
        Logger.debug("Attempting to resolve Playlist ID from: \(urlString)", category: .favorites)
        
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            Logger.debug("Failed to parse URL components for: \(urlString)", category: .favorites)
            return nil
        }
        
        if let listId = queryItems.first(where: { $0.name == "list" })?.value {
            Logger.debug("Found Playlist ID: \(listId)", category: .favorites)
            return listId
        } else {
             Logger.debug("No 'list' query parameter found.", category: .favorites)
             return nil
        }
    }
}
