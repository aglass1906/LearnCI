import SwiftUI

struct WordCrushGameView: View {
    @State private var viewModel: WordCrushGameViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(AudioManager.self) private var audioManager

    let sessionCardGoal: Int
    var onFinish: () -> Void
    var onGrade: ((SmartSessionManager.Grade) -> Void)?
    var onMatchFound: (() -> Void)?

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: viewModel.columns)
    }

    private var tileHeight: CGFloat {
        switch viewModel.config.wordCrushGridSize {
        case .small: return 64
        case .medium: return 56
        case .large: return 48
        }
    }

    init(deck: CardDeck, sessionCards: [LearningCard], sessionConfig: GameConfiguration, sessionCardGoal: Int = 20, onFinish: @escaping () -> Void, onGrade: ((SmartSessionManager.Grade) -> Void)? = nil, onMatchFound: (() -> Void)? = nil) {
        _viewModel = State(initialValue: WordCrushGameViewModel(
            deck: deck,
            sessionCards: sessionCards,
            config: sessionConfig,
            sessionCardGoal: sessionCardGoal,
            onGrade: onGrade
        ))
        self.sessionCardGoal = sessionCardGoal
        self.onFinish = onFinish
        self.onGrade = onGrade
        self.onMatchFound = onMatchFound
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer(minLength: 12)

                // Grid
                gridView
                    .padding(.horizontal, 12)

                Spacer()
            }

            // Match celebration overlay
            if let celebration = viewModel.matchCelebration {
                MatchCelebrationView(celebration: celebration)
                    .id(celebration.id)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            viewModel.audioManager = audioManager
            viewModel.onMatchFound = onMatchFound
            viewModel.onFinish = onFinish
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            // Score
            VStack(alignment: .leading, spacing: 2) {
                Text("Score")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(viewModel.score)")
                    .font(.title2.bold())
            }

            Spacer()

            // Streak
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

            // Matches
            VStack(alignment: .trailing, spacing: 2) {
                Text("Matches")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(viewModel.matchesFound)")
                    .font(.title2.bold())
            }
        }
        .animation(.easeInOut, value: viewModel.streak)
    }

    // MARK: - Grid

    private var gridView: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(sortedTiles) { tile in
                WordCrushTileView(
                    tile: tile,
                    isShaking: viewModel.shakeTileIds.contains(tile.id),
                    height: tileHeight,
                    folderName: viewModel.deck.baseFolderName
                )
                .onTapGesture {
                    viewModel.selectTile(tile)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.tiles)
    }

    private var sortedTiles: [WordCrushTile] {
        viewModel.tiles
            .filter { !$0.isMatched }
            .sorted { ($0.row * 10 + $0.col) < ($1.row * 10 + $1.col) }
    }
}

// MARK: - Tile View

struct WordCrushTileView: View {
    let tile: WordCrushTile
    let isShaking: Bool
    var height: CGFloat = 56
    var folderName: String?

    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        tileContent
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(tileColor)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tile.isSelected ? Color.yellow : Color.clear, lineWidth: 3)
            )
            .scaleEffect(tile.isSelected ? 1.08 : 1.0)
            .offset(x: shakeOffset)
            .animation(.spring(response: 0.2), value: tile.isSelected)
            .onChange(of: isShaking) { _, shaking in
                if shaking {
                    performShake()
                }
            }
    }

    @ViewBuilder
    private var tileContent: some View {
        if let media = tile.mediaFile {
            ImageLoaderView(filename: media, folderName: folderName, fallbackText: tile.word.isEmpty ? "?" : tile.word)
                .padding(4)
        } else {
            Text(tile.word)
                .font(.system(height < 56 ? .caption : .body, design: .rounded).bold())
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private var tileColor: Color {
        if tile.isTarget {
            return Color.blue.opacity(tile.isSelected ? 0.35 : 0.15)
        } else {
            return Color.green.opacity(tile.isSelected ? 0.35 : 0.15)
        }
    }

    private func performShake() {
        let duration = 0.06
        withAnimation(.linear(duration: duration)) { shakeOffset = 8 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.linear(duration: duration)) { shakeOffset = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 2) {
            withAnimation(.linear(duration: duration)) { shakeOffset = 6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 3) {
            withAnimation(.linear(duration: duration)) { shakeOffset = -4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 4) {
            withAnimation(.linear(duration: duration)) { shakeOffset = 0 }
        }
    }
}

// MARK: - Match Celebration

struct MatchCelebrationView: View {
    let celebration: MatchCelebration

    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var scale: CGFloat = 0.5
    @State private var particles: [(id: Int, x: CGFloat, y: CGFloat, emoji: String)] = []

    private let emojis = ["🎉", "⭐", "✨", "🔥", "💥", "🌟"]

    var body: some View {
        ZStack {
            // Particle emojis (for streaks >= 2)
            ForEach(particles, id: \.id) { particle in
                Text(particle.emoji)
                    .font(.title)
                    .offset(x: particle.x, y: particle.y)
                    .opacity(opacity)
            }

            // Floating points bubble
            VStack(spacing: 4) {
                Text("+\(celebration.points)")
                    .font(.system(size: celebration.streak >= 3 ? 32 : 24, weight: .black, design: .rounded))
                    .foregroundColor(bubbleColor)

                if celebration.streak >= 2 {
                    Text("\(celebration.streak)x Streak!")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                }

                Text(celebration.word)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: bubbleColor.opacity(0.3), radius: 8)
            )
            .scaleEffect(scale)
            .offset(y: offset)
            .opacity(opacity)
        }
        .onAppear {
            // Spawn particles for streaks
            if celebration.streak >= 2 {
                spawnParticles()
            }

            // Animate in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                scale = 1.0
            }

            // Float up to top of screen and fade out
            withAnimation(.easeOut(duration: 1.5).delay(0.3)) {
                offset = -UIScreen.main.bounds.height / 2
                opacity = 0
            }

            // Animate particles outward
            withAnimation(.easeOut(duration: 1.0).delay(0.1)) {
                for i in particles.indices {
                    particles[i].x *= 3
                    particles[i].y *= 3
                }
            }
        }
    }

    private var bubbleColor: Color {
        switch celebration.streak {
        case 1: return .green
        case 2: return .blue
        case 3: return .purple
        case 4: return .orange
        default: return .red
        }
    }

    private func spawnParticles() {
        let count = min(celebration.streak + 2, 8)
        particles = (0..<count).map { i in
            let angle = Double(i) / Double(count) * 2 * .pi
            let radius: CGFloat = 30
            return (
                id: i,
                x: cos(angle) * radius,
                y: sin(angle) * radius,
                emoji: emojis.randomElement()!
            )
        }
    }
}
