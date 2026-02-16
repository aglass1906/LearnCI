import SwiftUI
import Observation

@Observable
class SmartSessionManager {
    static let shared = SmartSessionManager()
    
    // The active queue of cards to review
    private(set) var activeQueue: [LearningCard] = []
    
    // Cards that have been successfully mastered in this session
    private(set) var masteredCards: [LearningCard] = []
    
    // Current card being shown
    var currentCard: LearningCard? {
        activeQueue.first
    }
    
    var progress: Double {
        let total = activeQueue.count + masteredCards.count
        guard total > 0 else { return 0 }
        return Double(masteredCards.count) / Double(total)
    }
    
    var remainingCount: Int {
        activeQueue.count
    }
    
    // MARK: - Lifecycle
    
    func startSession(cards: [LearningCard]) {
        self.activeQueue = cards
        self.masteredCards = []
        print("SmartSession: Started with \(cards.count) cards.")
    }
    
    // MARK: - Grading Logic
    
    enum Grade {
        case again // Fail: Re-insert soon (Index + 3)
        case hard  // Pass/Struggle: Re-insert later (Index + 10)
        case good  // Pass: Check one last time (End of Queue)
        case easy  // Mastered: Remove immediately
    }
    
    func handleGrade(_ grade: Grade) {
        guard !activeQueue.isEmpty else { return }
        let card = activeQueue.removeFirst()
        processGrade(card, grade: grade)
    }
    
    // MARK: - Batch Support (Bonding/Memory)
    
    /// Returns the next `count` cards from the queue without removing them.
    /// Use this to populate a round.
    func nextBatch(count: Int) -> [LearningCard] {
        return Array(activeQueue.prefix(count))
    }
    
    /// Grades a batch of cards.
    /// - Parameters:
    ///   - cards: The cards to grade (must be at the head of the queue ideally)
    ///   - grade: The grade to apply to all cards (or specific logic)
    func completeBatch(cards: [LearningCard], grade: Grade) {
        // We need to match these cards in the active queue and grade them.
        // For simplicity, we assume they are at the top if the game flow is correct.
        // However, to be safe, we find and remove them, then re-insert based on grade.
        
        for card in cards {
            if let index = activeQueue.firstIndex(where: { $0.id == card.id }) {
                let removed = activeQueue.remove(at: index)
                processGrade(removed, grade: grade)
            }
        }
    }
    
    private func processGrade(_ card: LearningCard, grade: Grade) {
        switch grade {
        case .again:
            let index = min(3, activeQueue.count)
            activeQueue.insert(card, at: index)
            print("SmartSession: \(card.wordTarget) -> Again (Insert at \(index))")
        case .hard:
            let index = min(10, activeQueue.count)
            activeQueue.insert(card, at: index)
            print("SmartSession: \(card.wordTarget) -> Hard (Insert at \(index))")
        case .good:
            activeQueue.append(card)
            print("SmartSession: \(card.wordTarget) -> Good (Move to End)")
        case .easy:
            masteredCards.append(card)
            print("SmartSession: \(card.wordTarget) -> Easy (Mastered!)")
        }
    }
    
    // Helper for "Good" logic if we want to differentiate "Mastered" vs "Review Again"
    // Using the user's specific request: "Good" = End of Queue (One final check). 
    // If you hit "Good" on the SAME card multiple times, it might loop forever?
    // Enhancement: Maybe track how many times it was "Good"? 
    // For now, let's trust the user's explicit logic. If they get tired, they hit "Easy".
}
