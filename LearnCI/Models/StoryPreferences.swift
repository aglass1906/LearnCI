import Foundation

struct StoryPreferences: Codable, Equatable {
    var humorLevel: Double = 0.5 // 0.0 (Funny) to 1.0 (Serious)
    var realismLevel: Double = 0.5 // 0.0 (Daily Life) to 1.0 (Sci-Fi)
    var genre: Genre = .mystery
    var dialogueAmount: DialogueAmount = .medium
    var voice: Voice = .alloy
    
    // New Advanced Options
    var coverArtStyle: CoverArtStyle = .storybook
    var storyLength: StoryLength = .medium
    var endingType: EndingType = .happy
    
    var protagonistName: String = ""
    var protagonistGender: Gender = .neutral
    
    var targetVocabulary: String = "" // Comma separated
    var grammarFocus: String = ""
    
    var audioSpeed: Double = 1.0
    var interactiveAudio: Bool = false
    var audioStyle: AudioStyle = .single

    var chapterQuote: Bool = false
    var chapterIntroInstructions: String = ""

    // Ambient sound — stored as the sound's id (e.g. "rain_night") or "none"
    var ambientSoundId: String = "none"
    var ambientVolume: Double = 0.3

    // No explicit CodingKeys needed. The property names match the Flutter JSON keys exactly (camelCase).
    // This ensures interactiveAudio and other fields are correctly parsed from Supabase.

    enum AudioStyle: String, Codable, CaseIterable, Identifiable {
        case single      = "single"
        case dramatized  = "dramatized"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .single:     return "Single Voice"
            case .dramatized: return "Dramatized"
            }
        }
    }

    enum Genre: String, Codable, CaseIterable, Identifiable {
        case romance = "Romance"
        case action = "Action"
        case mystery = "Mystery"
        case fantasy = "Fantasy"
        case sciFi = "Sci-Fi"
        case sliceOfLife = "Slice of Life"
        case comedy = "Comedy"
        case horror = "Horror"
        case historical = "Historical"
        
        var id: String { rawValue }
    }
    
    enum DialogueAmount: String, Codable, CaseIterable, Identifiable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        
        var id: String { rawValue }
    }
    
    enum Voice: String, Codable, CaseIterable, Identifiable {
        case alloy
        case echo
        case fable
        case onyx
        case nova
        case shimmer
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .alloy: return "Alloy (Neutral)"
            case .echo: return "Echo (Deep Male)"
            case .fable: return "Fable (British)"
            case .onyx: return "Onyx (Deep Authoritative)"
            case .nova: return "Nova (Energetic Female)"
            case .shimmer: return "Shimmer (Clear Female)"
            }
        }
    }
    
    enum CoverArtStyle: String, Codable, CaseIterable, Identifiable {
        case storybook = "Storybook"
        case realistic = "Realistic"
        case anime = "Anime"
        case watercolor = "Watercolor"
        case cyberpunk = "Cyberpunk"
        case pixelArt = "Pixel Art"
        case oilPainting = "Oil Painting"
        case claymation = "Claymation"
        
        var id: String { rawValue }
        
        nonisolated var promptDescription: String {
            switch self {
            case .storybook: return "storybook illustration, vibrant, charming"
            case .realistic: return "photorealistic, high detail, cinematic lighting"
            case .anime: return "anime style, manga art, vibrant colors"
            case .watercolor: return "watercolor painting, soft artistic style"
            case .cyberpunk: return "cyberpunk style, neon lights, futuristic"
            case .pixelArt: return "pixel art, 8-bit style"
            case .oilPainting: return "oil painting, textured, classic art"
            case .claymation: return "claymation style, plasticine texture"
            }
        }
    }
    
    enum StoryLength: String, Codable, CaseIterable, Identifiable {
        case short = "Short"
        case medium = "Medium"
        case long = "Long"
        case extended = "Extended"  // web pipeline value

        var id: String { rawValue }

        nonisolated var promptInstruction: String {
            switch self {
            case .short: return "Keep it under 150 words."
            case .medium: return "Keep it around 300 words."
            case .long: return "Keep it around 500 words."
            case .extended: return "Keep it around 800 words."
            }
        }
    }
    
    enum EndingType: String, Codable, CaseIterable, Identifiable {
        case happy = "Happy"
        case sad = "Sad"
        case cliffhanger = "Cliffhanger"
        case twist = "Twist"
        case moral = "Moral Lesson"
        
        var id: String { rawValue }
    }
    
    enum Gender: String, Codable, CaseIterable, Identifiable {
        case neutral = "Neutral"
        case male = "Male"
        case female = "Female"

        var id: String { rawValue }
    }

    // MARK: - Default Init
    init() {}

    // MARK: - Lenient Decoder
    // Decodes each enum field individually so an unknown value from the web
    // pipeline only drops that field to its default — not the entire struct.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        humorLevel              = (try? c.decode(Double.self,          forKey: .humorLevel))              ?? 0.5
        realismLevel            = (try? c.decode(Double.self,          forKey: .realismLevel))            ?? 0.5
        genre                   = (try? c.decode(Genre.self,           forKey: .genre))                   ?? .mystery
        dialogueAmount          = (try? c.decode(DialogueAmount.self,  forKey: .dialogueAmount))          ?? .medium
        voice                   = (try? c.decode(Voice.self,           forKey: .voice))                   ?? .alloy
        coverArtStyle           = (try? c.decode(CoverArtStyle.self,   forKey: .coverArtStyle))           ?? .storybook
        storyLength             = (try? c.decode(StoryLength.self,     forKey: .storyLength))             ?? .medium
        endingType              = (try? c.decode(EndingType.self,      forKey: .endingType))              ?? .happy
        protagonistName         = (try? c.decode(String.self,          forKey: .protagonistName))         ?? ""
        protagonistGender       = (try? c.decode(Gender.self,          forKey: .protagonistGender))       ?? .neutral
        targetVocabulary        = (try? c.decode(String.self,          forKey: .targetVocabulary))        ?? ""
        grammarFocus            = (try? c.decode(String.self,          forKey: .grammarFocus))            ?? ""
        audioSpeed              = (try? c.decode(Double.self,          forKey: .audioSpeed))              ?? 1.0
        interactiveAudio        = (try? c.decode(Bool.self,            forKey: .interactiveAudio))        ?? false
        audioStyle              = (try? c.decode(AudioStyle.self,      forKey: .audioStyle))              ?? .single
        chapterQuote            = (try? c.decode(Bool.self,            forKey: .chapterQuote))            ?? false
        chapterIntroInstructions = (try? c.decode(String.self,         forKey: .chapterIntroInstructions)) ?? ""
        ambientSoundId          = (try? c.decode(String.self,          forKey: .ambientSoundId))          ?? "none"
        ambientVolume           = (try? c.decode(Double.self,          forKey: .ambientVolume))           ?? 0.3
    }

    enum CodingKeys: String, CodingKey {
        case humorLevel, realismLevel, genre, dialogueAmount, voice
        case coverArtStyle, storyLength, endingType
        case protagonistName, protagonistGender
        case targetVocabulary, grammarFocus
        case audioSpeed, interactiveAudio, audioStyle
        case chapterQuote, chapterIntroInstructions
        case ambientSoundId, ambientVolume
    }
}
