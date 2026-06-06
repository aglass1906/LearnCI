import Foundation

enum PodcastFeedTranscriptError: LocalizedError {
    case invalidURL
    case unsupportedFormat
    case emptyTranscript
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The podcast transcript URL is invalid."
        case .unsupportedFormat:
            return "This podcast transcript format is not supported yet."
        case .emptyTranscript:
            return "The podcast transcript did not contain any timed lines."
        case .downloadFailed:
            return "Could not download the podcast transcript."
        }
    }
}

enum PodcastFeedTranscriptParser {
    struct TranscriptLink: Equatable {
        let url: String
        let type: String
        let language: String?
    }

    static func selectPreferredTranscript(
        from links: [TranscriptLink],
        preferredLanguageCode: String
    ) -> TranscriptLink? {
        guard !links.isEmpty else { return nil }

        let preferredPrefix = String(preferredLanguageCode.prefix(2)).lowercased()
        let timedLinks = links.filter { !isPlainTextOnly($0.type) }
        let candidates = timedLinks.isEmpty ? links : timedLinks

        let typePriority: [String: Int] = [
            "text/vtt": 0,
            "application/vtt": 0,
            "text/srt": 1,
            "application/srt": 1,
            "application/json": 2,
            "application/x-json": 2,
            "text/plain": 3
        ]

        return candidates.sorted { lhs, rhs in
            let lhsLang = languageMatchScore(lhs.language, preferredPrefix: preferredPrefix)
            let rhsLang = languageMatchScore(rhs.language, preferredPrefix: preferredPrefix)
            if lhsLang != rhsLang { return lhsLang < rhsLang }

            let lhsType = typePriority[lhs.type.lowercased()] ?? 99
            let rhsType = typePriority[rhs.type.lowercased()] ?? 99
            if lhsType != rhsType { return lhsType < rhsType }

            return lhs.url < rhs.url
        }.first
    }

    static func fetchAndParse(
        urlString: String,
        type: String?,
        fallbackDuration: Double = 0
    ) async throws -> [YouTubeCaptionCue] {
        guard let url = URL(string: urlString) else {
            throw PodcastFeedTranscriptError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        let resolvedType = resolvedMIMEType(
            declaredType: type,
            response: response,
            url: url
        )
        return try parse(data: data, type: resolvedType, fallbackDuration: fallbackDuration)
    }

    static func parse(
        data: Data,
        type: String,
        fallbackDuration: Double = 0
    ) throws -> [YouTubeCaptionCue] {
        let normalizedType = type.lowercased()
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)

        if normalizedType.contains("json") {
            return try parseJSON(data: data)
        }

        guard let text else {
            throw PodcastFeedTranscriptError.unsupportedFormat
        }

        if normalizedType.contains("vtt") || text.hasPrefix("WEBVTT") {
            return parseVTT(text)
        }

        if normalizedType.contains("srt") || looksLikeSRT(text) {
            return parseSRT(text)
        }

        if normalizedType.contains("xml") {
            return try YouTubeCaptionService.parseCues(fromXMLData: data)
        }

        throw PodcastFeedTranscriptError.unsupportedFormat
    }

    static func resolvedMIMEType(
        declaredType: String?,
        response: URLResponse?,
        url: URL
    ) -> String {
        if let declaredType, !declaredType.isEmpty {
            return declaredType.lowercased()
        }
        if let mime = response?.mimeType?.lowercased(), !mime.isEmpty, mime != "application/octet-stream" {
            return mime
        }
        switch url.pathExtension.lowercased() {
        case "vtt": return "text/vtt"
        case "srt": return "text/srt"
        case "json": return "application/json"
        case "xml": return "application/xml"
        default: return "application/octet-stream"
        }
    }

    static func parseVTT(_ text: String) -> [YouTubeCaptionCue] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var cues: [YouTubeCaptionCue] = []
        var index = 0
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                guard parts.count == 2,
                      let start = parseTimestamp(parts[0]),
                      let end = parseTimestamp(parts[1]) else {
                    lineIndex += 1
                    continue
                }

                var textLines: [String] = []
                lineIndex += 1
                while lineIndex < lines.count {
                    let next = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    if next.isEmpty || next.contains("-->") { break }
                    if next.hasPrefix("WEBVTT") || next.hasPrefix("NOTE") {
                        lineIndex += 1
                        continue
                    }
                    let cleaned = stripVTTMarkup(next)
                    if !cleaned.isEmpty {
                        textLines.append(cleaned)
                    }
                    lineIndex += 1
                }

                if let cueText = StudySubtitleText.mergedLines(textLines, separator: "\n"), !cueText.isEmpty {
                    cues.append(
                        YouTubeCaptionCue(
                            index: index,
                            startTime: start,
                            endTime: end,
                            text: cueText
                        )
                    )
                    index += 1
                }
                continue
            }
            lineIndex += 1
        }

        return cues
    }

    static func parseSRT(_ text: String) -> [YouTubeCaptionCue] {
        var cues: [YouTubeCaptionCue] = []
        var index = 0

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 2 else { continue }

            var timingLineIndex = 0
            if Int(lines[0].trimmingCharacters(in: .whitespacesAndNewlines)) != nil,
               lines.indices.contains(1) {
                timingLineIndex = 1
            }

            guard lines.indices.contains(timingLineIndex),
                  lines[timingLineIndex].contains("-->") else { continue }

            let timingParts = lines[timingLineIndex].components(separatedBy: "-->")
            guard timingParts.count == 2,
                  let start = parseTimestamp(timingParts[0]),
                  let end = parseTimestamp(timingParts[1]) else { continue }

            let textLines = lines[(timingLineIndex + 1)...]
                .map { StudySubtitleText.normalizeLine($0) }
                .filter { !$0.isEmpty }
            guard !textLines.isEmpty else { continue }

            let cueText = StudySubtitleText.mergedLines(textLines, separator: "\n") ?? ""
            guard !cueText.isEmpty else { continue }

            cues.append(
                YouTubeCaptionCue(
                    index: index,
                    startTime: start,
                    endTime: end,
                    text: cueText
                )
            )
            index += 1
        }

        return cues
    }

    static func parseJSON(data: Data) throws -> [YouTubeCaptionCue] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let root = object as? [String: Any] {
            if let segments = root["segments"] as? [[String: Any]] {
                return cuesFromSegments(segments)
            }
            if let transcript = root["transcript"] as? [[String: Any]] {
                return cuesFromSegments(transcript)
            }
            if let cues = root["cues"] as? [[String: Any]] {
                return cuesFromSegments(cues)
            }
            if let words = root["words"] as? [[String: Any]] {
                return cuesFromWords(words)
            }
        } else if let segments = object as? [[String: Any]] {
            return cuesFromSegments(segments)
        }

        throw PodcastFeedTranscriptError.unsupportedFormat
    }

    private static func cuesFromSegments(_ segments: [[String: Any]]) -> [YouTubeCaptionCue] {
        var cues: [YouTubeCaptionCue] = []
        for (index, segment) in segments.enumerated() {
            let text = (segment["body"] as? String)
                ?? (segment["text"] as? String)
                ?? (segment["caption"] as? String)
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let start = doubleValue(segment["startTime"])
                ?? doubleValue(segment["start"])
                ?? doubleValue(segment["begin"])
                ?? 0
            let end = doubleValue(segment["endTime"])
                ?? doubleValue(segment["end"])
                ?? doubleValue(segment["finish"])
                ?? (start + 1.5)

            cues.append(
                YouTubeCaptionCue(
                    index: index,
                    startTime: start,
                    endTime: end,
                    text: text
                )
            )
        }
        return cues
    }

    private static func cuesFromWords(_ words: [[String: Any]]) -> [YouTubeCaptionCue] {
        let timings: [WordTiming] = words.compactMap { item in
            guard let word = item["word"] as? String ?? item["text"] as? String else { return nil }
            let start = doubleValue(item["start"]) ?? doubleValue(item["startTime"]) ?? 0
            let end = doubleValue(item["end"]) ?? doubleValue(item["endTime"]) ?? (start + 0.25)
            return WordTiming(word: word, start: start, end: end)
        }

        let sentences = WhisperTranscriptProvider.groupIntoSentences(timings)
        return sentences.enumerated().map { index, sentence in
            YouTubeCaptionCue(
                index: index,
                startTime: sentence.start,
                endTime: sentence.end,
                text: sentence.text
            )
        }
    }

    private static func parseTimestamp(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
            .last?
            .replacingOccurrences(of: ",", with: ".") ?? ""

        if value.contains(":") {
            let parts = value.split(separator: ":").map(String.init)
            guard !parts.isEmpty else { return nil }

            if parts.count == 3 {
                guard let hours = Double(parts[0]),
                      let minutes = Double(parts[1]),
                      let seconds = Double(parts[2]) else { return nil }
                return hours * 3600 + minutes * 60 + seconds
            }

            if parts.count == 2 {
                guard let minutes = Double(parts[0]),
                      let seconds = Double(parts[1]) else { return nil }
                return minutes * 60 + seconds
            }
        }

        return Double(value)
    }

    private static func stripVTTMarkup(_ line: String) -> String {
        line
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeSRT(_ text: String) -> Bool {
        text.range(of: #"\d+\s*\n\d{2}:\d{2}:\d{2},\d{3}\s*-->"#, options: .regularExpression) != nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }

    private static func isPlainTextOnly(_ type: String) -> Bool {
        let normalized = type.lowercased()
        return normalized == "text/plain" || normalized == "text/html"
    }

    private static func languageMatchScore(_ language: String?, preferredPrefix: String) -> Int {
        guard let language, !language.isEmpty else { return 1 }
        let normalized = language.lowercased()
        if normalized.hasPrefix(preferredPrefix) { return 0 }
        return 2
    }
}
