import Foundation
import Observation

@Observable
@MainActor
final class StudySessionViewModel {
    let source: any StudyBlockSource
    let playbackController = StudyPlaybackController()

    private(set) var blocks: [StudyBlock]
    private(set) var currentBlockIndex: Int = 0
    private(set) var sessionDefinition: StudySessionDefinition?
    private(set) var completedBlockIndices: Set<Int> = []
    private var loopRestartTask: Task<Void, Never>?
    private let loopEndPauseDuration: Duration = .milliseconds(650)

    init(source: any StudyBlockSource) {
        self.source = source
        self.blocks = source.blocks
        syncCurrentBlockToPlaybackTime()
    }

    var resource: StudyResourceRef { source.resource }

    var mediaPlayer: any StudyMediaPlayer { source.mediaPlayer }

    var currentBlock: StudyBlock? {
        guard blocks.indices.contains(currentBlockIndex) else { return nil }
        return blocks[currentBlockIndex]
    }

    var sessionBlocks: [StudyBlock] {
        guard let sessionDefinition else { return blocks }
        return blocks.filter { sessionDefinition.contains(blockIndex: $0.index) }
    }

    var canGoPrevious: Bool {
        let minIndex = sessionDefinition?.startIndex ?? 0
        return currentBlockIndex > minIndex
    }

    var canGoNext: Bool {
        let maxIndex = sessionDefinition?.endIndex ?? (blocks.count - 1)
        return currentBlockIndex < maxIndex
    }

    var isLooping: Bool {
        playbackController.mode == .blockLoop || playbackController.mode == .sessionLoop
    }

    var isInDefinedSession: Bool {
        sessionDefinition != nil
    }

    var isBlockPlaying: Bool {
        playbackController.isBlockPlaybackActive
            && (mediaPlayer.isPlaying || loopRestartTask != nil)
    }

    var blockPositionLabel: String {
        let linesLabel = currentBlock.map { "\($0.captionLineCount) line\($0.captionLineCount == 1 ? "" : "s")" } ?? ""
        let position: String
        if let sessionDefinition {
            let sessionIndex = currentBlockIndex - sessionDefinition.startIndex + 1
            position = "Block \(sessionIndex) of \(sessionDefinition.blockCount)"
        } else {
            position = "Block \(currentBlockIndex + 1) of \(blocks.count)"
        }
        return linesLabel.isEmpty ? position : "\(position) · \(linesLabel)"
    }

    func rebuildBlocks(_ newBlocks: [StudyBlock], anchorTime: Double? = nil) {
        let preservedIndex = currentBlockIndex
        blocks = newBlocks
        guard !blocks.isEmpty else {
            currentBlockIndex = 0
            return
        }

        if playbackController.isBlockPlaybackActive {
            if playbackController.isSessionPlaybackMode, let sessionDefinition {
                currentBlockIndex = min(
                    max(sessionDefinition.startIndex, preservedIndex),
                    sessionDefinition.endIndex
                )
            } else {
                currentBlockIndex = min(preservedIndex, blocks.count - 1)
            }
            return
        }

        let time = anchorTime ?? mediaPlayer.currentTime
        if let matched = blocks.last(where: { $0.contains(time: time) }) {
            currentBlockIndex = matched.index
        } else {
            currentBlockIndex = min(preservedIndex, blocks.count - 1)
        }
    }

    func startSession(_ definition: StudySessionDefinition) {
        sessionDefinition = definition
        currentBlockIndex = definition.startIndex
        completedBlockIndices = []
        goToBlock(at: definition.startIndex, autoPlay: false)
    }

    func clearSession() {
        sessionDefinition = nil
        completedBlockIndices = []
    }

    func goToPreviousBlock(autoPlay: Bool = false) {
        guard canGoPrevious else { return }
        goToBlock(at: currentBlockIndex - 1, autoPlay: autoPlay)
    }

    func goToNextBlock(autoPlay: Bool = false) {
        guard canGoNext else { return }
        markCurrentBlockCompletedIfNeeded()
        goToBlock(at: currentBlockIndex + 1, autoPlay: autoPlay)
    }

    func goToBlock(at index: Int, autoPlay: Bool = false) {
        guard blocks.indices.contains(index) else { return }
        if let sessionDefinition, !sessionDefinition.contains(blockIndex: index) { return }

        cancelPendingLoopRestart()
        playbackController.stopBlockPlayback()
        currentBlockIndex = index
        guard let block = currentBlock else { return }

        if autoPlay {
            playCurrentBlockOnce()
        } else {
            mediaPlayer.pause()
            mediaPlayer.seek(to: block.mediaStart)
        }
    }

    func playCurrentBlockOnce() {
        guard let block = currentBlock else { return }
        if sessionDefinition != nil {
            playbackController.playSessionOnce()
        } else {
            playbackController.playBlockOnce()
        }
        mediaPlayer.setPlaybackRate(1.0)
        mediaPlayer.seekAndPlay(from: block.mediaStart)
    }

    func stopBlockPlayback() {
        cancelPendingLoopRestart()
        playbackController.stopBlockPlayback()
        mediaPlayer.pause()
    }

    func togglePlayStop() {
        if isBlockPlaying {
            stopBlockPlayback()
        } else {
            if isLooping {
                guard let block = currentBlock else { return }
                playbackController.resetBoundaryState()
                mediaPlayer.setPlaybackRate(1.0)
                mediaPlayer.seekAndPlay(from: block.mediaStart)
            } else {
                playCurrentBlockOnce()
            }
        }
    }

    func toggleLoopCurrentBlock() {
        guard let block = currentBlock else { return }
        let enabled: Bool
        if sessionDefinition != nil {
            enabled = playbackController.toggleSessionLoop()
        } else {
            enabled = playbackController.toggleBlockLoop()
        }
        if enabled {
            playbackController.resetBoundaryState()
            mediaPlayer.setPlaybackRate(1.0)
            mediaPlayer.seekAndPlay(from: block.mediaStart)
        } else {
            stopBlockPlayback()
        }
    }

    func handlePlaybackTime(_ time: Double, isPlaying: Bool) {
        syncCurrentBlockIndexIfNeeded(for: time)

        let action = playbackController.boundaryAction(
            for: time,
            block: currentBlock,
            session: sessionDefinition
        )
        switch action {
        case .none:
            if playbackController.shouldFallbackLoopRestart(
                at: time,
                block: currentBlock,
                session: sessionDefinition,
                isPlaying: isPlaying
            ) {
                if playbackController.mode == .sessionLoop {
                    restartSessionLoop()
                } else {
                    restartLoopPlayback()
                }
            }
        case .pause:
            playbackController.stopBlockPlayback()
            mediaPlayer.pause()
        case .loopToStart(let start):
            restartLoopPlayback(from: start)
        case .advanceToNextBlock:
            advanceToNextBlockDuringPlayback(at: time)
        case .loopSession:
            restartSessionLoop()
        }
    }

    private func restartLoopPlayback(from start: Double? = nil) {
        guard let block = currentBlock else { return }
        scheduleLoopRestart(from: start ?? block.mediaStart)
    }

    private func restartSessionLoop() {
        guard let session = sessionDefinition,
              blocks.indices.contains(session.startIndex) else { return }
        let startTime = blocks[session.startIndex].mediaStart
        scheduleLoopRestart(from: startTime) {
            self.currentBlockIndex = session.startIndex
        }
    }

    private func scheduleLoopRestart(from start: Double, beforeRestart: (() -> Void)? = nil) {
        playbackController.noteLoopRestart()
        mediaPlayer.setPlaybackRate(1.0)
        mediaPlayer.pause()

        cancelPendingLoopRestart()
        loopRestartTask = Task { @MainActor in
            try? await Task.sleep(for: loopEndPauseDuration)
            guard !Task.isCancelled, isLooping else { return }
            beforeRestart?()
            mediaPlayer.seekAndPlay(from: start)
        }
    }

    private func cancelPendingLoopRestart() {
        loopRestartTask?.cancel()
        loopRestartTask = nil
    }

    private func advanceToNextBlockDuringPlayback(at time: Double) {
        markCurrentBlockCompletedIfNeeded()
        guard canGoNext else { return }

        let nextIndex = currentBlockIndex + 1
        currentBlockIndex = nextIndex
        playbackController.resetBoundaryState()

        guard let nextBlock = currentBlock else { return }
        if time < nextBlock.mediaStart - 0.05 {
            mediaPlayer.setPlaybackRate(1.0)
            mediaPlayer.seekAndPlay(from: nextBlock.mediaStart)
        }
    }

    func syncCurrentBlockToPlaybackTime() {
        syncCurrentBlockIndexIfNeeded(for: mediaPlayer.currentTime)
    }

    private func syncCurrentBlockIndexIfNeeded(for time: Double) {
        let shouldSyncBlockFromTime = playbackController.mode == .free
            || playbackController.isSessionPlaybackMode
        guard shouldSyncBlockFromTime else { return }

        if let session = sessionDefinition,
           playbackController.isSessionPlaybackMode {
            if let matched = blocks.last(where: {
                session.contains(blockIndex: $0.index) && $0.contains(time: time)
            }) {
                currentBlockIndex = matched.index
            }
            return
        }

        if let matched = blocks.last(where: { $0.contains(time: time) }) {
            currentBlockIndex = matched.index
        }
    }

    private func markCurrentBlockCompletedIfNeeded() {
        completedBlockIndices.insert(currentBlockIndex)
    }

    func blockIndex(for cue: YouTubeCaptionCue) -> Int? {
        if let matched = blocks.first(where: { $0.contains(cueIndex: cue.index) }) {
            return matched.index
        }
        return blocks.first(where: { $0.id == cue.id })?.index
    }
}
