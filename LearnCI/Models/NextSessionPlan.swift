import Foundation
import SwiftData

enum NextSessionPlanStatus: String, Codable, CaseIterable {
    case pending
    case started
    case completed
    case skipped
}

enum NextSessionSourceType: String, Codable, CaseIterable {
    case story
    case podcast
    case youtube
}

@Model
final class NextSessionPlan {
    @Attribute(.unique) var id: UUID
    var userID: String?
    var createdAt: Date
    var scheduledFor: Date

    var sourceTypeRaw: String
    var sourceID: String
    var sourceTitle: String
    var chapterNumber: Int?
    var sceneIndex: Int?

    var targetMinutes: Int
    var wordReviewCount: Int
    var focusNote: String?

    var notificationTime: Date?
    var notificationID: String?

    var statusRaw: String
    var isSynced: Bool

    var sourceType: NextSessionSourceType {
        get { NextSessionSourceType(rawValue: sourceTypeRaw) ?? .story }
        set { sourceTypeRaw = newValue.rawValue }
    }

    var status: NextSessionPlanStatus {
        get { NextSessionPlanStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        userID: String? = nil,
        createdAt: Date = Date(),
        scheduledFor: Date,
        sourceType: NextSessionSourceType = .story,
        sourceID: String,
        sourceTitle: String,
        chapterNumber: Int? = nil,
        sceneIndex: Int? = nil,
        targetMinutes: Int = 10,
        wordReviewCount: Int = 5,
        focusNote: String? = nil,
        notificationTime: Date? = nil,
        notificationID: String? = nil,
        status: NextSessionPlanStatus = .pending
    ) {
        self.id = id
        self.userID = userID
        self.createdAt = createdAt
        self.scheduledFor = scheduledFor
        self.sourceTypeRaw = sourceType.rawValue
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.chapterNumber = chapterNumber
        self.sceneIndex = sceneIndex
        self.targetMinutes = targetMinutes
        self.wordReviewCount = wordReviewCount
        self.focusNote = focusNote
        self.notificationTime = notificationTime
        self.notificationID = notificationID
        self.statusRaw = status.rawValue
        self.isSynced = false
    }
}
