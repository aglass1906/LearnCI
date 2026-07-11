import SwiftUI

/// Stage 2 — loop the whole chapter audio N times (default 4) like a podcast.
/// The transcript is hidden by default so the ear takes the lead.
struct StoryPathLoopListenStageView: View {
    @Bindable var vm: StoryPathSessionViewModel

    @Environment(AudioManager.self) private var audioManager

    @State private var transcriptVisible: Bool = false
    @State private var chapterPlayer: StoryChapterAudioPlayer?
    @State private var listenTimer: Timer?
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
    private var heroImageURL: URL? { chapterPlayer?.currentImageURL ?? fallbackImageURL }

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
                            currentTime: chapterPlayer?.chapterTime,
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
                    : "Let your ear lead. Text is hidden by default.",
                confirmMessage: "You'll move to word lookup. You can come back with the ← button."
            )
        }
        .onAppear {
            setupPlayer()
            startListenClock()
        }
        .onDisappear { teardown() }
    }

    private var canAdvance: Bool {
        vm.currentLoopIndex >= vm.totalLoops
    }

    private var displayLoop: Int {
        min(vm.currentLoopIndex + (isPlaying ? 1 : 0), vm.totalLoops)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var loopHeader: some View {
        HStack {
            Label("Loop \(displayLoop) of \(vm.totalLoops)", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(timeString(chapterPlayer?.chapterTime ?? 0) + " / " + timeString(chapterPlayer?.chapterDuration ?? 0))
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
                if let url = heroImageURL {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay(ProgressView())
                    }
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "headphones")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(10)
                    }
                } else {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 220, height: 220)
                    Image(systemName: "headphones")
                        .font(.system(size: 84, weight: .light))
                        .foregroundStyle(Color.accentColor)
                }
            }

            HStack(spacing: 6) {
                ForEach(0..<max(1, vm.totalLoops), id: \.self) { i in
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
                .disabled(!hasChapterAudio)
            }
            .padding(.top, 4)

            if !hasChapterAudio {
                Text("No audio available for this chapter yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func setupPlayer() {
        guard chapterPlayer == nil else { return }
        let player = StoryChapterAudioPlayer(audioManager: audioManager)
        player.configure(story: vm.story, chapterIndex: vm.chapterArrayIndex)
        player.onLoopCompleted = { _, _ in
            vm.recordLoopCompleted()
        }
        chapterPlayer = player
        fallbackImageURL = StoryReaderDataAdapter(story: vm.story)
            .chapterImageURL(forChapterAt: vm.chapterArrayIndex)
        // Auto-start remaining loops when arriving mid-way through.
        if hasChapterAudio, vm.currentLoopIndex < vm.totalLoops {
            player.start(totalLoops: vm.totalLoops, fromLoop: vm.currentLoopIndex)
        }
    }

    private func togglePlayback() {
        guard let player = chapterPlayer else { return }
        if player.isPlaying {
            player.pause()
        } else if vm.currentLoopIndex < vm.totalLoops {
            if player.completedLoops >= player.totalLoops || audioManager.streamPlayer == nil {
                player.start(totalLoops: vm.totalLoops, fromLoop: vm.currentLoopIndex)
            } else {
                player.play()
            }
        }
    }

    private func startListenClock() {
        listenTimer?.invalidate()
        listenTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if chapterPlayer?.isPlaying == true {
                    vm.listenElapsedSeconds += 1
                }
            }
        }
    }

    private func onContinue() {
        teardown()
        vm.advanceToNextStage()
    }

    private func teardown() {
        listenTimer?.invalidate()
        listenTimer = nil
        chapterPlayer?.stop()
        vm.persist()
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
