import Foundation
import SwiftData
import SwiftUI

/// Coordinator for Study Mode's guided flow. A story is studied as an ordered
/// sequence of **chunks** (scenes). Each chunk runs a 4-stage guided pass
/// (Read → Listen → Look Up → Shadow), after which the learner can move to the
/// next chunk in-flow or wrap up for the day. The per-story `StoryStudyState`
/// keeps the story in Study Mode until every chunk is done or it's un-studied.
@Observable
@MainActor
final class StoryPathSessionViewModel {
    enum Stage: Int, CaseIterable {
        case read = 1
        case loopListen = 2
        case lookup = 3
        case shadow = 4

        var label: String {
            switch self {
            case .read: return "Read"
            case .loopListen: return "Listen"
            case .lookup: return "Look Up"
            case .shadow: return "Shadow"
            }
        }

        var systemImage: String {
            switch self {
            case .read: return "book.fill"
            case .loopListen: return "headphones"
            case .lookup: return "star.text.square.fill"
            case .shadow: return "mic.fill"
            }
        }
    }

    enum Phase {
        case studying      // working through a chunk's stages
        case chunkComplete // decision: next chunk or wrap up
        case wrapUp        // plan/finish for the session
        case finished      // whole story done
    }

    // MARK: - Inputs

    let story: Story
    let userID: String?
    private let context: ModelContext
    private let store: StoryPathProgressStore
    private let storyChapters: [StoryChapter]

    let chunks: [StoryStudyChunk]
    private(set) var studyState: StoryStudyState
    private(set) var chunkOrdinal: Int
    private(set) var progress: StoryPathProgress

    // MARK: - Config

    var targetReadMinutes: Int = 5
    var totalLoops: Int = 4

    // MARK: - Flow state

    var phase: Phase = .studying
    var currentStage: Stage
    var isSessionActive: Bool = true

    // Per-chunk live state
    var readElapsedSeconds: Int = 0
    var readTargetReached: Bool = false
    var currentLoopIndex: Int = 0
    var wordsMarkedThisSession: [UUID] = []
    var shadowRecordedLineIDs: Set<String> = []
    var listenElapsedSeconds: Int = 0
    private var stageEnteredAt: Date = Date()

    // Wrap-up (reminder) draft
    var remindTomorrow: Bool = false
    var reminderTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date().addingTimeInterval(86_400)) ?? Date().addingTimeInterval(86_400)

    // MARK: - Derived

    private var langCode: String { story.targetLanguageCode }

    var currentChunk: StoryStudyChunk? {
        chunks.indices.contains(chunkOrdinal) ? chunks[chunkOrdinal] : nil
    }
    var isLastChunk: Bool { currentChunk?.isLast ?? true }
    var chunkPositionLabel: String {
        guard let chunk = currentChunk else { return "" }
        return "Scene \(chunk.ordinal + 1) of \(chunk.total)"
    }

    private var chapterForChunk: StoryChapter? {
        guard let chunk = currentChunk, storyChapters.indices.contains(chunk.chapterArrayIndex) else { return nil }
        return storyChapters[chunk.chapterArrayIndex]
    }
    var scene: StoryScene? {
        guard let sceneIndex = currentChunk?.sceneIndex else { return nil }
        return chapterForChunk?.scenes.first { $0.sceneIndex == sceneIndex }
    }
    var chunkChapterArrayIndex: Int { currentChunk?.chapterArrayIndex ?? 0 }
    var chunkSceneIndex: Int { currentChunk?.sceneIndex ?? 0 }

    var chunkText: String {
        let caption = scene?.captionFor(langCode).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return caption.isEmpty ? story.targetLanguageText : caption
    }
    var chunkWordTimings: [WordTiming] {
        scene?.wordTimingsFor(langCode) ?? []
    }
    var chunkTitleDisplay: String {
        let chapterTitle = chapterForChunk?.titleFor(langCode) ?? ""
        let scenePart = "Scene \(chunkSceneIndex + 1)"
        return chapterTitle.isEmpty ? scenePart : "\(scenePart) · \(chapterTitle)"
    }

    var stageCompletion: [Bool] { progress.stageCompletion }

    // MARK: - Init

    init(
        story: Story,
        userID: String?,
        context: ModelContext,
        store: StoryPathProgressStore
    ) {
        self.story = story
        self.userID = userID
        self.context = context
        self.store = store
        self.storyChapters = story.chapters

        let allChunks = StoryStudyChunks.chunks(for: story)
        self.chunks = allChunks

        let state = store.startOrResumeStudy(
            storyID: story.id.uuidString,
            storyTitle: story.title,
            firstChunk: allChunks.first,
            userID: userID,
            in: context
        )
        self.studyState = state

        // Locate the chunk the state points at.
        let ordinal = allChunks.firstIndex(where: {
            $0.chapterNumber == state.currentChapterNumber && $0.sceneIndex == state.currentSceneIndex
        }) ?? min(state.currentOrdinal, max(0, allChunks.count - 1))
        self.chunkOrdinal = allChunks.isEmpty ? 0 : ordinal

        let chunk = allChunks.indices.contains(ordinal) ? allChunks[ordinal] : nil
        let record = store.resumeOrCreate(
            storyID: story.id.uuidString,
            storyTitle: story.title,
            chapterNumber: chunk?.chapterNumber ?? 0,
            sceneIndex: chunk?.sceneIndex,
            userID: userID,
            in: context
        )
        self.progress = record
        self.currentStage = Stage(rawValue: record.currentStage) ?? .read
        self.readElapsedSeconds = record.readMinutesAccumulated * 60
        self.currentLoopIndex = record.loopsCompleted
        self.wordsMarkedThisSession = record.wordsMarkedInSession.compactMap(UUID.init(uuidString:))
        self.shadowRecordedLineIDs = Set(record.shadowLineIDsRecorded)
    }

    // MARK: - Persistence

    private var hasMeaningfulProgress: Bool {
        currentStage != .read
            || readElapsedSeconds >= 20
            || !wordsMarkedThisSession.isEmpty
            || !shadowRecordedLineIDs.isEmpty
            || progress.stageCompletion.contains(true)
    }

    func persist() {
        progress.currentStage = currentStage.rawValue
        progress.readMinutesAccumulated = readElapsedSeconds / 60
        progress.loopsCompleted = currentLoopIndex
        progress.wordsMarkedInSession = wordsMarkedThisSession.map(\.uuidString)
        progress.shadowLineIDsRecorded = Array(shadowRecordedLineIDs)
        store.save(progress, in: context, allowInsert: hasMeaningfulProgress)
    }

    // MARK: - Stage flow (within a chunk)

    func markStageComplete(_ stage: Stage) {
        var flags = progress.stageCompletion
        let wasComplete = flags[stage.rawValue - 1]
        flags[stage.rawValue - 1] = true
        progress.stageCompletion = flags
        if !wasComplete { logActivity(for: stage) }
        persist()
    }

    func advance(to stage: Stage) {
        currentStage = stage
        stageEnteredAt = Date()
        persist()
    }

    func advanceToNextStage() {
        if let next = Stage(rawValue: currentStage.rawValue + 1) {
            markStageComplete(currentStage)
            advance(to: next)
        } else {
            completeChunk()
        }
    }

    var canGoBack: Bool { currentStage != .read }

    func goToPreviousStage() {
        guard let prev = Stage(rawValue: currentStage.rawValue - 1) else { return }
        currentStage = prev
        stageEnteredAt = Date()
        persist()
    }

    // MARK: - Chunk flow (across scenes)

    private func completeChunk() {
        markStageComplete(currentStage)
        store.complete(progress, in: context)
        // Point Study Mode at the next chunk so resuming later lands there.
        if let chunk = currentChunk, !chunk.isLast, chunks.indices.contains(chunkOrdinal + 1) {
            store.advanceStudy(studyState, to: chunks[chunkOrdinal + 1], in: context)
        }
        phase = .chunkComplete
    }

    /// Continue to the next scene without leaving the guided container.
    func studyNextChunk() {
        guard chunks.indices.contains(chunkOrdinal + 1) else {
            beginWrapUp()
            return
        }
        chunkOrdinal += 1
        loadCurrentChunk()
        phase = .studying
    }

    /// Jump directly to an arbitrary scene (header scene picker). Saves the
    /// current chunk's progress first, then points Study Mode at the chosen
    /// chunk so resuming later lands there.
    func jumpToChunk(at index: Int) {
        guard chunks.indices.contains(index), index != chunkOrdinal else { return }
        persist()
        chunkOrdinal = index
        store.advanceStudy(studyState, to: chunks[index], in: context)
        loadCurrentChunk()
        phase = .studying
    }

    /// Display title for an arbitrary chunk (scene picker rows), using the
    /// story-wide scene number to match `chunkPositionLabel`.
    func titleForChunk(_ chunk: StoryStudyChunk) -> String {
        let chapterTitle = storyChapters.indices.contains(chunk.chapterArrayIndex)
            ? storyChapters[chunk.chapterArrayIndex].titleFor(langCode)
            : ""
        let scenePart = "Scene \(chunk.ordinal + 1)"
        return chapterTitle.isEmpty ? scenePart : "\(scenePart) · \(chapterTitle)"
    }

    /// Ordinals of chunks whose guided pass is fully complete.
    func completedChunkOrdinals() -> Set<Int> {
        var completed: Set<Int> = []
        for (index, chunk) in chunks.enumerated() {
            if let record = store.progress(
                for: story.id.uuidString,
                chapterNumber: chunk.chapterNumber,
                sceneIndex: chunk.sceneIndex,
                userID: userID,
                in: context
            ), record.completedAt != nil {
                completed.insert(index)
            }
        }
        return completed
    }

    private func loadCurrentChunk() {
        // Reset per-chunk live state and pull that chunk's saved progress.
        readElapsedSeconds = 0
        readTargetReached = false
        currentLoopIndex = 0
        wordsMarkedThisSession = []
        shadowRecordedLineIDs = []
        listenElapsedSeconds = 0
        stageEnteredAt = Date()

        let chunk = currentChunk
        let record = store.resumeOrCreate(
            storyID: story.id.uuidString,
            storyTitle: story.title,
            chapterNumber: chunk?.chapterNumber ?? 0,
            sceneIndex: chunk?.sceneIndex,
            userID: userID,
            in: context
        )
        progress = record
        currentStage = Stage(rawValue: record.currentStage) ?? .read
        readElapsedSeconds = record.readMinutesAccumulated * 60
        currentLoopIndex = record.loopsCompleted
        wordsMarkedThisSession = record.wordsMarkedInSession.compactMap(UUID.init(uuidString:))
        shadowRecordedLineIDs = Set(record.shadowLineIDsRecorded)
    }

    func beginWrapUp() {
        phase = .wrapUp
    }

    /// Finish the session for now. Study Mode stays active at the current chunk.
    func finishForToday() {
        persist()
        isSessionActive = false
    }

    /// Finish the whole story — Study Mode ends.
    func finishStory() {
        store.completeStudy(studyState, in: context)
        phase = .finished
        isSessionActive = false
    }

    // MARK: - Activity logging

    private func logActivity(for stage: Stage) {
        let activityType: ActivityType
        let minutes: Int
        switch stage {
        case .read:
            activityType = .reading
            minutes = max(1, readElapsedSeconds / 60)
        case .loopListen:
            activityType = .listening
            minutes = max(1, listenElapsedSeconds / 60)
        case .lookup:
            activityType = .flashcards
            minutes = elapsedMinutesInStage()
        case .shadow:
            activityType = .shadowing
            minutes = elapsedMinutesInStage()
        }

        let activity = UserActivity(
            minutes: minutes,
            activityType: activityType,
            language: story.language,
            userID: userID,
            comment: "Study Mode · \(story.title) · \(chunkPositionLabel)"
        )
        context.insert(activity)
        try? context.save()
    }

    private func elapsedMinutesInStage() -> Int {
        max(1, Int(Date().timeIntervalSince(stageEnteredAt) / 60))
    }

    // MARK: - Per-chunk helpers

    func tickReadTimer(by seconds: Int) {
        readElapsedSeconds += seconds
        if !readTargetReached, readElapsedSeconds >= targetReadMinutes * 60 {
            readTargetReached = true
        }
    }

    func recordWordMarked(_ id: UUID) {
        guard !wordsMarkedThisSession.contains(id) else { return }
        wordsMarkedThisSession.append(id)
        persist()
    }

    func recordLoopCompleted() {
        currentLoopIndex = min(currentLoopIndex + 1, totalLoops)
        persist()
    }

    func recordShadowLineDone(_ lineID: String) {
        shadowRecordedLineIDs.insert(lineID)
        persist()
    }
}
