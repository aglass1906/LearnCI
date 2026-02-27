import SwiftUI

struct SessionFinishView: View {
    let learnedCount: Int
    let elapsedSeconds: Int
    @Binding var setupStage: GameView.GameSetupStage

    // Config Stats
    let deckTitle: String
    let coverImage: String?
    let folderName: String?
    let language: Language
    let level: Int
    let preset: GameConfiguration.Preset
    let gameType: GameConfiguration.GameType
    let duration: Int
    let cardGoal: Int
    let order: GameConfiguration.OrderStrategy
    var filterText: String? = nil

    let onPlayAgain: () -> Void

    // Animation state
    @State private var trophyScale: CGFloat = 0
    @State private var trophyRotation: Double = -20
    @State private var displayCount: Int = 0
    @State private var ringProgress: Double = 0
    @State private var showStats = false
    @State private var showSummary = false
    @State private var showButtons = false
    @State private var sparkleScales: [CGFloat] = Array(repeating: 0, count: 6)
    @State private var sparkleOpacities: [Double] = Array(repeating: 0, count: 6)

    // Sparkle positions: hexagonal arrangement at radius ~68
    private let sparkleOffsets: [(CGFloat, CGFloat)] = [
        (0, -68), (59, -34), (59, 34), (0, 68), (-59, 34), (-59, -34)
    ]
    private let sparkleSymbols = ["star.fill", "sparkle", "star.fill", "sparkle", "star.fill", "sparkle"]
    private let sparkleSizes: [CGFloat] = [16, 10, 16, 10, 16, 10]
    private let sparkleColors: [Color] = [.yellow, .orange, .yellow, .orange, .yellow, .orange]

    var percentComplete: Int {
        guard cardGoal > 0 else { return 100 }
        return min(100, Int(Double(learnedCount) / Double(cardGoal) * 100))
    }

    var motivationalMessage: String {
        switch percentComplete {
        case 100: return "Perfect! You crushed every card!"
        case 80..<100: return "Almost perfect! Incredible effort!"
        case 60..<80: return "Great session! You're making real progress."
        case 40..<60: return "Good effort! Keep practicing and you'll get there."
        default: return "Every session counts. Keep going!"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Celebration header
                celebrationHeader
                    .padding(.top, 24)

                // Circular progress with count-up
                mainStatView

                // Motivational message
                Text(motivationalMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(showStats ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showStats)

                // Stats cards
                if showStats {
                    statsGrid
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Compact session recap
                if showSummary {
                    sessionRecap
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }

                // Action buttons
                if showButtons {
                    actionButtons
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 48)
        }
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Celebration Header

    private var celebrationHeader: some View {
        ZStack {
            // Sparkles
            ForEach(0..<6, id: \.self) { i in
                Image(systemName: sparkleSymbols[i])
                    .font(.system(size: sparkleSizes[i]))
                    .foregroundColor(sparkleColors[i])
                    .offset(x: sparkleOffsets[i].0, y: sparkleOffsets[i].1)
                    .scaleEffect(sparkleScales[i])
                    .opacity(sparkleOpacities[i])
            }

            // Trophy + title
            VStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 68))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.5), radius: 16, y: 6)
                    .scaleEffect(trophyScale)
                    .rotationEffect(.degrees(trophyRotation))

                Text("Session Complete!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .opacity(trophyScale > 0.5 ? 1 : 0)
                    .animation(.easeIn(duration: 0.2).delay(0.3), value: trophyScale)
            }
        }
        .frame(height: 180)
    }

    // MARK: - Main Stat (circular progress + count-up)

    private var mainStatView: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.gray.opacity(0.12), lineWidth: 10)

            // Animated progress ring
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    gameType.tileColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.1).delay(0.4), value: ringProgress)

            // Count + label
            VStack(spacing: 2) {
                Text("\(displayCount)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundColor(gameType.tileColor)
                    .contentTransition(.numericText())

                Text("cards learned")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
        }
        .frame(width: 190, height: 190)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 12) {
            PodiumStatCard(
                icon: "clock.fill",
                label: "Time",
                value: formatTime(elapsedSeconds),
                color: .orange
            )
            PodiumStatCard(
                icon: "target",
                label: "Goal",
                value: "\(percentComplete)%",
                color: percentComplete == 100 ? .green : gameType.tileColor
            )
        }
    }

    // MARK: - Session Recap (compact)

    private var sessionRecap: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Details")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 14) {
                // Game icon pill
                Image(systemName: gameType.icon)
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(gameType.tileColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(gameType.rawValue)
                        .fontWeight(.semibold)
                    Text(deckTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(language.flag) \(language.rawValue)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(LevelManager.shared.displayString(level: level, language: language.code, preferredScale: .simple))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onPlayAgain) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Play Again")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(gameType.tileColor)
                .cornerRadius(15)
                .shadow(color: gameType.tileColor.opacity(0.3), radius: 8, y: 4)
            }

            Button(action: { setupStage = .gameSelection }) {
                HStack(spacing: 6) {
                    Image(systemName: "house")
                        .font(.subheadline)
                    Text("Return to Menu")
                        .font(.subheadline)
                }
                .foregroundColor(.secondary)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Trophy bounces in
        withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.1)) {
            trophyScale = 1
            trophyRotation = 0
        }

        // Sparkles pop in with stagger
        for i in 0..<6 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65).delay(0.35 + Double(i) * 0.07)) {
                sparkleScales[i] = 1
                sparkleOpacities[i] = 1
            }
        }

        // Count up from 0 to learnedCount
        if learnedCount > 0 {
            let steps = min(learnedCount, 40)
            let stepDuration = 0.9 / Double(steps)
            for i in 1...steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45 + Double(i) * stepDuration) {
                    displayCount = Int(Double(learnedCount) * Double(i) / Double(steps))
                }
            }
        }

        // Ring fills in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            ringProgress = min(1.0, Double(learnedCount) / Double(max(cardGoal, 1)))
        }

        // Stats
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.85)) {
            showStats = true
        }

        // Session recap
        withAnimation(.easeIn(duration: 0.25).delay(1.05)) {
            showSummary = true
        }

        // Buttons
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(1.15)) {
            showButtons = true
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let sec = seconds % 60
        return String(format: "%02d:%02d", minutes, sec)
    }
}

// MARK: - Podium Stat Card

private struct PodiumStatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
}
