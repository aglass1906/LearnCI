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
    
    // Config for specific games
    var matchMode: GameConfiguration.MemoryMatchMode = .pictureToWord
    
    let onRelearn: () -> Void
    let onLearned: () -> Void
    let onFinish: () -> Void
    let onNext: () -> Void
    let onPrev: () -> Void
    let onGrade: ((SmartSessionManager.Grade) -> Void)?
    
    // MARK: - Arcade Progress Strip

    /// True for self-contained arcade games that show the shared progress strip.
    /// Linker is excluded — it has its own round-based progress indicator built
    /// into its header, and the generic word-count strip doesn't fit its
    /// multi-round structure.
    private var isArcadeGame: Bool {
        [GameConfiguration.GameType.wordRain, .wordCrush, .memoryMatch]
            .contains(sessionConfig.gameType)
    }

    private var arcadeProgressStrip: some View {
        let remaining = max(0, sessionCardGoal - learnedCount)
        return VStack(spacing: 2) {
            ProgressView(value: Double(learnedCount), total: Double(max(1, sessionCardGoal)))
                .tint(.teal)
                .animation(.easeInOut(duration: 0.3), value: learnedCount)
            HStack {
                Text("\(learnedCount) / \(sessionCardGoal) words")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(remaining == 0 ? "Done!" : "\(remaining) left")
                    .font(.caption2)
                    .foregroundColor(remaining <= 3 ? .teal : .secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    var body: some View {
        VStack {
            if isArcadeGame {
                arcadeProgressStrip
            }

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
                        onPrev: onPrev,
                        onGrade: onGrade
                    )
                case .memoryMatch:
                    MemoryGameView(
                        deck: deck,
                        sessionCards: sessionCards,
                        sessionConfig: sessionConfig,
                        matchMode: matchMode,
                        onGameComplete: onFinish,
                        onMatchFound: onLearned
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
                        onPrev: onPrev,
                        onGrade: onGrade
                    )
                case .multipleChoice:
                    MultipleChoiceGameView(
                        deck: deck,
                        sessionCards: sessionCards,
                        currentCardIndex: currentCardIndex,
                        learnedCount: learnedCount,
                        sessionCardGoal: sessionCardGoal,
                        sessionConfig: sessionConfig,
                        onLearned: onLearned,
                        onFinish: onFinish,
                        onNext: onNext,
                        onGrade: onGrade
                    )
                case .audioCloze:
                    AudioClozeGameView(
                        deck: deck,
                        sessionCards: sessionCards,
                        currentCardIndex: currentCardIndex,
                        learnedCount: learnedCount,
                        sessionCardGoal: sessionCardGoal,
                        sessionConfig: sessionConfig,
                        onLearned: onLearned,
                        onFinish: onFinish,
                        onNext: onNext,
                        onGrade: onGrade
                    )
                case .linker:
                    LinkerGameView(
                        deck: deck,
                        sessionCards: sessionCards,
                        config: sessionConfig,
                        sessionCardGoal: sessionCardGoal,
                        onFinish: onFinish,
                        onGrade: onGrade,
                        onMatchFound: onLearned
                    )
                case .wordCrush:
                    WordCrushGameView(
                        deck: deck,
                        sessionCards: sessionCards,
                        sessionConfig: sessionConfig,
                        sessionCardGoal: sessionCardGoal,
                        onFinish: onFinish,
                        onGrade: onGrade,
                        onMatchFound: onLearned
                    )
                case .wordRain:
                    WordRainGameView(
                        deck: deck,
                        sessionCards: sessionCards,
                        sessionConfig: sessionConfig,
                        sessionCardGoal: sessionCardGoal,
                        onFinish: onFinish,
                        onGrade: onGrade,
                        onWordLearned: onLearned
                    )
                }
            } else {
                ProgressView("Loading Deck...")
            }
        }
    }
}
