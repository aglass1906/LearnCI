import SwiftUI

struct YouTubeStudyPanel: View {
    let trackLabel: String?
    let activeCue: YouTubeCaptionCue?
    let activeCueTranslation: String?
    let cues: [YouTubeCaptionCue]
    let activeCueID: String?
    let translationState: YouTubeStudyLoadState
    let translationForCue: (YouTubeCaptionCue) -> String?
    let onSeek: (Double) -> Void
    let onWordTap: (String, YouTubeCaptionCue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let activeCue {
                activeCueCard(activeCue)
            } else {
                ContentUnavailableView(
                    "Waiting for captions",
                    systemImage: "captions.bubble",
                    description: Text("Start the video or scrub to a captioned section to begin studying.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            transcriptSection
        }
    }

    private func activeCueCard(_ cue: YouTubeCaptionCue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Current Subtitle", systemImage: "text.bubble")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    onSeek(cue.startTime)
                } label: {
                    Label("Jump", systemImage: "gobackward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            CueWordText(cue: cue, onWordTap: onWordTap)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .tint(.primary)

            Group {
                if let activeCueTranslation, !activeCueTranslation.isEmpty {
                    Text(activeCueTranslation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if translationState == .loading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Translating current subtitle…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Translation will appear here as study mode caches it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transcript")
                    .font(.headline)

                Spacer()

                if let trackLabel {
                    Text(trackLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(cues) { cue in
                            transcriptRow(cue)
                                .id(cue.id)
                        }
                    }
                }
                .frame(minHeight: 260)
                .onChange(of: activeCueID) { newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private func transcriptRow(_ cue: YouTubeCaptionCue) -> some View {
        let isActive = cue.id == activeCueID

        return Button {
            onSeek(cue.startTime)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(cue.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                if let translation = translationForCue(cue), !translation.isEmpty {
                    Text(translation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(isActive ? Color.blue.opacity(0.12) : Color(UIColor.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? Color.blue.opacity(0.35) : Color.clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

}

private struct CueWordText: View {
    let cue: YouTubeCaptionCue
    let onWordTap: (String, YouTubeCaptionCue) -> Void

    var body: some View {
        Text(attributedText)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "x-learnci-word",
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let word = components.queryItems?.first(where: { $0.name == "word" })?.value else {
                    return .systemAction
                }
                onWordTap(word, cue)
                return .handled
            })
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(cue.text)
        attributed.foregroundColor = .primary

        let nsText = cue.text as NSString
        let regex = try? NSRegularExpression(pattern: "\\p{L}[\\p{L}\\p{Mn}'’-]*", options: [])
        let matches = regex?.matches(in: cue.text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []

        for match in matches {
            guard let range = Range(match.range, in: cue.text),
                  let lowerBound = AttributedString.Index(range.lowerBound, within: attributed),
                  let upperBound = AttributedString.Index(range.upperBound, within: attributed) else {
                continue
            }

            let word = String(cue.text[range])
            var components = URLComponents()
            components.scheme = "x-learnci-word"
            components.queryItems = [URLQueryItem(name: "word", value: word)]

            if let url = components.url {
                attributed[lowerBound..<upperBound].link = url
                attributed[lowerBound..<upperBound].underlineStyle = .single
            }
        }

        return attributed
    }
}
