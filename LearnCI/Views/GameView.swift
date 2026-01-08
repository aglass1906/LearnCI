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
    enum GameState {
        case configuration
        case active
        case finished
    }
    
    @State private var gameState: GameState = .configuration
    @State private var currentCardIndex: Int = 0
    @State private var isFlipped: Bool = false
    
    // Configuration Settings
    @State private var sessionDuration: Int = 15 // Minutes
    @State private var sessionCardGoal: Int = 20
    @State private var sessionLanguage: Language = .spanish
    @State private var sessionLevel: LearningLevel = .superBeginner
    
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
    @State private var isRandomOrder: Bool = false
    @State private var hasInitialized: Bool = false
    @State private var useTTSFallback: Bool = true
    @State private var ttsRate: Float = 0.5
    
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
        NavigationView {
            mainContent
                .navigationTitle(navigationTitle)
                .toolbar {
                    gameToolbar
                }
                .onAppear(perform: handleAppear)
                .onChange(of: sessionLanguage) { _, newValue in
                    // Only clear if the new language ACTUALLY differs from the currently selected deck.
                    // This allows us to programmatically update sessionLanguage to match a restored deck without clearing it.
                    if let deck = selectedDeck, deck.language == newValue {
                        return
                    }
                    print("DEBUG: sessionLanguage changed to \(newValue). Clearing selectedDeck.")
                    dataManager.discoverDecks(language: newValue, level: sessionLevel)
                    selectedDeck = nil
                }
                .onChange(of: sessionLevel) { _, newValue in
                    if let deck = selectedDeck, deck.level == newValue {
                        return
                    }
                    print("DEBUG: sessionLevel changed to \(newValue). Clearing selectedDeck.")
                    dataManager.discoverDecks(language: sessionLanguage, level: newValue)
                    selectedDeck = nil
                }
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
                .onChange(of: selectedDeck) { _, newDeck in
                    if let deck = newDeck {
                        print("DEBUG: selectedDeck CHANGED to: \(deck.title). Saving to profile.")
                        if let profile = userProfile {
                            profile.lastSelectedDeckId = deck.id
                            try? modelContext.save() // Explicitly save change
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
                            // Update session state to match the restored deck
                            if sessionLanguage != match.language { sessionLanguage = match.language }
                            if sessionLevel != match.level { sessionLevel = match.level }
                        }
                    }
                }
                // Fix: Watch for profile availability (e.g. after auth restore) to trigger restore
                .onChange(of: authManager.currentUser) { _, _ in
                    print("DEBUG: authManager.currentUser changed. Profile available? \(userProfile != nil)")
                    // If profile just became available and we have decks, try to restore
                    if selectedDeck == nil, let profile = userProfile, let lastId = profile.lastSelectedDeckId {
                         print("DEBUG: Trying restore from auth change...")
                         if let match = dataManager.availableDecks.first(where: { $0.id == lastId }) {
                            selectedDeck = match
                            if sessionLanguage != match.language { sessionLanguage = match.language }
                            if sessionLevel != match.level { sessionLevel = match.level }
                        }
                    }
                }
                .onChange(of: ttsRate) { _, newRate in
                    if let profile = userProfile {
                         profile.ttsRate = newRate
                         // Debounce save? For now explicit save is okay as slider settles
                         try? modelContext.save()
                    }
                }
                .onChange(of: customConfig) { _, newConfig in
                    if selectedPreset == .customize, let profile = userProfile {
                         print("DEBUG: Saving custom config to profile")
                         profile.customGameConfiguration = newConfig
                         // Optimization: Don't call try? modelContext.save() on every change if autosave is enabled,
                         // but explicitly saving ensures persistence on crash/exit.
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
    }

    @ViewBuilder
    var mainContent: some View {
        switch gameState {
        case .configuration:
            configurationView
        case .active:
            ActiveSessionView(
                errorMessage: dataManager.errorMessage,
                deck: deck,
                sessionCards: sessionCards,
                currentCardIndex: currentCardIndex,
                learnedCount: learnedCount,
                sessionCardGoal: sessionCardGoal,
                sessionConfig: sessionConfig,
                isFlipped: $isFlipped,
                onRelearn: relearnCard,
                onLearned: learnedCard,
                onFinish: finishSession,
                onNext: nextCard,
                onPrev: prevCard
            )
        case .finished:
            SessionFinishView(
                learnedCount: learnedCount,
                elapsedSeconds: elapsedSeconds,
                gameState: $gameState,
                deckTitle: selectedDeck?.title ?? "Unknown Deck",
                language: sessionLanguage,
                level: sessionLevel,
                preset: selectedPreset,
                gameType: sessionConfig.gameType,
                duration: sessionDuration,
                cardGoal: sessionCardGoal,
                isRandom: isRandomOrder
            )
        }
    }
    
    // MARK: - Event Handlers
    
    func handleAppear() {
        if gameState == .configuration {
            setupConfiguration()
            dataManager.discoverDecks(language: sessionLanguage, level: sessionLevel)
        }
    }
    
    @State private var wasPlayingBeforeBackground: Bool = false
    
    func handleScenePhase(_ oldPhase: ScenePhase, _ newPhase: ScenePhase) {
        if gameState == .active {
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
        switch gameState {
        case .configuration: return "Configure Session"
        case .active: return "" // Handled by toolbar principal
        case .finished: return "Session Complete"
        }
    }
    
    var configurationView: some View {
        GameConfigurationView(
            sessionLanguage: $sessionLanguage,
            sessionLevel: $sessionLevel,
            selectedDeck: $selectedDeck,
            sessionDuration: $sessionDuration,
            sessionCardGoal: $sessionCardGoal,
            isRandomOrder: $isRandomOrder,
            selectedPreset: $selectedPreset,
            customConfig: $customConfig,
            selectedGameType: $selectedGameType,
            useTTSFallback: $useTTSFallback,
            ttsRate: $ttsRate,
            availableDecks: dataManager.availableDecks,
            startAction: startActiveSession,
            onSavePreset: { newPreset in
                if let profile = userProfile {
                    profile.defaultGamePreset = newPreset
                }
            }
        )
    }

    
    // MARK: - Card Rendering Helpers
    

    
    @ToolbarContentBuilder
    private var gameToolbar: some ToolbarContent {
        if gameState == .active {
            ToolbarItem(placement: .topBarLeading) {
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
            }
            
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(deck?.title ?? "Learning")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: 200) // Constrain width to avoid hitting buttons
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
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
                     
                     Text(sessionLevel.rawValue)
                        .font(.caption)
                        .padding(6)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                 }
            }
    }
    }
    
    // MARK: - Logic
    
    func setupConfiguration() {
        print("DEBUG: setupConfiguration called. Profile: \(userProfile?.name ?? "nil"), Initialized: \(hasInitialized)")
        
        // Only initialize from profile ONCE to allow temporary overrides
        guard let profile = userProfile, !hasInitialized else { return }
        
        sessionLanguage = profile.currentLanguage
        sessionLevel = profile.currentLevel
        sessionCardGoal = profile.dailyCardGoal ?? 20
        selectedPreset = profile.defaultGamePreset
        selectedGameType = profile.currentGameType // Restore last game type
        // Load Global Audio Settings
        ttsRate = profile.ttsRate
        // useTTSFallback isn't in profile yet but is in GameConfig. 
        // We should treat GameConfig.useTTSFallback as the source of truth if loading a preset, 
        // OR we can add it to profile. For now, default true.
        useTTSFallback = true 
        
        // Sync customConfig if needed
        if selectedPreset != .customize {
             customConfig = GameConfiguration.from(preset: selectedPreset)
             // Inject global TTS rate into the fresh preset config
             customConfig.ttsRate = profile.ttsRate
        } else if let savedConfig = profile.customGameConfiguration {
             // If we have a saved config, use it...
             customConfig = savedConfig
             // ...BUT ensure the TTS rate reflects the current global preference as a baseline
             // (unless we want 'Review configuration' to persist its OWN rate separate from Profile?
             // User said "default to user's global tts speed".
             // It's safer to sync it here so the slider starts at the "Global" value.)
             customConfig.ttsRate = profile.ttsRate
        } else {
             // Fallback if Customize selected but no config? Should act like preset.
             customConfig.ttsRate = profile.ttsRate
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
                        self.sessionLevel = match.level
                        
                        // Populate the list for this context
                        self.dataManager.discoverDecks(language: match.language, level: match.level)
                        
                        // Set the deck
                        self.selectedDeck = match
                        print("DEBUG: Force-restored last played deck: \(match.title)")
                    }
                } else {
                     print("DEBUG: Could not find last deck with ID: \(lastId)")
                     // Fallback: Discover based on profile defaults
                     DispatchQueue.main.async {
                         self.dataManager.discoverDecks(language: self.sessionLanguage, level: self.sessionLevel)
                     }
                }
            }
        } else {
             // No last deck, just discover defaults
             dataManager.discoverDecks(language: sessionLanguage, level: sessionLevel)
        }
    }
    
    func startActiveSession() {
        guard let metDeck = selectedDeck else { return }
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
        
        sessionConfig.isRandomOrder = isRandomOrder
        sessionConfig.gameType = selectedGameType
        
        // Apply Global Audio Settings
        sessionConfig.ttsRate = ttsRate
        sessionConfig.useTTSFallback = useTTSFallback
        
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
             
             let filtered = filterCards(currentDeck.cards, for: selectedGameType)
             
             if sessionConfig.isRandomOrder {
                 sessionCards = filtered.shuffled()
             } else {
                 sessionCards = filtered
             }
        }
        
        withAnimation {
            gameState = .active
        }
        
        // Audio will be triggered by handleDeckLoaded if we waited, 
        // or we trigger it here if we hit cache.
        if !sessionCards.isEmpty {
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                 self.playCurrentCardAudio()
             }
        }
    }
    
    func playCurrentCardAudio() {
        // Only auto-play audio for Flashcards/Story mode.
        // Memory Match manages its own audio on tap.
        guard sessionConfig.gameType == .flashcards || sessionConfig.gameType == .story else { return }
        
        guard gameState == .active, !isPaused, !isFlipped, let deck = deck, currentCardIndex < sessionCards.count else { return }
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
        guard gameState == .active, !isPaused else { return }
        
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
            gameState = .finished
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
            if isRandomOrder {
                comment? += " (Random)"
            }
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
        if let deck = deck, currentCardIndex < deck.cards.count - 1 {
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
    
    func handleDeckLoaded(_ newDeck: CardDeck?) {
        // Race condition fix: If we started session but deck wasn't ready,
        // populate cards now that it is loaded.
        if gameState == .active && sessionCards.isEmpty, let deck = newDeck, !deck.cards.isEmpty {
            // Apply Deck Overrides (late load)
            // Note: We need to update the binding/state of sessionConfig too if we want it to reflect
            applyDeckOverrides(to: &sessionConfig, from: deck, type: sessionConfig.gameType)
            
            let filtered = filterCards(deck.cards, for: sessionConfig.gameType)
            
            if sessionConfig.isRandomOrder {
                sessionCards = filtered.shuffled()
            } else {
                sessionCards = filtered
            }
            
            // Trigger audio now that we have cards
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playCurrentCardAudio()
            }
        }
    }
    
    // MARK: - Deck Logic Helpers
    
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
        let lowerKey = type.rawValue.lowercased() // "flashcards"
        
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






struct SessionSummaryView: View {
    let deckTitle: String
    let language: Language
    let level: LearningLevel
    let preset: GameConfiguration.Preset
    let gameType: GameConfiguration.GameType
    let duration: Int
    let cardGoal: Int
    let isRandom: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Summary")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            VStack(spacing: 0) {
                // Focus Row (Language & Level)
                HStack {
                    Text(language.flag)
                        .font(.title3)
                    Text(language.rawValue)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(level.rawValue)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding()
                
                Divider()
                
                // Deck Row
                HStack {
                    Image(systemName: "menucard.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text(deckTitle)
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding()
                
                Divider()
                
                // Mode Row
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.purple)
                        .frame(width: 24)
                    if gameType == .flashcards {
                        Text(preset.rawValue)
                            .fontWeight(.medium)
                        if preset == .customize {
                            Text("(Custom)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } else {
                        // For non-flashcard games, show the Game Type Name
                        Text(gameType.rawValue)
                            .fontWeight(.medium)
                    }
                    Spacer()
                }
                .padding()
                
                Divider()
                
                // Options Row
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    Text("\(duration) min")
                    Text("·")
                        .foregroundColor(.secondary)
                    Text("\(cardGoal) cards")
                    
                    if isRandom {
                        Text("·")
                            .foregroundColor(.secondary)
                        Image(systemName: "shuffle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .background(Color.gray.opacity(0.1)) // Slightly darker for contrast
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
        }
    }
}


#Preview {
    GameView()
        .environment(DataManager())
        .environment(YouTubeManager())
        .environment(AuthManager())
}
