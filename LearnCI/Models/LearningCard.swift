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

enum CardType: String, Codable {
    case standard
    case intro
    case story
    case outro
}

struct LearningCard: Identifiable, Codable, Hashable {
    var id: String
    var wordTarget: String
    var wordNative: String
    var sentenceTarget: String
    var sentenceNative: String
    var audioWordFile: String?
    var audioSentenceFile: String?
    var mediaFile: String?
    
    // New Fields
    var type: CardType = .standard
    var order: Int = 0
    var usage: Set<String>? // e.g. ["story_only"]
    
    var isMastered: Bool?
    
    var masteredState: Bool {
        get { isMastered ?? false }
        set { isMastered = newValue }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, wordTarget, wordNative, sentenceTarget, sentenceNative
        case audioWordFile, audioSentenceFile, mediaFile, imageFile
        case type, order, usage, isMastered
        
        // Legacy keys
        case targetWord, nativeTranslation
    }
    
    init(id: String, wordTarget: String, wordNative: String, sentenceTarget: String, sentenceNative: String, audioWordFile: String? = nil, audioSentenceFile: String? = nil, mediaFile: String? = nil, type: CardType = .standard, order: Int = 0, usage: Set<String>? = nil, isMastered: Bool? = nil) {
        self.id = id
        self.wordTarget = wordTarget
        self.wordNative = wordNative
        self.sentenceTarget = sentenceTarget
        self.sentenceNative = sentenceNative
        self.audioWordFile = audioWordFile
        self.audioSentenceFile = audioSentenceFile
        self.mediaFile = mediaFile
        self.type = type
        self.order = order
        self.usage = usage
        self.isMastered = isMastered
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        
        // Smart Decoding for Word Target
        if let target = try container.decodeIfPresent(String.self, forKey: .wordTarget) {
            self.wordTarget = target
        } else {
            self.wordTarget = try container.decode(String.self, forKey: .targetWord)
        }
        
        // Smart Decoding for Native Word
        if let native = try container.decodeIfPresent(String.self, forKey: .wordNative) {
            self.wordNative = native
        } else {
            self.wordNative = try container.decode(String.self, forKey: .nativeTranslation)
        }
        
        // Optional Fields
        self.sentenceTarget = try container.decodeIfPresent(String.self, forKey: .sentenceTarget) ?? ""
        self.sentenceNative = try container.decodeIfPresent(String.self, forKey: .sentenceNative) ?? ""
        self.audioWordFile = try container.decodeIfPresent(String.self, forKey: .audioWordFile)
        self.audioSentenceFile = try container.decodeIfPresent(String.self, forKey: .audioSentenceFile)
        self.isMastered = try container.decodeIfPresent(Bool.self, forKey: .isMastered)
        self.type = try container.decodeIfPresent(CardType.self, forKey: .type) ?? .standard
        self.order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        self.usage = try container.decodeIfPresent(Set<String>.self, forKey: .usage)
        
        // Media File Fallback
        if let media = try container.decodeIfPresent(String.self, forKey: .mediaFile) {
            self.mediaFile = media
        } else {
            self.mediaFile = try container.decodeIfPresent(String.self, forKey: .imageFile)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(wordTarget, forKey: .wordTarget)
        try container.encode(wordNative, forKey: .wordNative)
        try container.encode(sentenceTarget, forKey: .sentenceTarget)
        try container.encode(sentenceNative, forKey: .sentenceNative)
        try container.encodeIfPresent(audioWordFile, forKey: .audioWordFile)
        try container.encodeIfPresent(audioSentenceFile, forKey: .audioSentenceFile)
        try container.encodeIfPresent(mediaFile, forKey: .mediaFile)
        try container.encodeIfPresent(isMastered, forKey: .isMastered)
        try container.encode(type, forKey: .type)
        try container.encode(order, forKey: .order)
        try container.encodeIfPresent(usage, forKey: .usage)
    }
}

struct DeckDefaults: Codable, Equatable {
    var audioAutoplay: Bool?
    var replayCount: Int?
    var nativeHiddenByDefault: Bool?
    var randomize: Bool?
}

struct CardDeck: Codable, Identifiable, Equatable {
    var id: String
    var language: Language
    var level: LearningLevel
    var title: String
    var cards: [LearningCard]
    
    // New Fields
    var supportedModes: Set<GameConfiguration.GameType>?
    var gameConfiguration: [String: DeckDefaults]?
    var defaults: DeckDefaults?
    var coverImage: String?
    
    var baseFolderName: String? 
    
    static func == (lhs: CardDeck, rhs: CardDeck) -> Bool {
        return lhs.id == rhs.id &&
               lhs.language == rhs.language &&
               lhs.level == rhs.level &&
               lhs.title == rhs.title &&
               lhs.cards == rhs.cards &&
               lhs.baseFolderName == rhs.baseFolderName
    }
}
