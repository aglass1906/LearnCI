
// MARK: - Linker Game ViewModel
/// Manages state and logic for the Column Connect (Linker) game.
/// This game has 3 rounds: Word-Word, Image-Word, and Audio-Word matching.
///
/// Session Settings Used:
/// - sessionCardGoal: Number of cards to use per round
/// - order: Card ordering (Sequential/Random/Smart)
/// - useTTSFallback: Enable TTS when audio files are missing
/// - ttsRate: Speech playback speed
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

    var isImage: Bool {
        if case .image = self { return true }
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
    var sessionCardGoal: Int // Total goal for the session
    
    // SRS / Queue State
    var sessionCards: [LearningCard] // The full queue passed from GameView
    
    // Round Queue State (Streaming)
    var roundQueue: [LearningCard] = []
    var batchErrors: [String: Bool] = [:] // mild tracking
    
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
    var onGrade: ((SmartSessionManager.Grade) -> Void)?
    var onMatchFound: (() -> Void)?
    
    init(deck: CardDeck, sessionCards: [LearningCard], config: GameConfiguration, sessionCardGoal: Int, onGrade: ((SmartSessionManager.Grade) -> Void)? = nil) {
        self.deck = deck
        self.sessionCards = sessionCards
        self.config = config
        self.sessionCardGoal = sessionCardGoal
        self.onGrade = onGrade

        // Start the game
        startRound()
    }
    
    func startRound() {
        guard currentRoundIndex < rounds.count else { return }
        let currentRound = rounds[currentRoundIndex]
        
        // Populate roundQueue with ALL session cards for this round
        roundQueue = sessionCards.shuffled() // Shuffle for randomness
        
        // Clear board
        leftItems.removeAll()
        rightItems.removeAll()
        
        // Initial Refill
        refillBoard()
    }
    
    private func refillBoard() {
        // Target visible count is 5
        // Using a while loop to fill up to 5 items
        while leftItems.count < 5 && !roundQueue.isEmpty {
            let card = roundQueue.removeFirst()
            let currentRound = rounds[currentRoundIndex]
            
            // Create Left Item
            let leftContent: LinkerItemType
            switch currentRound {
            case .word:
                leftContent = .text(card.wordNative) // Source language
            case .image:
                leftContent = .image(card.mediaFile ?? "placeholder") 
            case .audio:
                leftContent = .audio(card.audioWordFile ?? "audio_placeholder")
            }
            let leftItem = LinkerItem(cardId: card.id, content: leftContent)
            
            // Create Right Item (Target)
            let rightItem = LinkerItem(cardId: card.id, content: .text(card.wordTarget))
            
            leftItems.append(leftItem)
            rightItems.append(rightItem)
        }
        
        // Shuffle right column each refill to ensure randomness
        if !rightItems.isEmpty {
             rightItems.shuffle()
        }
        
        // Check for round completion if empty
        if leftItems.isEmpty && roundQueue.isEmpty {
           completeRound()
        }
    }
    
    private func completeRound() {
        if currentRoundIndex < rounds.count - 1 {
            currentRoundIndex += 1
            // Delay for transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startRound()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isGameOver = true
            }
        }
    }

    func selectLeft(_ item: LinkerItem) {
        if let selected = selectedLeftId, selected == item.id {
             selectedLeftId = nil // Deselect
             return
        }
        selectedLeftId = item.id

        // Play word audio for all round types
        playAudio(for: item)
    }
    
    func selectRight(_ item: LinkerItem) {
        // Play word audio for the tapped right-column card
        playAudio(for: item)

        guard let leftId = selectedLeftId, let leftItem = leftItems.first(where: { $0.id == leftId }) else { return }

        if leftItem.cardId == item.cardId {
            // Find index of left item
            if let index = leftItems.firstIndex(of: leftItem) {
                 handleMatch(leftIndex: index, rightItem: item)
            }
        } else {
            handleMismatch(rightItem: item)
        }
    }
    
    func refreshQueue() {
         // Reset for restart
         // We reuse the initialized sessionCards
         roundQueue = []
         leftItems = []
         rightItems = []
         batchErrors = [:]
    }
    
    var currentRound: LinkerRoundType {
        if currentRoundIndex < rounds.count {
            return rounds[currentRoundIndex]
        }
        return .word
    }

    private func handleMatch(leftIndex: Int, rightItem: LinkerItem) {
        // Find indices
        guard let rightIndex = rightItems.firstIndex(where: { $0.id == rightItem.id }) else { return }
        
        // Increment Score
        score += 1
        selectedLeftId = nil
        
        // Remove items
        withAnimation(.easeOut(duration: 0.3)) {
            leftItems.remove(at: leftIndex)
            rightItems.remove(at: rightIndex)
        }

        // GRADING & PROGRESS
        // Only grade and count progress if this is the FINAL round type (Audio)
        // or if we only have 1 round type configured.
        // Assuming [.word, .image, .audio] order.
        if currentRound == rounds.last {
            // Find the card object
            if let card = sessionCards.first(where: { $0.id == rightItem.cardId }) {
                // Determine grade
                let grade: SmartSessionManager.Grade = batchErrors[card.id] == true ? .hard : .good
                
                // Report to SmartSessionManager
                SmartSessionManager.shared.completeBatch(cards: [card], grade: grade)
                
                // Notify UI (increments learned count)
                onMatchFound?()
            }
        }
        
        // Refill
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring()) {
                self.refillBoard()
            }
        }
    }
    
    private func handleMismatch(rightItem: LinkerItem) {
        // Mark error for this card
        batchErrors[rightItem.cardId] = true
        
        // Visual feedback
        if let rightIndex = rightItems.firstIndex(where: { $0.id == rightItem.id }) {
            withAnimation {
                rightItems[rightIndex].isError = true
            }
            
            // Reset error after delay (look up by ID since index may be stale)
            let itemId = rightItem.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let idx = self.rightItems.firstIndex(where: { $0.id == itemId }) {
                    withAnimation {
                        self.rightItems[idx].isError = false
                    }
                }
            }
        }
    }
    
    private func playAudio(for item: LinkerItem) {
        guard let card = sessionCards.first(where: { $0.id == item.cardId })
                ?? deck.cards.first(where: { $0.id == item.cardId }) else { return }
        
        if let audioFile = card.audioWordFile {
            audioManager?.playAudio(
                named: audioFile,
                folderName: deck.baseFolderName,
                text: card.wordTarget,
                language: deck.language,
                useFallback: config.useTTSFallback,
                ttsRate: config.ttsRate
            )
        } else {
            audioManager?.speak(
                text: card.wordTarget,
                language: deck.language,
                gender: config.ttsVoiceGender,
                rate: config.ttsRate
            )
        }
    }
    
    func restartGame() {
        refreshQueue()
        score = 0
        isGameOver = false
        currentRoundIndex = 0
        startRound()
    }
}
