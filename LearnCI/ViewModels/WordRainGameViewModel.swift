import SwiftUI

struct FallingWord: Identifiable, Equatable {
    let id: UUID
    let card: LearningCard
    let text: String
    var xFraction: CGFloat       // 0..1 fraction of screen width (updated each frame in Hard mode)
    var yPosition: CGFloat       // current y in points
    var isCorrect: Bool
    var state: FallingWordState

    // Difficulty: Medium + Hard
    var individualSpeedMultiplier: CGFloat = 1.0  // per-word speed factor relative to base

    // Difficulty: Hard only — horizontal sine drift
    var xBasePosition: CGFloat = 0        // center x fraction to oscillate around
    var xDriftAmplitude: CGFloat = 0      // max drift in x-fraction units (e.g. 0.06 = 6% of width)
    var xDriftFrequency: Double = 0       // oscillations per second (e.g. 0.5)
    var xDriftPhaseOffset: Double = 0     // per-word phase so they don't move in sync
    var timeElapsed: Double = 0           // accumulated time used for sin() calculation

    enum FallingWordState {
        case falling, matched, missed
    }

    static func == (lhs: FallingWord, rhs: FallingWord) -> Bool {
        lhs.id == rhs.id && lhs.yPosition == rhs.yPosition && lhs.state == rhs.state
    }
}

@Observable
class WordRainGameViewModel {
    // MARK: - Game State
    var fallingWords: [FallingWord] = []
    var targetCard: LearningCard?
    var lives: Int = 3
    var score: Int = 0
    var streak: Int = 0
    var bestStreak: Int = 0
    var wordsCompleted: Int = 0
    var isGameOver: Bool = false
    var celebration: MatchCelebration?
    var streakBannerText: String? = nil
    var shakingWordIds: Set<UUID> = []
    var screenFlashing: Bool = false
    var speed: CGFloat = 85

    // MARK: - Data
    var deck: CardDeck
    var sessionCards: [LearningCard]
    var config: GameConfiguration
    var sessionCardGoal: Int

    // MARK: - Geometry (set by view in onAppear)
    var screenHeight: CGFloat = 800
    var screenWidth: CGFloat = 390

    // MARK: - Private
    private var cardQueue: [LearningCard] = []
    private var cardQueueIndex: Int = 0
    private var cardMissErrors: [String: Int] = [:]
    private var lastTickDate: Date? = nil
    private var finishCalled: Bool = false

    // MARK: - Dependencies
    var audioManager: AudioManager?
    var onGrade: ((SmartSessionManager.Grade) -> Void)?
    var onWordLearned: (() -> Void)?
    var onFinish: (() -> Void)?

    // MARK: - Computed
    var wordCount: Int {
        let available = deck.cards.count
        return min(config.wordRainWordCount, max(1, available))
    }

    var wordDropHeight: CGFloat { 48 }

    /// Y position at which the correct word is considered escaped
    var escapeBoundary: CGFloat { screenHeight - 160 }

    // MARK: - Init
    init(deck: CardDeck, sessionCards: [LearningCard], config: GameConfiguration,
         sessionCardGoal: Int, onGrade: ((SmartSessionManager.Grade) -> Void)? = nil) {
        self.deck = deck
        self.sessionCards = sessionCards
        self.config = config
        self.sessionCardGoal = sessionCardGoal
        self.onGrade = onGrade
        switch config.wordRainSpeed {
        case .slow:   self.speed = 55
        case .normal: self.speed = 85
        case .fast:   self.speed = 130
        }
        buildCardQueue()
    }

    // MARK: - Card Queue
    private func buildCardQueue() {
        cardQueue = sessionCards.shuffled()
        cardQueueIndex = 0
    }

    private func nextSessionCard() -> LearningCard {
        if cardQueueIndex >= cardQueue.count {
            cardQueue = sessionCards.shuffled()
            cardQueueIndex = 0
        }
        let card = cardQueue[cardQueueIndex]
        cardQueueIndex += 1
        return card
    }

    // MARK: - Wave Spawning
    func spawnNextWave() {
        guard !isGameOver else { return }

        let target = nextSessionCard()
        targetCard = target

        // Build distractor pool from the full deck, excluding the target card
        let distractorPool = deck.cards.filter { $0.id != target.id }
        let distractorCount = max(0, wordCount - 1)

        var distractors: [LearningCard] = []
        if !distractorPool.isEmpty && distractorCount > 0 {
            var pool = distractorPool.shuffled()
            while pool.count < distractorCount {
                pool.append(contentsOf: distractorPool.shuffled())
            }
            distractors = Array(pool.prefix(distractorCount))
        }

        // Mix correct word with distractors and shuffle
        var allWords: [(card: LearningCard, isCorrect: Bool)] = [(target, true)]
        allWords.append(contentsOf: distractors.map { ($0, false) })
        allWords.shuffle()

        // Assign evenly-spaced x fractions with slight jitter so words don't overlap
        let count = allWords.count
        let difficulty = config.wordRainDifficulty
        var words: [FallingWord] = []
        for (i, item) in allWords.enumerated() {
            let base = CGFloat(i + 1) / CGFloat(count + 1)
            let jitter = CGFloat.random(in: -0.05...0.05)
            let xFrac = min(max(base + jitter, 0.08), 0.92)
            let startY = CGFloat.random(in: (-wordDropHeight * 3.0)...(-wordDropHeight))

            var word = FallingWord(
                id: UUID(),
                card: item.card,
                text: item.card.wordTarget,
                xFraction: xFrac,
                yPosition: startY,
                isCorrect: item.isCorrect,
                state: .falling
            )

            switch difficulty {
            case .easy:
                break // uniform speed, no drift — defaults are already 1.0 / zeroes
            case .medium:
                word.individualSpeedMultiplier = CGFloat.random(in: 0.5...1.6)
            case .hard:
                word.individualSpeedMultiplier = CGFloat.random(in: 0.6...1.7)
                word.xBasePosition     = xFrac
                word.xDriftAmplitude   = CGFloat.random(in: 0.04...0.08)
                word.xDriftFrequency   = Double.random(in: 0.3...0.7)
                word.xDriftPhaseOffset = Double.random(in: 0...(2 * .pi))
            }

            words.append(word)
        }

        fallingWords = words
    }

    // MARK: - Game Loop Tick
    func tick(date: Date) {
        guard !isGameOver else { return }
        guard let last = lastTickDate else {
            lastTickDate = date
            return
        }

        let deltaTime = date.timeIntervalSince(last)
        lastTickDate = date

        // Clamp to avoid large jumps when app resumes from background
        let clampedDelta = min(deltaTime, 0.1)
        let baseMovePx = CGFloat(clampedDelta) * speed
        let difficulty = config.wordRainDifficulty

        var escapedCorrectIdx: Int? = nil

        for i in fallingWords.indices {
            guard fallingWords[i].state == .falling else { continue }

            // Per-word speed (Medium + Hard); Easy uses multiplier 1.0
            let wordMove = baseMovePx * fallingWords[i].individualSpeedMultiplier
            fallingWords[i].yPosition += wordMove

            // Hard: apply horizontal sine drift
            if difficulty == .hard {
                fallingWords[i].timeElapsed += clampedDelta
                let drift = fallingWords[i].xDriftAmplitude
                    * CGFloat(sin(fallingWords[i].timeElapsed * fallingWords[i].xDriftFrequency * 2 * .pi
                                  + fallingWords[i].xDriftPhaseOffset))
                fallingWords[i].xFraction = min(max(fallingWords[i].xBasePosition + drift, 0.05), 0.95)
            }

            if fallingWords[i].isCorrect && fallingWords[i].yPosition > escapeBoundary {
                escapedCorrectIdx = i
            }
            // Silently remove distractors past the visible area
            if !fallingWords[i].isCorrect && fallingWords[i].yPosition > screenHeight + wordDropHeight {
                fallingWords[i].state = .missed
            }
        }

        if let idx = escapedCorrectIdx {
            handleEscaped(wordIdx: idx)
        }
    }

    // MARK: - User Interaction
    func wordTapped(id: UUID) {
        guard !isGameOver,
              let idx = fallingWords.firstIndex(where: { $0.id == id }),
              fallingWords[idx].state == .falling else { return }

        if fallingWords[idx].isCorrect {
            handleCorrect(idx: idx)
        } else {
            handleWrong(idx: idx)
        }
    }

    // MARK: - Correct Hit
    private func handleCorrect(idx: Int) {
        let word = fallingWords[idx]
        streak += 1
        bestStreak = max(bestStreak, streak)

        let points = 10 + (streak * 2)
        score += points
        wordsCompleted += 1

        SoundManager.shared.play(.match)
        celebration = MatchCelebration(points: points, streak: streak, word: word.text)

        // Streak milestone banners
        if streak == 3 || streak == 5 || streak == 10 || (streak > 10 && streak % 5 == 0) {
            streakBannerText = "🔥 \(streak)x Streak!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.streakBannerText = nil
            }
        }

        // Clear the wave
        for i in fallingWords.indices {
            fallingWords[i].state = .matched
        }

        // Grade card
        let missCount = cardMissErrors[word.card.id] ?? 0
        let grade: SmartSessionManager.Grade = missCount > 0 ? .hard : .good
        SmartSessionManager.shared.completeBatch(cards: [word.card], grade: grade)
        onGrade?(grade)
        onWordLearned?()
        cardMissErrors.removeValue(forKey: word.card.id)

        playAudio(for: word.card)

        // Speed up every 5 correct answers
        if wordsCompleted % 5 == 0 {
            speed = min(speed + 15, 220)
        }

        // Check session goal
        if wordsCompleted >= sessionCardGoal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.endGame()
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.spawnNextWave()
        }
    }

    // MARK: - Wrong Hit
    private func handleWrong(idx: Int) {
        let cardId = fallingWords[idx].card.id
        cardMissErrors[cardId, default: 0] += 1
        streak = 0
        SoundManager.shared.play(.mismatch)

        let wordId = fallingWords[idx].id
        shakingWordIds.insert(wordId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.shakingWordIds.remove(wordId)
        }
    }

    // MARK: - Escape (correct word reached boundary)
    private func handleEscaped(wordIdx: Int) {
        guard fallingWords[wordIdx].state == .falling else { return }

        let card = fallingWords[wordIdx].card
        cardMissErrors[card.id, default: 0] += 1
        streak = 0

        for i in fallingWords.indices {
            fallingWords[i].state = .missed
        }

        SoundManager.shared.play(.mismatch)

        screenFlashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.screenFlashing = false
        }

        lives -= 1

        if lives <= 0 {
            endGame()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.spawnNextWave()
            }
        }
    }

    // MARK: - End Game
    private func endGame() {
        guard !finishCalled else { return }
        finishCalled = true
        isGameOver = true
        SoundManager.shared.play(.win)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.onFinish?()
        }
    }

    // MARK: - Audio
    private func playAudio(for card: LearningCard) {
        if let audioFile = card.audioWordFile {
            audioManager?.playAudio(
                named: audioFile,
                folderName: deck.baseFolderName,
                text: card.wordTarget,
                language: deck.language,
                useFallback: config.useTTSFallback,
                ttsRate: config.ttsRate
            )
        } else {
            audioManager?.speak(
                text: card.wordTarget,
                language: deck.language,
                gender: config.ttsVoiceGender,
                rate: config.ttsRate
            )
        }
    }
}
