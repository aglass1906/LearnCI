import SwiftUI
import Combine

@Observable
class GameSessionViewModel {

    // MARK: - Dependencies
    private let audioManager: AudioManager
    // Using shared singleton for now since MemoryGameViewModel and LinkerGameViewModel
    // also reference SmartSessionManager.shared directly. Will be refactored to owned instance
    // when those game VMs are updated to receive the session manager as a dependency.
    private var smartSessionManager: SmartSessionManager { SmartSessionManager.shared }

    // MARK: - Session Lifecycle (absorbed from SessionController)
    private(set) var isPlaying: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var isGameOver: Bool = false
    private(set) var timeRemaining: TimeInterval = 0
    private(set) var learnedCount: Int = 0
    private(set) var score: Int = 0
    private(set) var streak: Int = 0
    var duration: TimeInterval = 300
    var sessionCardGoal: Int = 20
    private var timer: AnyCancellable?

    // MARK: - Runtime Game State
    private(set) var sessionConfig: GameConfiguration = GameConfiguration.from(preset: .inputFocus)
    private(set) var sessionCards: [LearningCard] = []
    private var sessionStartTime: Date?
    private var wasPlayingBeforeBackground: Bool = false

    var currentCardIndex: Int = 0 {
        didSet {
            guard currentCardIndex != oldValue, isPlaying else { return }
            if !isFlipped {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.playCurrentCardAudio()
                }
            }
        }
    }

    var isFlipped: Bool = false {
        didSet {
            guard isFlipped != oldValue, isPlaying else { return }
            audioManager.stopAudio()
            let shouldForce = !isFlipped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.playCurrentCardAudio(force: shouldForce)
            }
        }
    }

    // MARK: - External References
    var deck: CardDeck?

    // MARK: - Callbacks
    var onSessionFinished: (() -> Void)?
    var onSessionStarting: (() -> Void)?

    // MARK: - Display Helpers

    var formattedTimeRemaining: String {
        let seconds = Int(timeRemaining)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var isTimeLow: Bool { timeRemaining < 30 }

    var elapsedSeconds: Int { Int(duration - timeRemaining) }

    // MARK: - Init

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
    }

    // MARK: - Session Lifecycle

    func startSession(
        deck: CardDeck,
        selectedPreset: GameConfiguration.Preset,
        customConfig: GameConfiguration,
        gameType: GameConfiguration.GameType,
        order: GameConfiguration.OrderStrategy,
        confirmationStyle: ConfirmationStyle,
        navigationStyle: NavigationStyle,
        autoNextDelay: TimeInterval,
        ttsRate: Float,
        useTTSFallback: Bool,
        sessionDuration: Int,
        sessionCardGoal: Int
    ) {
        self.deck = deck
        currentCardIndex = 0
        isFlipped = false
        sessionStartTime = Date()

        audioManager.configureAudioSession()

        // Build sessionConfig
        var config: GameConfiguration
        if selectedPreset == .customize {
            config = customConfig
        } else {
            config = GameConfiguration.from(preset: selectedPreset)
        }
        config.order = order
        config.gameType = gameType
        if config.order == .smart {
            config.confirmation = .srs
            print("DEBUG: Smart Queue active - Enforcing SRS grading style.")
        } else {
            config.confirmation = confirmationStyle
        }
        config.ttsRate = ttsRate
        config.useTTSFallback = useTTSFallback
        config.navigation = navigationStyle
        config.autoNextDelay = autoNextDelay
        config.linkerTargetMode = customConfig.linkerTargetMode
        config.memoryMatchMode = customConfig.memoryMatchMode
        config.wordCrushGridSize = customConfig.wordCrushGridSize
        config.wordCrushDisplayMode = customConfig.wordCrushDisplayMode
        config.wordRainSpeed = customConfig.wordRainSpeed
        config.wordRainWordCount = customConfig.wordRainWordCount
        config.wordRainDifficulty = customConfig.wordRainDifficulty
        config.multipleChoiceOptionCount = customConfig.multipleChoiceOptionCount
        config.multipleChoiceShowTranslation = customConfig.multipleChoiceShowTranslation
        config.audioClozeOptionCount = customConfig.audioClozeOptionCount
        config.audioClozeShowTranslation = customConfig.audioClozeShowTranslation

        // Timer/scoring reset
        self.duration = TimeInterval(sessionDuration * 60)
        self.sessionCardGoal = sessionCardGoal
        self.timeRemaining = self.duration
        self.isPlaying = true
        self.isPaused = false
        self.isGameOver = false
        self.score = 0
        self.streak = 0
        self.learnedCount = 0
        startTimer()

        // Prepare cards
        sessionCards = []
        applyDeckOverrides(to: &config, from: deck, type: gameType)
        let preparedCards = prepareSessionCards(deck.cards, config: config)

        if config.order == .smart {
            smartSessionManager.startSession(cards: preparedCards)
            sessionCards = smartSessionManager.activeQueue
        } else {
            sessionCards = preparedCards
        }

        self.sessionConfig = config

        print("DEBUG: GameSessionViewModel.startSession() complete. Cards: \(sessionCards.count)")
        onSessionStarting?()
    }

    func pauseSession() {
        isPaused = true
        timer?.cancel()
        audioManager.stopAudio()
    }

    func resumeSession() {
        isPaused = false
        startTimer()
        playCurrentCardAudio()
    }

    func endSession() {
        isPlaying = false
        isGameOver = true
        timer?.cancel()
        finishSession()
    }

    // MARK: - Scoring

    func registerSuccess() {
        score += 10 + (streak * 2)
        streak += 1
    }

    func registerFailure() {
        streak = 0
    }

    private func incrementLearned() {
        learnedCount += 1
        if learnedCount >= sessionCardGoal {
            endSession()
        }
    }

    /// Increments learnedCount for display/stats only.
    /// Used by self-contained games (Word Rain, etc.) that manage their own
    /// session end via onFinish — calling endSession() here would race with
    /// the game's own end animation.
    func recordWordLearned() {
        learnedCount += 1
    }

    // MARK: - Card Navigation

    func nextCard() {
        if currentCardIndex < sessionCards.count - 1 {
            withAnimation {
                currentCardIndex += 1
                isFlipped = false
            }
        }
    }

    func prevCard() {
        if currentCardIndex > 0 {
            withAnimation {
                currentCardIndex -= 1
                isFlipped = false
            }
        }
    }

    func learnedCard() {
        incrementLearned()
        if !isGameOver {
            nextCard()
        }
    }

    func relearnCard() {
        nextCard()
    }

    func handleGrade(_ grade: SmartSessionManager.Grade) {
        if sessionConfig.order == .smart {
            smartSessionManager.handleGrade(grade)
            sessionCards = smartSessionManager.activeQueue
        } else {
            if grade == .easy || grade == .good {
                incrementLearned()
            }
            if !sessionCards.isEmpty {
                sessionCards.removeFirst()
            }
        }

        // Update stats if card is mastered (SRS mode)
        if (grade == .easy || grade == .good) && sessionConfig.order == .smart {
            incrementLearned()
        }

        // If incrementLearned() triggered endSession(), don't advance the UI.
        guard !isGameOver else { return }

        // Check for completion
        if sessionCards.isEmpty {
            endSession()
        } else {
            // Reset to front side and first card
            // Since currentCardIndex stays at 0, didSet won't fire,
            // so we explicitly trigger audio after the animation settles.
            withAnimation {
                isFlipped = false
                currentCardIndex = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.playCurrentCardAudio(force: true)
            }
        }
    }

    // MARK: - Audio

    func playCurrentCardAudio(force: Bool = false) {
        guard sessionConfig.gameType == .flashcards || sessionConfig.gameType == .story else {
            return
        }
        guard isPlaying, !isPaused else { return }
        guard let deck = deck, currentCardIndex < sessionCards.count else { return }

        let card = sessionCards[currentCardIndex]
        var sequence: [AudioManager.AudioItem] = []
        let useFallback = sessionConfig.useTTSFallback

        if isFlipped {
            if sessionConfig.back.autoplay {
                if sessionConfig.back.translation != .hidden {
                    sequence.append(AudioManager.AudioItem(filename: "native_word", text: card.wordNative, language: .english))
                }
                if sessionConfig.back.sentenceMeaning != .hidden && !card.sentenceNative.isEmpty {
                    sequence.append(AudioManager.AudioItem(filename: "native_sentence", text: card.sentenceNative, language: .english))
                }
            }
        } else {
            let showWordAudio = force || sessionConfig.word.audio == .visible || (sessionConfig.word.audio == .hint && sessionConfig.word.autoplay)
            if showWordAudio, let wordFile = card.audioWordFile {
                sequence.append(AudioManager.AudioItem(filename: wordFile, text: card.wordTarget, language: deck.language))
            }

            let showSentenceAudio = force || sessionConfig.sentence.audio == .visible || (sessionConfig.sentence.audio == .hint && sessionConfig.sentence.autoplay)
            if showSentenceAudio, let sentenceFile = card.audioSentenceFile {
                sequence.append(AudioManager.AudioItem(filename: sentenceFile, text: card.sentenceTarget, language: deck.language))
            }
        }

        if !sequence.isEmpty {
            audioManager.playSequence(items: sequence, folderName: deck.baseFolderName, useFallback: useFallback, ttsRate: sessionConfig.ttsRate)
        }
    }

    // MARK: - Scene Phase Handling

    func handleScenePhase(old: ScenePhase, new: ScenePhase) {
        guard isPlaying else { return }

        if new == .background || new == .inactive {
            if old == .active {
                wasPlayingBeforeBackground = !isPaused
                pauseSession()
            }
        } else if new == .active {
            if wasPlayingBeforeBackground {
                resumeSession()
                wasPlayingBeforeBackground = false
            }
        }
    }

    // MARK: - Late Deck Load (Race Condition Fix)

    func handleDeckLoaded(_ newDeck: CardDeck?) {
        guard isPlaying, sessionCards.isEmpty, let deck = newDeck, !deck.cards.isEmpty else { return }

        var config = sessionConfig
        applyDeckOverrides(to: &config, from: deck, type: config.gameType)

        let preparedCards = prepareSessionCards(deck.cards, config: config)

        if config.order == .smart {
            smartSessionManager.startSession(cards: preparedCards)
            sessionCards = smartSessionManager.activeQueue
        } else {
            sessionCards = preparedCards
        }

        self.sessionConfig = config
        self.deck = deck

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.playCurrentCardAudio()
        }
    }

    // MARK: - Session Completion

    func finishSession() {
        onSessionFinished?()
    }

    /// Returns activity data for persistence. GameView handles SwiftData insertion.
    func makeActivity(language: Language, deckTitle: String?, totalCards: Int?, userID: String?, preset: GameConfiguration.Preset) -> UserActivity {
        let minutes = max(1, elapsedSeconds / 60)

        var comment: String?
        if let deckTitle = deckTitle {
            let total = totalCards ?? 0
            comment = "\(deckTitle) · \(learnedCount)/\(total) cards"
            comment? += " · \(preset.rawValue)"
            comment? += " (\(sessionConfig.order.rawValue))"
        }

        return UserActivity(
            date: Date(),
            minutes: minutes,
            activityType: .appLearning,
            language: language,
            userID: userID,
            comment: comment
        )
    }

    // MARK: - Private: Timer

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard isPlaying, !isPaused else { return }
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            endSession()
        }
    }

    // MARK: - Private: Card Preparation

    private func prepareSessionCards(_ allCards: [LearningCard], config: GameConfiguration) -> [LearningCard] {
        let filtered = filterCards(allCards, for: config.gameType)

        let limit = sessionCardGoal
        var workingSet: [LearningCard]

        if filtered.count > limit {
            if config.order == .sequential {
                workingSet = Array(filtered.prefix(limit))
            } else {
                workingSet = Array(filtered.shuffled().prefix(limit))
            }
        } else {
            workingSet = filtered
            if config.order != .sequential {
                workingSet.shuffle()
            }
        }

        if config.order == .smart {
            smartSessionManager.startSession(cards: workingSet)
            return smartSessionManager.activeQueue
        }

        return workingSet
    }

    private func filterCards(_ cards: [LearningCard], for type: GameConfiguration.GameType) -> [LearningCard] {
        return cards.filter { card in
            guard let usage = card.usage, !usage.isEmpty else { return true }
            if usage.contains("story_only") && type != .story {
                return false
            }
            return true
        }
    }

    private func applyDeckOverrides(to config: inout GameConfiguration, from deck: CardDeck, type: GameConfiguration.GameType) {
        guard let deckConfig = deck.gameConfiguration else { return }

        let key = type.rawValue
        var defaults: DeckDefaults?

        for (jsonKey, val) in deckConfig {
            if jsonKey.caseInsensitiveCompare(key) == .orderedSame {
                defaults = val
                break
            }
        }

        if let defaults = defaults {
            print("DEBUG: Applying deck defaults for \(type.rawValue): \(defaults)")

            if let autoPlay = defaults.audioAutoplay {
                if !autoPlay {
                    config.word.audio = .hint
                    config.sentence.audio = .hint
                    config.word.autoplay = false
                    config.sentence.autoplay = false
                } else {
                    config.word.audio = .visible
                    config.sentence.audio = .visible
                    config.word.autoplay = true
                    config.sentence.autoplay = true
                }
            }

            if let autoPlayBack = defaults.audioAutoplayBack {
                config.back.autoplay = autoPlayBack
            }
        }
    }
}
