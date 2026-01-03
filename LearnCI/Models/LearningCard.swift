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
    var imageFile: String?
    
    // For local tracking if needed, though mostly handled by DataManager/Game logic
    // We make this optional so it doesn't fail JSON decoding if missing
    var isMastered: Bool?
    
    var masteredState: Bool {
        get { isMastered ?? false }
        set { isMastered = newValue }
    }
}

struct CardDeck: Codable, Identifiable {
    var id: String
    var language: Language
    var level: LearningLevel
    var title: String
    var cards: [LearningCard]
    var baseFolderName: String? // Added to track resource folder
}
