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
