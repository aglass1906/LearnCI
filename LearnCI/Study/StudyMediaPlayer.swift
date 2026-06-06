import Foundation

@MainActor
protocol StudyMediaPlayer: AnyObject {
    var currentTime: Double { get }
    var duration: Double { get }
    var isPlaying: Bool { get }
    var playbackRate: Float { get }
    func seek(to time: Double)
    func seekAndPlay(from time: Double)
    func play()
    func pause()
    func setPlaybackRate(_ rate: Float)
}

/// Bridges YouTube iframe playback via closures wired from `VideoDetailSheet`.
@MainActor
final class YouTubeStudyMediaPlayer: StudyMediaPlayer {
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying: Bool = false
    var playbackRate: Float = 1.0

    var onSeek: ((Double) -> Void)?
    var onSeekAndPlay: ((Double) -> Void)?
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onSetRate: ((Float) -> Void)?

    func seek(to time: Double) {
        onSeek?(max(0, time))
    }

    func seekAndPlay(from time: Double) {
        onSeekAndPlay?(max(0, time))
    }

    func play() {
        onPlay?()
    }

    func pause() {
        onPause?()
    }

    func setPlaybackRate(_ rate: Float) {
        let clamped = max(0.25, min(rate, 2.0))
        playbackRate = clamped
        onSetRate?(clamped)
    }

    func applySnapshot(currentTime: Double, duration: Double, isPlaying: Bool, playbackRate: Float) {
        self.currentTime = max(0, currentTime)
        self.duration = max(0, duration)
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
    }
}

/// Bridges podcast / generic AVPlayer streaming via `AudioManager`.
@MainActor
final class AVPlayerStudyMediaPlayer: StudyMediaPlayer {
    private weak var audioManager: AudioManager?

    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying: Bool = false
    var playbackRate: Float = 1.0

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
    }

    func seek(to time: Double) {
        audioManager?.seekStream(to: max(0, time))
        currentTime = max(0, time)
    }

    func seekAndPlay(from time: Double) {
        let clamped = max(0, time)
        audioManager?.seekStream(to: clamped)
        audioManager?.setStreamRate(1.0)
        audioManager?.playStream()
        currentTime = clamped
        playbackRate = 1.0
        isPlaying = true
    }

    func play() {
        audioManager?.playStream()
        isPlaying = true
    }

    func pause() {
        audioManager?.pauseStream()
        isPlaying = false
    }

    func setPlaybackRate(_ rate: Float) {
        let clamped = max(0.25, min(rate, 2.0))
        playbackRate = clamped
        audioManager?.setStreamRate(clamped)
    }

    func applySnapshot(currentTime: Double, duration: Double, isPlaying: Bool, playbackRate: Float) {
        self.currentTime = max(0, currentTime)
        self.duration = max(0, duration)
        self.isPlaying = isPlaying
        self.playbackRate = max(0.25, min(playbackRate, 2.0))
    }
}
