import SwiftUI

/// Renders a block of text with individual words highlighted in sync with audio playback.
/// Pass the current stream time in seconds and word-level timings; the active word
/// highlights blue while past words dim, creating a read-along effect.
struct TimedTextView: View {
    let segment: StorySegmentTiming
    let currentTime: Double /// The current stream time in seconds
    var includesPadding: Bool = true
    @Environment(\.storyWordLookupAction) private var lookupAction

    var body: some View {
        Text(attributedParagraph)
            .multilineTextAlignment(.leading)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .padding(includesPadding ? 16 : 0)
            .animation(.easeInOut(duration: 0.1), value: currentTime)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "x-learnci-word",
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let word = components.queryItems?.first(where: { $0.name == "word" })?.value else {
                    return .systemAction
                }

                let queryItems = components.queryItems ?? []
                let time = queryItems.first(where: { $0.name == "t" })?.value.flatMap(Double.init)
                let endTime = queryItems.first(where: { $0.name == "e" })?.value.flatMap(Double.init)
                lookupAction?(
                    StoryWordLookupRequest(
                        word: word,
                        time: time,
                        endTime: endTime,
                        context: sentenceContaining(word: word, in: segment.text),
                        wordIndex: queryItems.first(where: { $0.name == "i" })?.value.flatMap(Int.init),
                        sourceText: segment.text
                    )
                )
                return .handled
            })
    }

    // Computes the text styles based on the current time
    private var attributedParagraph: AttributedString {
        var attrString = AttributedString(segment.text)
        attrString.font = .body
        attrString.foregroundColor = .primary.opacity(0.8)

        guard !segment.timings.isEmpty else {
            return attrString
        }

        // Use a regular expression to find word boundaries in the text,
        // then match them chronologically to the WordTiming objects.
        let textNSString = segment.text as NSString
        let regex = try? NSRegularExpression(pattern: "\\p{L}+", options: [])
        let matches = regex?.matches(in: segment.text, options: [], range: NSRange(location: 0, length: textNSString.length)) ?? []

        for (i, match) in matches.enumerated() {
            guard i < segment.timings.count else { break }
            let timing = segment.timings[i]

            if let swiftRange = Range(match.range, in: segment.text),
               let lowerBound = AttributedString.Index(swiftRange.lowerBound, within: attrString),
               let upperBound = AttributedString.Index(swiftRange.upperBound, within: attrString) {

                let attrRange = lowerBound..<upperBound
                let word = String(segment.text[swiftRange])
                let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
                attrString[attrRange].link = URL(string: "x-learnci-word://?word=\(encodedWord)&i=\(i)&t=\(timing.start)&e=\(timing.end)")

                // 150ms slack for smoother word-to-word transitions
                let slack: Double = 0.150
                if currentTime >= (timing.start - slack) && currentTime <= (timing.end + slack) {
                    attrString[attrRange].foregroundColor = .blue
                    attrString[attrRange].font = .body.bold()
                } else if currentTime > (timing.end + slack) {
                    attrString[attrRange].foregroundColor = .primary.opacity(0.4)
                }
            }
        }

        return attrString
    }

    private func sentenceContaining(word: String, in text: String) -> String? {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
        return sentences
            .first(where: { $0.localizedCaseInsensitiveContains(word) })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    TimedTextView(
        segment: StorySegmentTiming(
            speaker: "NARRATOR",
            text: "This is a test of the synchronized text view.",
            startTime: 0,
            endTime: 5.0,
            timings: [
                WordTiming(word: "This", start: 0, end: 1.0),
                WordTiming(word: "is", start: 1.0, end: 2.0),
                WordTiming(word: "a", start: 2.0, end: 3.0),
                WordTiming(word: "test", start: 3.0, end: 4.0),
            ]
        ),
        currentTime: 1.5
    )
}
