import Foundation

/// Represents a distinct segment of a story script spoken by a specific character.
struct StorySegmentTiming: Equatable {
    let speaker: String
    let text: String
    let startTime: Double
    let endTime: Double
    let timings: [WordTiming]
}

/// Parses story scripts that follow the [SPEAKER] Text format.
class ScriptParser {
    private static let tagPattern = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]", options: [])

    /// Removes stage directions formatted as (Parentheticals) to allow for cleaner word matching.
    static func stripStageDirections(_ text: String) -> String {
        let regex = try! NSRegularExpression(pattern: "\\s*\\([^)]+\\)", options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        var cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")

        let spaceRegex = try! NSRegularExpression(pattern: "  +", options: [])
        let spaceRange = NSRange(location: 0, length: cleaned.utf16.count)
        cleaned = spaceRegex.stringByReplacingMatches(in: cleaned, options: [], range: spaceRange, withTemplate: " ")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits a chapter script into speaker-labeled segments synced with audio timestamps.
    /// - Parameters:
    ///   - scriptText: The full script text containing [SPEAKER] tags.
    ///   - globalTimings: The word-level timings for the entire chapter.
    /// - Returns: A list of timed segments.
    static func parseSegments(scriptText: String, globalTimings: [WordTiming]) -> [StorySegmentTiming] {
        let trimmedScript = scriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedScript.isEmpty { return [] }

        var rawSegments: [(speaker: String, text: String)] = []
        let nsString = scriptText as NSString
        let matches = tagPattern.matches(in: scriptText, options: [], range: NSRange(location: 0, length: nsString.length))

        if matches.isEmpty {
            // No tags, treat the entire text as Narrator
            rawSegments.append((speaker: "NARRATOR", text: trimmedScript))
        } else {
            // Check for intro text before the first speaker tag
            if matches[0].range.location > 0 {
                let intro = nsString.substring(with: NSRange(location: 0, length: matches[0].range.location)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !intro.isEmpty {
                    rawSegments.append((speaker: "NARRATOR", text: intro))
                }
            }

            for (index, match) in matches.enumerated() {
                let speakerRange = match.range(at: 1)
                let rawTag = nsString.substring(with: speakerRange)
                let speaker = rawTag.replacingOccurrences(of: " ", with: "_").uppercased()

                let startOfText = match.range.location + match.range.length
                let nextStart = (index + 1 < matches.count) ? matches[index + 1].range.location : nsString.length

                let text = nsString.substring(with: NSRange(location: startOfText, length: nextStart - startOfText)).trimmingCharacters(in: .whitespacesAndNewlines)

                if !text.isEmpty {
                    // Merge consecutive tags for the same speaker
                    if let last = rawSegments.last, last.speaker == speaker {
                        let lastSegment = rawSegments.removeLast()
                        rawSegments.append((speaker: speaker, text: "\(lastSegment.text) \(text)"))
                    } else {
                        rawSegments.append((speaker: speaker, text: text))
                    }
                }
            }
        }

        // Map global word timings to segments based on word count
        var results: [StorySegmentTiming] = []
        var timingIndex = 0

        for (index, segment) in rawSegments.enumerated() {
            let stripped = stripStageDirections(segment.text)
            if stripped.isEmpty { continue }

            // Extract alphanumeric words only for accurate matching with timings
            let words = stripped.components(separatedBy: .whitespacesAndNewlines)
                .map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
                .filter { !$0.isEmpty }

            var segmentTimings: [WordTiming] = []
            var matchedCount = 0

            while timingIndex < globalTimings.count && matchedCount < words.count {
                let t = globalTimings[timingIndex]
                let cleanWord = t.word.lowercased().filter { $0.isLetter || $0.isNumber }
                if !cleanWord.isEmpty {
                    matchedCount += 1
                }
                segmentTimings.append(t)
                timingIndex += 1
            }

            // Ensure the last segment absorbs any trailing silence or end-of-chapter timings
            if index == rawSegments.count - 1 && timingIndex < globalTimings.count {
                segmentTimings.append(contentsOf: globalTimings[timingIndex...])
                timingIndex = globalTimings.count
            }

            let startTime = segmentTimings.first?.start ?? 0.0
            let endTime = segmentTimings.last?.end ?? startTime

            results.add(StorySegmentTiming(
                speaker: segment.speaker,
                text: segment.text,
                startTime: startTime,
                endTime: endTime,
                timings: segmentTimings
            ))
        }

        return results
    }
}

private extension Array {
    mutating func add(_ element: Element) {
        self.append(element)
    }
}
