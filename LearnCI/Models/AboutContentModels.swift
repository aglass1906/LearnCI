import Foundation

// MARK: - Root Document
struct AboutPageDocument: Codable {
    let schemaVersion: String
    let page: PageMetadata
    let assets: [String: AssetDefinition]
    let sections: [PageSection]
}

// MARK: - Metadata
struct PageMetadata: Codable {
    let id: String
    let locale: String
    let title: String
    let theme: String?
}

// MARK: - Assets
struct AssetDefinition: Codable {
    let type: String // "image" or "icon"
    let src: String?
    let alt: String?
    let name: String? // for icons
}

// MARK: - Sections
struct PageSection: Codable, Identifiable {
    let id: String
    let header: SectionHeader?
    let layout: SectionLayout
    let blocks: [ContentBlock]
}

struct SectionHeader: Codable {
    let title: String
}

struct SectionLayout: Codable {
    let type: String // "stack", "cards", "steps", "accordion"
    let padding: String?
    let gap: String?
    let columns: Int?
}

// MARK: - Blocks (Polymorphic-ish)
enum BlockType: String, Codable {
    case hero
    case callout
    case card
    case step
    case faq
    case buttonRow
    case unknown
}

struct ContentBlock: Codable, Identifiable {
    let id = UUID() // Local ID for ForEach loops
    
    // Base properties
    let type: BlockType?
    
    // Properties common to multiple or specific blocks
    let title: String?
    let subtitle: String?
    let text: String?
    let body: String?
    let style: String?
    let media: MediaReference?
    let badges: [String]?
    let index: Int?
    let icon: MediaReference?
    let q: String?
    let a: String?
    let buttons: [ButtonDefinition]?
    
    enum CodingKeys: String, CodingKey {
        case type, title, subtitle, text, body, style, media, badges, index, icon, q, a, buttons
    }
    
    // Custom decoder to handle unknown block types gracefully without failing the whole decode
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try decoding the type; if it fails or is unrecognized, default to .unknown
        if let typeString = try? container.decode(String.self, forKey: .type),
           let parsedType = BlockType(rawValue: typeString) {
            self.type = parsedType
        } else {
            self.type = .unknown
        }
        
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.body = try container.decodeIfPresent(String.self, forKey: .body)
        self.style = try container.decodeIfPresent(String.self, forKey: .style)
        self.media = try container.decodeIfPresent(MediaReference.self, forKey: .media)
        self.badges = try container.decodeIfPresent([String].self, forKey: .badges)
        self.index = try container.decodeIfPresent(Int.self, forKey: .index)
        self.icon = try container.decodeIfPresent(MediaReference.self, forKey: .icon)
        self.q = try container.decodeIfPresent(String.self, forKey: .q)
        self.a = try container.decodeIfPresent(String.self, forKey: .a)
        self.buttons = try container.decodeIfPresent([ButtonDefinition].self, forKey: .buttons)
    }
}

struct MediaReference: Codable {
    let assetId: String
}

struct ButtonDefinition: Codable, Identifiable {
    let id = UUID()
    let label: String
    let action: ButtonAction
    let style: String?
    
    enum CodingKeys: String, CodingKey {
        case label, action, style
    }
}

struct ButtonAction: Codable {
    let type: String // e.g. "navigate"
    let route: String?
}
