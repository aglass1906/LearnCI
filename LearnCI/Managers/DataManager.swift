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
        
        // Construct path/filename
        // note: Xcode "Copy Bundle Resources" usually flattens files unless added as folder references.
        // We renamed files to be unique: "{Language}_{LevelNoSpaces}.json"
        
        let levelPathName = level.rawValue.replacingOccurrences(of: " ", with: "")
        let filename = "\(language.rawValue)_\(levelPathName).json"
        
        // Try to load
        // First try finding it in the bundle (assuming flattened or just filename based lookup)
        if let fileURL = Bundle.main.url(forResource: filename, withExtension: nil) {
            decodeAndSet(from: fileURL, key: key)
        } else {
            // Fallback: check exact path in our presumed structure if Bundle lookup fails (e.g. if not flattened or in folders)
            // Or if running in a context where bundle isn't fully built like some previews/tests
            print("Warning: Could not find \(filename) in Bundle Main URL. Checking relative paths...")
            
            // Reconstruct the deep path just in case
            let deepPath = "Data/\(language.rawValue)/\(levelPathName)/\(filename)"
            let localPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/\(deepPath)"
            let localURL = URL(fileURLWithPath: localPath)
            
            if FileManager.default.fileExists(atPath: localPath) {
                 decodeAndSet(from: localURL, key: key)
            } else {
                 let err = "Error: Could not find card file at \(localPath). \n\nMake sure to add the 'Resources' folder to your Xcode project."
                 print(err)
                 
                 DispatchQueue.main.async {
                     self.errorMessage = err
                     // Provide fallback deck so UI isn't broken
                     self.loadedDeck = self.createFallbackDeck(language: language, level: level)
                 }
            }
        }
    }
    
    private func decodeAndSet(from url: URL, key: String) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let deck = try decoder.decode(CardDeck.self, from: data)
            
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
