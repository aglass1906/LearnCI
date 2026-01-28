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
    var autoplay: Bool = true // Default true for backward compatibility
    
    enum CodingKeys: String, CodingKey {
        case text, audio, autoplay
    }
    
    init(text: ElementVisibility, audio: ElementVisibility, autoplay: Bool = true) {
        self.text = text
        self.audio = audio
        self.autoplay = autoplay
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(ElementVisibility.self, forKey: .text)
        audio = try container.decode(ElementVisibility.self, forKey: .audio)
        autoplay = try container.decodeIfPresent(Bool.self, forKey: .autoplay) ?? (audio == .visible)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(audio, forKey: .audio)
        try container.encode(autoplay, forKey: .autoplay)
    }
}

enum NavigationStyle: String, Codable, CaseIterable, Identifiable {
    case swipe = "swipe"
    case buttons = "buttons"
    case autoNext = "autoNext"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .swipe: return "Swipe"
        case .buttons: return "Buttons"
        case .autoNext: return "Auto-Next"
        }
    }
}

enum ConfirmationStyle: String, Codable, CaseIterable, Identifiable {
    case quiz = "quiz"
    case srs = "srs" // Hard/Good/Easy
    case show = "show" // Simple Next
    case auto = "auto" // Auto-advance without confirmation (often paired with autoNext)
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .quiz: return "Quiz"
        case .srs: return "SRS"
        case .show: return "Show"
        case .auto: return "Auto"
        }
    }
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
        
        var key: String {
            switch self {
            case .customize: return "customize"
            case .inputFocus: return "inputFocus"
            case .audioCards: return "audioCards"
            case .pictureCard: return "pictureCard"
            case .flashcard: return "flashcard"
            case .story: return "story"
            }
        }
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
    
    // New Configuration Options
    var navigation: NavigationStyle = .swipe
    var autoNextDelay: TimeInterval = 2.0
    var confirmation: ConfirmationStyle = .quiz
    
    var isRandomOrder: Bool = false
    var useTTSFallback: Bool = true
    var ttsRate: Float = 0.5
    var ttsVoiceGender: String = "female"
    
    enum CodingKeys: String, CodingKey {
        case gameType, word, sentence, image, back, isRandomOrder, useTTSFallback, ttsRate, ttsVoiceGender
        case navigation, autoNextDelay, confirmation
    }
    
    init(gameType: GameType = .flashcards, 
         word: SectionConfiguration, 
         sentence: SectionConfiguration, 
         image: ElementVisibility, 
         back: BackConfiguration = BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible), 
         navigation: NavigationStyle = .swipe,
         autoNextDelay: TimeInterval = 2.0,
         confirmation: ConfirmationStyle = .quiz,
         isRandomOrder: Bool = false, 
         useTTSFallback: Bool = true, 
         ttsRate: Float = 0.5, 
         ttsVoiceGender: String = "female") {
        self.gameType = gameType
        self.word = word
        self.sentence = sentence
        self.image = image
        self.back = back
        self.navigation = navigation
        self.autoNextDelay = autoNextDelay
        self.confirmation = confirmation
        self.isRandomOrder = isRandomOrder
        self.useTTSFallback = useTTSFallback
        self.ttsRate = ttsRate
        self.ttsVoiceGender = ttsVoiceGender
    }
    
    // Custom decoding to handle defaults for existing JSONs
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameType = try container.decode(GameType.self, forKey: .gameType)
        word = try container.decode(SectionConfiguration.self, forKey: .word)
        sentence = try container.decode(SectionConfiguration.self, forKey: .sentence)
        image = try container.decode(ElementVisibility.self, forKey: .image)
        back = try container.decode(BackConfiguration.self, forKey: .back)
        isRandomOrder = try container.decodeIfPresent(Bool.self, forKey: .isRandomOrder) ?? false
        useTTSFallback = try container.decodeIfPresent(Bool.self, forKey: .useTTSFallback) ?? true
        ttsRate = try container.decodeIfPresent(Float.self, forKey: .ttsRate) ?? 0.5
        ttsVoiceGender = try container.decodeIfPresent(String.self, forKey: .ttsVoiceGender) ?? "female"
        
        // New Defaults
        navigation = try container.decodeIfPresent(NavigationStyle.self, forKey: .navigation) ?? .swipe
        autoNextDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .autoNextDelay) ?? 2.0
        confirmation = try container.decodeIfPresent(ConfirmationStyle.self, forKey: .confirmation) ?? .quiz
    }
    
    static func from(preset: Preset) -> GameConfiguration {
        switch preset {
        case .customize, .inputFocus:
            // Input Focus default (Word: Vis+Auto, Sent: Vis+Auto, Img: Hint)
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .visible, autoplay: true),
                sentence: SectionConfiguration(text: .visible, audio: .visible, autoplay: true),
                image: .hint,
                back: BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible),
                navigation: .swipe,
                confirmation: .quiz,
                useTTSFallback: true,
                ttsVoiceGender: "female"
            )
        case .audioCards:
            // Word Audio Only (Text Hidden), Sentence Audio Only (Text Hidden), No Image
            return GameConfiguration(
                word: SectionConfiguration(text: .hidden, audio: .visible, autoplay: true),
                sentence: SectionConfiguration(text: .hidden, audio: .visible, autoplay: true),
                image: .hidden,
                back: BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible),
                navigation: .swipe,
                confirmation: .quiz,
                useTTSFallback: true
            )
        case .pictureCard:
            // Yes Word (No Audio), No Sentence (No Audio), Yes Image
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .hidden, autoplay: false),
                sentence: SectionConfiguration(text: .hidden, audio: .hidden, autoplay: false),
                image: .visible,
                back: BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible),
                navigation: .swipe,
                confirmation: .quiz,
                useTTSFallback: true,
                ttsVoiceGender: "female"
            )
        case .flashcard:
            // Yes Word (No Audio), No Sentence, No Image
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .hidden, autoplay: false),
                sentence: SectionConfiguration(text: .hidden, audio: .hidden, autoplay: false),
                image: .hidden,
                back: BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible),
                navigation: .swipe,
                confirmation: .quiz,
                useTTSFallback: true
            )
        case .story:
            // Story Mode Defaults: Full Immersion
            // Text: Visible, Audio: Visible, Image: Visible
            // Back (Translations): Hint (Hidden by default, user taps to see)
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .visible, autoplay: true),
                sentence: SectionConfiguration(text: .visible, audio: .visible, autoplay: true),
                image: .visible,
                back: BackConfiguration(translation: .hint, sentenceMeaning: .hint, studyLinks: .visible),
                navigation: .swipe,
                confirmation: .quiz,
                useTTSFallback: true,
                ttsVoiceGender: "female"
            )
        }
    }
}

// MARK: - JSON Layout Models

struct FrontConfiguration: Codable, Equatable {
    var word: SectionConfiguration
    var sentence: SectionConfiguration
    var image: ElementVisibility
}
    
struct LayoutPreset: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let navigation: NavigationStyle
    let autoNextDelay: TimeInterval?
    let confirmation: ConfirmationStyle
    let front: FrontConfiguration
    let back: BackConfiguration
    let useTTSFallback: Bool
    
    func toGameConfiguration() -> GameConfiguration {
        return GameConfiguration(
            word: front.word,
            sentence: front.sentence,
            image: front.image,
            back: back,
            navigation: navigation,
            autoNextDelay: autoNextDelay ?? 2.0,
            confirmation: confirmation,
            useTTSFallback: useTTSFallback
        )
    }
}

struct LayoutsContainer: Codable {
    let presets: [LayoutPreset]
}
