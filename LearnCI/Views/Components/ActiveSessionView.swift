import SwiftUI

struct ActiveSessionView: View {
    let errorMessage: String?
    let deck: CardDeck?
    let sessionCards: [LearningCard]
    let currentCardIndex: Int
    let learnedCount: Int
    let sessionCardGoal: Int
    let sessionConfig: GameConfiguration
    @Binding var isFlipped: Bool
    
    let onRelearn: () -> Void
    let onLearned: () -> Void
    let onFinish: () -> Void
    let onNext: () -> Void
    let onPrev: () -> Void
    
    var body: some View {
        VStack {
            if let error = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Data Loading Issue")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                    .multilineTextAlignment(.center)
                        .padding()
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            if let deck = deck {
                // Game Router
                switch sessionConfig.gameType {
                case .flashcards:
                    FlashcardGameView(
                        deck: deck,
                        sessionCards: sessionCards,
                        currentCardIndex: currentCardIndex,
                        learnedCount: learnedCount,
                        sessionCardGoal: sessionCardGoal,
                        sessionConfig: sessionConfig,
                        isFlipped: $isFlipped,
                        onRelearn: onRelearn,
                        onLearned: onLearned,
                        onNext: onNext,
                        onPrev: onPrev
                    )
                case .memoryMatch:
                    MemoryGameView(
                        sessionCards: sessionCards,
                        deck: deck,
                        sessionConfig: sessionConfig,
                        onGameComplete: onFinish,
                        onMatchFound: onLearned
                    )
                case .sentenceBuilder:
                     ContentUnavailableView(
                        "Sentence Scramble Coming Soon",
                        systemImage: "text.bubble.fill",
                        description: Text("This game mode is under construction.")
                     )
                case .story:
                    // Reuse Flashcard View for Story Reading (Linear Mode)
                    FlashcardGameView(
                        deck: deck,
                        sessionCards: sessionCards,
                        currentCardIndex: currentCardIndex,
                        learnedCount: learnedCount,
                        sessionCardGoal: sessionCardGoal,
                        sessionConfig: sessionConfig,
                        isFlipped: $isFlipped,
                        onRelearn: onRelearn,
                        onLearned: onLearned,
                        onNext: onNext,
                        onPrev: onPrev
                    )
                }
            } else {
                ProgressView("Loading Deck...")
            }
        }
    }
}
