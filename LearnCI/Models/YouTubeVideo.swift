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

struct YouTubeChannel: Identifiable, Codable {
    let id: String
    let title: String
    let thumbnailURL: String
}
