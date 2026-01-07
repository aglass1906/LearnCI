import SwiftUI

struct FlashcardGameView: View {
    let deck: CardDeck
    let sessionCards: [LearningCard]
    let currentCardIndex: Int
    let learnedCount: Int
    let sessionCardGoal: Int
    let sessionConfig: GameConfiguration
    @Binding var isFlipped: Bool
    
    let onRelearn: () -> Void
    let onLearned: () -> Void
    let onNext: () -> Void
    let onPrev: () -> Void
    
    var body: some View {
        if sessionCards.isEmpty {
            Text("No cards available.")
        } else {
            let card = sessionCards[currentCardIndex]
            
            VStack {
                // Progress Header
                progressHeader
                
                // Card View
                ActiveCardStack(card: card, deck: deck, config: sessionConfig, isFlipped: $isFlipped)
                
                // Learning Success Controls
                if isFlipped {
                    successControls
                } else {
                    // Navigation Controls
                    navigationControls(deck: deck)
                }
            }
        }
    }
    
    var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Session Progress")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(learnedCount) / \(sessionCardGoal) cards")
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
            }
            
            ProgressView(value: Double(learnedCount), total: Double(sessionCardGoal))
                .tint(.blue)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    var successControls: some View {
        HStack(spacing: 20) {
            Button(action: onRelearn) {
                VStack {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 44))
                    Text("Relearn")
                        .font(.caption.bold())
                }
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
            
            Button(action: onLearned) {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    Text("Learned")
                        .font(.caption.bold())
                }
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 40)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    func navigationControls(deck: CardDeck) -> some View {
        HStack {
            Button(action: onPrev) {
                Image(systemName: "arrow.left.circle")
                    .font(.system(size: 50))
            }
            .disabled(currentCardIndex == 0)
            
            Spacer()
            
            Button(action: onNext) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 50))
            }
            .disabled(currentCardIndex >= deck.cards.count - 1)
        }
        .padding(.horizontal, 40)
    }
}
