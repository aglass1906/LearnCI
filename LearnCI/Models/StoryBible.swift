import Foundation

/// Subset of `bible_json` used on the learner preview screen.
struct StoryBible: Codable, Equatable {
    var logline: String?
    var storyOverview: String?

    enum CodingKeys: String, CodingKey {
        case logline
        case storyOverview
    }
}
