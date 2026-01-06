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
    @State private var customConfig: GameConfiguration = GameConfiguration.from(preset: .inputFocus)
    @State private var isRandomOrder: Bool = false
    
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
                    print("DEBUG: sessionLanguage changed to \(newValue). Clearing selectedDeck.")
                    dataManager.discoverDecks(language: newValue, level: sessionLevel)
                    selectedDeck = nil
                }
                .onChange(of: sessionLevel) { _, newValue in
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
                        }
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
                onNext: nextCard,
                onPrev: prevCard
            )
        case .finished:
            SessionFinishView(
                learnedCount: learnedCount,
                elapsedSeconds: elapsedSeconds,
                gameState: $gameState,
                selectedDeck: $selectedDeck,
                deckTitle: selectedDeck?.title ?? "Unknown Deck",
                language: sessionLanguage,
                level: sessionLevel,
                preset: selectedPreset,
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
    
    func handleScenePhase(_ oldPhase: ScenePhase, _ newPhase: ScenePhase) {
        if gameState == .active {
            if newPhase == .background || newPhase == .inactive {
                isPaused = true
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
        case .active: return deck?.title ?? "Learning"
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
        print("DEBUG: setupConfiguration called. Profile: \(userProfile?.name ?? "nil"), LastDeckID: \(userProfile?.lastSelectedDeckId ?? "nil")")
        if let profile = userProfile {
            sessionLanguage = profile.currentLanguage
            sessionLevel = profile.currentLevel
            sessionCardGoal = profile.dailyCardGoal ?? 20
            selectedPreset = profile.defaultGamePreset
            
            // Sync customConfig if needed
            if selectedPreset != .customize {
                customConfig = GameConfiguration.from(preset: selectedPreset)
            }
            
            // Attempt to restore last selected deck
            // FIX: Wrap in async to prevent onChange(of: language) from clearing the restored deck immediately
            if let lastId = profile.lastSelectedDeckId {
                DispatchQueue.main.async {
                    if self.selectedDeck == nil {
                         print("DEBUG: Attempting delayed restore for \(lastId)")
                         // If decks are already loaded, try to match immediately
                         if let match = self.dataManager.availableDecks.first(where: { $0.id == lastId }) {
                             print("DEBUG: Delayed restore SUCCESS: \(match.title)")
                             self.selectedDeck = match
                         } else {
                             // If not found yet, we rely on onChange(of: availableDecks)
                             print("DEBUG: Delayed restore deferring to availableDecks change...")
                         }
                    }
                }
            }
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
        
        // Capture final config
        if selectedPreset == .customize {
            sessionConfig = customConfig
        } else {
            sessionConfig = GameConfiguration.from(preset: selectedPreset)
        }
        
        sessionConfig.isRandomOrder = isRandomOrder
        
        // Prepare Cards
        if let currentDeck = deck {
            if sessionConfig.isRandomOrder {
                sessionCards = currentDeck.cards.shuffled()
            } else {
                sessionCards = currentDeck.cards
            }
        } else {
            sessionCards = []
        }
        
        withAnimation {
            gameState = .active
        }
        
        // Delay slightly to ensure view is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            playCurrentCardAudio()
        }
    }
    
    func playCurrentCardAudio() {
        guard gameState == .active, !isPaused, !isFlipped, let deck = deck, currentCardIndex < sessionCards.count else { return }
        let card = sessionCards[currentCardIndex]
        
        var sequence: [AudioManager.AudioItem] = []
        
        let useFallback = sessionConfig.useTTSFallback
        let language = deck.language

        // Only autoplay if visibility is 'visible'
        if sessionConfig.word.audio == .visible, let wordFile = card.audioWordFile {
             sequence.append(AudioManager.AudioItem(filename: wordFile, text: card.targetWord, language: language))
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
            activityType: .flashcards, 
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
            if sessionConfig.isRandomOrder {
                sessionCards = deck.cards.shuffled()
            } else {
                sessionCards = deck.cards
            }
            
            // Trigger audio now that we have cards
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playCurrentCardAudio()
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



struct StudyLinksView: View {
    let word: String
    let sentence: String
    let languageCode: String
    
    var body: some View {
        HStack(spacing: 15) {
            LinkButton(
                title: "Translate",
                icon: "character.book.closed.fill",
                color: .blue,
                action: {
                    // Google Translate (Deep link or web)
                    let url = "https://translate.google.com/?sl=\(languageCode)&tl=en&text=\(sentence)&op=translate"
                    openLink(url)
                }
            )
            
            LinkButton(
                title: "Images",
                icon: "photo.stack",
                color: .purple,
                action: {
                    // Google Image Search
                     let url = "https://www.google.com/search?tbm=isch&q=\(word)+\(languageName)"
                     openLink(url)
                }
            )
            
            LinkButton(
                title: "Search",
                icon: "magnifyingglass",
                color: .green,
                action: {
                    // Google Web Search
                    let url = "https://www.google.com/search?q=\(word)+\(languageName)+meaning"
                    openLink(url)
                }
            )
        }
        .padding(.top, 5)
    }
    
    private var languageName: String {
        // Simple mapping only for search context
        switch languageCode {
        case "es": return "spanish"
        case "ja": return "japanese"
        case "ko": return "korean"
        default: return ""
        }
    }
    
    private func openLink(_ url: String) {
         if let link = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
             UIApplication.shared.open(link)
         }
    }
}

struct LinkButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(color)
            .frame(width: 65, height: 60)
            .background(color.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}


struct SessionSummaryView: View {
    let deckTitle: String
    let language: Language
    let level: LearningLevel
    let preset: GameConfiguration.Preset
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
                    Image(systemName: "eye.fill")
                        .foregroundColor(.purple)
                        .frame(width: 24)
                    Text(preset.rawValue)
                        .fontWeight(.medium)
                    if preset == .customize {
                        Text("(Custom)")
                            .foregroundColor(.secondary)
                            .font(.caption)
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
