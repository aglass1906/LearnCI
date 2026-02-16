import SwiftUI
import Combine



enum MemoryCardType {
    case target
    case native
}

struct MemoryCard: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let associatedCardId: String
    let type: MemoryCardType
    var isFlipped: Bool = false
    var isMatched: Bool = false
    
    // For audio playback
    var audioFile: String?
    
    // For visual representation
    var mediaFile: String?
}

@Observable
class MemoryGameViewModel {
    var cards: [MemoryCard] = []
    var isProcessing: Bool = false
    var matchedPairs: Int = 0
    var totalPairs: Int = 0
    var moves: Int = 0
    var matchMode: GameConfiguration.MemoryMatchMode
    
    // Track current learning cards to grade them at the end of the round
    private var currentBatch: [LearningCard] = []
    
    var onGameComplete: (() -> Void)?
    var onMatchFound: (() -> Void)?
    var onMistake: (() -> Void)?
    var playAudio: ((String?, String) -> Void)?
    
    init(matchMode: GameConfiguration.MemoryMatchMode = .pictureToWord) {
        self.matchMode = matchMode
    }
    
    func startSession() {
        startNextRound()
    }
    
    private func startNextRound() {
        // Pull next batch of 8 cards (for 4x4 grid)
        let nextBatch = SmartSessionManager.shared.nextBatch(count: 8)
        
        if nextBatch.isEmpty {
            onGameComplete?()
            return
        }
        
        setupRound(with: nextBatch)
    }
    
    private func setupRound(with learningCards: [LearningCard]) {
        self.currentBatch = learningCards
        totalPairs = learningCards.count
        matchedPairs = 0
        // Don't reset moves if we want total session moves? 
        // Or reset per round? Let's keep it cumulative for the session or reset?
        // Usually moves per board is more relevant for "score", but "Session Moves" might be fun.
        // Let's reset for now to be clean per board.
        moves = 0
        
        var newCards: [MemoryCard] = []
        
        for card in learningCards {
            switch matchMode {
            case .wordToWord:
                // Target: Text, Native: Text
                newCards.append(MemoryCard(
                    content: card.wordTarget,
                    associatedCardId: card.id,
                    type: .target,
                    audioFile: card.audioWordFile,
                    mediaFile: nil
                ))
                newCards.append(MemoryCard(
                    content: card.wordNative,
                    associatedCardId: card.id,
                    type: .native,
                    mediaFile: nil
                ))
                
            case .wordToPicture:
                // Target: Picture, Native: Text
                newCards.append(MemoryCard(
                    content: card.wordTarget,
                    associatedCardId: card.id,
                    type: .target,
                    audioFile: card.audioWordFile,
                    mediaFile: card.mediaFile
                ))
                newCards.append(MemoryCard(
                    content: card.wordNative,
                    associatedCardId: card.id,
                    type: .native,
                    mediaFile: nil
                ))
                
            case .pictureToWord:
                // Target: Text, Native: Picture
                newCards.append(MemoryCard(
                    content: card.wordTarget,
                    associatedCardId: card.id,
                    type: .target,
                    audioFile: card.audioWordFile,
                    mediaFile: nil
                ))
                newCards.append(MemoryCard(
                    content: card.wordNative,
                    associatedCardId: card.id,
                    type: .native,
                    mediaFile: card.mediaFile
                ))
            }
        }
        
        cards = newCards.shuffled()
    }
    
    func flipCard(at index: Int) {
        guard index < cards.count, !cards[index].isMatched, !cards[index].isFlipped, !isProcessing else { return }
        
        // 1. Flip the card
        cards[index].isFlipped = true
        
        // Play audio if it's a target card
        if cards[index].type == .target {
            playAudio?(cards[index].audioFile, cards[index].content)
        }
        
        // 2. Check current state
        let flippedIndices = cards.indices.filter { cards[$0].isFlipped && !cards[$0].isMatched }
        
        if flippedIndices.count == 2 {
            moves += 1
            checkForMatch(indices: flippedIndices)
        }
    }
    
    private func checkForMatch(indices: [Int]) {
        isProcessing = true
        let card1 = cards[indices[0]]
        let card2 = cards[indices[1]]
        
        if card1.associatedCardId == card2.associatedCardId {
            // MATCH!
            handleMatch(indices: indices)
        } else {
            // MISMATCH
            handleMismatch(indices: indices)
        }
    }
    
    private func handleMatch(indices: [Int]) {
        // Delay slightly for visual satisfaction
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for index in indices {
                self.cards[index].isMatched = true
            }
            self.matchedPairs += 1
            self.onMatchFound?()
            self.isProcessing = false
            
            if self.matchedPairs == self.totalPairs {
                // Round Complete!
                self.completeRound()
            }
        }
    }
    
    private func handleMismatch(indices: [Int]) {
        onMistake?()
        // Delay to let user see the cards
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for index in indices {
                withAnimation {
                    self.cards[index].isFlipped = false
                }
            }
            self.isProcessing = false
        }
    }
    
    private func completeRound() {
        // Grade the current batch as "Good" (Passed)
        print("MemoryGame: Round complete. Grading batch.")
        SmartSessionManager.shared.completeBatch(cards: currentBatch, grade: .good)
        
        // Delay before starting next round (so user sees empty board or success state)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startNextRound()
        }
    }
}
