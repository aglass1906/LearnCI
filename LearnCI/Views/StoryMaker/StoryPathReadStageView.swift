import SwiftUI

/// Stage 1 — Read for ~5 minutes. Shows the chapter/scene image, a play/pause
/// narration control (word-synced highlighting), and the tappable body text so
/// the learner gets combined seeing + hearing input.
struct StoryPathReadStageView: View {
    @Bindable var vm: StoryPathSessionViewModel

    @Environment(AudioManager.self) private var audioManager

    @State private var timer: Timer?
    @State private var chapterPlayer: StoryChapterAudioPlayer?
    @State private var audioStarted: Bool = false
    @State private var fallbackImageURL: URL?

    private var chapter: StoryChapter? { vm.chapter }
    private var languageCode: String { vm.story.targetLanguageCode }
    private var bodyText: String {
        chapter?.bodyTextForLanguage(languageCode) ?? vm.story.targetLanguageText
    }
    private var wordTimings: [WordTiming] {
        chapter?.bodyWordTimingsForLanguage(languageCode) ?? vm.story.wordTimings
    }
    private var hasChapterAudio: Bool { chapterPlayer?.hasAudio ?? false }
    private var isPlaying: Bool { chapterPlayer?.isPlaying ?? false }

    private var heroImageURL: URL? {
        chapterPlayer?.currentImageURL ?? fallbackImageURL
    }
    private var highlightTime: Double? {
        audioStarted ? chapterPlayer?.chapterTime : nil
    }
    private var primaryTitle: String {
        vm.readTargetReached ? "Continue to Listen Loop" : "I'm Ready"
    }
    private var bottomCaption: String {
        vm.readTargetReached
            ? "Nice work — you've hit \(vm.targetReadMinutes) min of reading."
            : "Read at your own pace. Tap a word to look it up."
    }

    var body: some View {
        VStack(spacing: 0) {
            timerHeader
            if hasChapterAudio { audioBar }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroImage
                    if let plotSummary = chapter?.plotSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !plotSummary.isEmpty {
                        Text(plotSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                caption: bottomCaption,
                confirmMessage: "You'll move to the listening loop. You can come back with the ← button."
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

    @ViewBuilder
    private var audioBar: some View {
        HStack(spacing: 14) {
            Button(action: togglePlay) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(isPlaying ? "Listening along…" : (audioStarted ? "Paused" : "Play the narration"))
                    .font(.subheadline.weight(.medium))
                ProgressView(value: progressFraction)
                    .tint(.accentColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.6))
    }

    @ViewBuilder
    private var heroImage: some View {
        if let url = heroImageURL {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay(ProgressView())
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var progressFraction: Double {
        guard let player = chapterPlayer, player.chapterDuration > 0 else { return 0 }
        return min(1, max(0, player.chapterTime / player.chapterDuration))
    }

    // MARK: - Actions

    private func setupPlayer() {
        guard chapterPlayer == nil else { return }
        let player = StoryChapterAudioPlayer(audioManager: audioManager)
        player.configure(story: vm.story, chapterIndex: vm.chapterArrayIndex)
        player.onFinished = {
            // Leave audioStarted true so the highlight rests at the end.
        }
        chapterPlayer = player
        fallbackImageURL = StoryReaderDataAdapter(story: vm.story)
            .chapterImageURL(forChapterAt: vm.chapterArrayIndex)
    }

    private func togglePlay() {
        guard let player = chapterPlayer, player.hasAudio else { return }
        if player.isPlaying {
            player.pause()
        } else {
            if audioManager.streamPlayer == nil || player.completedLoops >= player.totalLoops {
                player.start(totalLoops: 1)
            } else {
                player.play()
            }
            audioStarted = true
        }
    }

    private func onContinue() {
        stopAudio()
        vm.advanceToNextStage()
    }

    private func stopAudio() {
        chapterPlayer?.stop()
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
