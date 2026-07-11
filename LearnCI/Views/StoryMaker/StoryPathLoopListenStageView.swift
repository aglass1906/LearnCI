import SwiftUI

/// Stage 2 — loop the chapter audio N times (default 4) like a podcast.
/// The transcript is hidden by default so the ear takes the lead.
struct StoryPathLoopListenStageView: View {
    @Bindable var vm: StoryPathSessionViewModel

    @Environment(AudioManager.self) private var audioManager

    @State private var transcriptVisible: Bool = false
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserver: Timer?

    private var chapter: StoryChapter? { vm.chapter }
    private var languageCode: String { vm.story.targetLanguageCode }
    private var bodyText: String {
        chapter?.bodyTextForLanguage(languageCode) ?? vm.story.targetLanguageText
    }
    private var wordTimings: [WordTiming] {
        chapter?.bodyWordTimingsForLanguage(languageCode) ?? vm.story.wordTimings
    }
    private var chapterAudioURL: URL? {
        if let scene = chapter?.scenes.sorted(by: { $0.sceneIndex < $1.sceneIndex }).first(where: { $0.audioUrlForLanguage(languageCode) != nil }),
           let urlString = scene.audioUrlForLanguage(languageCode),
           let url = URL(string: urlString) {
            return url
        }
        if let urlString = chapter?.chapterIntroAudioUrlForLanguage(languageCode),
           let url = URL(string: urlString) {
            return url
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            loopHeader
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    if transcriptVisible {
                        TappableStoryText(
                            text: bodyText,
                            font: .system(size: 18, design: .serif),
                            lineSpacing: 6,
                            timings: wordTimings,
                            currentTime: currentTime,
                            activeColor: .accentColor,
                            pastOpacity: 0.5
                        )
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 16)
            }
            StoryPathBottomBar(
                primaryTitle: canAdvance ? "Continue to Word Lookup" : "Continue",
                primaryEnabled: true,
                primaryAction: onContinue,
                secondaryTitle: transcriptVisible ? "Hide Text" : "Show Text",
                secondaryAction: { transcriptVisible.toggle() },
                caption: canAdvance
                    ? "You've completed \(vm.currentLoopIndex) of \(vm.totalLoops) loops."
                    : "Let your ear lead. Text is hidden by default."
            )
        }
        .onAppear { startPlaybackIfNeeded() }
        .onDisappear { teardown() }
    }

    private var canAdvance: Bool {
        vm.currentLoopIndex >= vm.totalLoops
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var loopHeader: some View {
        HStack {
            Label("Loop \(min(vm.currentLoopIndex + (isPlaying ? 1 : 0), vm.totalLoops)) of \(vm.totalLoops)", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(timeString(currentTime) + " / " + timeString(duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    @ViewBuilder
    private var heroCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 220, height: 220)
                Image(systemName: "headphones")
                    .font(.system(size: 84, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            HStack(spacing: 6) {
                ForEach(0..<vm.totalLoops, id: \.self) { i in
                    Circle()
                        .fill(i < vm.currentLoopIndex ? Color.green : (i == vm.currentLoopIndex && isPlaying ? Color.accentColor : Color(uiColor: .tertiarySystemFill)))
                        .frame(width: 10, height: 10)
                }
            }

            HStack(spacing: 24) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            if chapterAudioURL == nil {
                Text("No audio available for this chapter yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func startPlaybackIfNeeded() {
        guard vm.currentLoopIndex < vm.totalLoops else { return }
        guard let url = chapterAudioURL else { return }
        let remaining = max(1, vm.totalLoops - vm.currentLoopIndex)
        audioManager.streamRepeatCount = remaining
        audioManager.onStreamLoopCompleted = { completed, _ in
            Task { @MainActor in
                vm.recordLoopCompleted()
            }
        }
        audioManager.onStreamFinished = {
            Task { @MainActor in
                isPlaying = false
            }
        }
        audioManager.streamAudio(url: url)
        audioManager.playStream()
        isPlaying = true
        startClock()
    }

    private func togglePlayback() {
        if isPlaying {
            audioManager.pauseStream()
            isPlaying = false
        } else {
            if audioManager.streamPlayer == nil {
                startPlaybackIfNeeded()
            } else {
                audioManager.playStream()
                isPlaying = true
                startClock()
            }
        }
    }

    private func startClock() {
        timeObserver?.invalidate()
        timeObserver = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                currentTime = audioManager.streamCurrentTime
                duration = audioManager.streamDuration
            }
        }
    }

    private func onContinue() {
        teardown()
        vm.advanceToNextStage()
    }

    private func teardown() {
        timeObserver?.invalidate()
        timeObserver = nil
        audioManager.stopStream()
        isPlaying = false
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
