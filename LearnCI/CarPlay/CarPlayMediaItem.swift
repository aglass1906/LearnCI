import Foundation

struct CarPlayMediaItem: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case story
        case podcast
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let url: URL
    let duration: TimeInterval
    let resumePosition: TimeInterval
    let date: Date
    var artworkURL: URL? = nil
}
