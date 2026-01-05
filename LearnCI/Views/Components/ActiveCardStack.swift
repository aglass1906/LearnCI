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
            
            VStack(spacing: 20) {
                if !isFlipped {
                    LearningCardFrontView(card: card, deck: deck, config: config)
                } else {
                    LearningCardBackView(card: card, deck: deck)
                }
            }
            .padding()
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .frame(height: 350)
        .padding()
        .onTapGesture {
            withAnimation(.spring()) {
                isFlipped.toggle()
            }
        }
    }
}
