import Foundation
import SwiftData

@Observable
@MainActor
final class StoryPathProgressStore {
    init() {}

    // MARK: - Per-chunk progress (keyed by story + chapter + scene)

    /// Fetch the most-recently-updated progress row for this chunk (scene),
    /// scoped to the given user. Returns nil if none exists.
    func progress(
        for storyID: String,
        chapterNumber: Int,
        sceneIndex: Int?,
        userID: String?,
        in context: ModelContext
    ) -> StoryPathProgress? {
        let descriptor = FetchDescriptor<StoryPathProgress>(
            predicate: #Predicate {
                $0.storyID == storyID &&
                $0.chapterNumber == chapterNumber &&
                $0.sceneIndex == sceneIndex &&
                $0.userID == userID
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Return the existing in-progress row for this chunk, or a fresh
    /// **un-inserted** instance. The fresh instance is only persisted once
    /// `save(_:allowInsert:)` is called with meaningful progress.
    @discardableResult
    func resumeOrCreate(
        storyID: String,
        storyTitle: String,
        chapterNumber: Int,
        sceneIndex: Int?,
        userID: String?,
        in context: ModelContext
    ) -> StoryPathProgress {
        if let existing = progress(for: storyID, chapterNumber: chapterNumber, sceneIndex: sceneIndex, userID: userID, in: context),
           existing.completedAt == nil {
            return existing
        }
        return StoryPathProgress(
            userID: userID,
            storyID: storyID,
            storyTitle: storyTitle,
            chapterNumber: chapterNumber,
            sceneIndex: sceneIndex
        )
    }

    /// Persist mutations. Inserts the row on first meaningful save; once
    /// inserted, subsequent saves always persist.
    func save(_ progress: StoryPathProgress, in context: ModelContext, allowInsert: Bool = true) {
        let alreadyInserted = progress.modelContext != nil
        guard alreadyInserted || allowInsert else { return }
        if !alreadyInserted {
            context.insert(progress)
        }
        progress.updatedAt = Date()
        progress.isSynced = false
        try? context.save()
    }

    /// Mark every stage complete and set `completedAt`.
    func complete(_ progress: StoryPathProgress, in context: ModelContext) {
        if progress.modelContext == nil {
            context.insert(progress)
        }
        progress.stageCompletion = Array(repeating: true, count: StoryPathProgress.stageCount)
        progress.currentStage = StoryPathProgress.stageCount
        progress.completedAt = Date()
        progress.updatedAt = Date()
        progress.isSynced = false
        try? context.save()
    }

    func discard(_ progress: StoryPathProgress, in context: ModelContext) {
        guard progress.modelContext != nil else { return }
        context.delete(progress)
        try? context.save()
    }

    // MARK: - Study Mode state (per story)

    /// The active Study Mode state for a story, if any.
    func studyState(
        for storyID: String,
        userID: String?,
        in context: ModelContext
    ) -> StoryStudyState? {
        let descriptor = FetchDescriptor<StoryStudyState>(
            predicate: #Predicate {
                $0.storyID == storyID &&
                $0.userID == userID &&
                $0.isActive == true
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// All active Study Mode states for the user, most-recently-touched first.
    /// Powers the "Studying" section on the Learn tab.
    func activeStudyStates(
        for userID: String?,
        in context: ModelContext,
        limit: Int = 50
    ) -> [StoryStudyState] {
        var descriptor = FetchDescriptor<StoryStudyState>(
            predicate: #Predicate {
                $0.userID == userID &&
                $0.isActive == true
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Resume the active Study Mode state for a story, or start a fresh one at
    /// the given first chunk. Persisted immediately (marking for study is a
    /// deliberate action).
    @discardableResult
    func startOrResumeStudy(
        storyID: String,
        storyTitle: String,
        firstChunk: StoryStudyChunk?,
        userID: String?,
        in context: ModelContext
    ) -> StoryStudyState {
        if let existing = studyState(for: storyID, userID: userID, in: context) {
            return existing
        }
        let state = StoryStudyState(
            userID: userID,
            storyID: storyID,
            storyTitle: storyTitle,
            currentChapterNumber: firstChunk?.chapterNumber ?? 0,
            currentSceneIndex: firstChunk?.sceneIndex ?? 0,
            currentOrdinal: firstChunk?.ordinal ?? 0,
            totalChunks: firstChunk?.total ?? 0
        )
        context.insert(state)
        try? context.save()
        return state
    }

    /// Move the study state to a new current chunk.
    func advanceStudy(_ state: StoryStudyState, to chunk: StoryStudyChunk, in context: ModelContext) {
        state.currentChapterNumber = chunk.chapterNumber
        state.currentSceneIndex = chunk.sceneIndex
        state.currentOrdinal = chunk.ordinal
        state.totalChunks = chunk.total
        state.updatedAt = Date()
        state.isSynced = false
        try? context.save()
    }

    /// Mark the whole story finished — Study Mode ends.
    func completeStudy(_ state: StoryStudyState, in context: ModelContext) {
        state.currentOrdinal = state.totalChunks
        state.isActive = false
        state.completedAt = Date()
        state.updatedAt = Date()
        state.isSynced = false
        try? context.save()
    }

    /// User chose to un-study a story: drop the state and any per-chunk progress.
    func unstudy(_ state: StoryStudyState, in context: ModelContext) {
        let storyID = state.storyID
        let userID = state.userID
        context.delete(state)
        let descriptor = FetchDescriptor<StoryPathProgress>(
            predicate: #Predicate { $0.storyID == storyID && $0.userID == userID }
        )
        if let rows = try? context.fetch(descriptor) {
            for row in rows { context.delete(row) }
        }
        try? context.save()
    }
}
