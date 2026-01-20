import SwiftUI
import AVKit

struct LearningCardFrontView: View {
    let card: LearningCard
    let deck: CardDeck
    let config: GameConfiguration
    
    @Environment(AudioManager.self) private var audioManager
    @Environment(DataManager.self) private var dataManager
    
    // Internal state for hints
    @State private var isImageRevealed: Bool = false
    @State private var isWordRevealed: Bool = false
    @State private var isSentenceRevealed: Bool = false
    
    var isCardFlipped: Bool = false
    var onFlip: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            // Visual Media (Image or Video)
            if config.image != .hidden, let filename = card.mediaFile, !filename.isEmpty {
                let isVideo = isVideoFile(filename)
                
                // For videos, we strictly need a File URL
                if isVideo, let mediaURL = dataManager.resolveURL(folderName: deck.baseFolderName, filename: filename) {
                    if config.image == .hint && !isImageRevealed {
                        // Hint Mode: Tap to reveal
                        Button(action: {
                            withAnimation { isImageRevealed = true }
                        }) {
                            ZStack {
                                Color.black.opacity(0.8)
                                    .frame(height: 200)
                                    .cornerRadius(10)
                                
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                // Overlay Text
                                VStack {
                                    Image(systemName: "eye.fill")
                                        .font(.largeTitle)
                                    Text("Show Video")
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                    } else {
                        // Visible Video
                        CardVideoPlayer(url: mediaURL, audioManager: audioManager, shouldPause: isCardFlipped)
                            .frame(height: 220)
                            .cornerRadius(10)
                    }
                } 
                // For images, we use our helper that checks both File URL and Assets
                else if !isVideo, let uiImage = dataManager.loadImage(folderName: deck.baseFolderName, filename: filename) {
                    if config.image == .hint && !isImageRevealed {
                         // Hint Mode
                         Button(action: {
                             withAnimation { isImageRevealed = true }
                         }) {
                             ZStack {
                                 Image(uiImage: uiImage)
                                     .resizable()
                                     .scaledToFit()
                                     .blur(radius: 20)
                                     .opacity(0.8)
                                     .frame(maxHeight: 180)
                                     .cornerRadius(10)
                                 
                                 VStack {
                                     Image(systemName: "eye.fill")
                                         .font(.largeTitle)
                                     Text("Show Image")
                                         .fontWeight(.bold)
                                 }
                                 .foregroundColor(.white)
                                 .shadow(radius: 2)
                             }
                         }
                         .buttonStyle(PlainButtonStyle())
                    } else {
                        // Visible Image
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .cornerRadius(10)
                            .onTapGesture { onFlip() }
                    }
                }
                else if !isVideo {
                     // Image not found placeholder
                     Color.gray.opacity(0.3)
                         .frame(height: 180)
                         .cornerRadius(10)
                         .overlay(Text("Image not found").font(.caption).foregroundColor(.secondary))
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
                        Text(card.wordTarget)
                            .font(.system(size: 32, weight: .bold)) // Reduced from 40
                            .onTapGesture { onFlip() }
                    }
                    
                    if config.word.audio != .hidden, let file = card.audioWordFile {
                        let canPlay = audioManager.audioExists(named: file, folderName: deck.baseFolderName) || config.useTTSFallback
                        
                        if canPlay {
                            Button(action: {
                                audioManager.playAudio(
                                    named: file,
                                    folderName: deck.baseFolderName,
                                    text: card.wordTarget,
                                    language: deck.language,
                                    voiceGender: config.ttsVoiceGender,
                                    useFallback: config.useTTSFallback,
                                    ttsRate: config.ttsRate
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
                            .fixedSize(horizontal: false, vertical: true) // Allow full expansion
                            .padding(.horizontal)
                            .onTapGesture { onFlip() }
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
                                    voiceGender: config.ttsVoiceGender,
                                    useFallback: config.useTTSFallback,
                                    ttsRate: config.ttsRate
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
    
    // Helper to detect video extensions
    private func isVideoFile(_ filename: String) -> Bool {
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "webm"]
        let ext = (filename as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }
}

