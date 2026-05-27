import SwiftUI

// MARK: - Memory Match Game View
/// Grid-based card matching game (4x4 grid, requires multiples of 8 cards).
///
/// Session Settings Used:
/// - sessionCardGoal: Number of cards (must be multiples of 8)
/// - useTTSFallback: Enable TTS for audio playback
/// - ttsRate: Speech playback speed
///
/// Current State:
/// - Has internal state management via MemoryGameEngine
/// - Does NOT use SmartSessionManager
///
/// Future Refactor Notes (Phase 4):
/// - TODO: Extract MemoryGameEngine logic into MemoryGameViewModel
/// - TODO: Integrate with SmartSessionManager for deck management
/// - TODO: Respect sessionDuration timer
/// - TODO: Standardize init signature to match other games

struct MemoryGameView: View {
    let deck: CardDeck
    let sessionCards: [LearningCard]
    let sessionConfig: GameConfiguration
    let matchMode: GameConfiguration.MemoryMatchMode
    let onGameComplete: () -> Void
    let onMatchFound: () -> Void

    @Environment(AudioManager.self) private var audioManager
    @State private var viewModel: MemoryGameViewModel

    init(deck: CardDeck, sessionCards: [LearningCard], sessionConfig: GameConfiguration, matchMode: GameConfiguration.MemoryMatchMode = .pictureToWord, onGameComplete: @escaping () -> Void, onMatchFound: @escaping () -> Void) {
        self.deck = deck
        self.sessionCards = sessionCards
        self.sessionConfig = sessionConfig
        self.matchMode = matchMode
        self.onGameComplete = onGameComplete
        self.onMatchFound = onMatchFound
        _viewModel = State(initialValue: MemoryGameViewModel(sessionCards: sessionCards, matchMode: matchMode))
    }
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                headerView
                    .padding()
                
                // Grid
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(viewModel.cards.enumerated()), id: \.element.id) { index, card in
                        CardTile(card: card)
                            .onTapGesture {
                                GameFeedbackManager.shared.flip()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    viewModel.flipCard(at: index)
                                }
                            }
                    }
                }
                .padding()
                
                Spacer()
            }
            
            if viewModel.isRoundComplete {
                roundCompleteBanner
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            setupEngineCallbacks()
            // Start the session when view appears
            viewModel.startSession()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.isRoundComplete)
        // Removed onChange(of: sessionCards) as it's no longer needed
    }
    
    private var headerView: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory Match")
                        .font(.headline)
                        .foregroundColor(.purple)
                    Text("Round \(viewModel.currentRoundNumber) of \(viewModel.totalRounds)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Moves")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(viewModel.moves)")
                        .font(.title3.bold())
                        .monospacedDigit()
                }
            }
            
            ProgressView(value: Double(viewModel.matchedPairs), total: Double(max(1, viewModel.totalPairs)))
                .tint(.purple)
            
            HStack {
                Text("\(viewModel.matchedPairs) / \(viewModel.totalPairs) pairs")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.completedCards) cards cleared")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var roundCompleteBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)
            Text("Round Complete")
                .font(.title3.bold())
            Text("Nice board clear")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
    }
    
    func setupEngineCallbacks() {
        viewModel.playAudio = { filename, text in
            // Handle optional filename, but we always have text
            let safeFilename = filename ?? ""
            let item = AudioManager.AudioItem(filename: safeFilename, text: text, language: deck.language, voiceGender: sessionConfig.ttsVoiceGender)
            
            // Use TTS fallback and the session's configured speed
            let rate = sessionConfig.ttsRate
            audioManager.playSequence(items: [item], folderName: deck.baseFolderName, useFallback: true, ttsRate: rate)
        }
        
        viewModel.onGameComplete = {
            GameFeedbackManager.shared.complete()
            onGameComplete()
        }
        
        viewModel.onMatchFound = {
            GameFeedbackManager.shared.match()
            onMatchFound()
        }
        
        viewModel.onMistake = {
            GameFeedbackManager.shared.incorrect()
        }
    }
}

struct CardTile: View {
    let card: MemoryCard
    
    var body: some View {
        ZStack {
            // Card Back (Face Down)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.gradient)
                .overlay(
                    Image(systemName: "questionmark")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.5))
                )
                .opacity(card.isFlipped || card.isMatched ? 0 : 1)
            
            // Card Front (Face Up)
            RoundedRectangle(cornerRadius: 12)
                .fill(card.isMatched ? Color.green.opacity(0.2) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(card.isMatched ? Color.green : Color.gray.opacity(0.3), lineWidth: 2)
                )
                .overlay(
                    Group {
                        if let mediaFile = card.mediaFile, !mediaFile.isEmpty {
                            // Show image if available
                            AsyncImage(url: imageURL(for: mediaFile)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .padding(4)
                                case .failure(_), .empty:
                                    // Fallback to text if image fails
                                    Text(card.content)
                                        .font(.system(size: 14, weight: .semibold))
                                        .multilineTextAlignment(.center)
                                        .padding(4)
                                        .foregroundColor(.black)
                                @unknown default:
                                    Text(card.content)
                                        .font(.system(size: 14, weight: .semibold))
                                        .multilineTextAlignment(.center)
                                        .padding(4)
                                        .foregroundColor(.black)
                                }
                            }
                        } else {
                            // No image, show text
                            Text(card.content)
                                .font(.system(size: 14, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .padding(4)
                                .foregroundColor(.black)
                        }
                    }
                )
                .opacity(card.isFlipped || card.isMatched ? 1 : 0)
                .rotation3DEffect(
                    .degrees(180),
                    axis: (x: 0.0, y: 1.0, z: 0.0)
                )
        }
        .aspectRatio(0.75, contentMode: .fit)
        .rotation3DEffect(
            .degrees(card.isFlipped || card.isMatched ? 180 : 0),
            axis: (x: 0.0, y: 1.0, z: 0.0)
        )
        .scaleEffect(card.isMatched ? 0.96 : 1.0)
        .shadow(color: card.isMatched ? .green.opacity(0.28) : .clear, radius: 8)
        .animation(.default, value: card.isFlipped)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: card.isMatched)
    }
    
    // Helper to resolve image URL
    private func imageURL(for filename: String) -> URL? {
        // Try bundle resources first
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.isEmpty ? "jpg" : (filename as NSString).pathExtension
        
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Images") ??
                      Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Images") {
            return url
        }
        
        return nil
    }
}
