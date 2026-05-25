import Foundation

enum YouTubeCaptionServiceError: LocalizedError, Equatable {
    case invalidWatchPage
    case captionsUnavailable
    case trackNotFound
    case invalidTrackURL
    case invalidTranscriptPayload
    case transcriptEmpty
    case unsupportedTranscriptFormat

    var errorDescription: String? {
        switch self {
        case .invalidWatchPage:
            return "Unable to read caption data from this YouTube page."
        case .captionsUnavailable:
            return "No captions are available for this video."
        case .trackNotFound:
            return "A matching caption track could not be found."
        case .invalidTrackURL:
            return "The caption track URL was invalid."
        case .invalidTranscriptPayload:
            return "The transcript payload could not be decoded."
        case .transcriptEmpty:
            return "The transcript did not contain any usable caption lines."
        case .unsupportedTranscriptFormat:
            return "The transcript was returned in an unsupported format."
        }
    }
}

struct YouTubeCaptionTranscript: Sendable {
    let tracks: [YouTubeCaptionTrack]
    let selectedTrack: YouTubeCaptionTrack
    let cues: [YouTubeCaptionCue]
}

actor YouTubeCaptionService {
    private let session: URLSession
    private let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    private let androidUserAgent = "com.google.android.youtube/20.10.38 (Linux; U; Android 14 gzip)"
    private let androidClientName = "3"
    private let androidClientVersion = "20.10.38"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func discoverTracks(videoID: String) async throws -> [YouTubeCaptionTrack] {
        Logger.debug("Discovering caption tracks for video \(videoID)", category: .youtube)
        let html = try await fetchWatchPageHTML(videoID: videoID)
        let tracks: [YouTubeCaptionTrack]

        do {
            let apiKey = try Self.extractInnertubeAPIKey(fromWatchPageHTML: html)
            let playerResponse = try await fetchAndroidPlayerResponse(videoID: videoID, apiKey: apiKey)
            tracks = try Self.parseCaptionTracks(fromPlayerResponse: playerResponse)
            Logger.debug("Discovered caption tracks for video \(videoID) via Android player response", category: .youtube)
        } catch {
            Logger.warning(
                "Android player caption discovery failed for video \(videoID): \(error.localizedDescription). Falling back to watch page parsing.",
                category: .youtube
            )
            tracks = try Self.parseCaptionTracks(fromWatchPageHTML: html)
        }

        guard !tracks.isEmpty else {
            Logger.warning("No caption tracks found for video \(videoID)", category: .youtube)
            throw YouTubeCaptionServiceError.captionsUnavailable
        }
        Logger.info("Found \(tracks.count) caption tracks for video \(videoID)", category: .youtube)
        return Self.sortedTracks(tracks)
    }

    func fetchTranscript(
        videoID: String,
        preferredLanguageCode: String? = nil
    ) async throws -> YouTubeCaptionTranscript {
        let tracks = try await discoverTracks(videoID: videoID)
        guard let selectedTrack = Self.selectPreferredTrack(from: tracks, preferredLanguageCode: preferredLanguageCode) else {
            throw YouTubeCaptionServiceError.trackNotFound
        }
        let cues = try await fetchCues(for: selectedTrack)
        return YouTubeCaptionTranscript(tracks: tracks, selectedTrack: selectedTrack, cues: cues)
    }

    func fetchCues(for track: YouTubeCaptionTrack) async throws -> [YouTubeCaptionCue] {
        guard let urlString = track.url,
              let url = URL(string: urlString) else {
            throw YouTubeCaptionServiceError.invalidTrackURL
        }

        var request = URLRequest(url: url)
        request.setValue(androidUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(androidClientName, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(androidClientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")

        Logger.debug("Fetching caption cues for track \(track.id) from \(url.absoluteString)", category: .youtube)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            Logger.error("Caption cue request failed for track \(track.id)", category: .youtube)
            throw YouTubeCaptionServiceError.invalidTranscriptPayload
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
        Logger.debug(
            "Caption cue response for track \(track.id): status \(httpResponse.statusCode), content-type \(contentType), bytes \(data.count)",
            category: .youtube
        )

        guard !data.isEmpty else {
            Logger.error(
                "Caption cue response was empty for track \(track.id) from \(url.absoluteString)",
                category: .youtube
            )
            throw YouTubeCaptionServiceError.invalidTranscriptPayload
        }

        do {
            let cues = try Self.parseCues(fromJSON3Data: data)
            Logger.debug("Parsed \(cues.count) JSON3 caption cues for track \(track.id)", category: .youtube)
            return cues
        } catch {
            Logger.warning("JSON3 parse failed for track \(track.id): \(error.localizedDescription). Trying XML fallback.", category: .youtube)
            if let xmlCues = try? Self.parseCues(fromXMLData: data), !xmlCues.isEmpty {
                Logger.debug("Parsed \(xmlCues.count) XML caption cues for track \(track.id)", category: .youtube)
                return xmlCues
            }
            let payloadPreview = String(data: data.prefix(160), encoding: .utf8)?
                .replacingOccurrences(of: "\n", with: "\\n") ?? "<non-utf8>"
            Logger.error(
                "Caption parsing failed for track \(track.id): \(error.localizedDescription). Payload preview: \(payloadPreview)",
                category: .youtube
            )
            throw error
        }
    }

    private func fetchWatchPageHTML(videoID: String) async throws -> String {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)&hl=en") else {
            throw YouTubeCaptionServiceError.invalidWatchPage
        }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        Logger.debug("Fetching YouTube watch page for video \(videoID)", category: .youtube)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            Logger.error("Failed to fetch watch page for video \(videoID)", category: .youtube)
            throw YouTubeCaptionServiceError.invalidWatchPage
        }
        return html
    }

    private func fetchAndroidPlayerResponse(videoID: String, apiKey: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false&key=\(apiKey)") else {
            throw YouTubeCaptionServiceError.invalidWatchPage
        }

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": androidClientVersion
                ]
            ],
            "videoId": videoID
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue(androidUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(androidClientName, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(androidClientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")

        Logger.debug("Fetching Android player response for video \(videoID)", category: .youtube)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.error("Failed to fetch Android player response for video \(videoID)", category: .youtube)
            throw YouTubeCaptionServiceError.invalidWatchPage
        }
        return object
    }
}

extension YouTubeCaptionService {
    static func selectPreferredTrack(
        from tracks: [YouTubeCaptionTrack],
        preferredLanguageCode: String?
    ) -> YouTubeCaptionTrack? {
        let sorted = sortedTracks(tracks)
        guard let preferredLanguageCode else {
            return sorted.first
        }

        let normalizedPreference = normalizeLanguageCode(preferredLanguageCode)
        let matches = sorted.filter { track in
            normalizeLanguageCode(track.languageCode) == normalizedPreference
        }

        return matches.first ?? sorted.first
    }

    static func sortedTracks(_ tracks: [YouTubeCaptionTrack]) -> [YouTubeCaptionTrack] {
        tracks.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            if lhs.isAutoGenerated != rhs.isAutoGenerated {
                return !lhs.isAutoGenerated && rhs.isAutoGenerated
            }
            if normalizeLanguageCode(lhs.languageCode) == normalizeLanguageCode(rhs.languageCode) {
                return lhs.id < rhs.id
            }
            return lhs.languageName.localizedCaseInsensitiveCompare(rhs.languageName) == .orderedAscending
        }
    }

    static func parseCaptionTracks(fromWatchPageHTML html: String) throws -> [YouTubeCaptionTrack] {
        let playerResponse = try extractPlayerResponseJSON(fromWatchPageHTML: html)
        return try parseCaptionTracks(fromPlayerResponse: playerResponse)
    }

    static func parseCaptionTracks(fromPlayerResponse playerResponse: [String: Any]) throws -> [YouTubeCaptionTrack] {
        guard let captions = playerResponse["captions"] as? [String: Any],
              let tracklist = captions["playerCaptionsTracklistRenderer"] as? [String: Any],
              let captionTracks = tracklist["captionTracks"] as? [[String: Any]] else {
            throw YouTubeCaptionServiceError.captionsUnavailable
        }

        return captionTracks.compactMap { rawTrack in
            guard let languageCode = rawTrack["languageCode"] as? String,
                  let baseURL = rawTrack["baseUrl"] as? String else {
                return nil
            }

            let vssID = rawTrack["vssId"] as? String
            let kindString = rawTrack["kind"] as? String
            let isAutoGenerated = kindString == "asr" || (vssID?.hasPrefix("a.") == true)
            let kind: YouTubeCaptionTrackKind = isAutoGenerated ? .asr : .standard
            let trackID = vssID ?? "\(languageCode)::\(kind.rawValue)"
            let languageName = captionTrackDisplayName(from: rawTrack["name"]) ?? languageCode
            let isDefault = rawTrack["isDefault"] as? Bool ?? false
            let sourceLanguageCode = rawTrack["sourceLanguageCode"] as? String

            return YouTubeCaptionTrack(
                id: trackID,
                languageCode: languageCode,
                languageName: languageName,
                kind: kind,
                isDefault: isDefault,
                sourceLanguageCode: sourceLanguageCode,
                url: normalizeCaptionURLString(baseURL)
            )
        }
    }

    static func parseCues(fromJSON3Data data: Data) throws -> [YouTubeCaptionCue] {
        let rootObject: Any
        do {
            rootObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw YouTubeCaptionServiceError.invalidTranscriptPayload
        }

        guard let root = rootObject as? [String: Any],
              let events = root["events"] as? [[String: Any]] else {
            throw YouTubeCaptionServiceError.invalidTranscriptPayload
        }

        let parsed: [YouTubeCaptionCue] = events.enumerated().compactMap { offset, event in
            guard let segs = event["segs"] as? [[String: Any]] else { return nil }

            let joinedText = segs
                .compactMap { $0["utf8"] as? String }
                .joined()

            let normalizedText = normalizeCueText(joinedText)
            guard !normalizedText.isEmpty else { return nil }

            let startMs = numberValue(event["tStartMs"]) ?? 0
            let durationMs = numberValue(event["dDurationMs"]) ?? 0
            let startTime = startMs / 1000.0
            let fallbackDuration = max(1.5, durationMs / 1000.0)
            let endTime = startTime + fallbackDuration

            return YouTubeCaptionCue(
                index: offset,
                startTime: startTime,
                endTime: endTime,
                text: normalizedText
            )
        }

        guard !parsed.isEmpty else {
            throw YouTubeCaptionServiceError.transcriptEmpty
        }

        return parsed.enumerated().map { index, cue in
            YouTubeCaptionCue(
                id: cue.id,
                index: index,
                startTime: cue.startTime,
                endTime: cue.endTime,
                text: cue.text
            )
        }
    }

    static func parseCues(fromXMLData data: Data) throws -> [YouTubeCaptionCue] {
        let parserDelegate = TimedTextXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate

        guard parser.parse() else {
            throw YouTubeCaptionServiceError.unsupportedTranscriptFormat
        }

        guard !parserDelegate.cues.isEmpty else {
            throw YouTubeCaptionServiceError.transcriptEmpty
        }

        return parserDelegate.cues.enumerated().map { index, cue in
            YouTubeCaptionCue(
                id: cue.id,
                index: index,
                startTime: cue.startTime,
                endTime: cue.endTime,
                text: cue.text
            )
        }
    }

    static func normalizeCueText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractInnertubeAPIKey(fromWatchPageHTML html: String) throws -> String {
        let pattern = #""INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw YouTubeCaptionServiceError.invalidWatchPage
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let keyRange = Range(match.range(at: 1), in: html) else {
            throw YouTubeCaptionServiceError.invalidWatchPage
        }

        return String(html[keyRange])
    }

    private static func extractPlayerResponseJSON(fromWatchPageHTML html: String) throws -> [String: Any] {
        let patterns = [
            #"var\s+ytInitialPlayerResponse\s*=\s*\{"#,
            #"ytInitialPlayerResponse\s*=\s*\{"#,
            #"window\["ytInitialPlayerResponse"\]\s*=\s*\{"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            let matches = regex.matches(in: html, range: range)

            for match in matches {
                guard let matchRange = Range(match.range, in: html) else { continue }
                guard let jsonStart = html[matchRange.lowerBound...].firstIndex(of: "{") else { continue }
                guard let jsonString = extractBalancedJSONObject(from: html[jsonStart...]) else { continue }
                if let data = jsonString.data(using: .utf8),
                   let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return object
                }
            }
        }

        throw YouTubeCaptionServiceError.invalidWatchPage
    }

    private static func extractBalancedJSONObject(from substring: Substring) -> String? {
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var endIndex: Substring.Index?

        for index in substring.indices {
            let character = substring[index]

            if isEscaped {
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"" {
                isInsideString.toggle()
                continue
            }

            if isInsideString {
                continue
            }

            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    endIndex = substring.index(after: index)
                    break
                }
            }
        }

        guard let endIndex else { return nil }
        return String(substring[..<endIndex])
    }

    private static func captionTrackDisplayName(from rawName: Any?) -> String? {
        if let simple = rawName as? [String: Any],
           let text = simple["simpleText"] as? String {
            return text
        }
        if let runsContainer = rawName as? [String: Any],
           let runs = runsContainer["runs"] as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func numberValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String, let doubleValue = Double(value) { return doubleValue }
        return nil
    }

    private static func normalizeLanguageCode(_ code: String) -> String {
        code
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased() ?? code.lowercased()
    }

    private static func normalizeCaptionURLString(_ rawURL: String) -> String {
        if rawURL.hasPrefix("//") {
            return "https:\(rawURL)"
        }
        if rawURL.hasPrefix("/") {
            return "https://www.youtube.com\(rawURL)"
        }
        return rawURL
    }
}

private final class TimedTextXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var cues: [YouTubeCaptionCue] = []

    private var currentStart: Double?
    private var currentDuration: Double?
    private var currentText = ""
    private var currentIndex = 0
    private var currentCueElementName: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        switch elementName {
        case "text":
            currentCueElementName = elementName
            currentText = ""
            currentStart = Double(attributeDict["start"] ?? "")
            currentDuration = Double(attributeDict["dur"] ?? "")
        case "p":
            currentCueElementName = elementName
            currentText = ""
            if let startMilliseconds = Double(attributeDict["t"] ?? "") {
                currentStart = startMilliseconds / 1000.0
            } else {
                currentStart = nil
            }
            if let durationMilliseconds = Double(attributeDict["d"] ?? "") {
                currentDuration = durationMilliseconds / 1000.0
            } else {
                currentDuration = nil
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentCueElementName != nil else { return }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == currentCueElementName,
              let start = currentStart else { return }

        let duration = max(1.5, currentDuration ?? 0)
        let normalizedText = YouTubeCaptionService.normalizeCueText(currentText)
        defer {
            currentCueElementName = nil
            currentStart = nil
            currentDuration = nil
            currentText = ""
        }

        guard !normalizedText.isEmpty else { return }

        cues.append(
            YouTubeCaptionCue(
                index: currentIndex,
                startTime: start,
                endTime: start + duration,
                text: normalizedText
            )
        )
        currentIndex += 1
    }
}
