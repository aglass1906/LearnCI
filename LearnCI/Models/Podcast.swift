import Foundation
import SwiftData

@Model
final class PodcastShow: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var showDescription: String
    var feedUrl: String
    var artworkUrl: String?
    var languageRaw: String
    var addedAt: Date
    var userID: String?
    var isSynced: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \PodcastEpisode.show)
    var episodes: [PodcastEpisode] = []

    var language: Language {
        get { Language(rawValue: languageRaw) ?? .spanish }
        set { languageRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(),
         title: String,
         author: String,
         showDescription: String = "",
         feedUrl: String,
         artworkUrl: String? = nil,
         language: Language = .spanish,
         addedAt: Date = Date(),
         userID: String? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.showDescription = showDescription
        self.feedUrl = feedUrl
        self.artworkUrl = artworkUrl
        self.languageRaw = language.rawValue
        self.addedAt = addedAt
        self.userID = userID
        self.isSynced = false
    }
}

@Model
final class PodcastEpisode: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var episodeDescription: String
    var audioUrl: String
    var publishedDate: Date
    var duration: Double // seconds
    var playbackPosition: Double // for resume
    var isPlayed: Bool
    var isSynced: Bool = false

    var show: PodcastShow?

    init(id: UUID = UUID(),
         title: String,
         episodeDescription: String = "",
         audioUrl: String,
         publishedDate: Date = Date(),
         duration: Double = 0,
         playbackPosition: Double = 0,
         isPlayed: Bool = false) {
        self.id = id
        self.title = title
        self.episodeDescription = episodeDescription
        self.audioUrl = audioUrl
        self.publishedDate = publishedDate
        self.duration = duration
        self.playbackPosition = playbackPosition
        self.isPlayed = isPlayed
        self.isSynced = false
    }
}
