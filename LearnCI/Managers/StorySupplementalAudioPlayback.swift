import AVFoundation
import Foundation

/// Shared playback for reading-matter pages and chapter intros.
/// Uses generated audio through `AudioManager` when available, otherwise TTS.
@MainActor
@Observable
final class StorySupplementalAudioPlayback {
    enum Content: Equatable {
        case none
        case readingMatter(pageIndex: Int, pageID: String)
        case chapterIntro(chapterIndex: Int)
    }

    private(set) var activeContent: Content = .none
    private(set) var isPlaying = false
    private(set) var isUsingGeneratedAudio = false
    private(set) var isLoading = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var activeWordIndex: Int?

    var onFinished: (() -> Void)?

    private var story: Story?
    private var adapter: StoryReaderDataAdapter?
    private var audioManager: AudioManager?
    private var languageCode = "en"
    private var preferNative = false

    private var readingMatterPage: ReadingMatterPage?
    private var readingMatterPageIndex: Int?
    private var chapter: StoryChapter?
    private var chapterIndex: Int?

    private var synthesizer = AVSpeechSynthesizer()
    private var speechFinishTask: DispatchWorkItem?
    private var playbackRate: Float = 1.0

    var isActive: Bool {
        activeContent != .none
    }

    func bind(story: Story, audioManager: AudioManager = .shared) {
        self.story = story
        self.adapter = StoryReaderDataAdapter(story: story)
        self.audioManager = audioManager
        self.languageCode = story.languageRaw
    }

    func prepareReadingMatter(pageIndex: Int, page: ReadingMatterPage, preferNative: Bool) {
        stop(resetContent: false)
        readingMatterPageIndex = pageIndex
        readingMatterPage = page
        chapter = nil
        chapterIndex = nil
        self.preferNative = preferNative
        activeContent = .readingMatter(pageIndex: pageIndex, pageID: page.id)
        resetTimingState()
    }

    func prepareChapterIntro(chapterIndex: Int, chapter: StoryChapter, preferNative: Bool) {
        stop(resetContent: false)
        self.chapterIndex = chapterIndex
        self.chapter = chapter
        readingMatterPage = nil
        readingMatterPageIndex = nil
        self.preferNative = preferNative
        activeContent = .chapterIntro(chapterIndex: chapterIndex)
        resetTimingState()
    }

    var wordTimings: [WordTiming] {
        switch activeContent {
        case .readingMatter:
            return readingMatterPage?.wordTimingsForPlayback(preferNative: preferNative) ?? []
        case .chapterIntro:
            return chapter?.chapterIntroWordTimings ?? []
        case .none:
            return []
        }
    }

    var canSeek: Bool {
        isUsingGeneratedAudio && duration > 0
    }

    func hasGeneratedAudio(preferNative: Bool) -> Bool {
        switch activeContent {
        case .readingMatter:
            return readingMatterPage?.hasGeneratedAudio(preferNative: preferNative) ?? false
        case .chapterIntro:
            guard let chapter else { return false }
            return !(chapter.chapterIntroAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        case .none:
            return false
        }
    }

    func syncPlayback(shouldPlay: Bool, speakableText: String?) {
        if shouldPlay {
            if isUsingGeneratedAudio, let audioManager, audioManager.streamPlayer != nil {
                if !audioManager.isStreaming {
                    audioManager.playStream()
                    isPlaying = true
                }
                return
            }
            if synthesizer.isPaused {
                synthesizer.continueSpeaking()
                isPlaying = true
                return
            }
            if synthesizer.isSpeaking {
                return
            }
            if hasGeneratedAudio(preferNative: preferNative) || speakableText != nil {
                togglePlay(speakableText: speakableText)
            }
        } else {
            pause()
        }
    }

    func togglePlay(speakableText: String?) {
        if hasGeneratedAudio(preferNative: preferNative) {
            toggleGeneratedAudio()
            return
        }

        guard let speakableText, !speakableText.isEmpty else { return }

        if isPlaying {
            pauseSpeech()
            isPlaying = false
            return
        }

        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPlaying = true
            return
        }

        startSpeech(text: speakableText)
    }

    func pause() {
        isPlaying = false
        if isUsingGeneratedAudio {
            audioManager?.pauseStream()
        } else {
            pauseSpeech()
        }
    }

    func stop(resetContent: Bool = true) {
        speechFinishTask?.cancel()
        speechFinishTask = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        if isUsingGeneratedAudio {
            audioManager?.onStreamFinished = nil
            audioManager?.stopStream()
        }

        isPlaying = false
        isUsingGeneratedAudio = false
        isLoading = false
        resetTimingState()

        if resetContent {
            activeContent = .none
            readingMatterPage = nil
            readingMatterPageIndex = nil
            chapter = nil
            chapterIndex = nil
        }
    }

    func seek(to value: Double) {
        guard isUsingGeneratedAudio else { return }
        audioManager?.seekStream(to: value)
        currentTime = value
        updateWordHighlight(at: value)
        audioManager?.updateStreamNowPlayingInfo()
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        audioManager?.setStreamRate(rate)
        if isUsingGeneratedAudio {
            audioManager?.updateStreamNowPlayingInfo()
        }
    }

    func syncStreamState() {
        if isUsingGeneratedAudio, let audioManager {
            if audioManager.streamFinished {
                audioManager.streamFinished = false
                isPlaying = false
                let handler = onFinished
                onFinished = nil
                handler?()
                return
            }

            guard audioManager.streamPlayer != nil else { return }

            currentTime = audioManager.streamCurrentTime
            let streamDuration = audioManager.streamDuration
            if streamDuration > 0 {
                duration = max(duration, streamDuration)
            }
            isPlaying = audioManager.isStreaming
            updateWordHighlight(at: currentTime)
            return
        }

        if synthesizer.isSpeaking, !synthesizer.isPaused {
            isPlaying = true
        }
    }

    // MARK: - Generated audio

    private func toggleGeneratedAudio() {
        guard let audioManager else { return }

        if isUsingGeneratedAudio, audioManager.streamPlayer != nil {
            if audioManager.isStreaming {
                audioManager.pauseStream()
                isPlaying = false
            } else {
                audioManager.playStream()
                isPlaying = true
            }
            audioManager.updateStreamNowPlayingInfo()
            return
        }

        isPlaying = true
        startGeneratedAudio(startAt: 0)
    }

    private func startGeneratedAudio(startAt: Double) {
        guard let story, let adapter, let audioManager else { return }
        guard let clip = supplementalClip(adapter: adapter) else { return }

        stopSpeechOnly()
        isUsingGeneratedAudio = true
        activeWordIndex = nil
        isLoading = true

        Task {
            let playbackURL: URL?
            if let cached = adapter.cachedAudioURL(for: clip) {
                playbackURL = cached
            } else {
                playbackURL = await StoryReaderDataAdapter.downloadAndCacheAudioIfNeeded(
                    storyID: story.id,
                    clip: clip,
                    storyUpdatedAt: story.updatedAt
                ) ?? StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString)
            }

            await MainActor.run {
                isLoading = false
                guard let playbackURL else {
                    isPlaying = false
                    return
                }

                audioManager.streamAudio(url: playbackURL, startAt: startAt)
                audioManager.setStreamRate(playbackRate)
                audioManager.onStreamFinished = { [weak self] in
                    guard let self else { return }
                    self.isPlaying = false
                    self.audioManager?.streamFinished = false
                    let handler = self.onFinished
                    self.onFinished = nil
                    handler?()
                }
                let timedDuration = wordTimings.last?.end
                duration = max(timedDuration ?? 0, audioManager.streamDuration, 1)
                currentTime = startAt
                updateWordHighlight(at: startAt)
                audioManager.updateStreamNowPlayingInfo(
                    title: clip.title,
                    artist: story.title,
                    artworkImage: nil
                )
                if isPlaying {
                    audioManager.playStream()
                }
            }
        }
    }

    private func supplementalClip(adapter: StoryReaderDataAdapter) -> StorySceneAudioClip? {
        switch activeContent {
        case .readingMatter:
            guard let page = readingMatterPage, let pageIndex = readingMatterPageIndex else { return nil }
            return adapter.readingMatterAudioClip(
                pageIndex: pageIndex,
                page: page,
                preferNative: preferNative
            )
        case .chapterIntro:
            guard let chapterIndex else { return nil }
            return adapter.chapterIntroAudioClip(forChapterAt: chapterIndex)
        case .none:
            return nil
        }
    }

    // MARK: - TTS

    private func startSpeech(text: String) {
        stopSpeechOnly()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: speechLanguageCode)
        utterance.rate = 0.5
        synthesizer.speak(utterance)
        isPlaying = true

        let finishTask = DispatchWorkItem { [weak self] in
            guard let self else { return }
            isPlaying = false
            onFinished?()
        }
        speechFinishTask = finishTask
        DispatchQueue.main.asyncAfter(
            deadline: .now() + estimatedSpeechDuration(for: text),
            execute: finishTask
        )
    }

    private func pauseSpeech() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    private func stopSpeechOnly() {
        speechFinishTask?.cancel()
        speechFinishTask = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private var speechLanguageCode: String {
        if preferNative { return "en-US" }
        switch languageCode {
        case "es": return "es-MX"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "fr": return "fr-FR"
        case "vi": return "vi-VN"
        case "en": return "en-US"
        default: return languageCode
        }
    }

    private func estimatedSpeechDuration(for text: String) -> TimeInterval {
        max(2.0, Double(text.count) * 0.06)
    }

    private func resetTimingState() {
        currentTime = 0
        duration = 0
        activeWordIndex = nil
    }

    private func updateWordHighlight(at time: Double) {
        let timings = wordTimings
        guard !timings.isEmpty else {
            activeWordIndex = nil
            return
        }
        activeWordIndex = timings.firstIndex(where: { time >= $0.start && time <= $0.end })
    }
}
