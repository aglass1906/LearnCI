import Foundation

enum Language: String, Codable, CaseIterable, Identifiable {
    case spanish = "Spanish"
    case japanese = "Japanese"
    case korean = "Korean"
    
    var id: String { self.rawValue }
    
    var flag: String {
        switch self {
        case .spanish: return "🇪🇸"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        }
    }
    
    var code: String {
        switch self {
        case .spanish: return "es"
        case .japanese: return "ja"
        case .korean: return "ko"
        }
    }
}

enum LearningLevel: String, Codable, CaseIterable, Identifiable {
    case superBeginner = "Super Beginner"
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    
    var id: String { self.rawValue }
    
    var cerCode: String {
        switch self {
        case .superBeginner: return "A0"
        case .beginner: return "A1-A2"
        case .intermediate: return "B1-B2"
        case .advanced: return "C1-C2"
        }
    }
}

struct LearningCard: Identifiable, Codable, Hashable {
    var id: String
    var targetWord: String
    var nativeTranslation: String
    var sentenceTarget: String
    var sentenceNative: String
    var audioWordFile: String?
    var audioSentenceFile: String?
    var mediaFile: String?
    
    // For local tracking if needed, though mostly handled by DataManager/Game logic
    // We make this optional so it doesn't fail JSON decoding if missing
    var isMastered: Bool?
    
    var masteredState: Bool {
        get { isMastered ?? false }
        set { isMastered = newValue }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, targetWord, nativeTranslation, sentenceTarget, sentenceNative
        case audioWordFile, audioSentenceFile
        case mediaFile
        case imageFile // Legacy support
        case isMastered
    }
    
    init(id: String, targetWord: String, nativeTranslation: String, sentenceTarget: String, sentenceNative: String, audioWordFile: String? = nil, audioSentenceFile: String? = nil, mediaFile: String? = nil, isMastered: Bool? = nil) {
        self.id = id
        self.targetWord = targetWord
        self.nativeTranslation = nativeTranslation
        self.sentenceTarget = sentenceTarget
        self.sentenceNative = sentenceNative
        self.audioWordFile = audioWordFile
        self.audioSentenceFile = audioSentenceFile
        self.mediaFile = mediaFile
        self.isMastered = isMastered
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.targetWord = try container.decode(String.self, forKey: .targetWord)
        self.nativeTranslation = try container.decode(String.self, forKey: .nativeTranslation)
        self.sentenceTarget = try container.decode(String.self, forKey: .sentenceTarget)
        self.sentenceNative = try container.decode(String.self, forKey: .sentenceNative)
        self.audioWordFile = try container.decodeIfPresent(String.self, forKey: .audioWordFile)
        self.audioSentenceFile = try container.decodeIfPresent(String.self, forKey: .audioSentenceFile)
        self.isMastered = try container.decodeIfPresent(Bool.self, forKey: .isMastered)
        
        // Robust media file decoding: Prefers mediaFile, falls back to imageFile
        if let media = try container.decodeIfPresent(String.self, forKey: .mediaFile) {
            self.mediaFile = media
        } else {
            self.mediaFile = try container.decodeIfPresent(String.self, forKey: .imageFile)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(targetWord, forKey: .targetWord)
        try container.encode(nativeTranslation, forKey: .nativeTranslation)
        try container.encode(sentenceTarget, forKey: .sentenceTarget)
        try container.encode(sentenceNative, forKey: .sentenceNative)
        try container.encodeIfPresent(audioWordFile, forKey: .audioWordFile)
        try container.encodeIfPresent(audioSentenceFile, forKey: .audioSentenceFile)
        try container.encodeIfPresent(mediaFile, forKey: .mediaFile)
        try container.encodeIfPresent(isMastered, forKey: .isMastered)
    }
}

struct CardDeck: Codable, Identifiable, Equatable {
    var id: String
    var language: Language
    var level: LearningLevel
    var title: String
    var cards: [LearningCard]
    var baseFolderName: String? // Added to track resource folder
    
    static func == (lhs: CardDeck, rhs: CardDeck) -> Bool {
        return lhs.id == rhs.id &&
               lhs.language == rhs.language &&
               lhs.level == rhs.level &&
               lhs.title == rhs.title &&
               lhs.cards == rhs.cards &&
               lhs.baseFolderName == rhs.baseFolderName
    }
}
