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
