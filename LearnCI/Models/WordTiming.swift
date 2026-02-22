import Foundation

/// Represents the precise start and end times for a specific word in an audio file.
/// Used to drive UI highlighting during audio playback.
struct WordTiming: Codable, Equatable {
    let word: String
    let start: Double
    let end: Double
}
