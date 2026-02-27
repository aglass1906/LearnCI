import SwiftUI
import Combine

struct WordRainGameView: View {
    @State private var viewModel: WordRainGameViewModel
    @Environment(AudioManager.self) private var audioManager

    let onFinish: () -> Void
    let onGrade: ((SmartSessionManager.Grade) -> Void)?
    let onWordLearned: (() -> Void)?

    private let gameTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    init(deck: CardDeck, sessionCards: [LearningCard], sessionConfig: GameConfiguration,
         sessionCardGoal: Int = 20,
         onFinish: @escaping () -> Void,
         onGrade: ((SmartSessionManager.Grade) -> Void)? = nil,
         onWordLearned: (() -> Void)? = nil) {
        _viewModel = State(initialValue: WordRainGameViewModel(
            deck: deck,
            sessionCards: sessionCards,
            config: sessionConfig,
            sessionCardGoal: sessionCardGoal,
            onGrade: onGrade
        ))
        self.onFinish = onFinish
        self.onGrade = onGrade
        self.onWordLearned = onWordLearned
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                // Falling word drops
                fallingWordsLayer(geo: geo)

                // Red flash overlay when life is lost
                if viewModel.screenFlashing {
                    Color.red.opacity(0.25)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // HUD + progress + streak banner + target word
                VStack(spacing: 0) {
                    hudView
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    progressView
                        .padding(.top, 6)

                    if let banner = viewModel.streakBannerText {
                        streakBanner(text: banner)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer()

                    targetWordView
                        .padding(.bottom, 24)
                }

                // Match celebration overlay
                if let celebration = viewModel.celebration {
                    MatchCelebrationView(celebration: celebration)
                        .id(celebration.id)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                viewModel.audioManager = audioManager
                viewModel.onWordLearned = onWordLearned
                viewModel.onFinish = onFinish
                viewModel.screenHeight = geo.size.height
                viewModel.screenWidth = geo.size.width
                viewModel.spawnNextWave()
            }
        }
        .onReceive(gameTimer) { now in
            viewModel.tick(date: now)
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.streakBannerText != nil)
        .animation(.easeInOut(duration: 0.1), value: viewModel.screenFlashing)
        .animation(.easeInOut(duration: 0.2), value: viewModel.streak)
        .animation(.easeInOut(duration: 0.3), value: viewModel.wordsCompleted)
    }

    // MARK: - Falling Words

    @ViewBuilder
    private func fallingWordsLayer(geo: GeometryProxy) -> some View {
        ZStack {
            ForEach(viewModel.fallingWords) { word in
                if word.state == .falling {
                    FallingWordDropView(
                        word: word,
                        isShaking: viewModel.shakingWordIds.contains(word.id),
                        isHighStreak: viewModel.streak >= 3
                    )
                    .position(
                        x: word.xFraction * geo.size.width,
                        y: word.yPosition
                    )
                    .onTapGesture {
                        viewModel.wordTapped(id: word.id)
                    }
                }
            }
        }
    }

    // MARK: - HUD

    private var hudView: some View {
        HStack {
            // Lives (hearts)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < viewModel.lives ? "heart.fill" : "heart")
                        .foregroundColor(i < viewModel.lives ? .red : Color(UIColor.systemGray4))
                        .font(.title3)
                }
            }

            Spacer()

            // Streak indicator
            if viewModel.streak > 1 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("\(viewModel.streak)x")
                        .font(.headline.bold())
                        .foregroundColor(.orange)
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // Score
            VStack(alignment: .trailing, spacing: 2) {
                Text("Score")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(viewModel.score)")
                    .font(.title2.bold())
            }
        }
    }

    // MARK: - Progress Bar

    private var progressView: some View {
        let completed = viewModel.wordsCompleted
        let goal = max(1, viewModel.sessionCardGoal)
        let remaining = max(0, goal - completed)
        return VStack(spacing: 4) {
            ProgressView(value: Double(completed), total: Double(goal))
                .tint(.teal)
                .animation(.easeInOut(duration: 0.3), value: completed)
            HStack {
                Text("\(completed) / \(goal) words")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(remaining == 0 ? "Done!" : "\(remaining) left")
                    .font(.caption2)
                    .foregroundColor(remaining <= 3 ? .teal : .secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Streak Banner

    private func streakBanner(text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.orange)
                    .shadow(color: .orange.opacity(0.4), radius: 6)
            )
    }

    // MARK: - Target Word

    private var targetWordView: some View {
        VStack(spacing: 6) {
            Text("Tap the word for:")
                .font(.caption)
                .foregroundColor(.secondary)

            if let card = viewModel.targetCard {
                Text(card.wordNative)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.teal.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.teal, lineWidth: 2)
                            )
                    )
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Falling Word Drop View

struct FallingWordDropView: View {
    let word: FallingWord
    let isShaking: Bool
    let isHighStreak: Bool

    @State private var shakeOffset: CGFloat = 0
    @State private var glowPulse: Bool = false

    var body: some View {
        Text(word.text)
            .font(.system(.body, design: .rounded).bold())
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(dropBackground)
            .shadow(
                color: isHighStreak ? Color.orange.opacity(0.45) : Color.black.opacity(0.1),
                radius: isHighStreak ? (glowPulse ? 10 : 6) : 3
            )
            .scaleEffect(isHighStreak && glowPulse ? 1.04 : 1.0)
            .offset(x: shakeOffset)
            .onChange(of: isShaking) { _, shaking in
                if shaking { performShake() }
            }
            .onAppear {
                if isHighStreak {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        glowPulse = true
                    }
                }
            }
            .onChange(of: isHighStreak) { _, highStreak in
                if highStreak {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        glowPulse = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        glowPulse = false
                    }
                }
            }
    }

    private var dropBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(UIColor.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isHighStreak ? Color.orange.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
    }

    private func performShake() {
        let d = 0.06
        withAnimation(.linear(duration: d)) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + d) {
            withAnimation(.linear(duration: d)) { shakeOffset = -10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 2) {
            withAnimation(.linear(duration: d)) { shakeOffset = 7 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 3) {
            withAnimation(.linear(duration: d)) { shakeOffset = -4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 4) {
            withAnimation(.linear(duration: d)) { shakeOffset = 0 }
        }
    }
}
