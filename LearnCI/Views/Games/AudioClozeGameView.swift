import SwiftUI

struct AudioClozeGameView: View {
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
    
    @State private var challenge: ClozeChallenge?
    @State private var selectedOption: String?
    @State private var isCorrect: Bool = false
    @State private var hasAnswered: Bool = false
    @State private var hadWrongAttempt: Bool = false
    @State private var wrongAttemptCount: Int = 0
    
    // Audio State
    @Environment(AudioManager.self) private var audioManager
    
    // Feedback Animations
    @State private var shakeAmount: CGFloat = 0
    
    var currentCard: LearningCard {
        sessionCards[currentCardIndex]
    }

    /// Stable identifier for the card currently at `currentCardIndex`.
    private var currentCardId: String {
        guard currentCardIndex < sessionCards.count else { return "" }
        return sessionCards[currentCardIndex].id
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 1. Progress Header
            ProgressHeader
            
            Spacer()
            
            // 2. Main Game Content
            VStack(spacing: 30) {
                // Audio Button (Large)
                Button(action: playAudio) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Cloze Sentence
                if let challenge = challenge {
                    if sessionConfig.audioClozeShowSentence {
                        Text(challenge.sentenceWithBlank)
                            .font(.title2)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    } else {
                        Text("Fill in the missing word")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                } else {
                    ProgressView()
                }
            }
            .offset(x: shakeAmount)
            
            Spacer()
            
            // 3. Options Grid
            if let challenge = challenge {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                    ForEach(challenge.options, id: \.self) { option in
                        Button(action: {
                            handleSelection(option)
                        }) {
                            Text(option)
                                .font(.headline)
                                .foregroundColor(buttonTextColor(for: option))
                                .padding()
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(buttonBackgroundColor(for: option))
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(buttonBorderColor(for: option), lineWidth: 2)
                                )
                        }
                        .disabled(hasAnswered)
                    }
                }
                .padding()
            }
            
            // 4. Translation + Continue (appears after correct answer)
            if hasAnswered && isCorrect {
                VStack(spacing: 12) {
                    if sessionConfig.audioClozeShowTranslation,
                       let challenge = challenge,
                       !challenge.card.sentenceNative.isEmpty {
                        Text(challenge.card.sentenceNative)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button(action: handleContinue) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(15)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
                .animation(.easeOut(duration: 0.3), value: hasAnswered)
            }
        }
        .onAppear(perform: loadChallenge)
        .onChange(of: currentCardIndex) { _, _ in
            loadChallenge()
        }
        .onChange(of: currentCardId) { _, _ in
            loadChallenge()
        }
    }
    
    // MARK: - Subviews
    
    var ProgressHeader: some View {
        HStack {
            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("Listening Challenge")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(learnedCount)/\(sessionCardGoal)")
                .font(.subheadline)
                .bold()
                .padding(6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Logic
    
    func loadChallenge() {
        guard currentCardIndex < sessionCards.count else { return }

        // Reset State
        selectedOption = nil
        isCorrect = false
        hasAnswered = false
        hadWrongAttempt = false
        wrongAttemptCount = 0

        // Generate new challenge
        let card = currentCard
        let others = deck.cards.filter { $0.id != card.id }

        self.challenge = ClozeManager.shared.generateChallenge(
            for: card,
            distractors: others,
            optionCount: sessionConfig.audioClozeOptionCount
        )
        
        // Auto-play audio after slight delay
        let expectedCardId = card.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard currentCardIndex < sessionCards.count,
                  sessionCards[currentCardIndex].id == expectedCardId else { return }
            playAudio()
        }
    }
    
    func playAudio() {
        guard let challenge = challenge else { return }
        let card = challenge.card

        var sequence: [AudioManager.AudioItem] = []

        // Word audio (only when sequence includes word)
        if sessionConfig.audioClozeAudioSequence == .wordThenSentence {
            if let wordFile = card.audioWordFile {
                sequence.append(AudioManager.AudioItem(filename: wordFile, text: card.wordTarget, language: deck.language, voiceGender: sessionConfig.ttsVoiceGender))
            }
        }

        // Sentence audio
        if let sentenceFile = card.audioSentenceFile {
            sequence.append(AudioManager.AudioItem(filename: sentenceFile, text: card.sentenceTarget, language: deck.language, voiceGender: sessionConfig.ttsVoiceGender))
        } else if !card.sentenceTarget.isEmpty {
            sequence.append(AudioManager.AudioItem(filename: "", text: card.sentenceTarget, language: deck.language, voiceGender: sessionConfig.ttsVoiceGender))
        }

        // Fallback: TTS word if nothing else available
        if sequence.isEmpty && !card.wordTarget.isEmpty {
            sequence.append(AudioManager.AudioItem(filename: "", text: card.wordTarget, language: deck.language, voiceGender: sessionConfig.ttsVoiceGender))
        }

        if !sequence.isEmpty {
            audioManager.playSequence(items: sequence, folderName: deck.baseFolderName, useFallback: sessionConfig.useTTSFallback, ttsRate: sessionConfig.ttsRate)
        }
    }
    
    func playSentenceAudio() {
        guard let challenge = challenge else { return }
        let card = challenge.card
        var items: [AudioManager.AudioItem] = []
        if let sentenceFile = card.audioSentenceFile {
            items.append(AudioManager.AudioItem(filename: sentenceFile, text: card.sentenceTarget, language: deck.language, voiceGender: sessionConfig.ttsVoiceGender))
        } else if !card.sentenceTarget.isEmpty {
            items.append(AudioManager.AudioItem(filename: "", text: card.sentenceTarget, language: deck.language, voiceGender: sessionConfig.ttsVoiceGender))
        }
        if !items.isEmpty {
            audioManager.playSequence(items: items, folderName: deck.baseFolderName, useFallback: sessionConfig.useTTSFallback, ttsRate: sessionConfig.ttsRate)
        }
    }

    func handleSelection(_ option: String) {
        guard let challenge = challenge, !hasAnswered else { return }

        selectedOption = option

        if option == challenge.missingWord {
            // Correct
            isCorrect = true
            hasAnswered = true
            playSuccessSound()

            if sessionConfig.audioClozeReplayAfterCorrect {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    playSentenceAudio()
                }
            }
        } else {
            // Incorrect
            hadWrongAttempt = true
            wrongAttemptCount += 1
            playErrorFeedback()
            // selectedOption stays set (to show red)

            // "Try Again" style:
            withAnimation(.default) {
                shakeAmount = 10
            }
            withAnimation(.default.delay(0.1)) {
                shakeAmount = 0
            }
        }
    }
    
    func handleContinue() {
        if let onGrade = onGrade {
            onGrade(hadWrongAttempt ? .hard : .good)
        } else {
            onLearned()
        }
    }
    
    // MARK: - Helpers
    
    func playSuccessSound() {
        // Haptic or System Sound
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    func playErrorFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    // MARK: - UI Styling
    
    func buttonBackgroundColor(for option: String) -> Color {
        // 0. Hint: Reveal correct answer after 2 wrong attempts
        if wrongAttemptCount >= 2, let challenge = challenge, option == challenge.missingWord, !hasAnswered {
            return Color.green.opacity(0.15)
        }

        // 1. Reveal Correct Answer if answered
        if hasAnswered, let challenge = challenge, option == challenge.missingWord {
            return Color.green.opacity(0.2)
        }
        
        // 2. Show Selection (Wrong or Right)
        if option == selectedOption {
             // If we are here, and hasAnswered is false, it MUST be wrong (since Correct sets hasAnswered=true)
             // OR it's the moment before hasAnswered updates? No, state update matches.
             // If hasAnswered is true, we handled it above (if it was the correct one).
             // If selectedOption was the WRONG one, and we answered CORRECTLY later?
             // No, hasAnswered locks interactions.
             
             // Simple rule:
             if isCorrect {
                 return Color.green.opacity(0.2)
             } else {
                 return Color.red.opacity(0.2)
             }
        }
        
        return Color.white
    }
    
    func buttonBorderColor(for option: String) -> Color {
        if hasAnswered, let challenge = challenge, option == challenge.missingWord {
            return Color.green
        }
        
        if option == selectedOption && !isCorrect {
            return Color.red
        }
        
        // Hint: Reveal correct answer after 2 wrong attempts
        if wrongAttemptCount >= 2, let challenge = challenge, option == challenge.missingWord, !hasAnswered {
            return Color.green.opacity(0.5)
        }

        return Color.gray.opacity(0.2)
    }

    func buttonTextColor(for option: String) -> Color {
        if hasAnswered, let challenge = challenge, option == challenge.missingWord {
            return Color.green
        }
        if option == selectedOption && !isCorrect {
            return Color.red
        }
        return Color.primary
    }
}
