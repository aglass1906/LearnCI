import SwiftUI

struct LearningCardBackView: View {
    let card: LearningCard
    let deck: CardDeck
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Meaning:")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(card.nativeTranslation)
                .font(.title)
                .foregroundColor(.secondary)
            
            Divider()
            
            Text("Sentence Meaning:")
                .font(.caption)
                .foregroundColor(.gray)
                
            Text(card.sentenceNative)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
            
            // External Study Links
            StudyLinksView(word: card.targetWord, sentence: card.sentenceTarget, languageCode: deck.language.code)
        }
        .scaleEffect(x: -1, y: 1) // Mirror effect for the back side of a 3D rotation
    }
}
