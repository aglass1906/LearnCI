import SwiftUI

struct LearningCardBackView: View {
    let card: LearningCard
    let deck: CardDeck
    let config: GameConfiguration
    
    var body: some View {
        VStack(spacing: 15) {
            if config.back.translation != .hidden {
                Text("Meaning:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(card.nativeTranslation)
                    .font(.title)
                    .foregroundColor(.secondary)
                    .blur(radius: config.back.translation == .hint ? 5 : 0)
            }
            
            if config.back.translation != .hidden && config.back.sentenceMeaning != .hidden {
                Divider()
            }
            
            if config.back.sentenceMeaning != .hidden {
                Text("Sentence Meaning:")
                    .font(.caption)
                    .foregroundColor(.gray)
                    
                Text(card.sentenceNative)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .blur(radius: config.back.sentenceMeaning == .hint ? 5 : 0)
            }
            
            if config.back.studyLinks != .hidden {
                if config.back.translation != .hidden || config.back.sentenceMeaning != .hidden {
                     Divider()
                }
               
                // External Study Links
                StudyLinksView(word: card.targetWord, sentence: card.sentenceTarget, languageCode: deck.language.code)
                    .opacity(config.back.studyLinks == .hint ? 0.3 : 1.0)
            }
        }
        .scaleEffect(x: -1, y: 1) // Mirror effect for the back side of a 3D rotation
    }
}
