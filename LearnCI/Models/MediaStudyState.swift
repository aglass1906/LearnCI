import Foundation
import SwiftData

/// Study Mode umbrella row for non-story media (YouTube videos, podcast
/// episodes). Mirrors `StoryStudyState`: one active row per
/// (user, resource type, resource id). The row stays active until the user
/// un-studies the item. Local-only for now — `isSynced` is kept for future
/// parity with the synced models but there is no SyncManager wiring.
@Model
final class MediaStudyState {
    @Attribute(.unique) var id: UUID
    var userID: String?
    /// `StudyResourceType.rawValue`: "youtube" | "podcast".
    var resourceTypeRaw: String
    /// YouTube video id, or `PodcastEpisode.id.uuidString`.
    var resourceId: String
    var consumptionUrl: String

    // Snapshots — videos aren't persisted anywhere else, so the row must be
    // able to render (and rebuild a `YouTubeVideo`) on its own.
    var title: String
    /// Channel title (video) or show title (podcast episode).
    var subtitle: String?
    var artworkUrl: String?

    /// Media length in seconds; 0 = unknown.
    var durationSeconds: Double
    /// Last observed playback position in seconds.
    var lastPositionSeconds: Double
    var completedBlockCount: Int
    var totalBlockCount: Int

    var isActive: Bool
    var startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isSynced: Bool

    var resourceType: StudyResourceType? {
        StudyResourceType(rawValue: resourceTypeRaw)
    }

    var progressFraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, max(0, lastPositionSeconds / durationSeconds))
    }

    init(
        id: UUID = UUID(),
        userID: String? = nil,
        resourceType: StudyResourceType,
        resourceId: String,
        consumptionUrl: String,
        title: String,
        subtitle: String? = nil,
        artworkUrl: String? = nil,
        durationSeconds: Double = 0,
        lastPositionSeconds: Double = 0,
        completedBlockCount: Int = 0,
        totalBlockCount: Int = 0,
        isActive: Bool = true,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.resourceTypeRaw = resourceType.rawValue
        self.resourceId = resourceId
        self.consumptionUrl = consumptionUrl
        self.title = title
        self.subtitle = subtitle
        self.artworkUrl = artworkUrl
        self.durationSeconds = durationSeconds
        self.lastPositionSeconds = lastPositionSeconds
        self.completedBlockCount = completedBlockCount
        self.totalBlockCount = totalBlockCount
        self.isActive = isActive
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.isSynced = false
    }
}
