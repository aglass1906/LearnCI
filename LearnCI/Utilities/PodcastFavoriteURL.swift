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
}
