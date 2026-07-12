import Foundation
import SwiftData

/// Per-story Study Mode umbrella. When a story is marked for study, one active
/// row tracks which chunk (scene) is up next. Multiple stories can be in study
/// mode at once. The row stays active until every chunk is done or the user
/// un-studies the story.
@Model
final class StoryStudyState {
    @Attribute(.unique) var id: UUID
    var userID: String?
    var storyID: String
    var storyTitle: String

    /// The chunk the learner is currently on (next to study).
    var currentChapterNumber: Int
    var currentSceneIndex: Int
    /// Cached for progress display without re-deriving the chunk list.
    var currentOrdinal: Int
    var totalChunks: Int

    var isActive: Bool
    var startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isSynced: Bool

    var progressFraction: Double {
        guard totalChunks > 0 else { return 0 }
        return min(1, Double(currentOrdinal) / Double(totalChunks))
    }

    init(
        id: UUID = UUID(),
        userID: String? = nil,
        storyID: String,
        storyTitle: String,
        currentChapterNumber: Int,
        currentSceneIndex: Int,
        currentOrdinal: Int = 0,
        totalChunks: Int,
        isActive: Bool = true,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.storyID = storyID
        self.storyTitle = storyTitle
        self.currentChapterNumber = currentChapterNumber
        self.currentSceneIndex = currentSceneIndex
        self.currentOrdinal = currentOrdinal
        self.totalChunks = totalChunks
        self.isActive = isActive
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.isSynced = false
    }
}
