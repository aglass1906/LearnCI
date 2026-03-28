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
        
        var id: String { rawValue }
        
        nonisolated var promptInstruction: String {
            switch self {
            case .short: return "Keep it under 150 words."
            case .medium: return "Keep it around 300 words."
            case .long: return "Keep it around 500 words."
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
}
