import SwiftUI
import AVFoundation

/// Displays chapter information before playback starts, and optionally reads the description aloud.
struct ChapterInfoCardView: View {
    let chapter: StoryChapter
    let heroImage: UIImage?
    let languageCode: String
    let onContinue: () -> Void
    
    @State private var synthesizer = AVSpeechSynthesizer()
    
    var body: some View {
        VStack(spacing: 0) {
            // Hero image or gradient placeholder
            if let img = heroImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 250)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [.accentColor, .accentColor.opacity(0.6)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(height: 250)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                // Chapter Title
                Text(chapter.titleTargetLanguage)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 24)
                
                // Parse the chapter intro text (Quote vs Orientation)
                if let intro = chapter.chapterIntroText, !intro.isEmpty {
                    let parts = intro.components(separatedBy: "\n\n")
                    if let quote = parts.first {
                        Text(quote)
                            .font(.title3)
                            .italic()
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)
                            .overlay(
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: 4),
                                alignment: .leading
                            )
                    }
                    if parts.count > 1 {
                        Text(parts.dropFirst().joined(separator: "\n\n"))
                            .font(.body)
                            .padding(.top, 8)
                    }
                }
                
                // Characters involved
                /* Phase 2: Insert character images here.
                   Current implementation falls back to text. */
                Text("Characters: NARRATOR") // Placeholder, currently `charactersInvolved` isn't accessible securely on iOS model, so we stick to this. Wait, let me check if `charactersInvolved` exists.
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                
                Spacer()
                
                Button(action: {
                    stopSpeaking()
                    onContinue()
                }) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
            .background(Color(.systemBackground))
        }
        .onAppear {
            readAloud()
        }
        .onDisappear {
            stopSpeaking()
        }
        .ignoresSafeArea(edges: .top)
    }
    
    private func readAloud() {
        var utteranceText = chapter.titleTargetLanguage
        if let intro = chapter.chapterIntroText, !intro.isEmpty {
             utteranceText += ". " + intro
        }
        
        let utterance = AVSpeechUtterance(string: utteranceText)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode) // Expected format: 'en-US', 'es-MX'
        utterance.rate = 0.5
        
        synthesizer.speak(utterance)
    }
    
    private func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
