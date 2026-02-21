
import SwiftUI
import Observation

struct LinkerGameView: View {
    @State private var viewModel: LinkerGameViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(AudioManager.self) private var audioManager
    let sessionCardGoal: Int
    var onFinish: () -> Void
    var onGrade: ((SmartSessionManager.Grade) -> Void)?
    var onMatchFound: (() -> Void)?
    
    init(deck: CardDeck, sessionCards: [LearningCard], config: GameConfiguration, sessionCardGoal: Int, onFinish: @escaping () -> Void, onGrade: ((SmartSessionManager.Grade) -> Void)? = nil, onMatchFound: (() -> Void)? = nil) {
        _viewModel = State(initialValue: LinkerGameViewModel(deck: deck, sessionCards: sessionCards, config: config, sessionCardGoal: sessionCardGoal, onGrade: onGrade))
        self.sessionCardGoal = sessionCardGoal
        self.onFinish = onFinish
        self.onGrade = onGrade
        self.onMatchFound = onMatchFound
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
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    
                    // Right Column
                    VStack(spacing: 15) {
                        ForEach(viewModel.rightItems) { item in
                            LinkerItemView(item: item, isSelected: false)
                                .onTapGesture {
                                    viewModel.selectRight(item)
                                }
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
                .padding()
                .animation(.spring(), value: viewModel.leftItems)
                .animation(.spring(), value: viewModel.rightItems)
            }
            
            Spacer()
        }
        .onAppear {
            viewModel.audioManager = audioManager
            viewModel.onMatchFound = onMatchFound
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
        .frame(height: item.content.isImage ? 120 : 80)
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
            ImageLoaderView(filename: imageName, folderName: nil, fallbackText: nil)
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
