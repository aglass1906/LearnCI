import Foundation

/// User preference for podcast episode order (list display and playback queue).
enum PodcastPlayOrder {
    static let storageKey = "input.podcasts.playOldestFirst"

    static func sorted(_ episodes: [PodcastEpisode], oldestFirst: Bool) -> [PodcastEpisode] {
        episodes.sorted {
            oldestFirst ? $0.publishedDate < $1.publishedDate : $0.publishedDate > $1.publishedDate
        }
    }
}
