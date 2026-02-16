
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
    private var localQueue: [LearningCard] // Mutable queue for processing
    
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
    
    init(deck: CardDeck, sessionCards: [LearningCard], config: GameConfiguration, sessionCardGoal: Int, onGrade: ((SmartSessionManager.Grade) -> Void)? = nil) {
        self.deck = deck
        self.sessionCards = sessionCards
        self.config = config
        self.sessionCardGoal = sessionCardGoal
        self.onGrade = onGrade
        
        // Initialize local queue with the provided session cards
        self.localQueue = sessionCards
        
        // Start the game
        startRound()
    }
    
    var currentRound: LinkerRoundType {
        guard currentRoundIndex < rounds.count else { return .word }
        return rounds[currentRoundIndex]
    }
    
    // MARK: - Game Logic
    
    func refreshQueue() {
        if localQueue.isEmpty {
            localQueue = sessionCards.shuffled()
        }
    }
    
    func startRound() {
        guard currentRoundIndex < rounds.count else {
            isGameOver = true
            return
        }
        
        // Reset Board
        leftItems = []
        rightItems = []
        selectedLeftId = nil
        batchErrors = [:]
        
        // Load Queue for this round
        // We use the full local queue for each round type (Word -> Image -> Audio)
        // This means we cycle through ALL cards for Word, then ALL for Image, etc.
        // If localQueue is empty (smart mode updates?), refresh it.
        if localQueue.isEmpty {
            refreshQueue()
        }
        roundQueue = localQueue.shuffled()
        
        // Initial Refill
        refillBoard()
    }
    
    func refillBoard() {
        // Target 5 rows
        while leftItems.count < 5 && !roundQueue.isEmpty {
            let card = roundQueue.removeFirst()
            addPair(for: card)
        }
        
        // If after refill we have 0 items, round is done
        if leftItems.isEmpty && roundQueue.isEmpty {
            finishRound()
        }
    }
    
    private func addPair(for card: LearningCard) {
        let roundType = self.currentRound
        
        // Left Item
        let leftContent: LinkerItemType
        switch roundType {
        case .word:
            leftContent = .text(card.wordTarget)
        case .image:
            if let media = card.mediaFile, !media.isEmpty {
                leftContent = .image(media)
            } else {
                leftContent = .text(card.wordTarget)
            }
        case .audio:
            if let audio = card.audioWordFile {
                leftContent = .audio(audio)
            } else {
                leftContent = .text(card.wordTarget)
            }
        }
        
        // Right Item
        let rightContent: LinkerItemType
        switch config.linkerTargetMode {
        case .native:
            rightContent = .text(card.wordTarget)
        case .english:
            rightContent = .text(card.wordNative)
        }
        
        let leftItem = LinkerItem(cardId: card.id, content: leftContent)
        let rightItem = LinkerItem(cardId: card.id, content: rightContent)
        
        // Append Left (keeps stable order usually, or we could insert random?)
        // Appending effectively slides it in at the bottom.
        leftItems.append(leftItem)
        
        // Insert Right at random position to prevent alignment hints
        if rightItems.isEmpty {
            rightItems.append(rightItem)
        } else {
            let randomIndex = Int.random(in: 0...rightItems.count)
            rightItems.insert(rightItem, at: randomIndex)
        }
    }
    
    func finishRound() {
        // Delay before next round
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.currentRoundIndex += 1
            self.startRound()
        }
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
            playAudio(for: item)
        }
    }
    
    func selectRight(_ item: LinkerItem) {
        // guard !item.isMatched else { return } // Should be irrelevant as we remove matched items now
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
        // 1. Mark matched (optional, for animation)
        // With streaming, we want to REMOVE them.
        // Let's animate removal if possible.
        
        // Find indices
        guard let rightIndex = rightItems.firstIndex(where: { $0.id == rightItem.id }) else { return }
        
        // Increment Score
        score += 1
        selectedLeftId = nil
        
        // Remove items
        // Use withAnimation in View? Or trigger it here?
        // Observable arrays usually trigger view updates.
        // We'll trust Swift UI transitions for now.
        
        withAnimation(.easeOut(duration: 0.3)) {
            leftItems.remove(at: leftIndex)
            rightItems.remove(at: rightIndex)
        }
        
        // Refill
        // Delay slightly to allow exit animation? Or refill immediately?
        // Immediate refill feels more "streaming".
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
            
            // Reset error after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if rightIndex < self.rightItems.count {
                    withAnimation {
                         self.rightItems[rightIndex].isError = false
                    }
                }
            }
        }
    }
    
    private func playAudio(for item: LinkerItem) {
        guard let card = deck.cards.first(where: { $0.id == item.cardId }) else { return }
        
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
