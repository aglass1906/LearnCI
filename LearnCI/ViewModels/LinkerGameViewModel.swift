
import SwiftUI
import AVFoundation

enum LinkerRoundType {
    case word
    case image
    case audio
    
    var title: String {
        switch self {
        case .word: return "Word Match"
        case .image: return "Image Match"
        case .audio: return "Audio Match"
        }
    }
}

enum LinkerItemType: Equatable {
    case text(String)
    case image(String)
    case audio(String)
    
    var isAudio: Bool {
        if case .audio = self { return true }
        return false
    }
}

struct LinkerItem: Identifiable, Equatable {
    let id = UUID()
    let cardId: String
    let content: LinkerItemType
    var isMatched: Bool = false
    var isSelected: Bool = false
    var isError: Bool = false
    
    // Helper for debugging
    var debugDescription: String {
        return "\(cardId) - \(content)"
    }
}

@Observable
class LinkerGameViewModel {
    var deck: CardDeck
    var config: GameConfiguration
    var sessionCardGoal: Int
    
    // Game State
    var currentRoundIndex = 0
    var rounds: [LinkerRoundType] = [.word, .image, .audio]
    var isGameOver = false
    var score = 0
    
    // Current Round Data
    var leftItems: [LinkerItem] = []
    var rightItems: [LinkerItem] = []
    
    // Selection State
    var selectedLeftId: UUID?
    
    // Dependencies
    var audioManager: AudioManager?
    
    init(deck: CardDeck, config: GameConfiguration, sessionCardGoal: Int) {
        self.deck = deck
        self.config = config
        self.sessionCardGoal = sessionCardGoal
        startRound()
    }
    
    var currentRound: LinkerRoundType {
        guard currentRoundIndex < rounds.count else { return .word }
        return rounds[currentRoundIndex]
    }
    
    // MARK: - Game Logic
    
    func startRound() {
        guard currentRoundIndex < rounds.count else {
            isGameOver = true
            return
        }
        
        let roundType = rounds[currentRoundIndex]
        prepareItems(for: roundType)
    }
    
    func prepareItems(for roundType: LinkerRoundType) {
        // Select cards for this round based on sessionCardGoal
        let cardCount = min(sessionCardGoal, deck.cards.count)
        let roundCards = Array(deck.cards.shuffled().prefix(cardCount))
        
        leftItems = []
        rightItems = []
        
        for card in roundCards {
            // Left Column
            let leftContent: LinkerItemType
            switch roundType {
            case .word:
                leftContent = .text(card.wordNative) // Spanish
            case .image:
                // Use image if available, otherwise fallback to text with a placeholder indication or skip?
                // For now, if no image, specific logic might be needed. 
                // Assuming cards have images for Image round or fallback to word.
                if let media = card.mediaFile, !media.isEmpty {
                    leftContent = .image(media)
                } else {
                    leftContent = .text(card.wordNative) // Fallback
                }
            case .audio:
                if let audio = card.audioWordFile {
                    leftContent = .audio(audio)
                } else {
                    leftContent = .text(card.wordNative) // Fallback
                }
            }
            
            // Right Column
            let rightContent: LinkerItemType
            
            // "Native Word" in UI corresponds to matching Target(Left) to Target(Right) (e.g. Spanish-Spanish)
            // "English Word" corresponds to Target(Left) to Native(Right) (e.g. Spanish-English)
            switch config.linkerTargetMode {
            case .native:
                rightContent = .text(card.wordTarget)
            case .english:
                rightContent = .text(card.wordNative)
            } 
            
            // LEFT SIDE: Target (Spanish)
            // Wait, in my previous thought I said "Left: Target (Spanish)". 
            // `card.wordTarget` is Spanish.
            // `card.wordNative` is English.
            // So for .word round: Left = wordTarget, Right = wordNative.
            
            let actualLeftContent: LinkerItemType
            switch roundType {
            case .word:
                actualLeftContent = .text(card.wordTarget)
            case .image:
                 if let media = card.mediaFile, !media.isEmpty {
                    actualLeftContent = .image(media)
                } else {
                    actualLeftContent = .text(card.wordTarget)
                }
            case .audio:
                if let audio = card.audioWordFile {
                    actualLeftContent = .audio(audio)
                } else {
                    actualLeftContent = .text(card.wordTarget) 
                }
            }
            
            leftItems.append(LinkerItem(cardId: card.id, content: actualLeftContent))
            rightItems.append(LinkerItem(cardId: card.id, content: rightContent))
        }
        
        // Shuffle right items
        rightItems.shuffle()
    }
    
    // MARK: - User Interaction
    
    func selectLeft(_ item: LinkerItem) {
        // If already matched, ignore
        guard !item.isMatched else { return }
        
        // Deselect previous
        if let previousId = selectedLeftId, let index = leftItems.firstIndex(where: { $0.id == previousId }) {
            leftItems[index].isSelected = false
        }
        
        // Select new
        if let index = leftItems.firstIndex(where: { $0.id == item.id }) {
            leftItems[index].isSelected = true
            selectedLeftId = item.id
            
            // Play audio if it's an audio item or if we want to play audio on tap for words too
            // Request says: "Tap a word on the left (plays the audio)"
            playAudio(for: item)
        }
    }
    
    func selectRight(_ item: LinkerItem) {
        guard !item.isMatched else { return }
        guard let validSelectedId = selectedLeftId else { return }
        
        // Find left item
        guard let leftIndex = leftItems.firstIndex(where: { $0.id == validSelectedId }) else { return }
        let leftItem = leftItems[leftIndex]
        
        // Check Match
        if leftItem.cardId == item.cardId {
            // MATCH!
            handleMatch(leftIndex: leftIndex, rightItem: item)
        } else {
            // MISMATCH
            handleMismatch(rightItem: item)
        }
    }
    
    private func handleMatch(leftIndex: Int, rightItem: LinkerItem) {
        // 1. Mark Left as matched
        leftItems[leftIndex].isMatched = true
        leftItems[leftIndex].isSelected = false
        
        // 2. Mark Right as matched
        if let rightIndex = rightItems.firstIndex(where: { $0.id == rightItem.id }) {
            rightItems[rightIndex].isMatched = true
        }
        
        selectedLeftId = nil
        score += 1
        
        // Check round completion
        checkForRoundCompletion()
    }
    
    private func handleMismatch(rightItem: LinkerItem) {
        // Visual feedback for error could be handled here or in view
        // For simplicity, just deselect left
        
        // Ideally show error state on right item for a moment
        if let rightIndex = rightItems.firstIndex(where: { $0.id == rightItem.id }) {
            rightItems[rightIndex].isError = true
            
            // Reset error after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if rightIndex < self.rightItems.count {
                    self.rightItems[rightIndex].isError = false
                }
            }
        }
        
        // Provide haptic feedback?
    }
    
    private func playAudio(for item: LinkerItem) {
        // Find the card
        guard let card = deck.cards.first(where: { $0.id == item.cardId }) else { return }
        
        // Play audio with TTS fallback
        if let audioFile = card.audioWordFile {
            audioManager?.playAudio(
                named: audioFile,
                folderName: deck.baseFolderName,
                text: card.wordTarget,
                language: deck.language,
                useFallback: true,
                ttsRate: config.ttsRate
            )
        } else {
            // No audio file, use TTS directly
            audioManager?.speak(
                text: card.wordTarget,
                language: deck.language,
                gender: config.ttsVoiceGender,
                rate: config.ttsRate
            )
        }
    }
    
    private func checkForRoundCompletion() {
        let allMatched = leftItems.allSatisfy { $0.isMatched }
        if allMatched {
            // Delay before next round
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.currentRoundIndex += 1
                self.startRound()
            }
        }
    }
    
    func restartGame() {
        currentRoundIndex = 0
        score = 0
        isGameOver = false
        startRound()
    }
}
