import Foundation
import SwiftData

enum SavedStudyWordSourceType: String, Codable, CaseIterable, Identifiable {
    case flashcard
    case story
    case youtube
    case podcast
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flashcard: return "Flashcards"
        case .story: return "Stories"
        case .youtube: return "YouTube"
        case .podcast: return "Podcasts"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .flashcard: return "rectangle.stack.fill"
        case .story: return "book.pages.fill"
        case .youtube: return "play.rectangle.fill"
        case .podcast: return "headphones"
        case .other: return "star.fill"
        }
    }
}

struct SavedStudyWordCapture {
    let userID: String
    let word: String
    let translation: String?
    let lemma: String?
    let sentenceTarget: String?
    let sentenceNative: String?
    let languageCode: String
    let level: String?
    let partOfSpeech: String?
    let verbTense: String?
    let grammarNotes: String?
    let sourceType: SavedStudyWordSourceType
    let sourceId: String
    let sourceTitle: String
    let sourceUrl: String?
    let blockIndex: Int?
    let mediaStart: Double?
    let mediaEnd: Double?
    let audioWordFile: String?
    let audioSentenceFile: String?
    let deckFolderName: String?
}

@Model
final class SavedStudyWord {
    @Attribute(.unique) var id: UUID
    var userID: String
    var word: String
    var normalizedWord: String
    var lemma: String?
    var translation: String?
    var sentenceTarget: String?
    var sentenceNative: String?
    var languageCode: String
    var level: String?
    var partOfSpeech: String?
    var verbTense: String?
    var grammarNotes: String?
    var sourceTypeRaw: String
    var sourceId: String
    var sourceTitle: String
    var sourceUrl: String?
    var blockIndex: Int?
    var mediaStart: Double?
    var mediaEnd: Double?
    var audioWordFile: String?
    var audioSentenceFile: String?
    var deckFolderName: String?
    var createdAt: Date
    var updatedAt: Date
    var isSynced: Bool

    var sourceType: SavedStudyWordSourceType {
        get { SavedStudyWordSourceType(rawValue: sourceTypeRaw) ?? .other }
        set { sourceTypeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), capture: SavedStudyWordCapture, createdAt: Date = Date()) {
        self.id = id
        self.userID = capture.userID
        self.word = capture.word.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedWord = Self.normalize(capture.word)
        self.lemma = capture.lemma
        self.translation = capture.translation
        self.sentenceTarget = capture.sentenceTarget
        self.sentenceNative = capture.sentenceNative
        self.languageCode = capture.languageCode
        self.level = capture.level
        self.partOfSpeech = capture.partOfSpeech
        self.verbTense = capture.verbTense
        self.grammarNotes = capture.grammarNotes
        self.sourceTypeRaw = capture.sourceType.rawValue
        self.sourceId = capture.sourceId
        self.sourceTitle = capture.sourceTitle
        self.sourceUrl = capture.sourceUrl
        self.blockIndex = capture.blockIndex
        self.mediaStart = capture.mediaStart
        self.mediaEnd = capture.mediaEnd
        self.audioWordFile = capture.audioWordFile
        self.audioSentenceFile = capture.audioSentenceFile
        self.deckFolderName = capture.deckFolderName
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.isSynced = false
    }

    func merge(capture: SavedStudyWordCapture) {
        word = capture.word.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedWord = Self.normalize(capture.word)
        lemma = capture.lemma ?? lemma
        translation = capture.translation ?? translation
        sentenceTarget = capture.sentenceTarget ?? sentenceTarget
        sentenceNative = capture.sentenceNative ?? sentenceNative
        languageCode = capture.languageCode
        level = capture.level ?? level
        partOfSpeech = capture.partOfSpeech ?? partOfSpeech
        verbTense = capture.verbTense ?? verbTense
        grammarNotes = capture.grammarNotes ?? grammarNotes
        sourceTitle = capture.sourceTitle
        sourceUrl = capture.sourceUrl ?? sourceUrl
        blockIndex = capture.blockIndex ?? blockIndex
        mediaStart = capture.mediaStart ?? mediaStart
        mediaEnd = capture.mediaEnd ?? mediaEnd
        audioWordFile = capture.audioWordFile ?? audioWordFile
        audioSentenceFile = capture.audioSentenceFile ?? audioSentenceFile
        deckFolderName = capture.deckFolderName ?? deckFolderName
        updatedAt = Date()
        isSynced = false
    }

    func applyAnalysis(_ analysis: StudyWordAnalysis) {
        translation = analysis.translation?.nilIfBlank ?? translation
        lemma = analysis.lemma?.nilIfBlank ?? lemma
        partOfSpeech = analysis.partOfSpeech?.nilIfBlank ?? partOfSpeech
        level = analysis.level?.nilIfBlank ?? level
        verbTense = analysis.verbTense?.nilIfBlank ?? verbTense
        grammarNotes = analysis.grammarNotes?.nilIfBlank ?? grammarNotes
        updatedAt = Date()
        isSynced = false
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}

struct StudyWordAnalysis: Codable, Equatable {
    let translation: String?
    let lemma: String?
    let partOfSpeech: String?
    let level: String?
    let verbTense: String?
    let grammarNotes: String?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
