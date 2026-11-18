import Foundation
import Observation

/// Remembers that audio (a podcast episode or a story's listen queue) is still playing after
/// its screen was left, so the app-level mini player can control and reopen it.
@Observable
@MainActor
final class BackgroundPlaybackSession {
    static let shared = BackgroundPlaybackSession()

    enum Kind: Equatable {
        case podcast
        case story
    }

    struct Context: Equatable {
        let kind: Kind
        let contentID: UUID
        let title: String
        let subtitle: String
    }

    struct Target: Equatable {
        let kind: Kind
        let id: UUID
    }

    private(set) var context: Context?

    private init() {}

    func activate(_ newContext: Context) {
        context = newContext
    }

    func clear() {
        context = nil
    }

    /// True while something is remembered and a stream is still loaded.
    func isShowing(for audioManager: AudioManager) -> Bool {
        context != nil && audioManager.streamPlayer != nil
    }

    /// What is actually playing now. Queue items follow auto-advance, so prefer them over the
    /// context captured when the screen was left.
    func target(currentQueueItem item: CarPlayMediaItem?) -> Target? {
        if let item {
            let parts = item.id.split(separator: ":")
            if parts.count >= 2, let uuid = UUID(uuidString: String(parts[1])) {
                switch parts[0] {
                case "podcast": return Target(kind: .podcast, id: uuid)
                case "story": return Target(kind: .story, id: uuid)
                default: break
                }
            }
        }
        return context.map { Target(kind: $0.kind, id: $0.contentID) }
    }
}
