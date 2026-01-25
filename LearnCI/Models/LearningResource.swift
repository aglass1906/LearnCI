import Foundation

enum ResourceType: String, Codable, CaseIterable, Identifiable {
    case podcast
    case youtube
    case book
    case website
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .podcast: return "headphones"
        case .youtube: return "play.rectangle.fill"
        case .book: return "book.fill"
        case .website: return "globe"
        }
    }
    
    var displayName: String {
        switch self {
        case .podcast: return "Podcast"
        case .youtube: return "YouTube"
        case .book: return "Book"
        case .website: return "Website"
        }
    }
}

struct LearningResource: Codable, Identifiable {
    let id: UUID
    let type: ResourceType
    let title: String
    let author: String
    let description: String
    let coverImageUrl: String?
    let mainUrl: String
    let feedUrl: String?
    let tags: [String]
    let language: String // e.g., "es", "jp"
    let dialect: String? // e.g., "Spain", "Mexico"
    let difficulty: String // e.g., "Beginner", "CEFR A2"
    let avgRating: Double?
    let notes: String?
    let isFeatured: Bool
    let status: String // 'draft', 'published', 'rejected'
    let resourceLinks: [ResourceLink]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case author
        case description
        case coverImageUrl = "cover_image_url"
        case mainUrl = "main_url"
        case feedUrl = "feed_url"
        case tags
        case language
        case dialect
        case difficulty
        case avgRating = "avg_rating"
        case notes
        case isFeatured = "is_featured"
        case status
        case resourceLinks = "resource_links"
    }
}

struct ResourceLink: Codable, Identifiable {
    var id: String { url + label }
    let type: String
    let url: String
    let label: String
    let order: Int?
    let isActive: Bool?
    
    enum CodingKeys: String, CodingKey {
        case type
        case url
        case label
        case order
        case isActive
    }
}
