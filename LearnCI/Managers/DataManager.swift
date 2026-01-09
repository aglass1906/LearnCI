import Foundation
import SwiftData
import Observation
import UIKit

struct DeckMetadata: Identifiable, Equatable {
    let id: String
    let title: String
    let language: Language
    let level: LearningLevel
    let folderName: String
    let filename: String
    let supportedModes: Set<GameConfiguration.GameType>
    let gameConfiguration: [String: DeckDefaults]?
    let coverImage: String?
}

struct InspirationalQuote: Codable, Identifiable {
    var id: String { text }
    let text: String
    let author: String
}

@Observable
class DataManager {
    var loadedDeck: CardDeck?
    var errorMessage: String?
    var availableDecks: [DeckMetadata] = []
    var inspirationalQuotes: [InspirationalQuote] = []
    
    // UI State
    var isFullScreen: Bool = false
    
    // Cache for loaded decks to avoid reloading
    private var deckCache: [String: CardDeck] = [:]
    
    // Cache for resource URLs to avoid repeated recursive searches
    private var resourceURLCache: [String: URL] = [:]
    
    // Discover decks and return them
    @discardableResult
    func discoverDecks(language: Language, level: LearningLevel) -> [DeckMetadata] {
        let discovered = internalDiscover(language: language, level: level)
        
        // Deduplicate
        let uniqueDecks = discovered.reduce(into: [DeckMetadata]()) { result, deck in
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
    
    // Internal helper to reuse logic
    private func internalDiscover(language: Language?, level: LearningLevel?) -> [DeckMetadata] {
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
                        let langMatch = language == nil || metadata.language == language!
                        let levelMatch = level == nil || metadata.level == level!
                        
                        if langMatch && levelMatch {
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
                        let langMatch = language == nil || metadata.language == language!
                        let levelMatch = level == nil || metadata.level == level!
                        
                        if langMatch && levelMatch {
                            // Ensure we don't add duplicates if already found in local path
                            if !discoveredDecks.contains(where: { $0.id == metadata.id }) {
                                discoveredDecks.append(metadata)
                            }
                        }
                    }
                }
            }
        }
        
        return discoveredDecks
    }
    
    func findDeckMetadata(id: String) -> DeckMetadata? {
        // Scan everything (nil filters) and find by ID
        // Optimization: We could stop early, but reuse is cleaner for now.
        return internalDiscover(language: nil, level: nil).first { $0.id == id }
    }

    private func peekDeckMetadata(at url: URL, folderName: String) -> DeckMetadata? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            // We only need the basic info. If it's not a valid CardDeck JSON, it will fail here.
            let deck = try decoder.decode(CardDeck.self, from: data)
            let metadata = DeckMetadata(
                id: deck.id,
                title: deck.title,
                language: deck.language,
                level: deck.level,
                folderName: folderName,
                filename: url.lastPathComponent,
                supportedModes: deck.supportedModes ?? [.flashcards], // Default to flashcards
                gameConfiguration: deck.gameConfiguration,
                coverImage: deck.coverImage
            )
            // print("DEBUG: Loaded deck \(deck.id) from \(url.lastPathComponent) with modes: \(deck.supportedModes ?? [])")
            return metadata
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
        
        // Clear stale deck synchronously to prevent UI from reading old data during async load
        self.loadedDeck = nil
        
        if let url = resolveURL(folderName: metadata.folderName, filename: metadata.filename) {
            decodeAndSet(from: url, key: key, folderName: metadata.folderName)
        } else {
            self.errorMessage = "Could not find deck file for \(metadata.title)"
        }
    }

    // Helper to resolve the URL for a resource.
    // NOTE: For Assets.xcassets, we can't get a URL.
    // If this returns nil, UI should try UIImage(named: filename).
    func resolveURL(folderName: String?, filename: String) -> URL? {
        let cacheKey = "\(folderName ?? "root")/\(filename)"
        if let cached = resourceURLCache[cacheKey] {
            return cached
        }
        
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        
        // 2. Specific Bundle Subdirectories
        var subdirectories = [String]()
        if let folder = folderName {
            subdirectories.append("Resources/Data/\(folder)")
            subdirectories.append("Resources/Images/\(folder)")
            subdirectories.append("Data/\(folder)")
            subdirectories.append("Images/\(folder)")
        }
        subdirectories.append("Resources/Images")
        subdirectories.append("Resources/Data")
        subdirectories.append("Images")
        subdirectories.append("Data")
        
        for subDir in subdirectories {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subDir) {
                resourceURLCache[cacheKey] = url
                return url
            }
        }
        
        // 3. Fallback: Standard flattened bundle search
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            resourceURLCache[cacheKey] = url
            return url
        }
        
        // 4. Fallback: Recursive Search (Slowest, use as last resort)
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: Bundle.main.bundleURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.lowercased() == filename.lowercased() {
                    resourceURLCache[cacheKey] = fileURL
                    return fileURL
                }
            }
        }
        
        // If file not found in bundle, it might be in Assets.xcassets.
        return nil 
    }
    
    // NEW: Helper to load image transparently from either File or Asset
    func loadImage(folderName: String?, filename: String) -> UIImage? {
        // 1. Try file URL first
        if let url = resolveURL(folderName: folderName, filename: filename),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        
        // 2. Try Asset Catalog (stripping extension)
        let name = (filename as NSString).deletingPathExtension
        if let image = UIImage(named: name) {
            return image
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
    
    // Inspirational Quotes support
    func loadQuotes() {
        guard let url = resolveURL(folderName: nil, filename: "quotes.json") else {
            print("Quotes file not found")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            self.inspirationalQuotes = try decoder.decode([InspirationalQuote].self, from: data)
        } catch {
            print("Error loading quotes: \(error)")
        }
    }
    
    func getRandomQuote() -> InspirationalQuote? {
        if inspirationalQuotes.isEmpty {
            loadQuotes()
        }
        return inspirationalQuotes.randomElement()
    }
    
    private func createFallbackDeck(language: Language, level: LearningLevel) -> CardDeck {
        return CardDeck(
            id: "fallback",
            language: language,
            level: level,
            title: "No Decks Found",
            cards: [
                LearningCard(id: "f1", wordTarget: "Add Data", wordNative: "Please add JSON", sentenceTarget: "Add resources to Data folder", sentenceNative: "No matching decks found for \(language.rawValue) (\(level.rawValue))", audioWordFile: nil, audioSentenceFile: nil)
            ],
            baseFolderName: nil
        )
    }
}

