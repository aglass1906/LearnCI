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
        
        var id: String { rawValue }
    }
    
    var word: SectionConfiguration
    var sentence: SectionConfiguration
    var image: ElementVisibility
    var back: BackConfiguration
    var isRandomOrder: Bool = false
    var useTTSFallback: Bool = true
    
    init(word: SectionConfiguration, sentence: SectionConfiguration, image: ElementVisibility, back: BackConfiguration = BackConfiguration(translation: .visible, sentenceMeaning: .visible, studyLinks: .visible), isRandomOrder: Bool = false, useTTSFallback: Bool = true) {
        self.word = word
        self.sentence = sentence
        self.image = image
        self.back = back
        self.isRandomOrder = isRandomOrder
        self.useTTSFallback = useTTSFallback
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
                useTTSFallback: true
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
                useTTSFallback: true
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
        }
    }
}
