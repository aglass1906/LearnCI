import Foundation
import Observation

/// Remembers which podcast episode is still playing after its screen was left,
/// so the app-level mini player can control and reopen it.
@Observable
@MainActor
final class PodcastMiniPlayer {
    static let shared = PodcastMiniPlayer()

    struct Context: Equatable {
        let episodeID: UUID
        let title: String
        let subtitle: String
        let audioURL: URL
    }

    private(set) var context: Context?

    private init() {}

    func activate(_ newContext: Context) {
        context = newContext
    }

    func clear() {
        context = nil
    }

    /// True only while the remembered episode is still the loaded stream.
    func isShowing(for audioManager: AudioManager) -> Bool {
        guard let context, audioManager.streamPlayer != nil else { return false }
        return audioManager.currentStreamURL == context.audioURL
    }
}
