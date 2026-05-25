import Foundation
import SwiftData

fileprivate func encodeYouTubeStudyJSON<T: Encodable>(_ value: T) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

fileprivate func decodeYouTubeStudyJSON<T: Decodable>(_ type: T.Type, from json: String?) -> T? {
    guard let json, let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

struct YouTubeTranslatedCue: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let cueID: String?
    let cueIndex: Int
    let text: String

    init(cueID: String? = nil, cueIndex: Int, text: String) {
        self.cueID = cueID
        self.cueIndex = cueIndex
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = cueID ?? "translated-\(cueIndex)"
    }
}

@Model
final class YouTubeCaptionCache {
    @Attribute(.unique) var cacheKey: String
    var videoID: String
    var trackID: String
    var sourceLanguageCode: String
    var fetchedAt: Date
    var updatedAt: Date
    var trackJSON: String
    var cuesJSON: String

    @Transient var track: YouTubeCaptionTrack? {
        decodeYouTubeStudyJSON(YouTubeCaptionTrack.self, from: trackJSON)
    }

    @Transient var cues: [YouTubeCaptionCue] {
        decodeYouTubeStudyJSON([YouTubeCaptionCue].self, from: cuesJSON) ?? []
    }

    init(
        videoID: String,
        track: YouTubeCaptionTrack,
        cues: [YouTubeCaptionCue],
        fetchedAt: Date = Date()
    ) {
        self.cacheKey = Self.makeCacheKey(videoID: videoID, track: track)
        self.videoID = videoID
        self.trackID = track.id
        self.sourceLanguageCode = track.languageCode
        self.fetchedAt = fetchedAt
        self.updatedAt = fetchedAt
        self.trackJSON = encodeYouTubeStudyJSON(track) ?? ""
        self.cuesJSON = encodeYouTubeStudyJSON(cues) ?? "[]"
    }

    func replace(track: YouTubeCaptionTrack? = nil, cues: [YouTubeCaptionCue], updatedAt: Date = Date()) {
        let trackToPersist = track ?? self.track ?? YouTubeCaptionTrack(
            id: trackID,
            languageCode: sourceLanguageCode,
            languageName: sourceLanguageCode
        )
        self.trackID = trackToPersist.id
        self.sourceLanguageCode = trackToPersist.languageCode
        self.updatedAt = updatedAt
        self.trackJSON = encodeYouTubeStudyJSON(trackToPersist) ?? self.trackJSON
        self.cuesJSON = encodeYouTubeStudyJSON(cues) ?? self.cuesJSON
        self.cacheKey = Self.makeCacheKey(videoID: videoID, track: trackToPersist)
    }

    static func makeCacheKey(videoID: String, track: YouTubeCaptionTrack) -> String {
        "\(videoID)::\(track.cacheKey)"
    }
}

@Model
final class YouTubeCaptionTranslationCache {
    @Attribute(.unique) var cacheKey: String
    var videoID: String
    var trackID: String
    var sourceLanguageCode: String
    var targetLanguageCode: String
    var createdAt: Date
    var updatedAt: Date
    var translatedCuesJSON: String

    @Transient var translatedCues: [YouTubeTranslatedCue] {
        decodeYouTubeStudyJSON([YouTubeTranslatedCue].self, from: translatedCuesJSON) ?? []
    }

    init(
        videoID: String,
        trackID: String,
        sourceLanguageCode: String,
        targetLanguageCode: String,
        translatedCues: [YouTubeTranslatedCue],
        createdAt: Date = Date()
    ) {
        self.cacheKey = Self.makeCacheKey(
            videoID: videoID,
            trackID: trackID,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode
        )
        self.videoID = videoID
        self.trackID = trackID
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.translatedCuesJSON = encodeYouTubeStudyJSON(translatedCues) ?? "[]"
    }

    func replaceTranslatedCues(_ translatedCues: [YouTubeTranslatedCue], updatedAt: Date = Date()) {
        self.updatedAt = updatedAt
        self.translatedCuesJSON = encodeYouTubeStudyJSON(translatedCues) ?? self.translatedCuesJSON
    }

    static func makeCacheKey(
        videoID: String,
        trackID: String,
        sourceLanguageCode: String,
        targetLanguageCode: String
    ) -> String {
        "\(videoID)::\(trackID)::\(sourceLanguageCode)::\(targetLanguageCode)"
    }
}

@Model
final class YouTubeWordLookupCache {
    @Attribute(.unique) var cacheKey: String
    var videoID: String
    var sourceLanguageCode: String
    var word: String
    var contextText: String?
    var translation: String
    var partOfSpeech: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        videoID: String,
        sourceLanguageCode: String,
        word: String,
        contextText: String? = nil,
        translation: String,
        partOfSpeech: String? = nil,
        createdAt: Date = Date()
    ) {
        self.cacheKey = Self.makeCacheKey(
            videoID: videoID,
            sourceLanguageCode: sourceLanguageCode,
            word: word,
            contextText: contextText
        )
        self.videoID = videoID
        self.sourceLanguageCode = sourceLanguageCode
        self.word = word
        self.contextText = contextText
        self.translation = translation
        self.partOfSpeech = partOfSpeech
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    func applyResult(translation: String, partOfSpeech: String?, updatedAt: Date = Date()) {
        self.translation = translation
        self.partOfSpeech = partOfSpeech
        self.updatedAt = updatedAt
    }

    static func makeCacheKey(
        videoID: String,
        sourceLanguageCode: String,
        word: String,
        contextText: String?
    ) -> String {
        let normalizedWord = normalizeCacheComponent(word)
        let normalizedContext = normalizeCacheComponent(contextText)
        return "\(videoID)::\(sourceLanguageCode)::\(normalizedWord)::\(normalizedContext)"
    }

    private static func normalizeCacheComponent(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
