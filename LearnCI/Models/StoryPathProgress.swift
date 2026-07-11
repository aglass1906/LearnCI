import Foundation
import SwiftData

/// Tracks a user's progress through the 5-stage Story Guided Learning Path
/// for one story chapter. A row exists per (userID, storyID, chapterNumber);
/// completed rows are retained for history.
@Model
final class StoryPathProgress {
    @Attribute(.unique) var id: UUID
    var userID: String?
    var storyID: String
    var storyTitle: String
    var chapterNumber: Int
    var sceneIndex: Int?

    /// 1...5 — the stage currently in focus. Once all stages are complete this
    /// is capped at 5 and `completedAt` is set.
    var currentStage: Int

    /// 5-element JSON-encoded bool array of stage completion flags.
    /// Kept as JSON to avoid SwiftData nested-array pain.
    private var stageCompletionJSON: String

    var readMinutesAccumulated: Int
    var loopsCompleted: Int
    var wordsMarkedInSessionJSON: String
    var shadowLineIDsRecordedJSON: String

    var startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isSynced: Bool

    var stageCompletion: [Bool] {
        get {
            guard let data = stageCompletionJSON.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([Bool].self, from: data),
                  arr.count == 5 else {
                return [false, false, false, false, false]
            }
            return arr
        }
        set {
            let clamped = Array(newValue.prefix(5))
            let padded = clamped + Array(repeating: false, count: max(0, 5 - clamped.count))
            if let data = try? JSONEncoder().encode(padded), let json = String(data: data, encoding: .utf8) {
                stageCompletionJSON = json
            }
        }
    }

    var wordsMarkedInSession: [String] {
        get {
            guard let data = wordsMarkedInSessionJSON.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return arr
        }
        set {
            if let data = try? JSONEncoder().encode(newValue), let json = String(data: data, encoding: .utf8) {
                wordsMarkedInSessionJSON = json
            }
        }
    }

    var shadowLineIDsRecorded: [String] {
        get {
            guard let data = shadowLineIDsRecordedJSON.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return arr
        }
        set {
            if let data = try? JSONEncoder().encode(newValue), let json = String(data: data, encoding: .utf8) {
                shadowLineIDsRecordedJSON = json
            }
        }
    }

    var isComplete: Bool { completedAt != nil }

    init(
        id: UUID = UUID(),
        userID: String? = nil,
        storyID: String,
        storyTitle: String,
        chapterNumber: Int,
        sceneIndex: Int? = nil,
        currentStage: Int = 1,
        stageCompletion: [Bool] = [false, false, false, false, false],
        readMinutesAccumulated: Int = 0,
        loopsCompleted: Int = 0,
        wordsMarkedInSession: [String] = [],
        shadowLineIDsRecorded: [String] = [],
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.storyID = storyID
        self.storyTitle = storyTitle
        self.chapterNumber = chapterNumber
        self.sceneIndex = sceneIndex
        self.currentStage = currentStage
        self.stageCompletionJSON = (try? String(data: JSONEncoder().encode(stageCompletion), encoding: .utf8)) ?? "[false,false,false,false,false]"
        self.readMinutesAccumulated = readMinutesAccumulated
        self.loopsCompleted = loopsCompleted
        self.wordsMarkedInSessionJSON = (try? String(data: JSONEncoder().encode(wordsMarkedInSession), encoding: .utf8)) ?? "[]"
        self.shadowLineIDsRecordedJSON = (try? String(data: JSONEncoder().encode(shadowLineIDsRecorded), encoding: .utf8)) ?? "[]"
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.isSynced = false
    }
}
