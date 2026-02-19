import SwiftUI
import SwiftData
import Combine

struct GameView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allProfiles: [UserProfile]
    
    @Environment(AudioManager.self) private var audioManager
    
    // State Management
    enum GameSetupStage {
        case deckSelection           // Stage 1
        case sessionConfiguration     // Stage 2
        case gameSpecificConfig       // Stage 3
        case sessionSummary           // Stage 4
        case starting                 // Stage 5 (transition)
        case playing                  // Stage 6
        case finished                 // Stage 7
    }
    
    @State private var setupStage: GameSetupStage = .deckSelection
    @State private var currentCardIndex: Int = 0
    @State private var isFlipped: Bool = false
    
    // Configuration Settings
    @State private var sessionDuration: Int = 15 // Minutes
    @State private var sessionCardGoal: Int = 20
    @State private var sessionLanguage: Language = .spanish
    @State private var sessionLevel: Int = 1 // 1-6
    
    // Session Controller
    @State private var sessionController = SessionController()
    
    // Tracking (Now mostly in Controller)
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionStartTime: Date?
    
    // New selective deck flow
    @State private var selectedDeck: DeckMetadata?
    
    // Game Configuration
    @State private var selectedPreset: GameConfiguration.Preset = .inputFocus
    @State private var selectedGameType: GameConfiguration.GameType = .flashcards
    @State private var customConfig: GameConfiguration = GameConfiguration.from(preset: .inputFocus)
    @State private var order: GameConfiguration.OrderStrategy = .smart
    @State private var hasInitialized: Bool = false
    @State private var useTTSFallback: Bool = true
    @State private var ttsRate: Float = 0.5
    @State private var memoryMatchMode: GameConfiguration.MemoryMatchMode = .pictureToWord
    
    // UI Customization State
    @State private var navigationStyle: NavigationStyle = .swipe
    @State private var autoNextDelay: TimeInterval = 2.0
    @State private var confirmationStyle: ConfirmationStyle = .quiz
    @State private var linkerTargetMode: GameConfiguration.LinkerTargetMode = .english
    
    // Runtime config (captured at start)
    @State private var sessionConfig: GameConfiguration = GameConfiguration.from(preset: .inputFocus)
    @State private var sessionCards: [LearningCard] = []
    
    var userProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }
    
    var deck: CardDeck? {
        dataManager.loadedDeck
    }
    
    var body: some View {
        NavigationStack {
            mainContent
                .id(setupStage) // Force view refresh
                .navigationTitle(navigationTitle)
                .toolbar {
                    gameToolbar
                }
                .onAppear(perform: handleAppear)
                // Timer is now handled by Controller, but we watch controller state
                .onChange(of: scenePhase, handleScenePhase)
                .onChange(of: sessionController.isPaused, handlePauseState)
                .onChange(of: currentCardIndex, handleCardIndexChange)
                .onChange(of: isFlipped, handleFlipState)
                .onChange(of: sessionController.isGameOver) { _, gameOver in
                    if gameOver {
                        finishSession()
                    }
                }
                .onChange(of: dataManager.loadedDeck) { _, newDeck in
                    handleDeckLoaded(newDeck)
                }
                .onChange(of: setupStage) { oldStage, newStage in
                    print("DEBUG: setupStage changed from \(oldStage) to \(newStage)")
                    if newStage == .playing {
                        // Trigger first card audio when game starts
                        // Brief delay to ensure view is settled
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            playCurrentCardAudio()
                        }
                    }
                }
                .background(persistenceLogic)
        }
            .toolbar(setupStage == .playing ? .hidden : .visible, for: .navigationBar)
        .toolbar(setupStage == .playing ? .hidden : .visible, for: .tabBar)
    }

    var persistenceLogic: some View {
        deckLogic
            .background(appLogic)
    }

    var deckLogic: some View {
        EmptyView()
            .onChange(of: sessionLanguage) { _, newValue in
                if let deck = selectedDeck, deck.language == newValue { return }
                print("DEBUG: sessionLanguage changed to \(newValue). Clearing selectedDeck.")
                dataManager.discoverDecks(language: newValue, proficiency: sessionLevel)
                selectedDeck = nil
            }
            .onChange(of: sessionLevel) { _, newValue in
                if let deck = selectedDeck {
                   let deckProf = deck.proficiencyLevel ?? LevelManager.shared.normalize(deck.level)
                   if deckProf == newValue { return }
                }
                print("DEBUG: sessionLevel changed to \(newValue). Clearing selectedDeck.")
                dataManager.discoverDecks(language: sessionLanguage, proficiency: newValue)
                selectedDeck = nil
            }
            .onChange(of: selectedDeck) { _, newDeck in
                if let deck = newDeck {
                    print("DEBUG: selectedDeck CHANGED to: \(deck.title). Saving to profile.")
                    if let profile = userProfile {
                        profile.lastSelectedDeckId = deck.id
                        try? modelContext.save()
                    }
                } else {
                    print("DEBUG: selectedDeck CHANGED to NIL")
                }
            }
            .onChange(of: dataManager.availableDecks) { _, decks in
                print("DEBUG: availableDecks changed. Count: \(decks.count)")
                if selectedDeck == nil, let profile = userProfile, let lastId = profile.lastSelectedDeckId {
                    print("DEBUG: Trying restore from availableDecks for \(lastId)")
                    if let match = decks.first(where: { $0.id == lastId }) {
                        print("DEBUG: RESTORED deck from availableDecks: \(match.title)")
                        selectedDeck = match
                        if sessionLanguage != match.language { sessionLanguage = match.language }
                        let prof = match.proficiencyLevel ?? (match.level != nil ? LevelManager.shared.normalize(match.level!) : 1)
                        if sessionLevel != prof { sessionLevel = prof }
                    }
                }
            }
    }

    var appLogic: some View {
        EmptyView()
            .onChange(of: authManager.currentUser) { _, _ in
                print("DEBUG: authManager.currentUser changed. Profile available? \(userProfile != nil)")
                if selectedDeck == nil, let profile = userProfile, let lastId = profile.lastSelectedDeckId {
                     print("DEBUG: Trying restore from auth change...")
                     if let match = dataManager.availableDecks.first(where: { $0.id == lastId }) {
                        selectedDeck = match
                        if sessionLanguage != match.language { sessionLanguage = match.language }
                        let prof = match.proficiencyLevel ?? (match.level != nil ? LevelManager.shared.normalize(match.level!) : 1)
                        if sessionLevel != prof { sessionLevel = prof }
                    }
                }
            }
            .onChange(of: ttsRate) { _, newRate in
                if let profile = userProfile {
                     profile.ttsRate = newRate
                     try? modelContext.save()
                }
            }
            .onChange(of: customConfig) { _, newConfig in
                if selectedPreset == .customize, let profile = userProfile {
                     print("DEBUG: Saving custom config to profile")
                     profile.customGameConfiguration = newConfig
                }
            }
            .onChange(of: selectedGameType) { _, newType in
                if let profile = userProfile {
                    print("DEBUG: Saving selectedGameType \(newType.rawValue) to profile")
                    profile.currentGameType = newType
                     try? modelContext.save()
                }
            }
    }
    @ViewBuilder
    var mainContent: some View {
        switch setupStage {
        case .deckSelection:
            let _ = print("DEBUG: Showing deckSelection view")
            configurationView
        case .sessionConfiguration:
            SessionOptionsView(
                sessionDuration: $sessionDuration,
                sessionCardGoal: $sessionCardGoal,
                navigationStyle: $navigationStyle,
                autoNextDelay: $autoNextDelay,
                confirmationStyle: $confirmationStyle,
                useTTSFallback: $useTTSFallback,
                ttsRate: $ttsRate,
                order: $order,
                linkerTargetMode: $linkerTargetMode,
                gameType: selectedGameType,
                maxCards: deck?.cards.count,
                onNext: { setupStage = .gameSpecificConfig },
                onBack: { setupStage = .deckSelection },
                onSkipToSummary: { setupStage = .sessionSummary }
            )
        case .gameSpecificConfig:
            let _ = print("DEBUG: Showing gameSpecificConfig view")
            if let deckMeta = selectedDeck {
                GameSpecificConfigRouter(
                    gameType: selectedGameType,
                    deck: deckMeta,
                    selectedPreset: $selectedPreset,
                    customConfig: $customConfig,
                    memoryMatchMode: $memoryMatchMode,
                    onNext: { setupStage = .sessionSummary },
                    onBack: { setupStage = .sessionConfiguration },
                    onSkipToSummary: { setupStage = .sessionSummary }
                )
            } else {
                Text("No deck selected")
            }
        case .sessionSummary:
            PreGameSummaryView(
                deckTitle: (selectedDeck?.folderName == "Virtual" ? "Custom Deck" : (selectedDeck?.title ?? "Unknown Deck")),
                language: sessionLanguage,
                level: sessionLevel,
                preset: selectedPreset,
                gameType: selectedGameType,
                duration: sessionDuration,
                cardGoal: sessionCardGoal,
                order: order,
                filterText: (selectedDeck?.folderName == "Virtual" ? selectedDeck?.title.replacingOccurrences(of: "Focus: ", with: "") : nil),
                onStartGame: startActiveSession,
                onBack: { setupStage = .gameSpecificConfig }
            )
        case .starting:
            let _ = print("DEBUG: Showing starting transition")
            ProgressView("Preparing game...")
                .onAppear {
                    print("DEBUG: Starting transition onAppear - will move to .playing in 0.5s")
                    // Brief transition, then move to playing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("DEBUG: Transitioning from .starting to .playing")
                        setupStage = .playing
                    }
                }
        case .playing:
            let _ = print("DEBUG: Showing ActiveSessionView for playing stage")
            ActiveSessionView(
                errorMessage: dataManager.errorMessage,
                deck: deck,
                sessionCards: sessionCards,
                currentCardIndex: currentCardIndex,
                learnedCount: sessionController.learnedCount,
                sessionCardGoal: sessionCardGoal,
                sessionConfig: sessionConfig,
                isFlipped: $isFlipped,
                matchMode: memoryMatchMode,
                onRelearn: relearnCard,
                onLearned: learnedCard,
                onFinish: { sessionController.endSession() },
                onNext: nextCard,
                onPrev: prevCard,
                onGrade: handleGrade
            )
        case .finished:
            SessionFinishView(
                learnedCount: sessionController.learnedCount,
                elapsedSeconds: Int(sessionController.duration - sessionController.timeRemaining),
                setupStage: $setupStage,
                deckTitle: (selectedDeck?.folderName == "Virtual" ? "Custom Deck" : (selectedDeck?.title ?? "Unknown Deck")),
                language: sessionLanguage,
                level: sessionLevel,
                preset: selectedPreset,
                gameType: sessionConfig.gameType,
                duration: sessionDuration,
                cardGoal: sessionCardGoal,
                order: sessionConfig.order,
                filterText: (selectedDeck?.folderName == "Virtual" ? selectedDeck?.title.replacingOccurrences(of: "Focus: ", with: "") : nil),
                onPlayAgain: startActiveSession
            )
        }
    }
    
    // MARK: - Event Handlers
    
    func handleAppear() {
        if setupStage == .deckSelection {
            setupConfiguration()
            dataManager.discoverDecks(language: sessionLanguage, proficiency: sessionLevel)
        }
    }
    
    @State private var wasPlayingBeforeBackground: Bool = false
    
    func handleScenePhase(_ oldPhase: ScenePhase, _ newPhase: ScenePhase) {
        if setupStage == .playing {
            if newPhase == .background || newPhase == .inactive {
                if oldPhase == .active {
                    wasPlayingBeforeBackground = !sessionController.isPaused
                    sessionController.pauseSession()
                }
            } else if newPhase == .active {
                if wasPlayingBeforeBackground {
                    sessionController.resumeSession()
                    wasPlayingBeforeBackground = false
                }
            }
        }
    }
    
    func handlePauseState(_: Bool, newValue: Bool) {
        // Paused state change
        if newValue {
            audioManager.stopAudio()
        } else {
            playCurrentCardAudio()
        }
    }
    
    func handleCardIndexChange(_: Int, _: Int) {
        if !isFlipped {
            // Add slight delay to ensure state stabilization (e.g. from flip reset)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.playCurrentCardAudio()
            }
        }
    }
    
    func handleFlipState(_: Bool, newValue: Bool) {
        // Stop any current audio before starting new flip audio
        audioManager.stopAudio()
        
        // Brief delay to allow flip animation to settle before audio starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            playCurrentCardAudio()
        }
    }
    
    var navigationTitle: String {
        switch setupStage {
        case .deckSelection: return "Select Deck"
        case .sessionConfiguration: return "Session Options"
        case .gameSpecificConfig: return "Game Settings"
        case .sessionSummary: return "Review"
        case .starting: return ""
        case .playing: return ""
        case .finished: return "Session Complete"
        }
    }
    
    var configurationView: some View {
        GameConfigurationView(
            sessionLanguage: $sessionLanguage,
            sessionLevel: $sessionLevel,
            preferredScale: userProfile?.preferredScale ?? .simple,
            selectedDeck: $selectedDeck,
            selectedGameType: $selectedGameType,
            availableDecks: dataManager.availableDecks,
            onNext: { setupStage = .sessionConfiguration },
            onSkipToSummary: { setupStage = .sessionSummary }
        )
    }

    
    // MARK: - Card Rendering Helpers
    

    
    @ToolbarContentBuilder
    private var gameToolbar: some ToolbarContent {
        Group {
            // Leading buttons based on stage
            ToolbarItem(placement: .topBarLeading) {
                if setupStage == .playing {
                    HStack {
                        Button(action: { 
                            if sessionController.isPaused {
                                sessionController.resumeSession()
                            } else {
                                sessionController.pauseSession()
                            }
                        }) {
                            Image(systemName: sessionController.isPaused ? "play.fill" : "pause.fill")
                                .foregroundColor(sessionController.isPaused ? .green : .orange)
                        }
                        
                        Button(action: { sessionController.endSession() }) {
                            Image(systemName: "stop.fill")
                            .foregroundColor(.red)
                        }
                    }
                } else if setupStage != .deckSelection && setupStage != .starting && setupStage != .finished {
                    // Show Back button for stages 2-4
                    Button("Back") {
                        switch setupStage {
                        case .sessionConfiguration:
                            setupStage = .deckSelection
                        case .gameSpecificConfig:
                            setupStage = .sessionConfiguration
                        case .sessionSummary:
                            setupStage = .gameSpecificConfig
                        default:
                            break
                        }
                    }
                }
            }
            
            // Principal (center) content
            if setupStage == .playing {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(deck?.title ?? "Learning")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: 200)
                    }
                }
            }
            
            // Trailing buttons based on stage
            trailingToolbarItems
        }
    }

    @ToolbarContentBuilder
    private var trailingToolbarItems: some ToolbarContent {
        switch setupStage {
        case .playing:
            playingToolbarItems
        case .deckSelection:
            deckSelectionToolbarItems
        case .sessionConfiguration:
            sessionConfigToolbarItems
        case .gameSpecificConfig:
            gameSpecificConfigToolbarItems
        default:
            ToolbarItem(placement: .automatic) { EmptyView() }
        }
    }
    
    @ToolbarContentBuilder
    private var playingToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                timerView
                levelBadgeView
            }
        }
    }

    private var timerView: some View {
        Text(formatTime(Int(sessionController.timeRemaining)))
            .font(.system(.body, design: .monospaced))
            .foregroundColor(sessionController.timeRemaining < 30 ? .red : .primary)
            .fixedSize()
            .padding(6)
            .frame(minWidth: 60)
            .background(sessionController.isPaused ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                   .stroke(sessionController.isPaused ? Color.orange : Color.clear, lineWidth: 1)
            )
    }

    private var levelBadgeView: some View {
        Text(LevelManager.shared.displayString(level: sessionLevel, language: sessionLanguage.code, preferredScale: userProfile?.preferredScale ?? .simple))
           .font(.caption)
           .padding(6)
           .background(Color.gray.opacity(0.2))
           .cornerRadius(8)
    }
    
    @ToolbarContentBuilder
    private var deckSelectionToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Next") {
                setupStage = .sessionConfiguration
            }
            .disabled(selectedDeck == nil)
        }
    }

    @ToolbarContentBuilder
    private var sessionConfigToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Next") {
                setupStage = .gameSpecificConfig
            }
        }
    }

    @ToolbarContentBuilder
    private var gameSpecificConfigToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Next") {
                setupStage = .sessionSummary
            }
        }
    }
    
    // MARK: - Logic
    
    func setupConfiguration() {
        // ... (unchanged) ...
        print("DEBUG: setupConfiguration called. Profile: \(userProfile?.name ?? "nil"), Initialized: \(hasInitialized)")
        
        // Only initialize from profile ONCE to allow temporary overrides
        guard let profile = userProfile, !hasInitialized else { return }
        
        sessionLanguage = profile.currentLanguage
        sessionLevel = profile.proficiencyLevel
        sessionCardGoal = profile.dailyCardGoal ?? 20
        selectedPreset = profile.defaultGamePreset
        selectedGameType = profile.currentGameType 
        
        ttsRate = profile.ttsRate
        useTTSFallback = true 
        
        if selectedPreset != .customize {
             customConfig = GameConfiguration.from(preset: selectedPreset)
             customConfig.ttsRate = profile.ttsRate
        } else {
             if let savedConfig = profile.customGameConfiguration {
                 customConfig = savedConfig
                 customConfig.ttsRate = profile.ttsRate
             } else {
                 customConfig.ttsRate = profile.ttsRate
             }
        }
        
        hasInitialized = true
        
        if let lastId = profile.lastSelectedDeckId {
            DispatchQueue.global(qos: .userInitiated).async {
                if let match = self.dataManager.findDeckMetadata(id: lastId) {
                    DispatchQueue.main.async {
                        self.sessionLanguage = match.language
                        self.sessionLevel = match.proficiencyLevel ?? LevelManager.shared.normalize(match.level)
                        self.dataManager.discoverDecks(language: match.language, proficiency: self.sessionLevel)
                        self.selectedDeck = match
                    }
                } else {
                     DispatchQueue.main.async {
                         self.dataManager.discoverDecks(language: self.sessionLanguage, proficiency: self.sessionLevel)
                     }
                }
            }
        } else {
             dataManager.discoverDecks(language: sessionLanguage, proficiency: sessionLevel)
        }
    }
    
    func startActiveSession() {
        print("DEBUG: ====== startActiveSession() called ======")
        guard let metDeck = selectedDeck else {
            print("DEBUG: ERROR - No selected deck!")
            return
        }
        print("DEBUG: Selected deck: \(metDeck.title)")
        _ = dataManager.loadDeck(from: metDeck)
        
        currentCardIndex = 0
        isFlipped = false
        sessionStartTime = Date()
        
        // Ensure audio session is active and ready for playback
        audioManager.configureAudioSession()
        
        // Capture final config
        if selectedPreset == .customize {
            sessionConfig = customConfig
        } else {
            sessionConfig = GameConfiguration.from(preset: selectedPreset)
        }
        
        sessionConfig.order = order
        sessionConfig.gameType = selectedGameType
        
        // Apply Global Audio Settings
        sessionConfig.ttsRate = ttsRate
        sessionConfig.useTTSFallback = useTTSFallback
        
        // Apply Global UI Settings
        sessionConfig.navigation = navigationStyle
        sessionConfig.autoNextDelay = autoNextDelay
        sessionConfig.confirmation = confirmationStyle
        sessionConfig.linkerTargetMode = linkerTargetMode
        
        // Initialize Controller
        // Note: We re-create it or reset it? Ideally reset.
        // But since it's @State, better to just call startSession on existing instance
        sessionController.duration = TimeInterval(sessionDuration * 60)
        sessionController.sessionCardGoal = sessionCardGoal
        sessionController.startSession()
        
        // Prepare Cards
        sessionCards = []
        
        if let currentDeck = deck, currentDeck.id == metDeck.id {
             applyDeckOverrides(to: &sessionConfig, from: currentDeck, type: selectedGameType)
             let preparedCards = prepareSessionCards(currentDeck.cards)
             
             if sessionConfig.order == .smart {
                 // Initialize Smart Session Logic
                 SmartSessionManager.shared.startSession(cards: preparedCards)
                 sessionCards = SmartSessionManager.shared.activeQueue
             } else {
                 sessionCards = preparedCards
             }
        }
        
        print("DEBUG: About to set setupStage to .starting")
        withAnimation {
            setupStage = .starting
            dataManager.isFullScreen = true
        }
    }
    
    func playCurrentCardAudio() {
        // Only auto-play audio for Flashcards/Story mode.
        guard sessionConfig.gameType == .flashcards || sessionConfig.gameType == .story else { 
            print("DEBUG: playCurrentCardAudio SKIPPED (Wrong GameType: \(sessionConfig.gameType))")
            return 
        }
        
        guard setupStage == .playing else { 
            print("DEBUG: playCurrentCardAudio SKIPPED (Not Playing: \(setupStage))")
            return 
        }
        
        guard !sessionController.isPaused else { 
            print("DEBUG: playCurrentCardAudio SKIPPED (Paused)")
            return 
        }
        
        guard let deck = deck, currentCardIndex < sessionCards.count else { 
            print("DEBUG: playCurrentCardAudio SKIPPED (No deck or invalid index: \(currentCardIndex))")
            return 
        }
        
        print("DEBUG: playCurrentCardAudio STARTING for index \(currentCardIndex)")
        let card = sessionCards[currentCardIndex]
        
        var sequence: [AudioManager.AudioItem] = []
        let useFallback = sessionConfig.useTTSFallback
        
        if isFlipped {
            // BACK of card: Use English TTS for meanings
            if sessionConfig.back.translation != .hidden {
                // We use an empty filename to trigger fallback TTS in AudioManager
                sequence.append(AudioManager.AudioItem(filename: "native_word", text: card.wordNative, language: .english))
            }
            if sessionConfig.back.sentenceMeaning != .hidden && !card.sentenceNative.isEmpty {
                 sequence.append(AudioManager.AudioItem(filename: "native_sentence", text: card.sentenceNative, language: .english))
            }
        } else {
            // FRONT of card: Use target language audio
            let showWordAudio = sessionConfig.word.audio == .visible || (sessionConfig.word.audio == .hint && sessionConfig.word.autoplay)
            if showWordAudio, let wordFile = card.audioWordFile {
                 sequence.append(AudioManager.AudioItem(filename: wordFile, text: card.wordTarget, language: deck.language))
            }
            
            let showSentenceAudio = sessionConfig.sentence.audio == .visible || (sessionConfig.sentence.audio == .hint && sessionConfig.sentence.autoplay)
            if showSentenceAudio, let sentenceFile = card.audioSentenceFile {
                 sequence.append(AudioManager.AudioItem(filename: sentenceFile, text: card.sentenceTarget, language: deck.language))
            }
        }
        
        if !sequence.isEmpty {
            audioManager.playSequence(items: sequence, folderName: deck.baseFolderName, useFallback: useFallback, ttsRate: sessionConfig.ttsRate)
        }
    }
    
    // handleTimerTick removed - handled by Controller
    
    func finishSession() {
        saveActivity()
        withAnimation {
            setupStage = .finished
            dataManager.isFullScreen = false 
        }
    }
    
    func saveActivity() {
        let minutes = max(1, Int(sessionController.duration - sessionController.timeRemaining) / 60)
        let language = sessionLanguage
        
        var comment: String?
        if let deckTitle = selectedDeck?.title {
            let totalCards = deck?.cards.count ?? 0
            comment = "\(deckTitle) · \(sessionController.learnedCount)/\(totalCards) cards"
            comment? += " · \(selectedPreset.rawValue)"
            comment? += " (\(sessionConfig.order.rawValue))"
        }
        
        let activity = UserActivity(
            date: Date(), 
            minutes: minutes, 
            activityType: .appLearning, 
            language: language, 
            userID: authManager.currentUser,
            comment: comment
        )
        modelContext.insert(activity)
    }
    
    func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let sec = seconds % 60
        return String(format: "%02d:%02d", minutes, sec)
    }
    
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
        sessionController.incrementLearned()
        if sessionController.isGameOver {
             // Already triggered endSession() inside incrementLearned which sets isGameOver
             // FinishSession will be called via onChange(of: isGameOver)
        } else {
             nextCard()
        }
    }
    
    func relearnCard() {
        nextCard()
    }
    
    func handleGrade(_ grade: SmartSessionManager.Grade) {
        if sessionConfig.order == .smart {
            // Apply grade to SRS queue
            SmartSessionManager.shared.handleGrade(grade)
            
            // Sync active queue
            sessionCards = SmartSessionManager.shared.activeQueue
            
        } else {
            // Non-Smart Mode: Just increment counts and remove current card
            if grade == .easy || grade == .good {
                 sessionController.incrementLearned()
            }
            if !sessionCards.isEmpty {
                sessionCards.removeFirst()
            }
        }
        
        // Update stats if card is mastered (SRS also tracks this internally, but we track for session total)
        if (grade == .easy || grade == .good) && sessionConfig.order == .smart {
            sessionController.incrementLearned()
        }
        
        // Check for completion
        if sessionCards.isEmpty {
            sessionController.endSession()
        } else {
            // Reset view state for next card
            withAnimation {
                isFlipped = false
                currentCardIndex = 0 // In Smart mode (and now non-smart too), we work from head of queue
            }
        }
    }
    func handleDeckLoaded(_ newDeck: CardDeck?) {
        // Race condition fix: If we started session but deck wasn't ready,
        // populate cards now that it is loaded.
        if setupStage == .playing && sessionCards.isEmpty, let deck = newDeck, !deck.cards.isEmpty {
            // Apply Deck Overrides (late load)
            applyDeckOverrides(to: &sessionConfig, from: deck, type: sessionConfig.gameType) // Used sessionConfig.gameType instead of selectedGameType for consistency.
            
            let preparedCards = prepareSessionCards(deck.cards)
            
            if sessionConfig.order == .smart {
                // Initialize Smart Session Logic
                SmartSessionManager.shared.startSession(cards: preparedCards)
                sessionCards = SmartSessionManager.shared.activeQueue
            } else {
                sessionCards = preparedCards
            }
    
            // Trigger audio now that we have cards
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playCurrentCardAudio()
            }
        }
    }
    
    // MARK: - Deck Logic Helpers
    
    func prepareSessionCards(_ allCards: [LearningCard]) -> [LearningCard] {
        let filtered = filterCards(allCards, for: sessionConfig.gameType)
        
        let limit = sessionCardGoal
        var workingSet: [LearningCard] = []
        
        if filtered.count > limit {
             if sessionConfig.order == .sequential {
                 workingSet = Array(filtered.prefix(limit))
             } else {
                 // For Random/Smart, pick a random subset
                 workingSet = Array(filtered.shuffled().prefix(limit))
             }
        } else {
             workingSet = filtered
             // If random/smart, shuffle even if full set (Smart Queue might re-order, but random start is good)
             if sessionConfig.order != .sequential {
                 workingSet.shuffle()
             }
        }
        
        // Setup Smart Queue if needed
        if sessionConfig.order == .smart {
            SmartSessionManager.shared.startSession(cards: workingSet)
            return SmartSessionManager.shared.activeQueue
        }
        
        return workingSet
    }
    
    func filterCards(_ cards: [LearningCard], for type: GameConfiguration.GameType) -> [LearningCard] {
        return cards.filter { card in
            guard let usage = card.usage, !usage.isEmpty else { return true }
            
            // Story Only Logic
            if usage.contains("story_only") && type != .story {
                return false
            }
            
            // Flashcard Only Logic ?? ("flashcard_only" - hypothetical)
            
            return true
        }
    }
    
    func applyDeckOverrides(to config: inout GameConfiguration, from deck: CardDeck, type: GameConfiguration.GameType) {
        // Check for game-specific defaults from the deck JSON
        // The key in JSON is the rawValue (e.g. "Flashcards", "Memory Match", "Story")
        // NOTE: My JSON keys were lowercase "flashcards", "memoryMatch" in some places??
        // Let's check `DataManager` / `GameConfiguration` raw values.
        // GameType rawValues are "Flashcards", "Memory Match".
        // My JSON updates used: "flashcards" (lowercase) in keys.
        // I need to be careful with case sensitivity here.
        
        guard let deckConfig = deck.gameConfiguration else { return }
        
        // Try exact match first, then lowercase match
        let key = type.rawValue
        
        // Find which key exists
        // My JSON wrote: "flashcards": { ... }
        // GameType.flashcards.rawValue is "Flashcards"
        
        var defaults: DeckDefaults?
        
        // Iterate keys to find case-insensitive match
        for (jsonKey, val) in deckConfig {
            if jsonKey.caseInsensitiveCompare(key) == .orderedSame {
                defaults = val
                break
            }
            // Also check for "flashcards" vs "Flashcards" specifically if caseInsensitive didn't catch specific 'camelCase' vs 'Title Case' mapping issues (though caseInsensitive should)
        }
        
        if let defaults = defaults {
            print("DEBUG: Applying deck defaults for \(type.rawValue): \(defaults)")
            
            // Dictionary "randomize" is now handled in GameConfigurationView to allow for user overrides.
            // We do NOT override it here anymore.
            
            /*
            if let random = defaults.randomize {
                config.isRandomOrder = random
            }
            */
            
            if let autoPlay = defaults.audioAutoplay {
                // If TRUE -> Visible. If FALSE -> Hint?
                // For input focus, typical is Visible.
                if !autoPlay {
                    // Turn off autoplay by setting audio to .hint or .hidden
                    // .hint = Manual Play
                    config.word.audio = .hint
                    config.sentence.audio = .hint
                } else {
                    config.word.audio = .visible
                    config.sentence.audio = .visible
                }
            }
        }
    }
}
    

// MARK: - Helpers

struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.bold)
        }
    }
}









#Preview {
    GameView()
        .environment(DataManager())
        .environment(YouTubeManager())
        .environment(AuthManager())
}
