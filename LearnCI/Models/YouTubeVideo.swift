import Foundation

struct YouTubeVideoChapter: Identifiable, Hashable {
    let startTime: TimeInterval
    let title: String

    var id: String {
        "\(Int(startTime))-\(title)"
    }

    var formattedTimestamp: String {
        let totalSeconds = max(0, Int(startTime.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct YouTubeVideo: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let thumbnailURL: String
    let channelTitle: String
    /// YouTube channel ID (`UC…`) when available from the Data API snippet.
    var channelId: String? = nil
    let duration: String
    let publishedAt: Date
    
    // For direct video files (non-YouTube)
    var videoStreamURL: String?
    
    // Track when video was added to channel feed
    var addedToFeedAt: Date?
    
    // Optional tagging for discovery
    var language: Language?
    var level: LearningLevel?
    
    var durationInSeconds: Int {
        parseDuration(duration)
    }
    
    var durationInMinutes: Int {
        durationInSeconds / 60
    }
    
    var isShort: Bool {
        durationInSeconds <= 61
    }

    var chapters: [YouTubeVideoChapter] {
        parseChapters(from: description)
    }
    
    private func parseDuration(_ iso8601: String) -> Int {
        var result = 0
        let components = iso8601.dropFirst(2) // Remove "PT"
        
        // Simple manual parsing for H, M, S
        // PT1H2M10S
        
        var currentNum = ""
        for char in components {
            if char.isNumber {
                currentNum.append(char)
            } else {
                let val = Int(currentNum) ?? 0
                currentNum = ""
                
                switch char {
                case "H": result += val * 3600
                case "M": result += val * 60
                case "S": result += val
                default: break
                }
            }
        }
        
        return result
    }

    private func parseChapters(from description: String) -> [YouTubeVideoChapter] {
        guard !description.isEmpty else { return [] }

        let pattern = #"^\s*((?:\d{1,2}:)?\d{1,2}:\d{2})\s*(?:[-|:]\s*)?(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var chapters: [YouTubeVideoChapter] = []
        var seenStartTimes: Set<Int> = []

        for line in description.components(separatedBy: .newlines) {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: nsRange),
                  let timestampRange = Range(match.range(at: 1), in: line),
                  let titleRange = Range(match.range(at: 2), in: line) else {
                continue
            }

            let timestamp = String(line[timestampRange])
            let title = String(line[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let startSeconds = timestampToSeconds(timestamp)

            guard !title.isEmpty else { continue }
            guard seenStartTimes.insert(startSeconds).inserted else { continue }

            chapters.append(
                YouTubeVideoChapter(
                    startTime: TimeInterval(startSeconds),
                    title: title
                )
            )
        }

        let sortedChapters = chapters.sorted { $0.startTime < $1.startTime }
        return sortedChapters.count >= 2 ? sortedChapters : []
    }

    private func timestampToSeconds(_ timestamp: String) -> Int {
        let components = timestamp
            .split(separator: ":")
            .compactMap { Int($0) }

        guard !components.isEmpty else { return 0 }

        return components.reduce(0) { partialResult, value in
            (partialResult * 60) + value
        }
    }
}

struct YouTubeChannel: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let thumbnailURL: String
    var isPlaylist: Bool = false // Default to false, mutable for manual setting
    var itemCount: Int? = nil
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case thumbnailURL = "thumbnail" // Assuming API mapping or internal mapping
        // Exclude isPlaylist from coding if it's not in JSON, or make it optional in keys
    }
    
    // Custom init to support default parameter
    init(id: String, title: String, thumbnailURL: String, isPlaylist: Bool = false, itemCount: Int? = nil) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.isPlaylist = isPlaylist
        self.itemCount = itemCount
    }
    
    // Allow decoding without isPlaylist
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        
        // Handle title - might be nested in snippet->title in real API, 
        // but this struct might be a simplified internal model.
        // If it's used for API decoding, I should check YouTubeManager to see how it's decoded.
        // Assuming simple decoding for now based on existing fields.
        title = try container.decode(String.self, forKey: .title)
        thumbnailURL = try container.decode(String.self, forKey: .thumbnailURL)
        isPlaylist = false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(thumbnailURL, forKey: .thumbnailURL)
    }
}
