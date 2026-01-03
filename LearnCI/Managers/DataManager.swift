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
        var discoveredDecks: [DeckMetadata] = []
        let fm = FileManager.default
        
        // 1. Check local resources directory first (development)
        let localDataPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Data"
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
        
        // 2. Check Bundle robustly (Fallback/Production)
        let bundleURL = Bundle.main.bundleURL
        if let enumerator = fm.enumerator(at: bundleURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "json" {
                    let folderName = fileURL.deletingLastPathComponent().lastPathComponent
                    if let metadata = peekDeckMetadata(at: fileURL, folderName: folderName) {
                        if metadata.language == language && metadata.level == level {
                            // Ensure we don't add duplicates if already found in local path
                            if !discoveredDecks.contains(where: { $0.id == metadata.id }) {
                                discoveredDecks.append(metadata)
                            }
                        }
                    }
                }
            }
        }
        
        // Deduplicate just in case
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
            // We only need the basic info. If it's not a valid CardDeck JSON, it will fail here.
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
            // Ignore files that are not CardDecks
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
        
        if let url = resolveURL(folderName: metadata.folderName, filename: metadata.filename) {
            decodeAndSet(from: url, key: key, folderName: metadata.folderName)
        } else {
            self.errorMessage = "Could not find deck file for \(metadata.title)"
        }
    }

    // Helper to resolve the URL for a resource, trying local development path first, then bundle.
    private func resolveURL(folderName: String, filename: String) -> URL? {
        let fm = FileManager.default
        
        // 1. Try local dev path
        let localPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Data/\(folderName)/\(filename)"
        if fm.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }
        
        // 2. Try Bundle with subdirectory
        if let url = Bundle.main.url(forResource: (filename as NSString).deletingPathExtension, 
                                     withExtension: (filename as NSString).pathExtension, 
                                     subdirectory: "Resources/Data/\(folderName)") ?? 
                    Bundle.main.url(forResource: (filename as NSString).deletingPathExtension, 
                                     withExtension: (filename as NSString).pathExtension, 
                                     subdirectory: "Data/\(folderName)") {
            return url
        }
        
        // 3. Robust recursive search in bundle
        let bundleURL = Bundle.main.bundleURL
        if let enumerator = fm.enumerator(at: bundleURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == filename {
                    return fileURL
                }
            }
        }
        
        return nil
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
        
        guard let finalURL = resolveURL(folderName: metadata.folderName, filename: metadata.filename) else { return nil }
        
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

