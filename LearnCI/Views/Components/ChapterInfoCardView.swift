import SwiftUI

/// Chapter intro presentation shown before chapter body or dialog playback.
/// Audio is driven externally via `StorySupplementalAudioPlayback`.
struct ChapterInfoCardView: View {
    let chapter: StoryChapter
    let heroImage: UIImage?
    @Binding var selectedLanguage: StorySessionView.DisplayLanguage
    var playbackTime: Double = 0
    var onUserScroll: (() -> Void)? = nil

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
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard abs(value.translation.height) > abs(value.translation.width),
                              abs(value.translation.height) > 12 else { return }
                        onUserScroll?()
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    @ViewBuilder
    private func introTextView(proseWidth: CGFloat) -> some View {
        if let intro = displayIntroText {
            if selectedLanguage == .target,
               let timings = chapter.chapterIntroWordTimings, !timings.isEmpty,
               chapter.chapterIntroAudioUrl != nil {
                TimedTextView(
                    segment: StorySegmentTiming(
                        speaker: "",
                        text: intro,
                        startTime: 0,
                        endTime: .greatestFiniteMagnitude,
                        timings: chapter.chapterIntroBodyWordTimings(
                            preferNative: selectedLanguage == .native
                        )
                    ),
                    currentTime: playbackTime,
                    includesPadding: false
                )
                .frame(width: proseWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                let parts = intro.components(separatedBy: "\n\n")
                if let quote = parts.first {
                    Group {
                        if selectedLanguage == .target {
                            TappableStoryText(
                                text: quote,
                                font: .title3.italic(),
                                lineSpacing: 4,
                                foregroundColor: .secondary
                            )
                        } else {
                            Text(quote)
                                .font(.title3)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                    }
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
                    let body = parts.dropFirst().joined(separator: "\n\n")
                    Group {
                        if selectedLanguage == .target {
                            TappableStoryText(
                                text: body,
                                font: .body,
                                lineSpacing: 6,
                                foregroundColor: .primary
                            )
                        } else {
                            Text(body)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                        .frame(width: proseWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
        }
    }
}

extension StorySupplementalAudioPlayback {
    static func chapterIntroSpeakableText(
        chapter: StoryChapter,
        preferNative: Bool
    ) -> String? {
        let title: String
        let intro: String?

        if preferNative {
            let english = chapter.titleEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
            title = english.isEmpty ? chapter.titleTargetLanguage : english
            intro = chapter.chapterIntroTextEnglish ?? chapter.chapterIntroText
        } else {
            title = chapter.titleTargetLanguage
            intro = chapter.chapterIntroText
        }

        let marker = "\(chapter.spokenChapterReferenceTitle) intro"
        var parts = [title.isEmpty ? marker : "\(marker): \(title)"]
        if let intro {
            let trimmed = intro.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }

        let text = parts.joined(separator: ". ")
        return text.isEmpty ? nil : text
    }
}
