
import SwiftUI

struct LinkerGameView: View {
    @State private var viewModel: LinkerGameViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(AudioManager.self) private var audioManager
    let sessionCardGoal: Int
    var onFinish: () -> Void
    
    init(deck: CardDeck, config: GameConfiguration, sessionCardGoal: Int, onFinish: @escaping () -> Void) {
        _viewModel = State(initialValue: LinkerGameViewModel(deck: deck, config: config, sessionCardGoal: sessionCardGoal))
        self.sessionCardGoal = sessionCardGoal
        self.onFinish = onFinish
    }
    
    var body: some View {
        VStack {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                Spacer()
                Text(viewModel.currentRound.title)
                    .font(.headline)
                Spacer()
                Text("Score: \(viewModel.score)")
                    .font(.subheadline)
            }
            .padding()
            
            if viewModel.isGameOver {
                GameOverView(score: viewModel.score, onRestart: viewModel.restartGame, onDismiss: onFinish)
            } else {
                // Game Area
                HStack(spacing: 20) {
                    // Left Column
                    VStack(spacing: 15) {
                        ForEach(viewModel.leftItems) { item in
                            LinkerItemView(item: item, isSelected: viewModel.selectedLeftId == item.id)
                                .onTapGesture {
                                    viewModel.selectLeft(item)
                                }
                                .disabled(item.isMatched)
                                .opacity(item.isMatched ? 0.0 : 1.0) // Fade out matched
                        }
                    }
                    
                    // Right Column
                    VStack(spacing: 15) {
                        ForEach(viewModel.rightItems) { item in
                            LinkerItemView(item: item, isSelected: false)
                                .onTapGesture {
                                    viewModel.selectRight(item)
                                }
                                .disabled(item.isMatched)
                                .opacity(item.isMatched ? 0.0 : 1.0)
                        }
                    }
                }
                .padding()
            }
            
            Spacer()
        }
        .onAppear {
            viewModel.audioManager = audioManager
            viewModel.startRound()
        }
        .onChange(of: viewModel.currentRoundIndex) { _, _ in
             // Round changed, maybe play a sound?
        }
    }
}

struct LinkerItemView: View {
    let item: LinkerItem
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardColor)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 2)
            
            contentView
                .padding()
        }
        .frame(height: 80)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(), value: isSelected)
    }
    
    var cardColor: Color {
        if item.isMatched { return .green.opacity(0.2) }
        if item.isError { return .red.opacity(0.2) }
        if isSelected { return .blue.opacity(0.2) }
        return Color(.secondarySystemBackground)
    }
    
    @ViewBuilder
    var contentView: some View {
        switch item.content {
        case .text(let text):
            Text(text)
                .font(.body.bold())
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        case .image(let imageName):
            // Placeholder for actual image loading logic
            // Assuming we have a helper or AsyncImage
            if let uiImage = UIImage(named: imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
            }
        case .audio(_):
            Image(systemName: "speaker.wave.2.fill")
                .font(.title)
                .foregroundColor(.blue)
        }
    }
}

struct GameOverView: View {
    let score: Int
    let onRestart: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Text("Game Over!")
                .font(.largeTitle.bold())
            
            Text("Final Score: \(score)")
                .font(.title)
            
            HStack(spacing: 20) {
                Button("Restart") {
                    onRestart()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
    }
}
