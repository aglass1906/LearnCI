import Foundation

enum PodcastFavoriteURL {
    private static let episodePrefix = "learn-ci://podcast/episode/"

    static func episode(_ episodeId: UUID) -> String {
        "\(episodePrefix)\(episodeId.uuidString)"
    }

    static func episodeId(from consumptionUrl: String) -> UUID? {
        guard consumptionUrl.hasPrefix(episodePrefix) else { return nil }
        let idString = String(consumptionUrl.dropFirst(episodePrefix.count))
        return UUID(uuidString: idString)
    }

    static func isEpisodeFavorite(_ consumptionUrl: String) -> Bool {
        episodeId(from: consumptionUrl) != nil
    }

    static func normalizedFeedKey(_ urlString: String) -> String {
        var value = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    struct Index {
        var episodeIds: Set<UUID> = []
        var showFeedKeys: Set<String> = []

        static func build(from favorites: [Favorite], userID: String) -> Index {
            var index = Index()
            for favorite in favorites where favorite.userID == userID {
                switch favorite.type {
                case .podcastEpisode:
                    if let episodeId = episodeId(from: favorite.consumptionUrl) {
                        index.episodeIds.insert(episodeId)
                    } else if let sourceId = favorite.sourceResourceId,
                              let episodeId = UUID(uuidString: sourceId) {
                        index.episodeIds.insert(episodeId)
                    }
                case .podcast:
                    index.showFeedKeys.insert(normalizedFeedKey(favorite.consumptionUrl))
                default:
                    break
                }
            }
            return index
        }

        func matchesFavoritedEpisode(_ episode: PodcastEpisode) -> Bool {
            episodeIds.contains(episode.id)
        }

        func matches(_ show: PodcastShow) -> Bool {
            showFeedKeys.contains(PodcastFavoriteURL.normalizedFeedKey(show.feedUrl))
        }
    }
}
