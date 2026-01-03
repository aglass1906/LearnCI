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
    
    // Discover decks and return them
    @discardableResult
    func discoverDecks(language: Language, level: LearningLevel) -> [DeckMetadata] {
        // 1. Check local resources directory first (development)
        let localDataPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Data"
        var discoveredDecks: [DeckMetadata] = []
        
        let fm = FileManager.default
        if fm.fileExists(atPath: localDataPath), let enumerator = fm.enumerator(atPath: localDataPath) {
            while let path = enumerator.nextObject() as? String {
                if path.hasSuffix(".json") {
                    let fullPath = (localDataPath as NSString).appendingPathComponent(path)
                    let fileURL = URL(fileURLWithPath: fullPath)
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
        
        let uniqueDecks = discoveredDecks.reduce(into: [DeckMetadata]()) { result, deck in
            if !result.contains(where: { $0.id == deck.id }) {
                result.append(deck)
            }
        }
        
        // Update the observable property on the main thread for the UI
        DispatchQueue.main.async {
            self.availableDecks = uniqueDecks
        }
        
        return uniqueDecks
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
        let decks = discoverDecks(language: language, level: level)
        
        if let first = decks.first {
            self.loadDeck(metadata: first)
        } else {
            self.loadedDeck = self.createFallbackDeck(language: language, level: level)
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
    
    // Fetch a deterministic Word of the Day based on language and level
    func fetchWordOfDay(language: Language, level: LearningLevel) async -> (card: LearningCard, folder: String)? {
        // Ensure discovery is done and get results immediately
        let decks = discoverDecks(language: language, level: level)
        
        guard let metadata = decks.first else { 
            print("Word of Day: No decks found for \(language.rawValue) \(level.rawValue)")
            return nil 
        }
        
        // Load the deck data
        let localPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Data/\(metadata.folderName)/\(metadata.filename)"
        let url = FileManager.default.fileExists(atPath: localPath) 
            ? URL(fileURLWithPath: localPath)
            : Bundle.main.url(forResource: metadata.folderName, withExtension: "json", subdirectory: "Data/\(metadata.folderName)")
            
        guard let finalURL = url else { return nil }
        
        do {
            let data = try Data(contentsOf: finalURL)
            let deck = try JSONDecoder().decode(CardDeck.self, from: data)
            guard !deck.cards.isEmpty else { return nil }
            
            // Seed based on current date
            let calendar = Calendar.current
            let day = calendar.ordinality(of: .day, in: .year, for: Date()) ?? 1
            let year = calendar.component(.year, from: Date())
            let seed = day + year
            
            let index = seed % deck.cards.count
            return (deck.cards[index], metadata.folderName)
        } catch {
            print("Error fetching word of day: \(error)")
            return nil
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

