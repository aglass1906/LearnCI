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
    
    // Tracking
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionStartTime: Date?
    @State private var elapsedSeconds: Int = 0
    @State private var remainingSeconds: Int = 0
    @State private var isPaused: Bool = false
    @State private var learnedCount: Int = 0
    
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
    @State private var memoryMatchMode: MemoryMatchMode = .pictureToWord
    
    // UI Customization State
    @State private var navigationStyle: NavigationStyle = .swipe
    @State private var autoNextDelay: TimeInterval = 2.0
    @State private var confirmationStyle: ConfirmationStyle = .quiz
    
    // Runtime config (captured at start)
    @State private var sessionConfig: GameConfiguration = GameConfiguration.from(preset: .inputFocus)
    @State private var sessionCards: [LearningCard] = []
    

    
    static let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
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
                .onReceive(GameView.timer) { _ in
                    handleTimerTick()
                }
                .onChange(of: scenePhase, handleScenePhase)
                .onChange(of: isPaused, handlePauseState)
                .onChange(of: currentCardIndex, handleCardIndexChange)
                .onChange(of: isFlipped, handleFlipState)
                .onChange(of: dataManager.loadedDeck) { _, newDeck in
                    handleDeckLoaded(newDeck)
                }
                .onChange(of: setupStage) { oldStage, newStage in
                    print("DEBUG: setupStage changed from \(oldStage) to \(newStage)")
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
                learnedCount: learnedCount,
                sessionCardGoal: sessionCardGoal,
                sessionConfig: sessionConfig,
                isFlipped: $isFlipped,
                matchMode: memoryMatchMode,
                onRelearn: relearnCard,
                onLearned: learnedCard,
                onFinish: finishSession,
                onNext: nextCard,
                onPrev: prevCard,
                onGrade: handleGrade
            )
        case .finished:
            SessionFinishView(
                learnedCount: learnedCount,
                elapsedSeconds: elapsedSeconds,
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
                // If we are leaving, check if we were playing.
                // If !isPaused, we were playing.
                // We only want to auto-resume if we were actually playing.
                if oldPhase == .active {
                    wasPlayingBeforeBackground = !isPaused
                    isPaused = true
                }
            } else if newPhase == .active {
                // Return to app: Resuming playback if we were playing before
                if wasPlayingBeforeBackground {
                    isPaused = false
                    wasPlayingBeforeBackground = false
                }
            }
        }
    }
    
    func handlePauseState(_: Bool, newValue: Bool) {
        if newValue {
            audioManager.stopAudio()
        } else {
            playCurrentCardAudio()
        }
    }
    
    func handleCardIndexChange(_: Int, _: Int) {
        if !isFlipped {
            playCurrentCardAudio()
        }
    }
    
    func handleFlipState(_: Bool, newValue: Bool) {
        if !newValue {
            playCurrentCardAudio()
        } else {
            audioManager.stopAudio()
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
                        Button(action: { isPaused.toggle() }) {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .foregroundColor(isPaused ? .green : .orange)
                        }
                        
                        Button(action: { finishSession() }) {
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
            ToolbarItem(placement: .topBarTrailing) {
                if setupStage == .playing {
                    HStack {
                        // Timer View
                        Text(formatTime(remainingSeconds))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(remainingSeconds < 30 ? .red : .primary)
                            .fixedSize()
                            .padding(6)
                            .frame(minWidth: 60)
                            .background(isPaused ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                   .stroke(isPaused ? Color.orange : Color.clear, lineWidth: 1)
                            )
                        
                        Text(LevelManager.shared.displayString(level: sessionLevel, language: sessionLanguage.code, preferredScale: userProfile?.preferredScale ?? .simple))
                           .font(.caption)
                           .padding(6)
                           .background(Color.gray.opacity(0.2))
                           .cornerRadius(8)
                    }
                } else if setupStage == .deckSelection {
                    // Stage 1: Next and Skip to Summary
                    HStack {
                        Button("Skip to Summary") {
                            setupStage = .sessionSummary
                        }
                        .font(.subheadline)
                        .disabled(selectedDeck == nil)
                        
                        Button(action: {
                            setupStage = .sessionConfiguration
                        }) {
                            Text("Next")
                                .fontWeight(.bold)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedDeck == nil)
                    }
                } else if setupStage == .sessionConfiguration {
                    // Stage 2: Skip to Summary and Next
                    HStack {
                        Button("Skip to Summary") {
                            setupStage = .sessionSummary
                        }
                        .font(.subheadline)
                        
                        Button(action: {
                            setupStage = .gameSpecificConfig
                        }) {
                            Text("Next")
                                .fontWeight(.bold)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if setupStage == .gameSpecificConfig {
                    // Stage 3: Skip to Summary and Next
                    HStack {
                        Button("Skip to Summary") {
                            setupStage = .sessionSummary
                        }
                        .font(.subheadline)
                        
                        Button(action: {
                            setupStage = .sessionSummary
                        }) {
                            Text("Next")
                                .fontWeight(.bold)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
    
    // MARK: - Logic
    
    func setupConfiguration() {
        print("DEBUG: setupConfiguration called. Profile: \(userProfile?.name ?? "nil"), Initialized: \(hasInitialized)")
        
        // Only initialize from profile ONCE to allow temporary overrides
        guard let profile = userProfile, !hasInitialized else { return }
        
        print("DEBUG: Accessing currentLanguage")
        sessionLanguage = profile.currentLanguage
        print("DEBUG: Accessing proficiencyLevel")
        sessionLevel = profile.proficiencyLevel
        print("DEBUG: Accessing dailyCardGoal")
        sessionCardGoal = profile.dailyCardGoal ?? 20
        print("DEBUG: Accessing defaultGamePreset")
        selectedPreset = profile.defaultGamePreset
        print("DEBUG: Accessing currentGameType")
        selectedGameType = profile.currentGameType // Restore last game type
        print("DEBUG: Loaded currentGameType = \(selectedGameType.rawValue)")
        
        // Load Global Audio Settings
        print("DEBUG: Accessing ttsRate")
        ttsRate = profile.ttsRate
        useTTSFallback = true 
        
        // Sync customConfig if needed
        if selectedPreset != .customize {
             print("DEBUG: Generating config from preset")
             customConfig = GameConfiguration.from(preset: selectedPreset)
             // Inject global TTS rate into the fresh preset config
             customConfig.ttsRate = profile.ttsRate
        } else {
             print("DEBUG: Checking customGameConfiguration")
             if let savedConfig = profile.customGameConfiguration {
                 print("DEBUG: Loaded customGameConfiguration")
                 customConfig = savedConfig
                 customConfig.ttsRate = profile.ttsRate
             } else {
                 print("DEBUG: No saved config, using default")
                 // Fallback if Customize selected but no config? Should act like preset.
                 customConfig.ttsRate = profile.ttsRate
             }
        }
        
        hasInitialized = true
        
        // Restore deck robustly
        if let lastId = profile.lastSelectedDeckId {
            // Run on background to assume IO, then update on Main
            DispatchQueue.global(qos: .userInitiated).async {
                if let match = self.dataManager.findDeckMetadata(id: lastId) {
                    DispatchQueue.main.async {
                        // Found it! Force state to match this deck
                        self.sessionLanguage = match.language
                        self.sessionLevel = match.proficiencyLevel ?? LevelManager.shared.normalize(match.level)
                        
                        // Populate the list for this context
                        self.dataManager.discoverDecks(language: match.language, proficiency: self.sessionLevel)
                        
                        // Set the deck
                        self.selectedDeck = match
                        print("DEBUG: Force-restored last played deck: \(match.title)")
                    }
                } else {
                     print("DEBUG: Could not find last deck with ID: \(lastId)")
                     // Fallback: Discover based on profile defaults
                     DispatchQueue.main.async {
                         self.dataManager.discoverDecks(language: self.sessionLanguage, proficiency: self.sessionLevel)
                     }
                }
            }
        } else {
             // No last deck, just discover defaults
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
        dataManager.loadDeck(metadata: metDeck)
        
        currentCardIndex = 0
        learnedCount = 0
        elapsedSeconds = 0
        remainingSeconds = sessionDuration * 60
        isPaused = false
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
        
        // Prepare Cards
        // CRITICAL FIX: Do NOT try to read `deck` (loadedDeck) immediately here for the new session,
        // because DataManager clears it (or it might be stale) and loads asynchronously.
        // We set sessionCards to empty and rely on onChange(of: loadedDeck) -> handleDeckLoaded to populate them.
        sessionCards = []
        
        // If we happen to hit the cache in DataManager, loadedDeck might ALREADY be set instantly.
        // So we check:

        if let currentDeck = deck, currentDeck.id == metDeck.id {
             // Apply Deck Overrides (e.g. Randomization from JSON)
             applyDeckOverrides(to: &sessionConfig, from: currentDeck, type: selectedGameType)
             
             // Filter and Select Cards (Limit to Session Goal)
             sessionCards = prepareSessionCards(currentDeck.cards)
        }
        
        print("DEBUG: About to set setupStage to .starting")
        withAnimation {
            setupStage = .starting
            // Enable full screen for all game modes
            dataManager.isFullScreen = true
        }
        print("DEBUG: setupStage is now: \(setupStage)")
        
        // Note: Audio playback removed here - FlashcardConfigView and game views manage their own audio
    }
    
    func playCurrentCardAudio() {
        // Only auto-play audio for Flashcards/Story mode.
        // Memory Match manages its own audio on tap.
        guard sessionConfig.gameType == .flashcards || sessionConfig.gameType == .story else { return }
        
        guard setupStage == .playing, !isPaused, !isFlipped, let deck = deck, currentCardIndex < sessionCards.count else { return }
        let card = sessionCards[currentCardIndex]
        
        var sequence: [AudioManager.AudioItem] = []
        
        let useFallback = sessionConfig.useTTSFallback
        let language = deck.language

        // Only autoplay if visibility is 'visible'
        if sessionConfig.word.audio == .visible, let wordFile = card.audioWordFile {
             sequence.append(AudioManager.AudioItem(filename: wordFile, text: card.wordTarget, language: language))
        }
        if sessionConfig.sentence.audio == .visible, let sentenceFile = card.audioSentenceFile {
             sequence.append(AudioManager.AudioItem(filename: sentenceFile, text: card.sentenceTarget, language: language))
        }
        
        if !sequence.isEmpty {
            audioManager.playSequence(items: sequence, folderName: deck.baseFolderName, useFallback: useFallback)
        }
    }
    
    func handleTimerTick() {
        guard setupStage == .playing, !isPaused else { return }
        
        elapsedSeconds += 1
        if remainingSeconds > 0 {
            remainingSeconds -= 1
        } else {
            finishSession()
        }
    }
    
    func finishSession() {
        saveActivity()
        withAnimation {
            setupStage = .finished
            dataManager.isFullScreen = false // Ensure we exit full screen
        }
    }
    
    func saveActivity() {
        let minutes = max(1, elapsedSeconds / 60)
        let language = sessionLanguage
        
        // Build comment with deck name and stats
        var comment: String?
        if let deckTitle = selectedDeck?.title {
            let totalCards = deck?.cards.count ?? 0
            comment = "\(deckTitle) · \(learnedCount)/\(totalCards) cards"
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
        learnedCount += 1
        if learnedCount >= sessionCardGoal {
            finishSession()
        } else {
            nextCard()
        }
    }
    
    func relearnCard() {
        nextCard()
    }
    
    func handleGrade(_ grade: SmartSessionManager.Grade) {
        // Apply grade to queue
        SmartSessionManager.shared.handleGrade(grade)
        
        // Update stats if card is mastered
        if grade == .easy {
            learnedCount += 1
        }
        
        // Sync active queue
        sessionCards = SmartSessionManager.shared.activeQueue
        
        // Check for completion
        if sessionCards.isEmpty {
            finishSession()
            return
        }
        
        // Animate to "next" card (which is effectively just updating the view since index 0 changed)
        // Since we removed item at index 0, the next item slides into place.
        // We might want to force a "reset" of animation state.
        
        // If we want a slide animation:
        // We can pretend we moved to next, but the list changed.
        
        // Simple update for now:
        withAnimation {
            isFlipped = false
            // currentCardIndex should stay 0 as we pop from front
            // If currentCardIndex was > 0, we should reset it?
            // Smart Sesion Manager assumes we work on head of queue.
            currentCardIndex = 0 
        }
    }
    
    func handleDeckLoaded(_ newDeck: CardDeck?) {
        // Race condition fix: If we started session but deck wasn't ready,
        // populate cards now that it is loaded.
        if setupStage == .playing && sessionCards.isEmpty, let deck = newDeck, !deck.cards.isEmpty {
            // Apply Deck Overrides (late load)
            // Note: We need to update the binding/state of sessionConfig too if we want it to reflect
            applyDeckOverrides(to: &sessionConfig, from: deck, type: sessionConfig.gameType)
            
            // Filter and Select Cards (Limit to Session Goal)
            sessionCards = prepareSessionCards(deck.cards)
            
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
