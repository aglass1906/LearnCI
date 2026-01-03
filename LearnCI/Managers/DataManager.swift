import Foundation
import SwiftData

@Observable
class DataManager {
    var loadedDeck: CardDeck?
    var errorMessage: String?
    
    // Cache for loaded decks to avoid reloading
    private var deckCache: [String: CardDeck] = [:]
    
    // Load cards for a specific Language and Level
    func loadCards(language: Language, level: LearningLevel) {
        self.errorMessage = nil
        let key = "\(language.rawValue)_\(level.rawValue)"
        
        if let cached = deckCache[key] {
            self.loadedDeck = cached
            return
        }
        
        // Construct structured folder and filename
        // Example: spanish_super_beginner/spanish_super_beginner.json
        let langLower = language.rawValue.lowercased()
        let levelLower = level.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
        let folderName = "\(langLower)_\(levelLower)"
        let filename = "\(folderName).json"
        
        // Try Bundle lookup in the specific Data/{folderName} subdirectory
        if let fileURL = Bundle.main.url(forResource: folderName, withExtension: "json", subdirectory: "Data/\(folderName)") {
            decodeAndSet(from: fileURL, key: key, folderName: folderName)
        } else if let fileURL = Bundle.main.url(forResource: folderName, withExtension: "json") {
            // Fallback for flattened bundle
            decodeAndSet(from: fileURL, key: key, folderName: folderName)
        } else {
            // 2. Fallback: check exact path in our presumed local structure
            let deepPath = "Data/\(folderName)/\(filename)"
            let localPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/\(deepPath)"
            let localURL = URL(fileURLWithPath: localPath)
            
            if FileManager.default.fileExists(atPath: localPath) {
                 decodeAndSet(from: localURL, key: key, folderName: folderName)
            } else {
                 let err = "Error: Could not find card file at \(localPath). \n\nMake sure the folder \(folderName) exists in Resources/Data/"
                 print(err)
                 
                 DispatchQueue.main.async {
                     self.errorMessage = err
                     self.loadedDeck = self.createFallbackDeck(language: language, level: level)
                 }
            }
        }
    }
    
    private func decodeAndSet(from url: URL, key: String, folderName: String) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            var deck = try decoder.decode(CardDeck.self, from: data)
            deck.baseFolderName = folderName // Track which folder assets are in
            
            DispatchQueue.main.async {
                self.deckCache[key] = deck
                self.loadedDeck = deck
            }
        } catch {
            print("Error loading deck: \(error)")
            // If it's a decoding error, print more details
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("Key not found: \(key.stringValue) in \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("Value not found type: \(type) in \(context.codingPath)")
                case .typeMismatch(let type, let context):
                    print("Type mismatch type: \(type) in \(context.codingPath)")
                case .dataCorrupted(let context):
                     print("Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("Unknown decoding error")
                }
            }
            
            DispatchQueue.main.async {
                self.errorMessage = "Failed to decode JSON: \(error.localizedDescription)"
            }
        }
    }
    
    private func createFallbackDeck(language: Language, level: LearningLevel) -> CardDeck {
        return CardDeck(
            id: "fallback",
            language: language,
            level: level,
            title: "Fallback Deck (Files Not Found)",
            cards: [
                LearningCard(id: "f1", targetWord: "File Not Found", nativeTranslation: "Please add Info", sentenceTarget: "Add Resources folder to Xcode", sentenceNative: "See instructions", audioWordFile: nil, audioSentenceFile: nil)
            ]
        )
    }
}
