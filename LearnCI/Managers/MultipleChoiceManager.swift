import Foundation
import SwiftData

struct MultipleChoiceChallenge: Identifiable {
    let id: UUID = UUID()
    let correctCard: LearningCard
    let options: [LearningCard]
    let mode: ChallengeMode
    
    enum ChallengeMode {
        case image
        case text
    }
}

class MultipleChoiceManager {
    static let shared = MultipleChoiceManager()
    
    private init() {}
    
    func generateChallenge(for card: LearningCard, deck: CardDeck, sessionCards: [LearningCard]) -> MultipleChoiceChallenge {
        // 1. Determine Mode
        // Prefer image mode if the correct card has an image
        let hasImage = card.mediaFile != nil
        let mode: MultipleChoiceChallenge.ChallengeMode = hasImage ? .image : .text
        
        // 2. Select Distractors
        // We need 3 distractors.
        // Priority 1: Use sessionCards (filtered set) if possible to keep context relevant
        // Priority 2: Fallback to full deck if sessionCards is too small
        
        var pool: [LearningCard] = []
        
        // Exclude self from pool
        if sessionCards.count >= 4 {
             pool = sessionCards.filter { $0.id != card.id }
        } else {
             // Fallback to full deck (excluding self)
             pool = deck.cards.filter { $0.id != card.id }
        }
        
        // If we are in image mode, we ideally want distractors that ALSO have images
        // so the grid looks consistent.
        if mode == .image {
            let imagePool = pool.filter { $0.mediaFile != nil }
            // Only enforce image pool if we have enough options, otherwise Mixed is better than crashing
            if imagePool.count >= 3 {
                pool = imagePool
            }
        }
        
        // Shuffle and pick 3
        let distractors = Array(pool.shuffled().prefix(3))
        
        // 3. Assemble Options
        var options = distractors
        options.append(card)
        options.shuffle()
        
        return MultipleChoiceChallenge(correctCard: card, options: options, mode: mode)
    }
}
