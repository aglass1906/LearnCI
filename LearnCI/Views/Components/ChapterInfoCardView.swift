import SwiftUI
import AVFoundation
import Combine

/// Chapter intro content shown before chapter body playback.
/// Play/pause is driven by the shared story footer via [isPlaying].
struct ChapterInfoCardView: View {
    let story: Story
    let chapter: StoryChapter
    let chapterIndex: Int
    let heroImage: UIImage?
    let languageCode: String
    @Binding var selectedLanguage: StorySessionView.DisplayLanguage
    @Binding var isPlaying: Bool
    let onIntroFinished: () -> Void

    @State private var playback = StorySupplementalAudioPlayback()
    @State private var didCompleteIntro = false

    let introTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let horizontalPadding: CGFloat = 16
            let proseWidth = max(1, geo.size.width - horizontalPadding * 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .bottom) {
                        if let img = heroImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 220)
                                .clipped()
                        } else {
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(height: 220)
                        }
                    }
                    .frame(width: proseWidth, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(chapterNumberLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())

                    Text(displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(width: proseWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    introTextView(proseWidth: proseWidth)

                    Text("Characters: NARRATOR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)

                    Color.clear.frame(height: 180)
                }
                .frame(width: proseWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            didCompleteIntro = false
            playback.bind(story: story)
            playback.onFinished = finishIntro
            playback.prepareChapterIntro(
                chapterIndex: chapterIndex,
                chapter: chapter,
                preferNative: selectedLanguage == .native
            )
        }
        .onDisappear {
            didCompleteIntro = true
            playback.stop()
        }
        .onChange(of: selectedLanguage) { _, newValue in
            let wasPlaying = isPlaying
            playback.stop()
            playback.prepareChapterIntro(
                chapterIndex: chapterIndex,
                chapter: chapter,
                preferNative: newValue == .native
            )
            if wasPlaying {
                playback.togglePlay(isPlaying: &isPlaying, speakableText: speakableIntroText)
            }
        }
        .onChange(of: isPlaying) { _, playing in
            playback.syncPlayback(isPlaying: &isPlaying, speakableText: speakableIntroText)
        }
        .onReceive(introTimer) { _ in
            playback.syncStreamState(isPlaying: &isPlaying)
        }
    }

    var hasIntroContent: Bool {
        hasIntroAudio || hasIntroText
    }

    private var hasIntroAudio: Bool {
        guard let path = chapter.chapterIntroAudioUrl else { return false }
        return !path.isEmpty
    }

    private var hasIntroText: Bool {
        !(chapter.chapterIntroText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var chapterNumberLabel: String {
        let chapterLabel: String
        if chapter.isPrologue {
            chapterLabel = "Prologue"
        } else if chapter.isEpilogue {
            chapterLabel = "Epilogue"
        } else {
            chapterLabel = "Chapter \(chapter.chapterNumber)"
        }
        return "Chapter Intro · \(chapterLabel)"
    }

    private var displayTitle: String {
        switch selectedLanguage {
        case .target:
            return chapter.titleTargetLanguage
        case .native:
            let english = chapter.titleEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
            return english.isEmpty ? chapter.titleTargetLanguage : english
        }
    }

    private var displayIntroText: String? {
        let text: String?
        switch selectedLanguage {
        case .target:
            text = chapter.chapterIntroText
        case .native:
            text = chapter.chapterIntroTextEnglish ?? chapter.chapterIntroText
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var speakableIntroText: String? {
        var parts: [String] = []
        if !displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(displayTitle)
        }
        if let intro = displayIntroText {
            parts.append(intro)
        }
        let text = parts.joined(separator: ". ")
        return text.isEmpty ? nil : text
    }

    @ViewBuilder
    private func introTextView(proseWidth: CGFloat) -> some View {
        if let intro = displayIntroText {
            if playback.isUsingGeneratedAudio,
               !playback.wordTimings.isEmpty,
               hasIntroAudio {
                TimedTextView(
                    segment: StorySegmentTiming(
                        speaker: "",
                        text: intro,
                        startTime: 0,
                        endTime: .greatestFiniteMagnitude,
                        timings: playback.wordTimings
                    ),
                    currentTime: playback.currentTime,
                    includesPadding: false
                )
                .frame(width: proseWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                let parts = intro.components(separatedBy: "\n\n")
                if let quote = parts.first {
                    Text(quote)
                        .font(.title3)
                        .italic()
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .frame(width: proseWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: 4),
                            alignment: .leading
                        )
                }
                if parts.count > 1 {
                    Text(parts.dropFirst().joined(separator: "\n\n"))
                        .font(.body)
                        .foregroundStyle(selectedLanguage == .native ? .secondary : .primary)
                        .frame(width: proseWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func finishIntro() {
        guard !didCompleteIntro else { return }
        didCompleteIntro = true
        playback.stop()
        isPlaying = false
        onIntroFinished()
    }
}
