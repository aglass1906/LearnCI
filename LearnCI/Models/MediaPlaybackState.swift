import Foundation
import SwiftData

/// Local resume state for media watched inside LearnCI. This is deliberately
/// separate from `MediaStudyState`: watching a video does not imply that the
/// user added it to Study Mode.
@Model
final class MediaPlaybackState {
    @Attribute(.unique) var id: UUID
    var userID: String?
    var resourceTypeRaw: String
    var resourceId: String
    var title: String
    var subtitle: String?
    var artworkUrl: String?
    var durationSeconds: Double
    var lastPositionSeconds: Double
    var startedAt: Date
    var updatedAt: Date

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
        title: String,
        subtitle: String? = nil,
        artworkUrl: String? = nil,
        durationSeconds: Double = 0,
        lastPositionSeconds: Double = 0,
        startedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.resourceTypeRaw = resourceType.rawValue
        self.resourceId = resourceId
        self.title = title
        self.subtitle = subtitle
        self.artworkUrl = artworkUrl
        self.durationSeconds = durationSeconds
        self.lastPositionSeconds = lastPositionSeconds
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}
