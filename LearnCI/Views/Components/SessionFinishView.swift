import SwiftUI

struct SessionFinishView: View {
    let learnedCount: Int
    let elapsedSeconds: Int
    @Binding var gameState: GameView.GameState
    // Removed selectedDeck binding to persist selection
    
    // Config Stats
    let deckTitle: String
    let language: Language
    let level: LearningLevel
    let preset: GameConfiguration.Preset
    let gameType: GameConfiguration.GameType
    let duration: Int
    let cardGoal: Int
    let isRandom: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header: Trophy + Stats Side-by-Side
                HStack(spacing: 20) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.yellow)
                        .shadow(radius: 5)
                        .frame(width: 80)
                    
                    VStack(spacing: 5) {
                        Text("You learned")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(learnedCount)")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundColor(.blue)
                        Text("cards in \(formatTime(elapsedSeconds))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(15)
                }
                .padding(.top, 10)
                
                SessionSummaryView(
                    deckTitle: deckTitle,
                    language: language,
                    level: level,
                    preset: preset,
                    gameType: gameType,
                    duration: duration,
                    cardGoal: cardGoal,
                    isRandom: isRandom
                )
                .padding(.horizontal)
                
                VStack(spacing: 15) {
                    Button(action: {
                        withAnimation {
                            gameState = .configuration
                            // Do NOT clear selectedDeck
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Start New Session")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(15)
                    }
                    
                    Button(action: {
                        // Navigate back or close (Context dependent)
                        gameState = .configuration
                        // Do NOT clear selectedDeck
                    }) {
                        Text("Return to Menu")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 40)
            }
            .padding()
            .padding(.bottom, 100) // Ensure clearing TabBar
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let sec = seconds % 60
        return String(format: "%02d:%02d", minutes, sec)
    }
}
