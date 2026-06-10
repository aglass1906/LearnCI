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
    /// User-marked start of study content (skips intro/ads before this timestamp).
    var studyContentStartSeconds: Double = 0
    /// Manual nudge applied to transcript block timings (+ = shift later, − = shift earlier).
    var studyTranscriptOffsetSeconds: Double = 0
    var transcriptUrl: String?
    var transcriptType: String?
    var isSynced: Bool = false

    var show: PodcastShow?

    var hasFeedTranscript: Bool {
        guard let transcriptUrl else { return false }
        return !transcriptUrl.isEmpty
    }

    init(id: UUID = UUID(),
         title: String,
         episodeDescription: String = "",
         audioUrl: String,
         publishedDate: Date = Date(),
         duration: Double = 0,
         playbackPosition: Double = 0,
         isPlayed: Bool = false,
         studyContentStartSeconds: Double = 0,
         studyTranscriptOffsetSeconds: Double = 0,
         transcriptUrl: String? = nil,
         transcriptType: String? = nil) {
        self.id = id
        self.title = title
        self.episodeDescription = episodeDescription
        self.audioUrl = audioUrl
        self.publishedDate = publishedDate
        self.duration = duration
        self.playbackPosition = playbackPosition
        self.isPlayed = isPlayed
        self.studyContentStartSeconds = studyContentStartSeconds
        self.studyTranscriptOffsetSeconds = studyTranscriptOffsetSeconds
        self.transcriptUrl = transcriptUrl
        self.transcriptType = transcriptType
        self.isSynced = false
    }

    var playableAudioURL: URL? {
        PodcastPlaybackURL.make(from: audioUrl)
    }

    var favoriteConsumptionUrl: String {
        PodcastFavoriteURL.episode(id)
    }

    var favoriteSubtitle: String? {
        var parts: [String] = []
        if duration > 0 {
            let minutes = Int(duration) / 60
            if minutes > 0 {
                parts.append("\(minutes) min")
            }
        }
        let dateText = publishedDate.formatted(date: .abbreviated, time: .omitted)
        parts.append(dateText)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
