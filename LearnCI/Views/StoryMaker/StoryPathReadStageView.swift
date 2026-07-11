import SwiftUI

/// Stage 1 — Read for ~5 minutes. Renders the chapter body with tappable
/// words + optional listen-along audio for combined seeing+hearing input.
struct StoryPathReadStageView: View {
    @Bindable var vm: StoryPathSessionViewModel

    @Environment(AudioManager.self) private var audioManager

    @State private var timer: Timer?
    @State private var listenAlong: Bool = false
    @State private var currentAudioTime: Double? = nil
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
        // Prefer first scene audio; fall back to chapter intro audio.
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
            timerHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let plotSummary = chapter?.plotSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !plotSummary.isEmpty {
                        Text(plotSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }
                    TappableStoryText(
                        text: bodyText,
                        font: .system(size: 20, weight: .regular, design: .serif),
                        lineSpacing: 8,
                        timings: wordTimings,
                        currentTime: listenAlong ? currentAudioTime : nil,
                        activeColor: .accentColor,
                        pastOpacity: 0.5
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            StoryPathBottomBar(
                primaryTitle: vm.readTargetReached ? "Continue to Listen Loop" : "I'm Ready",
                primaryEnabled: true,
                primaryAction: onContinue,
                secondaryTitle: audioSecondaryTitle,
                secondaryAction: chapterAudioURL == nil ? nil : toggleListenAlong,
                caption: vm.readTargetReached
                    ? "Nice work — you've hit \(vm.targetReadMinutes) min of reading."
                    : "Read at your own pace. Tap a word to look it up."
            )
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer(); stopAudio() }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var timerHeader: some View {
        HStack {
            Label(formatElapsed(vm.readElapsedSeconds), systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(vm.readTargetReached ? .green : .primary)
            Spacer()
            Text("Target \(vm.targetReadMinutes) min")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var audioSecondaryTitle: String {
        chapterAudioURL == nil ? "" : (listenAlong ? "Stop Audio" : "Listen Along")
    }

    // MARK: - Actions

    private func onContinue() {
        stopAudio()
        vm.advanceToNextStage()
    }

    private func toggleListenAlong() {
        listenAlong.toggle()
        if listenAlong {
            guard let url = chapterAudioURL else { return }
            audioManager.streamRepeatCount = 1
            audioManager.streamAudio(url: url)
            audioManager.onStreamFinished = {
                listenAlong = false
                currentAudioTime = nil
            }
            startAudioClockObserver()
        } else {
            stopAudio()
        }
    }

    private func startAudioClockObserver() {
        timeObserver?.invalidate()
        timeObserver = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                currentAudioTime = audioManager.streamCurrentTime
            }
        }
    }

    private func stopAudio() {
        timeObserver?.invalidate()
        timeObserver = nil
        audioManager.stopStream()
        currentAudioTime = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                vm.tickReadTimer(by: 1)
                if vm.readElapsedSeconds % 30 == 0 { vm.persist() }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        vm.persist()
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
