import SwiftUI

/// Callbacks the host screen supplies. Anything left nil is hidden or no-op.
struct UnifiedPlayerActions {
    var onPlayPause: () -> Void = {}
    var onSkip: (TimeInterval) -> Void = { _ in }
    var onPreviousChapter: () -> Void = {}
    var onNextChapter: () -> Void = {}
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onSelectChapter: (PlaybackChapter) -> Void = { _ in }
    var onSleepTimer: (() -> Void)? = nil
    var onCarPlay: (() -> Void)? = nil
    var onTranscript: (() -> Void)? = nil
    var onMore: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
}

/// The full-screen player layout shared by stories, audiobooks and podcasts:
/// artwork, status line, scrubber, transport, utility row, chapter navigator.
struct UnifiedPlayerView<Artwork: View>: View {
    @Bindable var state: PlaybackState
    var backgroundImage: Image? = nil
    var actions: UnifiedPlayerActions
    @ViewBuilder var artwork: () -> Artwork

    @State private var showsChapters = false

    var body: some View {
        ZStack {
            PlayerBackground(image: backgroundImage)

            VStack(spacing: 20) {
                topBar

                artwork()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: PlayerTheme.artworkCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                    .padding(.horizontal, 20)

                PlayerStatusLine(
                    title: state.title,
                    subtitle: state.subtitle,
                    fractionComplete: state.duration > 0 ? state.fractionComplete : nil,
                    timeRemaining: state.duration > 0 ? state.timeRemaining : nil,
                    chapterLabel: state.chapterLabel,
                    onTapChapter: state.chapters.count > 1 ? { showsChapters = true } : nil
                )
                .padding(.horizontal, 20)

                PlayerScrubber(
                    position: state.position,
                    duration: state.duration,
                    chapters: state.chapters,
                    isEnabled: state.duration > 0,
                    onSeek: actions.onSeek
                )
                .padding(.horizontal, 24)

                PlayerTransportControls(
                    isPlaying: state.isPlaying,
                    isBuffering: state.isBuffering,
                    canGoPrevious: state.canGoPrevious,
                    canGoNext: state.canGoNext,
                    onPrevious: actions.onPreviousChapter,
                    onSkipBackward: { actions.onSkip(-15) },
                    onPlayPause: actions.onPlayPause,
                    onSkipForward: { actions.onSkip(15) },
                    onNext: actions.onNextChapter
                )
                .padding(.horizontal, 12)

                PlayerSecondaryRow(
                    rate: $state.rate,
                    onSleepTimer: actions.onSleepTimer,
                    onCarPlay: actions.onCarPlay,
                    onChapters: state.chapters.count > 1 ? { showsChapters = true } : nil,
                    onTranscript: actions.onTranscript,
                    onMore: actions.onMore
                )
                .padding(.horizontal, 12)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsChapters) {
            ChapterNavigatorSheet(
                chapters: state.chapters,
                currentIndex: state.currentChapterIndex,
                currentProgress: state.currentChapterProgress,
                isPlaying: state.isPlaying,
                onSelect: actions.onSelectChapter
            )
        }
    }

    @ViewBuilder
    private var topBar: some View {
        if let onDismiss = actions.onDismiss {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(PlayerTheme.iconTint)
                        .frame(minWidth: PlayerTheme.minTapTarget, minHeight: PlayerTheme.minTapTarget)
                }
                .accessibilityLabel("Close player")
                Spacer()
            }
            .padding(.horizontal, 8)
        }
    }
}

#if DEBUG
extension PlaybackState {
    static var preview: PlaybackState {
        let s = PlaybackState()
        s.title = "Part 1: Track 3"
        s.subtitle = "Richard Adams"
        s.duration = 3600
        s.position = 840
        s.chapters = (0..<8).map { i in
            PlaybackChapter(
                id: "c\(i)",
                title: ["The Notice Board", "The Departure", "The Fields", "The Road", "The Stream", "The Down", "The Warren", "Home"][i],
                startTime: Double(i) * 450,
                endTime: Double(i + 1) * 450
            )
        }
        return s
    }
}

#Preview("Unified player") {
    UnifiedPlayerView(state: .preview, actions: UnifiedPlayerActions(onDismiss: {})) {
        LinearGradient(colors: [.orange, .brown], startPoint: .top, endPoint: .bottom)
            .overlay(Text("Cover").font(.largeTitle.bold()).foregroundStyle(.white))
    }
}

#Preview("Chapter navigator") {
    let s = PlaybackState.preview
    return ChapterNavigatorSheet(
        chapters: s.chapters,
        currentIndex: s.currentChapterIndex,
        currentProgress: s.currentChapterProgress,
        isPlaying: true,
        onSelect: { _ in }
    )
}
#endif
