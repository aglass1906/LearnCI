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
        VStack {
            // Header
            HStack {
                Text("Memory Match")
                    .font(.headline)
                    .foregroundColor(.purple)
                Spacer()
                Text("Moves: \(viewModel.moves)")
                    .font(.subheadline)
                    .monospacedDigit()
            }
            .padding()
            
            // Grid
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(viewModel.cards.enumerated()), id: \.element.id) { index, card in
                    CardTile(card: card)
                        .onTapGesture {
                            SoundManager.shared.play(.flip)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                viewModel.flipCard(at: index)
                            }
                        }
                }
            }
            .padding()
            
            Spacer()
        }
        .onAppear {
            setupEngineCallbacks()
            // Start the session when view appears
            viewModel.startSession()
        }
        // Removed onChange(of: sessionCards) as it's no longer needed
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
            SoundManager.shared.play(.win)
            onGameComplete()
        }
        
        viewModel.onMatchFound = {
            SoundManager.shared.play(.match)
            onMatchFound()
        }
        
        viewModel.onMistake = {
            SoundManager.shared.play(.mismatch)
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
        .animation(.default, value: card.isFlipped)
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
