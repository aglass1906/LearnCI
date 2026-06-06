import Foundation
import SwiftData

@Model
final class StudySessionRecord {
    @Attribute(.unique) var id: UUID
    var userID: String
    var resourceType: String
    var resourceId: String
    var consumptionUrl: String
    var title: String
    var startBlockIndex: Int
    var endBlockIndex: Int
    var targetMinutes: Int?
    var startedAt: Date
    var completedAt: Date?
    var completedBlockIndicesJSON: String

    init(
        userID: String,
        resource: StudyResourceRef,
        definition: StudySessionDefinition,
        startedAt: Date = Date()
    ) {
        self.id = UUID()
        self.userID = userID
        self.resourceType = resource.type.rawValue
        self.resourceId = resource.resourceId
        self.consumptionUrl = resource.consumptionUrl
        self.title = resource.title
        self.startBlockIndex = definition.startIndex
        self.endBlockIndex = definition.endIndex
        self.targetMinutes = definition.targetMinutes
        self.startedAt = startedAt
        self.completedBlockIndicesJSON = "[]"
    }

    var completedBlockIndices: [Int] {
        get {
            guard let data = completedBlockIndicesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([Int].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            completedBlockIndicesJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }
}

@Model
final class StudyNote {
    @Attribute(.unique) var id: UUID
    var userID: String
    var resourceType: String
    var resourceId: String
    var consumptionUrl: String
    var blockIndex: Int
    var offsetSec: Double
    var mediaTime: Double
    var body: String
    var createdAt: Date
    var updatedAt: Date

    init(
        userID: String,
        resource: StudyResourceRef,
        blockIndex: Int,
        offsetSec: Double,
        mediaTime: Double,
        body: String,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.userID = userID
        self.resourceType = resource.type.rawValue
        self.resourceId = resource.resourceId
        self.consumptionUrl = resource.consumptionUrl
        self.blockIndex = blockIndex
        self.offsetSec = offsetSec
        self.mediaTime = mediaTime
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

@Model
final class MarkedStudyWord {
    @Attribute(.unique) var id: UUID
    var userID: String
    var resourceType: String
    var resourceId: String
    var consumptionUrl: String
    var blockIndex: Int
    var word: String
    var lemma: String?
    var translation: String?
    var contextSnippet: String?
    var mediaTime: Double
    var createdAt: Date

    init(
        userID: String,
        resource: StudyResourceRef,
        blockIndex: Int,
        word: String,
        lemma: String? = nil,
        translation: String? = nil,
        contextSnippet: String? = nil,
        mediaTime: Double,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.userID = userID
        self.resourceType = resource.type.rawValue
        self.resourceId = resource.resourceId
        self.consumptionUrl = resource.consumptionUrl
        self.blockIndex = blockIndex
        self.word = word
        self.lemma = lemma
        self.translation = translation
        self.contextSnippet = contextSnippet
        self.mediaTime = mediaTime
        self.createdAt = createdAt
    }
}

/// Whisper (or other) transcripts for audio without native captions — Phase 4+.
@Model
final class MediaTranscriptCache {
    @Attribute(.unique) var cacheKey: String
    var consumptionUrl: String
    var languageCode: String
    var blocksJSON: String
    var wordsJSON: String?
    var cuesJSON: String?
    var fetchedAt: Date
    var updatedAt: Date

    init(
        consumptionUrl: String,
        languageCode: String,
        blocks: [StudyBlock],
        words: [WordTiming]? = nil,
        cues: [YouTubeCaptionCue]? = nil,
        fetchedAt: Date = Date()
    ) {
        self.cacheKey = Self.makeCacheKey(consumptionUrl: consumptionUrl, languageCode: languageCode)
        self.consumptionUrl = consumptionUrl
        self.languageCode = languageCode
        self.blocksJSON = Self.encodeBlocks(blocks)
        self.wordsJSON = words.flatMap { Self.encodeWords($0) }
        self.cuesJSON = cues.flatMap { Self.encodeCues($0) }
        self.fetchedAt = fetchedAt
        self.updatedAt = fetchedAt
    }

    var blocks: [StudyBlock] {
        Self.decodeBlocks(from: blocksJSON)
    }

    var words: [WordTiming] {
        guard let wordsJSON else { return [] }
        return Self.decodeWords(from: wordsJSON)
    }

    var cues: [YouTubeCaptionCue] {
        guard let cuesJSON else { return [] }
        return Self.decodeCues(from: cuesJSON)
    }

    func replace(
        blocks: [StudyBlock],
        words: [WordTiming]? = nil,
        cues: [YouTubeCaptionCue]? = nil,
        updatedAt: Date = Date()
    ) {
        self.blocksJSON = Self.encodeBlocks(blocks)
        if let words {
            self.wordsJSON = Self.encodeWords(words)
        }
        if let cues {
            self.cuesJSON = Self.encodeCues(cues)
        }
        self.updatedAt = updatedAt
    }

    static func makeCacheKey(consumptionUrl: String, languageCode: String) -> String {
        "\(consumptionUrl)::\(languageCode)"
    }

    private static func encodeBlocks(_ blocks: [StudyBlock]) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(blocks) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeBlocks(from json: String) -> [StudyBlock] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([StudyBlock].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func encodeWords(_ words: [WordTiming]) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(words) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeWords(from json: String) -> [WordTiming] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([WordTiming].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func encodeCues(_ cues: [YouTubeCaptionCue]) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(cues) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeCues(from json: String) -> [YouTubeCaptionCue] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([YouTubeCaptionCue].self, from: data) else {
            return []
        }
        return decoded
    }
}
