import SwiftUI

/// Stage 1 — Read for ~5 minutes. Renders the chapter body with tappable
/// words + optional listen-along audio (full chapter, word-synced) for
/// combined seeing+hearing input.
struct StoryPathReadStageView: View {
    @Bindable var vm: StoryPathSessionViewModel

    @Environment(AudioManager.self) private var audioManager

    @State private var timer: Timer?
    @State private var listenAlong: Bool = false
    @State private var chapterPlayer: StoryChapterAudioPlayer?

    private var chapter: StoryChapter? { vm.chapter }
    private var languageCode: String { vm.story.targetLanguageCode }
    private var bodyText: String {
        chapter?.bodyTextForLanguage(languageCode) ?? vm.story.targetLanguageText
    }
    private var wordTimings: [WordTiming] {
        chapter?.bodyWordTimingsForLanguage(languageCode) ?? vm.story.wordTimings
    }
    private var hasChapterAudio: Bool { chapterPlayer?.hasAudio ?? false }

    // Hoisted out of `body` with explicit types — ternaries mixing method
    // references / nil otherwise overwhelm the SwiftUI body type-checker.
    private var highlightTime: Double? {
        listenAlong ? chapterPlayer?.chapterTime : nil
    }
    private var primaryTitle: String {
        vm.readTargetReached ? "Continue to Listen Loop" : "I'm Ready"
    }
    private var listenSecondaryTitle: String? {
        guard hasChapterAudio else { return nil }
        return listenAlong ? "Stop Audio" : "Listen Along"
    }
    private var listenSecondaryAction: (() -> Void)? {
        guard hasChapterAudio else { return nil }
        return { toggleListenAlong() }
    }
    private var bottomCaption: String {
        vm.readTargetReached
            ? "Nice work — you've hit \(vm.targetReadMinutes) min of reading."
            : "Read at your own pace. Tap a word to look it up."
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
                        currentTime: highlightTime,
                        activeColor: .accentColor,
                        pastOpacity: 0.5
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            StoryPathBottomBar(
                primaryTitle: primaryTitle,
                primaryEnabled: true,
                primaryAction: onContinue,
                secondaryTitle: listenSecondaryTitle,
                secondaryAction: listenSecondaryAction,
                caption: bottomCaption
            )
        }
        .onAppear {
            setupPlayer()
            startTimer()
        }
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

    // MARK: - Actions

    private func setupPlayer() {
        guard chapterPlayer == nil else { return }
        let player = StoryChapterAudioPlayer(audioManager: audioManager)
        player.configure(story: vm.story, chapterIndex: vm.chapterArrayIndex)
        player.onFinished = {
            listenAlong = false
        }
        chapterPlayer = player
    }

    private func onContinue() {
        stopAudio()
        vm.advanceToNextStage()
    }

    private func toggleListenAlong() {
        listenAlong.toggle()
        if listenAlong {
            chapterPlayer?.start(totalLoops: 1)
        } else {
            chapterPlayer?.stop()
        }
    }

    private func stopAudio() {
        chapterPlayer?.stop()
        listenAlong = false
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
