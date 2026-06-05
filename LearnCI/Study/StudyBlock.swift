import Foundation

// MARK: - Resource identity

enum StudyResourceType: String, Codable, CaseIterable {
    case youtube
    case story
    case podcast
    case mediaUrl
}

struct StudyResourceRef: Hashable, Sendable {
    let type: StudyResourceType
    let resourceId: String
    let consumptionUrl: String
    let title: String
    let languageCode: String?

    static func youtube(videoID: String, title: String, languageCode: String?) -> StudyResourceRef {
        StudyResourceRef(
            type: .youtube,
            resourceId: videoID,
            consumptionUrl: "https://www.youtube.com/watch?v=\(videoID)",
            title: title,
            languageCode: languageCode
        )
    }
}

// MARK: - Focus window (YouTube caption grouping)

enum StudyFocusWindowSize: Int, CaseIterable, Identifiable, Sendable {
    case single = 1
    case sentence = 3
    case extended = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .single: return "1 line"
        case .sentence: return "3 lines"
        case .extended: return "5 lines"
        }
    }

    var captionCount: Int { rawValue }
}

// MARK: - Block

struct StudyBlock: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let index: Int
    let targetText: String
    let nativeText: String?
    let mediaStart: Double
    let mediaEnd: Double
    /// Inclusive indices into the source cue list (YouTube captions).
    let cueStartIndex: Int?
    let cueEndIndex: Int?

    var duration: Double {
        max(0, mediaEnd - mediaStart)
    }

    var captionLineCount: Int {
        guard let cueStartIndex, let cueEndIndex else { return 1 }
        return max(1, cueEndIndex - cueStartIndex + 1)
    }

    func contains(time: Double, slack: Double = 0.05) -> Bool {
        time >= (mediaStart - slack) && time <= (mediaEnd + slack)
    }

    func contains(cueIndex: Int) -> Bool {
        guard let cueStartIndex, let cueEndIndex else { return false }
        return cueIndex >= cueStartIndex && cueIndex <= cueEndIndex
    }
}

// MARK: - Session definition

struct StudySessionDefinition: Equatable, Sendable {
    let startIndex: Int
    let endIndex: Int
    let targetMinutes: Int?

    var blockCount: Int {
        max(0, endIndex - startIndex + 1)
    }

    func contains(blockIndex: Int) -> Bool {
        blockIndex >= startIndex && blockIndex <= endIndex
    }
}

enum StudySessionRangeBuilder {
    static func byBlockCount(_ count: Int, from startIndex: Int, in blocks: [StudyBlock]) -> StudySessionDefinition? {
        guard !blocks.isEmpty, count > 0 else { return nil }
        let start = min(max(0, startIndex), blocks.count - 1)
        let end = min(blocks.count - 1, start + count - 1)
        return StudySessionDefinition(startIndex: start, endIndex: end, targetMinutes: nil)
    }

    static func byDurationMinutes(_ minutes: Int, from startIndex: Int, in blocks: [StudyBlock]) -> StudySessionDefinition? {
        guard !blocks.isEmpty, minutes > 0 else { return nil }
        let start = min(max(0, startIndex), blocks.count - 1)
        let budget = Double(minutes) * 60
        var accumulated = 0.0
        var end = start

        for index in start..<blocks.count {
            accumulated += blocks[index].duration
            end = index
            if accumulated >= budget { break }
        }

        return StudySessionDefinition(startIndex: start, endIndex: end, targetMinutes: minutes)
    }

    static func fullTranscript(in blocks: [StudyBlock]) -> StudySessionDefinition? {
        guard let last = blocks.indices.last else { return nil }
        return StudySessionDefinition(startIndex: 0, endIndex: last, targetMinutes: nil)
    }
}

// MARK: - Block source

protocol StudyBlockSource {
    var resource: StudyResourceRef { get }
    var blocks: [StudyBlock] { get }
    var mediaPlayer: any StudyMediaPlayer { get }
}
