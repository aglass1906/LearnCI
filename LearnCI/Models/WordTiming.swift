import Foundation

/// Represents the precise start and end times for a specific word in an audio file.
/// Used to drive UI highlighting during audio playback.
struct WordTiming: Codable, Equatable {
    let word: String
    let start: Double
    let end: Double
}

extension WordTiming {
    /// Counts spoken words using the same word-boundary rules as `TimedTextView`.
    static func spokenWordCount(in text: String) -> Int {
        let nsText = text as NSString
        let regex = try? NSRegularExpression(pattern: "\\p{L}+", options: [])
        return regex?.numberOfMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        ) ?? 0
    }

    /// Drops leading timings that correspond to a spoken title shown separately from body text.
    static func bodyTimings(
        fullTimings: [WordTiming],
        skippingLeadingSpokenText prefix: String?
    ) -> [WordTiming] {
        guard let prefix = prefix?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prefix.isEmpty else {
            return fullTimings
        }

        let prefixWordCount = spokenWordCount(in: prefix)
        guard prefixWordCount > 0, prefixWordCount < fullTimings.count else {
            return fullTimings
        }

        return Array(fullTimings.dropFirst(prefixWordCount))
    }
}
