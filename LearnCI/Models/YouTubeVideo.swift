import Foundation

struct YouTubeVideo: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let thumbnailURL: String
    let channelTitle: String
    let duration: String
    let publishedAt: Date
    
    // For direct video files (non-YouTube)
    var videoStreamURL: String?
    
    // Optional tagging for discovery
    var language: Language?
    var level: LearningLevel?
    
    var durationInSeconds: Int {
        parseDuration(duration)
    }
    
    var durationInMinutes: Int {
        durationInSeconds / 60
    }
    
    var isShort: Bool {
        durationInSeconds <= 61
    }
    
    private func parseDuration(_ iso8601: String) -> Int {
        var result = 0
        let components = iso8601.dropFirst(2) // Remove "PT"
        
        // Simple manual parsing for H, M, S
        // PT1H2M10S
        
        var currentNum = ""
        for char in components {
            if char.isNumber {
                currentNum.append(char)
            } else {
                let val = Int(currentNum) ?? 0
                currentNum = ""
                
                switch char {
                case "H": result += val * 3600
                case "M": result += val * 60
                case "S": result += val
                default: break
                }
            }
        }
        
        return result
    }
}

struct YouTubeChannel: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let thumbnailURL: String
    var isPlaylist: Bool = false // Default to false, mutable for manual setting
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case thumbnailURL = "thumbnail" // Assuming API mapping or internal mapping
        // Exclude isPlaylist from coding if it's not in JSON, or make it optional in keys
    }
    
    // Custom init to support default parameter
    init(id: String, title: String, thumbnailURL: String, isPlaylist: Bool = false) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.isPlaylist = isPlaylist
    }
    
    // Allow decoding without isPlaylist
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        
        // Handle title - might be nested in snippet->title in real API, 
        // but this struct might be a simplified internal model.
        // If it's used for API decoding, I should check YouTubeManager to see how it's decoded.
        // Assuming simple decoding for now based on existing fields.
        title = try container.decode(String.self, forKey: .title)
        thumbnailURL = try container.decode(String.self, forKey: .thumbnailURL)
        isPlaylist = false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(thumbnailURL, forKey: .thumbnailURL)
    }
}
