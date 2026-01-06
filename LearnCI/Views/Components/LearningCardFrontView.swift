import SwiftUI

struct LearningCardFrontView: View {
    let card: LearningCard
    let deck: CardDeck
    let config: GameConfiguration
    
    @Environment(AudioManager.self) private var audioManager
    
    // Internal state for hints
    @State private var isImageRevealed: Bool = false
    @State private var isWordRevealed: Bool = false
    @State private var isSentenceRevealed: Bool = false
    
    var body: some View {
        VStack(spacing: 15) {
            // Optional Image
            if config.image != .hidden {
                if let image = resolveImage(card.imageFile, folder: deck.baseFolderName) {
                    if config.image == .hint && !isImageRevealed {
                        // Hint Mode: Tap to reveal
                        Button(action: {
                            withAnimation { isImageRevealed = true }
                        }) {
                            ZStack {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .blur(radius: 20)
                                    .opacity(0.8)
                                
                                VStack {
                                    Image(systemName: "eye.fill")
                                        .font(.largeTitle)
                                    Text("Show Image")
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                            }
                            .frame(maxHeight: 180)
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // Visible Mode or Revealed
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .cornerRadius(10)
                    }
                }
            }
            
            if config.word.text != .hidden {
                HStack {
                    if config.word.text == .hint && !isWordRevealed {
                         Button(action: {
                             withAnimation { isWordRevealed = true }
                         }) {
                             Text("?")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.5))
                                .frame(minWidth: 60)
                         }
                         .buttonStyle(PlainButtonStyle())
                    } else {
                        Text(card.targetWord)
                            .font(.system(size: 40, weight: .bold))
                    }
                    
                    if config.word.audio != .hidden, let file = card.audioWordFile {
                        let canPlay = audioManager.audioExists(named: file, folderName: deck.baseFolderName) || config.useTTSFallback
                        
                        if canPlay {
                            Button(action: {
                                audioManager.playAudio(
                                    named: file,
                                    folderName: deck.baseFolderName,
                                    text: card.targetWord,
                                    language: deck.language,
                                    useFallback: config.useTTSFallback
                                )
                            }) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.title)
                                    .foregroundColor(config.word.audio == .visible ? .blue : .orange)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            if config.sentence.text != .hidden {
                VStack {
                    if config.sentence.text == .hint && !isSentenceRevealed {
                         Button(action: {
                             withAnimation { isSentenceRevealed = true }
                         }) {
                             Text("Tap to see sentence")
                                .font(.subheadline)
                                .italic()
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                         }
                         .buttonStyle(PlainButtonStyle())
                    } else {
                        Text(card.sentenceTarget)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    if config.sentence.audio != .hidden, let file = card.audioSentenceFile {
                        let canPlay = audioManager.audioExists(named: file, folderName: deck.baseFolderName) || config.useTTSFallback
                        
                        if canPlay {
                            Button(action: {
                                audioManager.playAudio(
                                    named: file,
                                    folderName: deck.baseFolderName,
                                    text: card.sentenceTarget,
                                    language: deck.language,
                                    useFallback: config.useTTSFallback
                                )
                            }) {
                                HStack {
                                    Image(systemName: "speaker.wave.2.circle.fill")
                                    Text("Play Sentence")
                                }
                                .font(.subheadline)
                                .padding(8)
                                .background(config.sentence.audio == .visible ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
            }
        }
        // Reset state when card changes
        .id(card.id) 
    }
    
    // Helper needed for image resolution (copied from GameView logic or we can move it to a shared helper)
    // For now, I'll include the logic here, but relying on DataManager would be better if we had access.
    // However, the original code used a helper method in GameView.
    // Let's rely on DataManager being present in Environment or passing a resolver closure.
    // Actually, `resolveImage` logic was fairly self-contained but used `UIImage(contentsOfFile:)`.
    // To avoid duplication, let's inject a way to resolve images or just duplicate the simple logic since it depends on DataManager to resolve URL.
    // Wait, the original `resolveImage` used `dataManager.resolveURL`. DataManager is in environment.
    
    @Environment(DataManager.self) private var dataManager

    private func resolveImage(_ filename: String?, folder: String?) -> Image? {
        guard let name = filename, !name.isEmpty else { return nil }
        
        // System fallback if name looks like a system icon
        if name.contains("system:") {
            let systemName = name.replacingOccurrences(of: "system:", with: "")
            return Image(systemName: systemName)
        }

        // Use DataManager's optimized lookup
        if let url = dataManager.resolveURL(folderName: folder, filename: name) {
            if let uiImage = UIImage(contentsOfFile: url.path) {
                return Image(uiImage: uiImage)
            }
        }
        
        return nil
    }
}
