import SwiftUI

struct MultipleChoiceGameView: View {
    let deck: CardDeck
    let sessionCards: [LearningCard]
    let currentCardIndex: Int
    let learnedCount: Int
    let sessionCardGoal: Int
    let sessionConfig: GameConfiguration
    
    // Callbacks
    let onLearned: () -> Void
    let onFinish: () -> Void
    let onNext: () -> Void
    var onGrade: ((SmartSessionManager.Grade) -> Void)?
    
    @Environment(AudioManager.self) private var audioManager
    
    // Internal State
    @State private var challenge: MultipleChoiceChallenge?
    @State private var selectedOptionId: String? // ID of card selected
    @State private var isAnswered: Bool = false
    @State private var showFeedback: Bool = false
    @State private var isCorrect: Bool = false
    
    // Animation
    @State private var shakeTrigger: Int = 0
    
    /// Stable identifier for the card currently at `currentCardIndex`.
    private var currentCardId: String {
        guard currentCardIndex < sessionCards.count else { return "" }
        return sessionCards[currentCardIndex].id
    }

    var body: some View {
        VStack {
            // Header
            progressHeader
            
            Spacer()
            
            if let challenge = challenge {
                // Stimulus (Audio + Text)
                VStack(spacing: 20) {
                    Button(action: { playAudio() }) {
                        Image(systemName: "speaker.wave.2.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                            .shadow(radius: 5)
                            .scaleEffect(audioManager.isPlaying ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3), value: audioManager.isPlaying)
                    }
                    
                    Text(challenge.correctCard.sentenceTarget)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 30)
                
                Spacer()
                
                // Options Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(challenge.options) { option in
                         Button(action: { handleSelection(option) }) {
                             OptionCard(
                                card: option,
                                mode: challenge.mode,
                                isSelected: selectedOptionId == option.id,
                                isAnswered: isAnswered,
                                isCorrectTarget: option.id == challenge.correctCard.id
                             )
                         }
                         .disabled(isAnswered)
                    }
                }
                .padding()
                
            } else {
                ProgressView("Preparing Challenge...")
            }
            
            Spacer()
        }
        .onAppear {
            loadNextChallenge()
        }
        .onChange(of: currentCardIndex) { _, _ in
            loadNextChallenge()
        }
        .onChange(of: currentCardId) { _, _ in
            loadNextChallenge()
        }
    }
    
    // MARK: - Subviews
    
    var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Challenge")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(learnedCount) / \(sessionCardGoal) points")
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
    
    // MARK: - Logic
    
    func loadNextChallenge() {
        guard currentCardIndex < sessionCards.count else { return }
        print("DEBUG: loadNextChallenge for index \(currentCardIndex)")
        let card = sessionCards[currentCardIndex]
        
        // Reset State
        selectedOptionId = nil
        isAnswered = false
        showFeedback = false
        isCorrect = false
        
        // Generate
        withAnimation {
            challenge = MultipleChoiceManager.shared.generateChallenge(for: card, deck: deck, sessionCards: sessionCards)
        }
        
        // Auto Play
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("DEBUG: MC AutoPlay triggering for index \(self.currentCardIndex)")
            self.playAudio()
        }
    }
    
    func playAudio() {
        guard let challenge = challenge else { 
            print("DEBUG: MC playAudio SKIPPED (No challenge)")
            return 
        }
        print("DEBUG: MC playAudio STARTING for \(challenge.correctCard.wordTarget)")
        let card = challenge.correctCard
        
        var sequence: [AudioManager.AudioItem] = []
        
        // Play text audio first? Or just sentence?
        // Usually target sentence is best context.
        if let audio = card.audioSentenceFile {
             sequence.append(AudioManager.AudioItem(filename: audio, text: card.sentenceTarget, language: deck.language))
        } else if let audio = card.audioWordFile {
             sequence.append(AudioManager.AudioItem(filename: audio, text: card.wordTarget, language: deck.language))
        } else {
            // Fallback (TTS)
            sequence.append(AudioManager.AudioItem(filename: "", text: card.sentenceTarget, language: deck.language, voiceGender: sessionConfig.ttsVoiceGender))
        }
        
        if !sequence.isEmpty {
            audioManager.playSequence(items: sequence, folderName: deck.baseFolderName, useFallback: sessionConfig.useTTSFallback, ttsRate: sessionConfig.ttsRate)
        }
    }
    
    func handleSelection(_ option: LearningCard) {
        guard let challenge = challenge, !isAnswered else { return }
        
        selectedOptionId = option.id
        isAnswered = true
        
        if option.id == challenge.correctCard.id {
            // Correct
            isCorrect = true
            SoundManager.shared.play(.win)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let onGrade = onGrade {
                    onGrade(.good)
                } else {
                    onLearned()
                }
            }
        } else {
            // Incorrect
            isCorrect = false
            SoundManager.shared.play(.mismatch)
            shakeTrigger += 1

            // Report wrong answer to SRS so the card is re-queued
            onGrade?(.again)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                 onNext()
            }
        }
    }
}

// Option Card Component
struct OptionCard: View {
    let card: LearningCard
    let mode: MultipleChoiceChallenge.ChallengeMode
    let isSelected: Bool
    let isAnswered: Bool
    let isCorrectTarget: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: 3)
                )
            
            content
                .padding()
        }
        .aspectRatio(1.2, contentMode: .fit) // Square-ish
    }
    
    @ViewBuilder
    var content: some View {
        if mode == .image {
            // Try to load image
            if let media = card.mediaFile {
                 // We need a way to load UIImage.
                 // Reusing DataManager is hard inside a pure View without EnvironmentObject if DataManager isn't passed around.
                 // BUT `ActiveSessionView` usually has `deck`.
                 // Let's assume standard Image view works if in bundle, or use a helper.
                 // AsyncImage is for URL.
                 // Let's use a helper view or just Image(media) if it's in assets.
                 // IF it's a file path... complexity.
                 // Given the codebase uses `Image(uiImage: ...)` usually.
                 // I will use a simplified Text placeholder if image fails for now, or assume Bundle Image.
                 
                 ImageLoaderView(filename: media, folderName: nil, fallbackText: card.wordTarget) // We'll need to know folder.
            } else {
                 Text(card.wordTarget) // Fallback to Target Word
            }
        } else {
            Text(card.wordNative)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.primary)
        }
    }
    
    var backgroundColor: Color {
        if isAnswered {
            if isCorrectTarget { return Color.green.opacity(0.2) }
            if isSelected { return Color.red.opacity(0.2) }
        }
        return Color(UIColor.secondarySystemGroupedBackground)
    }
    
    var borderColor: Color {
        if isAnswered {
            if isCorrectTarget { return Color.green }
            if isSelected { return Color.red }
        }
        return Color.clear
    }
    
    var shadowColor: Color {
        return Color.black.opacity(0.1)
    }
}

// Helper to load images safely
struct ImageLoaderView: View {
    let filename: String
    let folderName: String?
    let fallbackText: String?
    
    // We can access DataManager via Environment if needed, or just standard Bundle load
    @Environment(DataManager.self) private var dataManager
    
    var body: some View {
        if let image = dataManager.loadImage(folderName: folderName, filename: filename) {
             Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(8)
        } else {
             if let fallback = fallbackText {
                 Text(fallback)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
             } else {
                 Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
             }
        }
    }
}
