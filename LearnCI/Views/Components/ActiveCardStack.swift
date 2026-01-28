import SwiftUI

struct ActiveCardStack: View {
    let card: LearningCard
    let deck: CardDeck
    let config: GameConfiguration
    
    @Binding var isFlipped: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(isFlipped ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                .shadow(radius: 5)
                .onTapGesture {
                    withAnimation(.spring()) {
                        isFlipped.toggle()
                    }
                }
            
            ZStack {
                // Front View (Persisted)
                LearningCardFrontView(card: card, deck: deck, config: config, isCardFlipped: isFlipped, onFlip: {
                    withAnimation(.spring()) {
                        isFlipped.toggle()
                    }
                })
                .id(card.id) // Force reset of state (isImageRevealed, etc.) when card changes
                .opacity(isFlipped ? 0 : 1)
                .accessibilityHidden(isFlipped)
                
                // Back View (Persisted)
                LearningCardBackView(card: card, deck: deck, config: config)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(isFlipped ? 1 : 0)
                    .accessibilityHidden(!isFlipped)
                    .onTapGesture {
                        withAnimation(.spring()) {
                            isFlipped.toggle()
                        }
                    }
            }
            .padding()
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .frame(minHeight: 350) // Allow expansion for long story text
        .padding()
    }
}
