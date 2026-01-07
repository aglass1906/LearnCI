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
}

@Observable
class MemoryGameEngine {
    var cards: [MemoryCard] = []
    var isProcessing: Bool = false
    var matchedPairs: Int = 0
    var totalPairs: Int = 0
    var moves: Int = 0
    
    var onGameComplete: (() -> Void)?
    var onMatchFound: (() -> Void)?
    var onMistake: (() -> Void)?
    var playAudio: ((String?, String) -> Void)?
    
    init(learningCards: [LearningCard]) {
        setupGame(with: learningCards)
    }
    
    func setupGame(with learningCards: [LearningCard]) {
        // Take up to 8 cards for a 4x4 grid
        let selectedCards = Array(learningCards.prefix(8))
        totalPairs = selectedCards.count
        matchedPairs = 0
        moves = 0
        
        var newCards: [MemoryCard] = []
        
        for card in selectedCards {
            // Target Card (Word in Target Language)
            newCards.append(MemoryCard(
                content: card.targetWord,
                associatedCardId: card.id,
                type: .target,
                audioFile: card.audioWordFile
            ))
            
            // Native Card (Translation)
            newCards.append(MemoryCard(
                content: card.nativeTranslation,
                associatedCardId: card.id,
                type: .native
            ))
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
                self.onGameComplete?()
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
}
