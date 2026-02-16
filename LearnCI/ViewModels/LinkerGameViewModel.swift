
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
    
    // Current Batch State
    var currentBatch: [LearningCard] = []
    var batchErrors: [String: Bool] = [:] // mild tracking: did this card have ANY error in ANY round?
    
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
        
        startNextBatch()
    }
    
    var currentRound: LinkerRoundType {
        guard currentRoundIndex < rounds.count else { return .word }
        return rounds[currentRoundIndex]
    }
    
    // MARK: - Game Logic
    
    func startNextBatch() {
        // 1. Check if we have cards left
        if localQueue.isEmpty && config.order != .smart {
            isGameOver = true
            return
        }
        
        if config.order == .smart {
            // New Batch API: Request 5 cards (or fewer if queue is small)
            // Note: nextBatch returns cards without removing them from queue
            let batch = SmartSessionManager.shared.nextBatch(count: 5)
            
            // If we got nothing, refresh (shouldn't happen if queue has cards)
            if batch.isEmpty {
                refreshQueue()
                if localQueue.isEmpty {
                    currentBatch = []
                    isGameOver = true
                    return
                }
                // Fallback to local queue if SmartSession failure
                currentBatch = Array(localQueue.prefix(5))
            } else {
                currentBatch = batch
            }
        } else {
            // Standard/Random modes: maintain local queue behavior
            currentBatch = Array(localQueue.prefix(5))
            if currentBatch.isEmpty {
                isGameOver = true
                return
            }
        }
        
        selectedLeftId = nil
        batchErrors = [:] // Reset error tracking for new batch
        
        // Remove these from the queue so we don't pick them again immediately within this session loop
        // (For Smart Mode, GameView refetches into localQueue after grading, so this removal is temporary local state)
        if config.order != .smart {
            localQueue.removeFirst(min(5, localQueue.count))
        }
        
        // Start the rounds for this batch
        currentRoundIndex = 0
        startRound()
    }
    
    func refreshQueue() {
        // Only needed for non-smart modes or if smart queue exhausted
        if localQueue.isEmpty && config.order != .smart {
            localQueue = sessionCards.shuffled()
        }
    }
    
    func startRound() {
        guard currentRoundIndex < rounds.count else {
            finishBatch()
            return
        }
        
        let roundType = rounds[currentRoundIndex]
        prepareItems(for: roundType)
    }
    
    func finishBatch() {
        refreshQueue()
        
        // 3. Start Next
        startNextBatch()
    }
    
    func prepareItems(for roundType: LinkerRoundType) {
        // Use currentBatch
        leftItems = []
        rightItems = []
        
        for card in currentBatch {
            // Left Column
            let leftContent: LinkerItemType
            switch roundType {
            case .word:
                leftContent = .text(card.wordNative) // Spanish
            case .image:
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
            
            // Actual Left Content Logic (Fixing previous logic)
            // .word round: Left = Target(Spanish), Right = Native(English) or Target depending on config
            
            let actualLeftContent: LinkerItemType
            switch roundType {
            case .word:
                actualLeftContent = .text(card.wordTarget) // Target Language
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
        
        // Shuffle right items to make it a game
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
        // Mark error for this card
        batchErrors[rightItem.cardId] = true
        
        // Visual feedback
        if let rightIndex = rightItems.firstIndex(where: { $0.id == rightItem.id }) {
            rightItems[rightIndex].isError = true
            
            // Reset error after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if rightIndex < self.rightItems.count {
                    self.rightItems[rightIndex].isError = false
                }
            }
        }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.currentRoundIndex += 1
                self.startRound()
            }
        }
    }
    
    func restartGame() {
        // Reload queue
        refreshQueue()
        score = 0
        isGameOver = false
        startNextBatch()
    }
}
