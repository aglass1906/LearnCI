import SwiftUI

/// Pre-game summary view (Stage 4) - Shows final confirmation before starting game
struct PreGameSummaryView: View {
    let deckTitle: String
    let language: Language
    let level: Int
    let preset: GameConfiguration.Preset
    let gameType: GameConfiguration.GameType
    let duration: Int
    let cardGoal: Int
    let order: GameConfiguration.OrderStrategy
    
    let onStartGame: () -> Void
    let onBack: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Ready to Start!")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Review your setup below")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Summary Card
                SessionSummaryView(
                    deckTitle: deckTitle,
                    language: language,
                    level: level,
                    preset: preset,
                    gameType: gameType,
                    duration: duration,
                    cardGoal: cardGoal,
                    order: order
                )
                .padding(.horizontal)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 15) {
                    Button(action: onStartGame) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Game")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(15)
                    }
                    
                    Button(action: onBack) {
                        Text("Go Back")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Start Game") {
                    onStartGame()
                }
                .fontWeight(.bold)
            }
        }
    }
}
