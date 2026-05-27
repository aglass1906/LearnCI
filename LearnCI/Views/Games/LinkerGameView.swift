
import SwiftUI
import Observation

struct LinkerGameView: View {
    @State private var viewModel: LinkerGameViewModel
    @Environment(AudioManager.self) private var audioManager
    @State private var showRoundBanner = true
    @State private var didFinish = false
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
        ZStack {
            VStack(spacing: 0) {
                headerView
                    .padding()
                
                if viewModel.isGameOver {
                    completionView
                } else {
                    gameArea
                }
                
                Spacer()
            }
            
            if showRoundBanner && !viewModel.isGameOver {
                roundBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            viewModel.audioManager = audioManager
            viewModel.onMatchFound = onMatchFound
            showTransientRoundBanner()
        }
        .onChange(of: viewModel.currentRoundIndex) { _, _ in
            showTransientRoundBanner()
        }
        .onChange(of: viewModel.isGameOver) { _, isGameOver in
            guard isGameOver, !didFinish else { return }
            didFinish = true
            GameFeedbackManager.shared.complete()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onFinish()
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentRound.title)
                        .font(.headline)
                    Text("Round \(viewModel.currentRoundIndex + 1) of \(viewModel.rounds.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Score")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(viewModel.score)")
                        .font(.title3.bold())
                        .monospacedDigit()
                }
            }
            
            ProgressView(value: viewModel.currentRoundProgress)
                .tint(.cyan)
            
            HStack {
                Text("\(viewModel.currentRoundCompleted) / \(viewModel.currentRoundTotal) links")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(max(0, viewModel.currentRoundTotal - viewModel.currentRoundCompleted)) left")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var gameArea: some View {
        HStack(spacing: 20) {
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
    
    private var roundBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.currentRound.iconName)
                .font(.system(size: 38))
                .foregroundColor(.cyan)
            Text(viewModel.currentRound.title)
                .font(.title3.bold())
            Text("Round \(viewModel.currentRoundIndex + 1)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
    }
    
    private var completionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            Text("Column Connect Complete")
                .font(.title3.bold())
            Text("Wrapping up your session...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func showTransientRoundBanner() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showRoundBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.2)) {
                showRoundBanner = false
            }
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
