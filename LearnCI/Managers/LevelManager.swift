import Foundation
import Observation

// MARK: - Taxonomy Models
struct LanguageTaxonomy: Codable {
    let languages: [String: String]
    let levels: [String: LevelDefinition]
    let scales: [String: ScaleDefinition]
}

struct LevelDefinition: Codable {
    let `default`: String
    let CEFR: String
    let JLPT: String
}

struct ScaleDefinition: Codable {
    let name: String
    let appliesTo: ScaleApplicability
    
    enum ScaleApplicability: Codable {
        case all
        case specific([String])
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self), str == "all" {
                self = .all
            } else {
                let list = try container.decode([String].self)
                self = .specific(list)
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .all: try container.encode("all")
            case .specific(let list): try container.encode(list)
            }
        }
    }
}

enum ProficiencyScale: String, CaseIterable, Identifiable {
    case simple = "Simple"
    case cefr = "CEFR"
    case jlpt = "JLPT"
    
    var id: String { self.rawValue }
}

@Observable
class LevelManager {
    static let shared = LevelManager()
    
    private var taxonomy: LanguageTaxonomy?
    private var isLoaded = false
    
    init() {
        loadTaxonomy()
    }
    
    private func loadTaxonomy() {
        guard let url = Bundle.main.url(forResource: "language_taxonomy", withExtension: "json", subdirectory: "Resources/Data") ??
              Bundle.main.url(forResource: "language_taxonomy", withExtension: "json") else {
            print("LevelManager: Could not find language_taxonomy.json")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            self.taxonomy = try JSONDecoder().decode(LanguageTaxonomy.self, from: data)
            self.isLoaded = true
            print("LevelManager: Taxonomy loaded successfully")
        } catch {
            print("LevelManager: Failed to load taxonomy: \(error)")
        }
    }
    
    // Convert Legacy String Level to Normalized Int (1-6)
    func normalize(_ level: LearningLevel?) -> Int {
        guard let level = level else { return 1 } // Default if missing
        switch level {
        case .superBeginner: return 1
        case .beginner: return 2
        case .intermediate: return 3
        case .advanced: return 5 // Default to C1/Advanced. Level 6 is Mastery.
        }
    }
    
    // Get display string for a deck based on preference
    func displayString(for deck: DeckMetadata, preferredScale: ProficiencyScale) -> String {
        let level = deck.proficiencyLevel ?? normalize(deck.level)
        return displayString(level: level, language: deck.language.code, preferredScale: preferredScale)
    }
    
    // Core display logic
    func displayString(level: Int, language: String, preferredScale: ProficiencyScale) -> String {
        guard let taxonomy = taxonomy,
              let levelDef = taxonomy.levels[String(level)] else {
            return "Lvl \(level)" // Fallback if taxonomy missing
        }
        
        // Check if scale applies to this language
        let scaleDef = taxonomy.scales[preferredScale.rawValue]
        let applies: Bool
        
        if let def = scaleDef {
            switch def.appliesTo {
            case .all: applies = true
            case .specific(let langs): applies = langs.contains(language)
            }
        } else {
            applies = false
        }
        
        if !applies {
            // Fallback to "Simple" (Default) if preferred scale doesn't apply
            return levelDef.default
        }
        
        // Return specifics
        switch preferredScale {
        case .simple: return levelDef.default
        case .cefr: return levelDef.CEFR
        case .jlpt: return levelDef.JLPT
        }
    }
    
    // Helper to get all language names
    func languageName(for code: String) -> String {
        return taxonomy?.languages[code] ?? code.uppercased()
    }
}
