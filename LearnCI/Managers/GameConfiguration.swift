import Foundation

enum ElementVisibility: String, Codable, CaseIterable, Identifiable {
    case visible = "Show"      // Text: Visible, Audio: Auto-play
    case hint = "Hint"         // Text: Blur/Tap to Show, Audio: Manual Play
    case hidden = "Hide"       // Text: Hidden, Audio: Disabled
    
    var id: String { rawValue }
}

struct SectionConfiguration: Codable, Equatable {
    var text: ElementVisibility
    var audio: ElementVisibility
}

struct BackConfiguration: Codable, Equatable {
    var translation: ElementVisibility
    var sentenceMeaning: ElementVisibility
    var studyLinks: ElementVisibility
}

struct GameConfiguration: Codable, Equatable {
    enum Preset: String, CaseIterable, Identifiable {
        case customize = "Customize"
        case inputFocus = "Input Focus"
        case audioCards = "Audio Cards"
        case pictureCard = "Picture Card"
        case flashcard = "Flashcard"
        case story = "Story"
        
        var id: String { rawValue }
    }
    
    enum GameType: String, Codable, CaseIterable, Identifiable {
        case flashcards = "Flashcards"
        case memoryMatch = "Memory Match"
        case sentenceBuilder = "Sentence Scramble"
        case story = "Story" // Renamed for clarity
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .flashcards: return "rectangle.stack.fill"
            case .memoryMatch: return "square.grid.2x2.fill"
            case .sentenceBuilder: return "text.bubble.fill"
            case .story: return "book.fill"
            }
        }
        
        // Custom decoding to handle case-insensitive "flashcards" vs "Flashcards"
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawString = try container.decode(String.self)
            
            // Try exact match first
            if let type = GameType(rawValue: rawString) {
                self = type
                return
            }
            
            // Try case-insensitive scan
            let lowercased = rawString.lowercased()
            if let type = GameType.allCases.first(where: {
                $0.rawValue.lowercased() == lowercased ||
                String(describing: $0).lowercased() == lowercased // checks "flashcards" against case name if needed
            }) {
                self = type
                return
            }
            
            // Fallback for known legacy keys if rawValue didn't catch them
            switch lowercased {
            case "flashcards": self = .flashcards
            case "memorymatch", "memory match": self = .memoryMatch
            case "story": self = .story
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid GameType: \(rawString)")
            }
        }
    }
    
    var gameType: GameType = .flashcards
    var word: SectionConfiguration
    var sentence: SectionConfiguration
    var image: ElementVisibility
    var back: BackConfiguration
    var isRandomOrder: Bool = false
    var useTTSFallback: Bool = true
    var ttsRate: Float = 0.5
    var ttsVoiceGender: String = "female"
    
    init(gameType: GameType = .flashcards, word: SectionConfiguration, sentence: SectionConfiguration, image: ElementVisibility, back: BackConfiguration = BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible), isRandomOrder: Bool = false, useTTSFallback: Bool = true, ttsRate: Float = 0.5, ttsVoiceGender: String = "female") {
        self.gameType = gameType
        self.word = word
        self.sentence = sentence
        self.image = image
        self.back = back
        self.isRandomOrder = isRandomOrder
        self.useTTSFallback = useTTSFallback
        self.ttsRate = ttsRate
        self.ttsVoiceGender = ttsVoiceGender
    }
    
    static func from(preset: Preset) -> GameConfiguration {
        switch preset {
        case .customize, .inputFocus:
            // Input Focus default (Word: Vis+Auto, Sent: Vis+Auto, Img: Hint)
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .visible),
                sentence: SectionConfiguration(text: .visible, audio: .visible),
                image: .hint,
                back: BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible),
                useTTSFallback: true,
                ttsVoiceGender: "female" // Default
            )
        case .audioCards:
            // Word Audio Only (Text Hidden), Sentence Audio Only (Text Hidden), No Image
            return GameConfiguration(
                word: SectionConfiguration(text: .hidden, audio: .visible),
                sentence: SectionConfiguration(text: .hidden, audio: .visible),
                image: .hidden,
                back: BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible),
                useTTSFallback: true
            )
        case .pictureCard:
            // Yes Word (No Audio), No Sentence (No Audio), Yes Image
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .hidden),
                sentence: SectionConfiguration(text: .hidden, audio: .hidden),
                image: .visible,
                back: BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible),
                useTTSFallback: true,
                ttsVoiceGender: "female"
            )
        case .flashcard:
            // Yes Word (No Audio), No Sentence, No Image
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .hidden),
                sentence: SectionConfiguration(text: .hidden, audio: .hidden),
                image: .hidden,
                back: BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible),
                useTTSFallback: true
            )
        case .story:
            // Story Mode Defaults: Full Immersion
            // Text: Visible, Audio: Visible, Image: Visible
            // Back (Translations): Hint (Hidden by default, user taps to see)
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .visible),
                sentence: SectionConfiguration(text: .visible, audio: .visible),
                image: .visible,
                back: BackConfiguration(translation: .hint, sentenceMeaning: .hint, studyLinks: .visible),
                useTTSFallback: true,
                ttsVoiceGender: "female"
            )
        }
    }
}
