import Foundation
import SwiftUI

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
    var autoplay: Bool = false // Default to false for back of card
    
    enum CodingKeys: String, CodingKey {
        case translation, sentenceMeaning, studyLinks, autoplay
    }
    
    init(translation: ElementVisibility, sentenceMeaning: ElementVisibility, studyLinks: ElementVisibility, autoplay: Bool = false) {
        self.translation = translation
        self.sentenceMeaning = sentenceMeaning
        self.studyLinks = studyLinks
        self.autoplay = autoplay
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translation = try container.decode(ElementVisibility.self, forKey: .translation)
        sentenceMeaning = try container.decode(ElementVisibility.self, forKey: .sentenceMeaning)
        studyLinks = try container.decode(ElementVisibility.self, forKey: .studyLinks)
        autoplay = try container.decodeIfPresent(Bool.self, forKey: .autoplay) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(translation, forKey: .translation)
        try container.encode(sentenceMeaning, forKey: .sentenceMeaning)
        try container.encode(studyLinks, forKey: .studyLinks)
        try container.encode(autoplay, forKey: .autoplay)
    }
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
        case story = "Story Mode"
        case multipleChoice = "Multiple Choice"
        case audioCloze = "Listening Challenge"
        case linker = "Column Connect"
        case wordCrush = "Word Crush"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .flashcards: return "rectangle.stack.fill"
            case .memoryMatch: return "square.grid.2x2.fill"
            case .story: return "book.fill"
            case .multipleChoice: return "list.bullet.clipboard"
            case .audioCloze: return "headphones"
            case .linker: return "link"
            case .wordCrush: return "square.grid.3x3.fill"
            }
        }

        var description: String {
            switch self {
            case .flashcards: return "Classic study mode with spaced repetition."
            case .memoryMatch: return "Match words with their meanings."
            case .story: return "Read and listen to immersive stories."
            case .multipleChoice: return "Select the correct answer from 4 options."
            case .audioCloze: return "Listen and fill in the missing word."
            case .linker: return "Connect matching items between two columns."
            case .wordCrush: return "Match word pairs in a cascading grid."
            }
        }

        var imageName: String {
            switch self {
            case .flashcards: return "game_flashcards"
            case .memoryMatch: return "game_memory_match"
            case .story: return "game_story"
            case .multipleChoice: return "game_multiple_choice"
            case .audioCloze: return "game_audio_cloze"
            case .linker: return "game_linker"
            case .wordCrush: return "game_word_crush"
            }
        }

        var tileColor: Color {
            switch self {
            case .flashcards: return .blue
            case .memoryMatch: return .purple
            case .story: return .orange
            case .multipleChoice: return .green
            case .audioCloze: return .pink
            case .linker: return .cyan
            case .wordCrush: return .indigo
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
            case "multiplechoice": self = .multipleChoice
            case "wordcrush", "word crush", "word_crush": self = .wordCrush
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid GameType: \(rawString)")
            }
        }
    }
    
    enum OrderStrategy: String, Codable, CaseIterable, Identifiable {
        case sequential = "Ordered"
        case random = "Random"
        case smart = "Smart Queue"
        
        var id: String { rawValue }
    }
    
    enum LinkerTargetMode: String, Codable, CaseIterable, Identifiable {
        case english = "English Word"
        case native = "Native Word"
        
        var id: String { rawValue }
    }
    
    enum MemoryMatchMode: String, Codable, CaseIterable, Identifiable {
        case wordToWord = "Word to Word"
        case wordToPicture = "Word to Picture"
        case pictureToWord = "Picture to Word"

        var id: String { rawValue }
    }

    enum WordCrushGridSize: String, Codable, CaseIterable, Identifiable {
        case small = "Small"    // 3x4 = 12 tiles, 6 pairs
        case medium = "Medium"  // 4x5 = 20 tiles, 10 pairs
        case large = "Large"    // 5x6 = 30 tiles, 15 pairs

        var id: String { rawValue }

        var columns: Int {
            switch self {
            case .small: return 3
            case .medium: return 4
            case .large: return 5
            }
        }

        var rows: Int {
            switch self {
            case .small: return 4
            case .medium: return 5
            case .large: return 6
            }
        }
    }

    enum WordCrushDisplayMode: String, Codable, CaseIterable, Identifiable {
        case wordToWord = "Word \u{2194} Word"
        case wordToSentence = "Word \u{2194} Sentence"
        case imageToWord = "Image \u{2194} Word"

        var id: String { rawValue }
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
    
    var order: OrderStrategy = .smart
    var useTTSFallback: Bool = true
    var ttsRate: Float = 0.5
    var ttsVoiceGender: String = "female"
    
    var linkerTargetMode: LinkerTargetMode = .english
    var wordCrushGridSize: WordCrushGridSize = .small
    var wordCrushDisplayMode: WordCrushDisplayMode = .wordToWord

    enum CodingKeys: String, CodingKey {
        case gameType, word, sentence, image, back, isRandomOrder, order, useTTSFallback, ttsRate, ttsVoiceGender
        case navigation, autoNextDelay, confirmation, linkerTargetMode
        case wordCrushGridSize, wordCrushDisplayMode
    }
    
    init(gameType: GameType = .flashcards, 
         word: SectionConfiguration, 
         sentence: SectionConfiguration, 
         image: ElementVisibility, 
         back: BackConfiguration = BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible), 
         navigation: NavigationStyle = .swipe,
         autoNextDelay: TimeInterval = 2.0,
         confirmation: ConfirmationStyle = .quiz,
         order: OrderStrategy = .smart, 
         useTTSFallback: Bool = true, 
         ttsRate: Float = 0.5, 
         ttsVoiceGender: String = "female",
         linkerTargetMode: LinkerTargetMode = .english,
         wordCrushGridSize: WordCrushGridSize = .small,
         wordCrushDisplayMode: WordCrushDisplayMode = .wordToWord) {
        self.gameType = gameType
        self.word = word
        self.sentence = sentence
        self.image = image
        self.back = back
        self.navigation = navigation
        self.autoNextDelay = autoNextDelay
        self.confirmation = confirmation
        self.order = order
        self.useTTSFallback = useTTSFallback
        self.ttsRate = ttsRate
        self.ttsVoiceGender = ttsVoiceGender
        self.linkerTargetMode = linkerTargetMode
        self.wordCrushGridSize = wordCrushGridSize
        self.wordCrushDisplayMode = wordCrushDisplayMode
    }
    
    // Custom decoding to handle defaults for existing JSONs
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameType = try container.decode(GameType.self, forKey: .gameType)
        word = try container.decode(SectionConfiguration.self, forKey: .word)
        sentence = try container.decode(SectionConfiguration.self, forKey: .sentence)
        image = try container.decode(ElementVisibility.self, forKey: .image)
        back = try container.decode(BackConfiguration.self, forKey: .back)
        
        // Backward Compatibility: Check 'order' enum first, then fallback to 'isRandomOrder' bool
        if let strategy = try container.decodeIfPresent(OrderStrategy.self, forKey: .order) {
            order = strategy
        } else if let isRandom = try container.decodeIfPresent(Bool.self, forKey: .isRandomOrder) {
            order = isRandom ? .random : .sequential
        } else {
            order = .sequential
        }
        
        useTTSFallback = try container.decodeIfPresent(Bool.self, forKey: .useTTSFallback) ?? true
        ttsRate = try container.decodeIfPresent(Float.self, forKey: .ttsRate) ?? 0.5
        ttsVoiceGender = try container.decodeIfPresent(String.self, forKey: .ttsVoiceGender) ?? "female"
        
        // New Defaults
        navigation = try container.decodeIfPresent(NavigationStyle.self, forKey: .navigation) ?? .swipe
        autoNextDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .autoNextDelay) ?? 2.0
        confirmation = try container.decodeIfPresent(ConfirmationStyle.self, forKey: .confirmation) ?? .quiz
        linkerTargetMode = try container.decodeIfPresent(LinkerTargetMode.self, forKey: .linkerTargetMode) ?? .english
        wordCrushGridSize = try container.decodeIfPresent(WordCrushGridSize.self, forKey: .wordCrushGridSize) ?? .small
        wordCrushDisplayMode = try container.decodeIfPresent(WordCrushDisplayMode.self, forKey: .wordCrushDisplayMode) ?? .wordToWord
    }
    
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gameType, forKey: .gameType)
        try container.encode(word, forKey: .word)
        try container.encode(sentence, forKey: .sentence)
        try container.encode(image, forKey: .image)
        try container.encode(back, forKey: .back)
        try container.encode(order, forKey: .order)
        try container.encode(navigation, forKey: .navigation)
        try container.encode(autoNextDelay, forKey: .autoNextDelay)
        try container.encode(confirmation, forKey: .confirmation)
        try container.encode(useTTSFallback, forKey: .useTTSFallback)
        try container.encode(ttsRate, forKey: .ttsRate)
        try container.encode(ttsVoiceGender, forKey: .ttsVoiceGender)
        try container.encode(linkerTargetMode, forKey: .linkerTargetMode)
        try container.encode(wordCrushGridSize, forKey: .wordCrushGridSize)
        try container.encode(wordCrushDisplayMode, forKey: .wordCrushDisplayMode)

        // Backward Compatibility
        try container.encode(order == .random, forKey: .isRandomOrder)
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
