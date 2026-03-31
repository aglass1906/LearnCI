import SwiftUI

/// A component that renders a single StorySegmentTiming,
/// highlighting words dynamically based on the current playback time in seconds.
struct KaraokeTextChunk: View {
    let segment: StorySegmentTiming
    let currentTime: Double /// The current stream time in seconds
    
    // UI Theme Constants
    let baseFontSize: CGFloat = 28
    let highlightFontSize: CGFloat = 32
    
    var body: some View {
        Text(attributedParagraph)
            .multilineTextAlignment(.leading)
            .lineSpacing(12)
            .padding()
            .animation(.easeInOut(duration: 0.1), value: currentTime)
    }
    
    // Computes the text styles based on the current time
    private var attributedParagraph: AttributedString {
        var attrString = AttributedString(segment.text)
        attrString.font = .system(size: baseFontSize, weight: .regular, design: .serif)
        attrString.foregroundColor = .primary.opacity(0.8)
        
        guard !segment.timings.isEmpty else {
            return attrString
        }

        // We use a regular expression to find word boundaries in the text,
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
                
                // Highlight logic: apply slack for smoother transition (e.g. 150ms slack)
                let slack: Double = 0.150
                if currentTime >= (timing.start - slack) && currentTime <= (timing.end + slack) {
                    attrString[attrRange].foregroundColor = .blue
                    attrString[attrRange].font = .system(size: highlightFontSize, weight: .bold, design: .serif)
                } else if currentTime > (timing.end + slack) {
                    // Previously spoken words can have a different opacity if desired
                    attrString[attrRange].foregroundColor = .primary.opacity(0.4)
                }
            }
        }
        
        return attrString
    }
}

#Preview {
    KaraokeTextChunk(
        segment: StorySegmentTiming(
            speaker: "NARRATOR",
            text: "This is a test of the karaoke system.",
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
