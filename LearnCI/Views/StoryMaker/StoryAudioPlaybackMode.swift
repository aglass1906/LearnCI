import Foundation

/// How story audio playback should behave in [AudioBookReaderView].
enum StoryAudioPlaybackMode: Equatable {
    /// Full audio book reader: chapter quiz, Word Focus, manual start.
    case standard
    /// Hands-free / CarPlay: scene narration only, auto-play, skips quiz and vocab.
    case continuousAudio
}
