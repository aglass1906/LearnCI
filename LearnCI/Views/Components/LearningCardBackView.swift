import SwiftUI

struct LearningCardBackView: View {
    let card: LearningCard
    let deck: CardDeck
    let config: GameConfiguration
    
    var body: some View {
        VStack(spacing: 15) {
            // Word Meaning
            if config.back.translation != .hidden {
                Text("Meaning:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(card.wordNative)
                    .font(.title)
                    .foregroundColor(.secondary)
                    .blur(radius: config.back.translation == .hint ? 5 : 0)
            }
            
            // Divider if both are shown
            if config.back.translation != .hidden && config.back.sentenceMeaning != .hidden {
                Divider()
            }
            
            // Sentence Meaning
            if config.back.sentenceMeaning != .hidden && !card.sentenceNative.isEmpty {
                Text("Sentence Meaning:")
                    .font(.caption)
                    .foregroundColor(.gray)
                    
                Text(card.sentenceNative)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .blur(radius: config.back.sentenceMeaning == .hint ? 5 : 0)
            }
            
            Spacer()
            
            // Study Links
            if config.back.studyLinks != .hidden {
                 Divider()
                 StudyLinksView(word: card.wordTarget, sentence: card.sentenceTarget, languageCode: deck.language.code)
                    .opacity(config.back.studyLinks == .hint ? 0.3 : 1.0)
            }
        }
    }
}
