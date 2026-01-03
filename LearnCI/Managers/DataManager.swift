import Foundation
import SwiftData
import Observation

struct DeckMetadata: Identifiable, Equatable {
    let id: String
    let title: String
    let language: Language
    let level: LearningLevel
    let folderName: String
    let filename: String
}

@Observable
class DataManager {
    var loadedDeck: CardDeck?
    var errorMessage: String?
    var availableDecks: [DeckMetadata] = []
    
    // Cache for loaded decks to avoid reloading
    private var deckCache: [String: CardDeck] = [:]
    
    // Discover decks for a specific Language and Level
    func discoverDecks(language: Language, level: LearningLevel) {
        self.availableDecks = []
        
        // 1. Check local resources directory first (development)
        let localDataPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Data"
        var discoveredDecks: [DeckMetadata] = []
        
        if let enumerator = FileManager.default.enumerator(atPath: localDataPath) {
            while let path = enumerator.nextObject() as? String {
                // Look for any JSON file in subdirectories
                if path.hasSuffix(".json") {
                    let fullPath = (localDataPath as NSString).appendingPathComponent(path)
                    let fileURL = URL(fileURLWithPath: fullPath)
                    
                    // The folder name is the immediate parent directory of the JSON
                    let folderName = fileURL.deletingLastPathComponent().lastPathComponent
                    
                    if let metadata = peekDeckMetadata(at: fileURL, folderName: folderName) {
                        if metadata.language == language && metadata.level == level {
                            discoveredDecks.append(metadata)
                        }
                    }
                }
            }
        }
        
        // 2. Check Bundle (Fallback/Release)
        // In Bundle, we might need to be more specific if enumerator is restricted
        // For common naming patterns, we try a direct check if discovery was empty
        if discoveredDecks.isEmpty {
            let langLower = language.rawValue.lowercased()
            let levelLower = level.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
            let folderPrefix = "\(langLower)_\(levelLower)"
            
            if let url = Bundle.main.url(forResource: folderPrefix, withExtension: "json", subdirectory: "Data/\(folderPrefix)") {
                 if let deck = peekDeckMetadata(at: url, folderName: folderPrefix) {
                     discoveredDecks.append(deck)
                 }
            }
        }
        
        DispatchQueue.main.async {
            // Remove duplicates by ID
            self.availableDecks = discoveredDecks.reduce(into: [DeckMetadata]()) { result, deck in
                if !result.contains(where: { $0.id == deck.id }) {
                    result.append(deck)
                }
            }
        }
    }
    
    private func peekDeckMetadata(at url: URL, folderName: String) -> DeckMetadata? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            // We only need the basic info
            let deck = try decoder.decode(CardDeck.self, from: data)
            return DeckMetadata(
                id: deck.id,
                title: deck.title,
                language: deck.language,
                level: deck.level,
                folderName: folderName,
                filename: url.lastPathComponent
            )
        } catch {
            print("Error peeking at deck: \(error)")
            return nil
        }
    }
    
    // Load a specific deck
    func loadDeck(metadata: DeckMetadata) {
        self.errorMessage = nil
        let key = metadata.id
        
        if let cached = deckCache[key] {
            self.loadedDeck = cached
            return
        }
        
        // Try local path first
        let localPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Data/\(metadata.folderName)/\(metadata.filename)"
        let url = FileManager.default.fileExists(atPath: localPath) 
            ? URL(fileURLWithPath: localPath)
            : Bundle.main.url(forResource: metadata.folderName, withExtension: "json", subdirectory: "Data/\(metadata.folderName)")
            
        if let url = url {
            decodeAndSet(from: url, key: key, folderName: metadata.folderName)
        } else {
            self.errorMessage = "Could not find deck file for \(metadata.title)"
        }
    }

    // Legacy/Convenience: Load cards for a specific Language and Level (picks first available)
    func loadCards(language: Language, level: LearningLevel) {
        self.errorMessage = nil
        discoverDecks(language: language, level: level)
        
        // Usually called after discovery, but if called directly we need to wait or use fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let first = self.availableDecks.first {
                self.loadDeck(metadata: first)
            } else {
                self.loadedDeck = self.createFallbackDeck(language: language, level: level)
            }
        }
    }
    
    private func decodeAndSet(from url: URL, key: String, folderName: String) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            var deck = try decoder.decode(CardDeck.self, from: data)
            deck.baseFolderName = folderName
            
            DispatchQueue.main.async {
                self.deckCache[key] = deck
                self.loadedDeck = deck
            }
        } catch {
            print("Error loading deck: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to load \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }
    
    private func createFallbackDeck(language: Language, level: LearningLevel) -> CardDeck {
        return CardDeck(
            id: "fallback",
            language: language,
            level: level,
            title: "No Decks Found",
            cards: [
                LearningCard(id: "f1", targetWord: "Add Data", nativeTranslation: "Please add JSON", sentenceTarget: "Add resources to Data folder", sentenceNative: "No matching decks found for \(language.rawValue) (\(level.rawValue))", audioWordFile: nil, audioSentenceFile: nil)
            ],
            baseFolderName: nil
        )
    }
}

