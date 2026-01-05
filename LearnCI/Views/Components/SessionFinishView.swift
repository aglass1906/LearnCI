import SwiftUI

struct SessionFinishView: View {
    let learnedCount: Int
    let elapsedSeconds: Int
    @Binding var gameState: GameView.GameState
    @Binding var selectedDeck: DeckMetadata?
    
    // Config Stats
    let deckTitle: String
    let language: Language
    let level: LearningLevel
    let preset: GameConfiguration.Preset
    let duration: Int
    let cardGoal: Int
    let isRandom: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 80))
                .foregroundColor(.yellow)
                .shadow(radius: 10)
            
            Text("Session Complete!")
                .font(.largeTitle.bold())
            
            VStack(spacing: 10) {
                Text("You learned")
                Text("\(learnedCount)")
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundColor(.blue)
                Text("cards in \(formatTime(elapsedSeconds))")
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(20)
            
            SessionSummaryView(
                deckTitle: deckTitle,
                language: language,
                level: level,
                preset: preset,
                duration: duration,
                cardGoal: cardGoal,
                isRandom: isRandom
            )
            .padding(.horizontal)
            
            VStack(spacing: 15) {
                Button(action: {
                    withAnimation {
                        gameState = .configuration
                        selectedDeck = nil
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
                    selectedDeck = nil
                }) {
                    Text("Return to Menu")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 40)
        }
        .padding()
        .transition(.scale.combined(with: .opacity))
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let sec = seconds % 60
        return String(format: "%02d:%02d", minutes, sec)
    }
}
