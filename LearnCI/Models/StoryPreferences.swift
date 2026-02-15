import Foundation

struct StoryPreferences: Codable, Equatable {
    var humorLevel: Double = 0.5 // 0.0 (Funny) to 1.0 (Serious)
    var realismLevel: Double = 0.5 // 0.0 (Daily Life) to 1.0 (Sci-Fi)
    var genre: Genre = .mystery
    var dialogueAmount: DialogueAmount = .medium
    
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
}
