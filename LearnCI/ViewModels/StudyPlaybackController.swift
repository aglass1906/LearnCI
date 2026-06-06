import Foundation
import Observation

enum StudyBlockPlaybackMode: Equatable {
    case free
    case blockOnce
    case blockLoop
    case sessionOnce
    case sessionLoop
}

enum StudyPlaybackBoundaryAction: Equatable {
    case none
    case pause
    case loopToStart(Double)
    case advanceToNextBlock
    case loopSession
}

@Observable
@MainActor
final class StudyPlaybackController {
    private(set) var mode: StudyBlockPlaybackMode = .free
    private let endSlack: Double = 0.05
    private let rearmLead: Double = 0.25
    private var boundaryConsumed = false
    private var lastLoopRestartAt: Date?
    private let loopRestartCooldown: TimeInterval = 0.9

    var isBlockPlaybackActive: Bool {
        switch mode {
        case .free: return false
        case .blockOnce, .blockLoop, .sessionOnce, .sessionLoop: return true
        }
    }

    var isSessionPlaybackMode: Bool {
        mode == .sessionOnce || mode == .sessionLoop
    }

    func setMode(_ newMode: StudyBlockPlaybackMode) {
        mode = newMode
    }

    func playBlockOnce() {
        mode = .blockOnce
        resetBoundaryState()
    }

    func playSessionOnce() {
        mode = .sessionOnce
        resetBoundaryState()
    }

    func toggleBlockLoop() -> Bool {
        if mode == .blockLoop {
            mode = .free
            resetBoundaryState()
            return false
        }
        mode = .blockLoop
        resetBoundaryState()
        return true
    }

    func toggleSessionLoop() -> Bool {
        if mode == .sessionLoop {
            mode = .free
            resetBoundaryState()
            return false
        }
        mode = .sessionLoop
        resetBoundaryState()
        return true
    }

    func stopBlockPlayback() {
        mode = .free
        resetBoundaryState()
    }

    func resetBoundaryState() {
        boundaryConsumed = false
        lastLoopRestartAt = nil
    }

    func shouldFallbackLoopRestart(
        at time: Double,
        block: StudyBlock?,
        session: StudySessionDefinition?,
        isPlaying: Bool
    ) -> Bool {
        guard mode == .blockLoop || mode == .sessionLoop, let block else { return false }
        let atPlaybackEnd: Bool
        if mode == .sessionLoop, let session, block.index >= session.endIndex {
            atPlaybackEnd = time >= block.mediaEnd - endSlack
        } else if mode == .blockLoop {
            atPlaybackEnd = time >= block.mediaEnd - endSlack
        } else {
            return false
        }
        guard atPlaybackEnd else { return false }
        if let lastLoopRestartAt, Date().timeIntervalSince(lastLoopRestartAt) < loopRestartCooldown {
            return false
        }
        return !isPlaying || time >= block.mediaEnd
    }

    func noteLoopRestart() {
        lastLoopRestartAt = Date()
        boundaryConsumed = true
    }

    func boundaryAction(
        for time: Double,
        block: StudyBlock?,
        session: StudySessionDefinition?
    ) -> StudyPlaybackBoundaryAction {
        guard isBlockPlaybackActive, let block else {
            resetBoundaryState()
            return .none
        }

        if time <= block.mediaEnd - rearmLead {
            boundaryConsumed = false
        }

        guard !boundaryConsumed else { return .none }
        guard time >= block.mediaEnd - endSlack else { return .none }

        boundaryConsumed = true

        switch mode {
        case .blockOnce:
            mode = .free
            return .pause
        case .blockLoop:
            return .loopToStart(block.mediaStart)
        case .sessionOnce:
            guard let session, session.contains(blockIndex: block.index) else {
                mode = .free
                return .pause
            }
            if block.index < session.endIndex {
                return .advanceToNextBlock
            }
            mode = .free
            return .pause
        case .sessionLoop:
            guard let session, session.contains(blockIndex: block.index) else {
                mode = .free
                return .pause
            }
            if block.index < session.endIndex {
                return .advanceToNextBlock
            }
            return .loopSession
        case .free:
            return .none
        }
    }
}
