import Foundation

struct YouTubeVideo: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let thumbnailURL: String
    let channelTitle: String
    let duration: String
    let publishedAt: Date
    
    // Optional tagging for discovery
    var language: Language?
    var level: LearningLevel?
    
    var durationInMinutes: Int {
        // Parse ISO 8601 duration (PT1H30M15S) to minutes
        parseDuration(duration)
    }
    
    private func parseDuration(_ iso8601: String) -> Int {
        var result = 0
        let components = iso8601.dropFirst(2) // Remove "PT"
        
        if let hRange = components.range(of: "H") {
            if let hours = Int(components[..<hRange.lowerBound]) {
                result += hours * 60
            }
        }
        
        if let mRange = components.range(of: "M") {
            let start = components.range(of: "H")?.upperBound ?? components.startIndex
            if let minutes = Int(components[start..<mRange.lowerBound]) {
                result += minutes
            }
        }
        
        return result
    }
}

struct YouTubeChannel: Identifiable, Codable {
    let id: String
    let title: String
    let thumbnailURL: String
}
