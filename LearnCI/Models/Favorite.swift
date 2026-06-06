import Foundation
import SwiftData

enum FavoriteType: String, Codable, CaseIterable, Identifiable {
    case channel
    case website
    case youtube // New dedicated type
    case webScan // New: Scans page for videos
    case podcast
    case podcastEpisode
    case book // If we have book links
    case other
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .channel: return "play.rectangle.fill"
        case .youtube: return "play.circle.fill" 
        case .webScan: return "doc.text.viewfinder"
        case .podcast: return "headphones"
        case .podcastEpisode: return "waveform.circle.fill"
        case .book: return "book.fill"
        case .website, .other: return "globe"
        }
    }
}

@Model
final class Favorite {
    var id: UUID
    var userID: String
    var consumptionUrl: String // YouTube Channel ID or Link URL
    var typeRaw: String
    var title: String
    var author: String?
    var subtitle: String?
    var imageUrl: String?
    var sourceResourceId: String?
    var createdAt: Date
    var isSynced: Bool = false
    
    var type: FavoriteType {
        get { 
            // Try exact match first
            if let exact = FavoriteType(rawValue: typeRaw) {
                return exact
            }
            // Try lowercase match
            return FavoriteType.allCases.first { $0.rawValue.lowercased() == typeRaw.lowercased() } ?? .other
        }
        set { typeRaw = newValue.rawValue }
    }
    
    init(userID: String, consumptionUrl: String, type: FavoriteType, title: String, author: String? = nil, subtitle: String? = nil, imageUrl: String? = nil, sourceResourceId: String? = nil) {
        self.id = UUID()
        self.userID = userID
        self.consumptionUrl = consumptionUrl
        self.typeRaw = type.rawValue
        self.title = title
        self.author = author
        self.subtitle = subtitle
        self.imageUrl = imageUrl
        self.sourceResourceId = sourceResourceId
        self.createdAt = Date()
        self.isSynced = false
    }
}
