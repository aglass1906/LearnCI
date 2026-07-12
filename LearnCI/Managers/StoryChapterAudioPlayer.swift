import Foundation
import SwiftUI

/// Plays a story chapter's body scene clips in order and can loop the whole
/// chapter N times (podcast style). Wraps `AudioManager` streaming and reuses
/// `StoryReaderDataAdapter` for clip discovery + URL resolution (cached local
/// file when present, otherwise the resolved remote storage URL), matching the
/// behaviour of the production readers.
///
/// `chapterTime` is a continuous timeline across scenes (clip.startOffset +
/// in-clip position), so it lines up with `StoryChapter.bodyWordTimingsForLanguage`
/// for synchronized highlighting.
@Observable
@MainActor
final class StoryChapterAudioPlayer {
    private let audioManager: AudioManager

    private(set) var clips: [StorySceneAudioClip] = []
    private var storyID: UUID = UUID()
    private var storyUpdatedAt: Date?

    private(set) var currentClipIndex: Int = 0
    private(set) var isPlaying: Bool = false
    private(set) var chapterTime: Double = 0
    private(set) var chapterDuration: Double = 0

    /// Number of full-chapter loops requested (1 = play once).
    private(set) var totalLoops: Int = 1
    /// Number of full-chapter loops completed so far.
    private(set) var completedLoops: Int = 0

    /// Fires each time a full chapter loop finishes (including the last).
    var onLoopCompleted: ((_ completed: Int, _ total: Int) -> Void)?
    /// Fires once, after the final requested loop completes.
    var onFinished: (() -> Void)?

    private var clockTimer: Timer?

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
    }

    var hasAudio: Bool { !clips.isEmpty }

    /// Image for the scene currently being narrated (falls back to the first
    /// clip's image). Used to show the right visual while listening.
    var currentImageURL: URL? {
        if clips.indices.contains(currentClipIndex) {
            return clips[currentClipIndex].imageURL
        }
        return clips.first?.imageURL
    }

    /// Resolve the chapter's body scene clips. `chapterIndex` is the index into
    /// `story.chapters`, not the chapter number.
    func configure(story: Story, chapterIndex: Int) {
        let adapter = StoryReaderDataAdapter(story: story)
        clips = adapter.audioClips(forChapter: chapterIndex)
        storyID = story.id
        storyUpdatedAt = story.updatedAt
        chapterDuration = clips.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    /// Configure for a single scene (Study Mode chunk). The clip's timeline is
    /// normalized to start at 0 so it lines up with the scene's own word
    /// timings.
    func configureScene(story: Story, chapterIndex: Int, sceneIndex: Int) {
        let adapter = StoryReaderDataAdapter(story: story)
        if let clip = adapter.audioClips(forChapter: chapterIndex).first(where: { $0.sceneIndex == sceneIndex }) {
            clips = [
                StorySceneAudioClip(
                    id: clip.id,
                    chapterIndex: clip.chapterIndex,
                    sceneIndex: clip.sceneIndex,
                    sceneOrdinal: clip.sceneOrdinal,
                    urlString: clip.urlString,
                    duration: clip.duration,
                    startOffset: 0,
                    title: clip.title,
                    caption: clip.caption,
                    imageURL: clip.imageURL
                )
            ]
        } else {
            clips = []
        }
        storyID = story.id
        storyUpdatedAt = story.updatedAt
        chapterDuration = clips.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    /// Begin playback, looping the chapter `totalLoops` times. `fromLoop` lets a
    /// resumed session skip loops already completed.
    func start(totalLoops: Int, fromLoop: Int = 0) {
        self.totalLoops = max(1, totalLoops)
        self.completedLoops = min(max(0, fromLoop), self.totalLoops)
        guard hasAudio, completedLoops < self.totalLoops else {
            onFinished?()
            return
        }
        playClip(at: 0, autoplay: true)
        startClock()
    }

    func play() {
        guard hasAudio else { return }
        if audioManager.streamPlayer == nil {
            playClip(at: currentClipIndex, autoplay: true)
        } else {
            audioManager.playStream()
        }
        isPlaying = true
        startClock()
    }

    func pause() {
        audioManager.pauseStream()
        isPlaying = false
    }

    func stop() {
        clockTimer?.invalidate()
        clockTimer = nil
        audioManager.onStreamFinished = nil
        audioManager.stopStream()
        isPlaying = false
    }

    // MARK: - Internals

    private func playClip(at index: Int, autoplay: Bool) {
        guard clips.indices.contains(index) else { return }
        currentClipIndex = index
        let clip = clips[index]

        // Single-item streaming — the chapter sequence + looping is driven here.
        let url = StoryReaderDataAdapter.cachedAudioURL(
            storyID: storyID,
            clip: clip,
            storyUpdatedAt: storyUpdatedAt
        ) ?? StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString)

        guard let url else {
            // Skip clips we can't resolve rather than stalling the chapter.
            advanceAfterClip()
            return
        }

        audioManager.streamAudio(url: url)
        audioManager.onStreamFinished = { [weak self] in
            Task { @MainActor in self?.advanceAfterClip() }
        }
        if autoplay {
            audioManager.playStream()
            isPlaying = true
        }
        prefetch(index + 1)
    }

    private func advanceAfterClip() {
        let next = currentClipIndex + 1
        if clips.indices.contains(next) {
            playClip(at: next, autoplay: true)
            return
        }

        // Reached the end of the chapter — one full loop done.
        completedLoops += 1
        onLoopCompleted?(completedLoops, totalLoops)

        if completedLoops < totalLoops {
            playClip(at: 0, autoplay: true)
        } else {
            stop()
            onFinished?()
        }
    }

    private func startClock() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let base = self.clips.indices.contains(self.currentClipIndex)
                    ? self.clips[self.currentClipIndex].startOffset
                    : 0
                self.chapterTime = base + self.audioManager.streamCurrentTime
            }
        }
    }

    private func prefetch(_ index: Int) {
        guard clips.indices.contains(index) else { return }
        let clip = clips[index]
        if StoryReaderDataAdapter.cachedAudioURL(storyID: storyID, clip: clip, storyUpdatedAt: storyUpdatedAt) != nil {
            return
        }
        let sid = storyID
        let updatedAt = storyUpdatedAt
        Task {
            _ = await StoryReaderDataAdapter.downloadAndCacheAudioIfNeeded(
                storyID: sid,
                clip: clip,
                storyUpdatedAt: updatedAt
            )
        }
    }
}
