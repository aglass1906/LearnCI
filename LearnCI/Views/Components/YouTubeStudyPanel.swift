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

    private enum MergedTranslationState {
        case ready(AttributedString)
        case loading
        case placeholder
    }

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
        let contextCues = cueContext(around: cue)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Subtitle Context", systemImage: "text.bubble")
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

            MergedCueContextText(
                cues: contextCues,
                activeCueID: cue.id,
                onWordTap: onWordTap
            )
                .font(.system(size: 20, weight: .regular, design: .serif))
                .tint(.primary)

            switch mergedTranslationState(for: contextCues, activeCueID: cue.id) {
            case .ready(let mergedTranslation):
                Text(mergedTranslation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Translating subtitle context…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .placeholder:
                Text("Translation will appear here as study mode caches nearby lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func cueContext(around cue: YouTubeCaptionCue) -> [YouTubeCaptionCue] {
        guard let activeIndex = cues.firstIndex(where: { $0.id == cue.id }) else {
            return [cue]
        }

        let lowerBound = max(0, activeIndex - 1)
        let upperBound = min(cues.count - 1, activeIndex + 1)
        return Array(cues[lowerBound...upperBound])
    }

    private func mergedTranslationState(
        for contextCues: [YouTubeCaptionCue],
        activeCueID: String
    ) -> MergedTranslationState {
        let activeCueHasTranslation = contextCues.contains { cue in
            cue.id == activeCueID &&
            !(translationForCue(cue)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ?? true)
        }

        if !activeCueHasTranslation, translationState == .loading {
            return .loading
        }

        var merged = AttributedString()
        var hasAnyTranslation = false

        for (index, cue) in contextCues.enumerated() {
            let translation = translationForCue(cue)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isActive = cue.id == activeCueID
            let hasTranslation = !(translation?.isEmpty ?? true)

            let displayText = hasTranslation ? (translation ?? "") : "..."
            var attributedSegment = AttributedString(displayText)
            attributedSegment.foregroundColor = .secondary
            attributedSegment.font = .system(size: 17, weight: isActive ? .semibold : .regular)
            merged.append(attributedSegment)

            if hasTranslation {
                hasAnyTranslation = true
            }

            if index < contextCues.count - 1 {
                merged.append(AttributedString(" "))
            }
        }

        return hasAnyTranslation ? .ready(merged) : .placeholder
    }

}

private struct MergedCueContextText: View {
    let cues: [YouTubeCaptionCue]
    let activeCueID: String
    let onWordTap: (String, YouTubeCaptionCue) -> Void

    var body: some View {
        Text(attributedText)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "x-learnci-word",
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let word = components.queryItems?.first(where: { $0.name == "word" })?.value,
                      let cueIndexValue = components.queryItems?.first(where: { $0.name == "cueIndex" })?.value,
                      let cueIndex = Int(cueIndexValue),
                      let cue = cues.first(where: { $0.index == cueIndex }) else {
                    return .systemAction
                }
                onWordTap(word, cue)
                return .handled
            })
    }

    private var attributedText: AttributedString {
        var merged = AttributedString()

        for (index, cue) in cues.enumerated() {
            var cueAttributed = AttributedString(cue.text)
            let isActive = cue.id == activeCueID
            cueAttributed.foregroundColor = isActive ? .primary : .secondary
            cueAttributed.font = .system(size: 20, weight: isActive ? .semibold : .regular, design: .serif)

            let nsText = cue.text as NSString
            let regex = try? NSRegularExpression(pattern: "\\p{L}[\\p{L}\\p{Mn}'’-]*", options: [])
            let matches = regex?.matches(in: cue.text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []

            for match in matches {
                guard let range = Range(match.range, in: cue.text),
                      let lowerBound = AttributedString.Index(range.lowerBound, within: cueAttributed),
                      let upperBound = AttributedString.Index(range.upperBound, within: cueAttributed) else {
                    continue
                }

                let word = String(cue.text[range])
                var components = URLComponents()
                components.scheme = "x-learnci-word"
                components.queryItems = [
                    URLQueryItem(name: "word", value: word),
                    URLQueryItem(name: "cueIndex", value: String(cue.index))
                ]

                if let url = components.url {
                    cueAttributed[lowerBound..<upperBound].link = url
                    cueAttributed[lowerBound..<upperBound].underlineStyle = .single
                }
            }

            merged.append(cueAttributed)

            if index < cues.count - 1 {
                merged.append(AttributedString(" "))
            }
        }

        return merged
    }
}
