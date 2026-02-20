import SwiftUI

struct LearningCardBackView: View {
    let card: LearningCard
    let deck: CardDeck
    let config: GameConfiguration
    
    @Environment(AudioManager.self) private var audioManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Word Meaning
            if config.back.translation != .hidden {
                VStack(spacing: 8) {
                    Text("Meaning:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack {
                        Spacer()
                        Text(card.wordNative)
                            .font(.title)
                            .foregroundColor(.secondary)
                            .blur(radius: config.back.translation == .hint ? 5 : 0)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            audioManager.playAudio(
                                named: "native_word",
                                folderName: deck.baseFolderName,
                                text: card.wordNative,
                                language: .english,
                                voiceGender: config.ttsVoiceGender,
                                useFallback: true,
                                ttsRate: config.ttsRate
                            )
                        }) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.body)
                                .foregroundColor(.blue)
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                }
            }
            
            // Divider if both are shown
            if config.back.translation != .hidden && config.back.sentenceMeaning != .hidden && !card.sentenceNative.isEmpty {
                Divider()
            }
            
            // Sentence Meaning
            if config.back.sentenceMeaning != .hidden && !card.sentenceNative.isEmpty {
                VStack(spacing: 8) {
                    Text("Sentence Meaning:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack {
                        Spacer()
                        Text(card.sentenceNative)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .blur(radius: config.back.sentenceMeaning == .hint ? 5 : 0)
                        
                        Button(action: {
                            audioManager.playAudio(
                                named: "native_sentence",
                                folderName: deck.baseFolderName,
                                text: card.sentenceNative,
                                language: .english,
                                voiceGender: config.ttsVoiceGender,
                                useFallback: true,
                                ttsRate: config.ttsRate
                            )
                        }) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(6)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                }
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
