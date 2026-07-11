import Foundation
import SwiftData
import SwiftUI

/// Coordinator for the 5-stage Story Guided Learning Path.
///
/// This is deliberately a sibling to `GameSessionViewModel` — the card-focused
/// state on that VM (currentCardIndex, isFlipped, deck) doesn't fit read/loop/
/// lookup/shadow/plan stages, and shoehorning would obscure both.
@Observable
@MainActor
final class StoryPathSessionViewModel {
    enum Stage: Int, CaseIterable {
        case read = 1
        case loopListen = 2
        case lookup = 3
        case shadow = 4
        case planNext = 5

        var label: String {
            switch self {
            case .read: return "Read"
            case .loopListen: return "Listen"
            case .lookup: return "Look Up"
            case .shadow: return "Shadow"
            case .planNext: return "Plan Next"
            }
        }

        var systemImage: String {
            switch self {
            case .read: return "book.fill"
            case .loopListen: return "headphones"
            case .lookup: return "star.text.square.fill"
            case .shadow: return "mic.fill"
            case .planNext: return "calendar"
            }
        }
    }

    // MARK: - Inputs / persistence

    let story: Story
    let chapterNumber: Int
    private(set) var progress: StoryPathProgress
    private unowned let context: ModelContext
    private unowned let progressStore: StoryPathProgressStore

    // MARK: - Config

    var targetReadMinutes: Int = 5
    var totalLoops: Int = 4
    var shadowLineCount: Int = 2

    // MARK: - Live state

    var currentStage: Stage
    var isSessionActive: Bool = true

    // Stage 1
    var readElapsedSeconds: Int = 0
    var readTargetReached: Bool = false

    // Stage 2
    var currentLoopIndex: Int = 0

    // Stage 3
    var wordsMarkedThisSession: [UUID] = []

    // Stage 4
    var shadowRecordedLineIDs: Set<String> = []

    // Stage 5 — draft config for the next-day plan
    var planNextChapter: Int
    var planTargetMinutes: Int = 10
    var planWordCount: Int = 5
    var planNotificationEnabled: Bool = false
    var planNotificationTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date().addingTimeInterval(86_400)) ?? Date().addingTimeInterval(86_400)

    // MARK: - Derived

    var chapter: StoryChapter? {
        story.chapters.first(where: { $0.chapterNumber == chapterNumber })
            ?? story.chapters.first
    }

    var nextChapterOptions: [StoryChapter] {
        story.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
    }

    var stageCompletion: [Bool] { progress.stageCompletion }

    var overallProgress: Double {
        let completed = stageCompletion.filter { $0 }.count
        return Double(completed) / Double(Stage.allCases.count)
    }

    // MARK: - Init

    init(
        story: Story,
        chapterNumber: Int?,
        userID: String?,
        context: ModelContext,
        progressStore: StoryPathProgressStore
    ) {
        self.story = story
        self.context = context
        self.progressStore = progressStore

        let effectiveChapterNumber = chapterNumber
            ?? story.chapters.first?.chapterNumber
            ?? 1
        self.chapterNumber = effectiveChapterNumber

        let record = progressStore.resumeOrCreate(
            storyID: story.id.uuidString,
            storyTitle: story.title,
            chapterNumber: effectiveChapterNumber,
            sceneIndex: nil,
            userID: userID,
            in: context
        )
        self.progress = record
        self.currentStage = Stage(rawValue: record.currentStage) ?? .read
        self.readElapsedSeconds = record.readMinutesAccumulated * 60
        self.currentLoopIndex = record.loopsCompleted
        self.wordsMarkedThisSession = record.wordsMarkedInSession.compactMap(UUID.init(uuidString:))
        self.shadowRecordedLineIDs = Set(record.shadowLineIDsRecorded)

        // Default plan chapter = current + 1, capped to last chapter's number.
        let chapters = story.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
        let last = chapters.last?.chapterNumber ?? effectiveChapterNumber
        self.planNextChapter = min(effectiveChapterNumber + 1, last)
    }

    // MARK: - Persistence

    func persist() {
        progress.currentStage = currentStage.rawValue
        progress.readMinutesAccumulated = max(1, readElapsedSeconds / 60)
        progress.loopsCompleted = currentLoopIndex
        progress.wordsMarkedInSession = wordsMarkedThisSession.map(\.uuidString)
        progress.shadowLineIDsRecorded = Array(shadowRecordedLineIDs)
        progressStore.save(progress, in: context)
    }

    func markStageComplete(_ stage: Stage) {
        var flags = progress.stageCompletion
        flags[stage.rawValue - 1] = true
        progress.stageCompletion = flags
        persist()
    }

    func advance(to stage: Stage) {
        currentStage = stage
        persist()
    }

    func advanceToNextStage() {
        if let next = Stage(rawValue: currentStage.rawValue + 1) {
            markStageComplete(currentStage)
            advance(to: next)
        } else {
            complete()
        }
    }

    func complete() {
        markStageComplete(currentStage)
        progressStore.complete(progress, in: context)
        isSessionActive = false
    }

    // MARK: - Stage helpers

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

    var chapterTitleDisplay: String {
        chapter?.titleFor(story.targetLanguageCode) ?? "Chapter \(chapterNumber)"
    }
}
