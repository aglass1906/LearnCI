import Foundation
import SwiftData

@Observable
@MainActor
final class StoryPathProgressStore {
    init() {}

    /// Fetch the most-recently-updated progress row for this story + chapter,
    /// scoped to the given user. Returns nil if none exists.
    func progress(
        for storyID: String,
        chapterNumber: Int,
        userID: String?,
        in context: ModelContext
    ) -> StoryPathProgress? {
        let descriptor = FetchDescriptor<StoryPathProgress>(
            predicate: #Predicate {
                $0.storyID == storyID &&
                $0.chapterNumber == chapterNumber &&
                $0.userID == userID
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// The most-recently-touched in-progress row for this story (any chapter).
    /// Used by `StoryAboutView` to relabel its CTA.
    func mostRecentActive(
        for storyID: String,
        userID: String?,
        in context: ModelContext
    ) -> StoryPathProgress? {
        let descriptor = FetchDescriptor<StoryPathProgress>(
            predicate: #Predicate {
                $0.storyID == storyID &&
                $0.userID == userID &&
                $0.completedAt == nil
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// All in-progress rows for the user, most-recently updated first.
    /// Powers the "Continue Your Story" section on the Learn tab.
    func activeInProgress(
        for userID: String?,
        in context: ModelContext,
        limit: Int = 20
    ) -> [StoryPathProgress] {
        var descriptor = FetchDescriptor<StoryPathProgress>(
            predicate: #Predicate {
                $0.userID == userID &&
                $0.completedAt == nil
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Return the existing in-progress row for this (story, chapter, user), or a
    /// fresh **un-inserted** instance. The fresh instance is only persisted once
    /// `save(_:allowInsert:)` is called with meaningful progress, so merely
    /// opening the path and backing out leaves no resume clutter.
    @discardableResult
    func resumeOrCreate(
        storyID: String,
        storyTitle: String,
        chapterNumber: Int,
        sceneIndex: Int?,
        userID: String?,
        in context: ModelContext
    ) -> StoryPathProgress {
        if let existing = progress(for: storyID, chapterNumber: chapterNumber, userID: userID, in: context),
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

    /// Mark all 5 stages complete and set `completedAt`.
    func complete(_ progress: StoryPathProgress, in context: ModelContext) {
        if progress.modelContext == nil {
            context.insert(progress)
        }
        progress.stageCompletion = [true, true, true, true, true]
        progress.currentStage = 5
        progress.completedAt = Date()
        progress.updatedAt = Date()
        progress.isSynced = false
        try? context.save()
    }

    /// Discards an in-progress row so a new fresh path can begin on the same
    /// chapter. Used by the "Start Over" menu item.
    func discard(_ progress: StoryPathProgress, in context: ModelContext) {
        guard progress.modelContext != nil else { return }
        context.delete(progress)
        try? context.save()
    }
}
