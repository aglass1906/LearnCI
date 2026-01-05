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
    var isRandomOrder: Bool = false
    
    init(word: SectionConfiguration, sentence: SectionConfiguration, image: ElementVisibility, isRandomOrder: Bool = false) {
        self.word = word
        self.sentence = sentence
        self.image = image
        self.isRandomOrder = isRandomOrder
    }
    
    static func from(preset: Preset) -> GameConfiguration {
        switch preset {
        case .customize, .inputFocus:
            // Input Focus default (Word: Vis+Auto, Sent: Vis+Auto, Img: Hint)
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .visible),
                sentence: SectionConfiguration(text: .visible, audio: .visible),
                image: .hint
            )
        case .audioCards:
            // Word Audio Only (Text Hidden), Sentence Audio Only (Text Hidden), No Image
            return GameConfiguration(
                word: SectionConfiguration(text: .hidden, audio: .visible),
                sentence: SectionConfiguration(text: .hidden, audio: .visible),
                image: .hidden
            )
        case .pictureCard:
            // Yes Word (No Audio), No Sentence (No Audio), Yes Image
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .hidden),
                sentence: SectionConfiguration(text: .hidden, audio: .hidden),
                image: .visible
            )
        case .flashcard:
            // Yes Word (No Audio), No Sentence, No Image
            return GameConfiguration(
                word: SectionConfiguration(text: .visible, audio: .hidden),
                sentence: SectionConfiguration(text: .hidden, audio: .hidden),
                image: .hidden
            )
        }
    }
}
