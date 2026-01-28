import SwiftUI

struct FlashcardGameView: View {
    let deck: CardDeck
    let sessionCards: [LearningCard]
    let currentCardIndex: Int
    let learnedCount: Int
    let sessionCardGoal: Int
    let sessionConfig: GameConfiguration
    @Binding var isFlipped: Bool
    
    let onRelearn: () -> Void
    let onLearned: () -> Void
    let onNext: () -> Void
    let onPrev: () -> Void
    
    @Environment(AudioManager.self) private var audioManager
    
    // Track which card index the timer was started for
    @State private var timerCardIndex: Int?
    
    var body: some View {
        if sessionCards.isEmpty {
            Text("No cards available.")
        } else {
            let card = sessionCards[currentCardIndex]
            
            VStack {
                // Top Navigation (Only for .buttons style)
                if sessionConfig.navigation == .buttons {
                    topNavigation
                }
                
                ScrollView {
                    VStack {
                        // Progress Header (Hide if .buttons? Keep for now)
                        progressHeader
                        
                        // Card View with Conditional Drag Gesture and Slide Animation
                        ActiveCardStack(card: card, deck: deck, config: sessionConfig, isFlipped: $isFlipped)
                            .offset(x: cardOffset)
                            .gesture(dragGesture)
                    }
                    .padding(.bottom, 20)
                }
                
                // Bottom Controls - Always visible
                confirmationControls
            }
            .onChange(of: audioManager.isPlaying) { wasPlaying, isNowPlaying in
                // When audio finishes (isPlaying goes false), start auto-advance timer
                if sessionConfig.navigation == .autoNext && wasPlaying && !isNowPlaying {
                    startAutoNextTimer()
                }
            }
            .onChange(of: currentCardIndex) { _, newIndex in
                // Reset timer tracking and card position when card changes
                timerCardIndex = nil
                cardOffset = 0
            }
        }
    }
    
    // MARK: - Animation State
    
    @State private var cardOffset: CGFloat = 0
    
    // MARK: - Gestures
    
    var dragGesture: some Gesture {
        DragGesture()
            .onEnded { value in
                guard sessionConfig.navigation == .swipe else { return }
                
                let threshold: CGFloat = 50
                let screenWidth = UIScreen.main.bounds.width
                
                if value.translation.width < -threshold && currentCardIndex < sessionCards.count - 1 {
                    // Swipe left - animate card off to the left, then next (only if not last card)
                    withAnimation(.easeOut(duration: 0.2)) {
                        cardOffset = -screenWidth
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onNext()
                    }
                } else if value.translation.width > threshold && currentCardIndex > 0 {
                    // Swipe right - animate card off to the right, then prev (only if not first card)
                    withAnimation(.easeOut(duration: 0.2)) {
                        cardOffset = screenWidth
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onPrev()
                    }
                }
            }
    }
    
    // MARK: - Auto Next
    
    func startAutoNextTimer() {
        guard sessionConfig.navigation == .autoNext else { return }
        
        // Prevent duplicate timers for the same card
        guard timerCardIndex != currentCardIndex else { return }
        timerCardIndex = currentCardIndex
        
        let expectedIndex = currentCardIndex
        
        DispatchQueue.main.asyncAfter(deadline: .now() + sessionConfig.autoNextDelay) {
            // Only advance if we're still on the expected card
            if currentCardIndex == expectedIndex && sessionConfig.navigation == .autoNext {
                onNext()
            }
        }
    }
    
    // MARK: - Subviews
    
    var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Session Progress")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(learnedCount) / \(sessionCardGoal) cards")
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
    
    var topNavigation: some View {
        HStack {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .padding()
            }
            .disabled(currentCardIndex == 0)
            
            Spacer()
            
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .padding()
            }
            .disabled(currentCardIndex >= deck.cards.count - 1)
        }
        .background(Color(.systemBackground))
    }
    
    var confirmationControls: some View {
        Group {
            switch sessionConfig.confirmation {
            case .quiz:
                quizControls
            case .srs:
                srsControls
            case .show:
                showControls
            case .auto:
                EmptyView() // Handled by AutoNext or manual swipe
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
    
    var quizControls: some View {
        HStack(spacing: 20) {
            Button(action: onRelearn) {
                VStack {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.largeTitle)
                    Text("Relearn")
                        .font(.caption.bold())
                }
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
            
            Button(action: onLearned) {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                    Text("Learned")
                        .font(.caption.bold())
                }
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    var srsControls: some View {
        HStack(spacing: 12) {
            Button(action: onRelearn) {
                VStack {
                    Text("Hard")
                        .font(.headline)
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
            
            // "Good" usually maps to Learned (or intermediate logic if we had it)
            // For now, mapping Good -> Learned
            Button(action: onLearned) {
                VStack {
                    Text("Good")
                        .font(.headline)
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            
            // "Easy" also maps to Learned 
            Button(action: onLearned) {
                VStack {
                    Text("Easy")
                        .font(.headline)
                }
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    var showControls: some View {
        Button(action: onNext) {
            Label("Next Card", systemImage: "arrow.right.circle.fill")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
        }
    }
    // "navigationControls" func removed as replaced by topNavigation and confirmationControls logic
}
