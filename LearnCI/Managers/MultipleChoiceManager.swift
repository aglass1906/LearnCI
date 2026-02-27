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
    
    func generateChallenge(for card: LearningCard, deck: CardDeck, sessionCards: [LearningCard], optionCount: Int = 4) -> MultipleChoiceChallenge {
        let distractorCount = max(1, optionCount - 1)

        // 1. Determine Mode
        let hasImage = card.mediaFile != nil
        let mode: MultipleChoiceChallenge.ChallengeMode = hasImage ? .image : .text

        // 2. Select Distractors
        var pool: [LearningCard] = []

        if sessionCards.count > optionCount {
             pool = sessionCards.filter { $0.id != card.id }
        } else {
             pool = deck.cards.filter { $0.id != card.id }
        }

        if mode == .image {
            let imagePool = pool.filter { $0.mediaFile != nil }
            if imagePool.count >= distractorCount {
                pool = imagePool
            }
        }

        let distractors = Array(pool.shuffled().prefix(distractorCount))

        // 3. Assemble Options
        var options = distractors
        options.append(card)
        options.shuffle()

        return MultipleChoiceChallenge(correctCard: card, options: options, mode: mode)
    }
}
