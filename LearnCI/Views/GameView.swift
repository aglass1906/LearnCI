import SwiftUI
import SwiftData
import Combine

struct GameView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @Query private var allProfiles: [UserProfile]

    @Environment(AudioManager.self) private var audioManager
    private let availableGameTypes: [GameConfiguration.GameType]
    private let initialGameType: GameConfiguration.GameType?
    private let initialDeck: DeckMetadata?

    // State Management
    enum GameSetupStage {
        case gameSelection            // Stage 0
        case deckSelection           // Stage 1
        case sessionConfiguration     // Stage 2
        case gameSpecificConfig       // Stage 3
        case sessionSummary           // Stage 4
        case starting                 // Stage 5 (transition)
        case playing                  // Stage 6
        case finished                 // Stage 7
    }

    @State private var setupStage: GameSetupStage = .gameSelection

    // Configuration Settings (drive setup UI bindings)
    @State private var sessionDuration: Int = 15 // Minutes
    @State private var sessionCardGoal: Int = 20
    @State private var sessionLanguage: Language = .spanish
    @State private var sessionLevel: Int = 1 // 1-6

    // Scene Phase
    @Environment(\.scenePhase) private var scenePhase

    // New selective deck flow
    @State private var selectedDeck: DeckMetadata?

    // Game Configuration (setup UI bindings)
    @State private var selectedPreset: GameConfiguration.Preset = .inputFocus
    @State private var selectedGameType: GameConfiguration.GameType = .flashcards
    @State private var customConfig: GameConfiguration = GameConfiguration.from(preset: .inputFocus)
    @State private var order: GameConfiguration.OrderStrategy = .smart
    @State private var hasInitialized: Bool = false
    @State private var useTTSFallback: Bool = true
    @State private var ttsRate: Float = 0.5
    // UI Customization State
    @State private var navigationStyle: NavigationStyle = .swipe
    @State private var autoNextDelay: TimeInterval = 2.0
    @State private var confirmationStyle: ConfirmationStyle = .quiz

    // ViewModel (owns all runtime game state)
    @State private var viewModel: GameSessionViewModel?

    init(
        availableGameTypes: [GameConfiguration.GameType] = GameConfiguration.GameType.allCases,
        initialGameType: GameConfiguration.GameType? = nil,
        initialDeck: DeckMetadata? = nil
    ) {
        let normalizedTypes = availableGameTypes.isEmpty ? GameConfiguration.GameType.allCases : availableGameTypes
        self.availableGameTypes = normalizedTypes
        self.initialGameType = initialGameType
        self.initialDeck = initialDeck
        _selectedGameType = State(initialValue: initialGameType ?? normalizedTypes.first ?? .flashcards)
        _selectedDeck = State(initialValue: initialDeck)
        _setupStage = State(initialValue: initialDeck == nil ? .gameSelection : .sessionConfiguration)
    }

    private var isStudyFlow: Bool {
        availableGameTypes == [.flashcards]
    }

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
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if setupStage == .playing {
                        viewModel?.handleScenePhase(old: oldPhase, new: newPhase)
                    }
                }
                .onChange(of: dataManager.loadedDeck) { _, newDeck in
                    viewModel?.handleDeckLoaded(newDeck)
                }
                .onChange(of: setupStage) { oldStage, newStage in
                    print("DEBUG: setupStage changed from \(oldStage) to \(newStage)")
                    if newStage == .playing {
                        applyGameFeedbackPreferences()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            viewModel?.playCurrentCardAudio()
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

                    // Clamp card goal to available cards
                    if let loaded = dataManager.loadDeck(from: deck) {
                        let count = loaded.cards.count
                        if sessionCardGoal > count {
                            print("DEBUG: Clamping sessionCardGoal from \(sessionCardGoal) to \(count)")
                            sessionCardGoal = count
                        }
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

                if let deck = selectedDeck, !deck.supportedModes.contains(newType) {
                    selectedDeck = quickStartDeck(for: newType)
                }
            }
            .onChange(of: userProfile?.gameSoundEffectsEnabled) { _, _ in
                applyGameFeedbackPreferences()
            }
            .onChange(of: userProfile?.gameHapticsEnabled) { _, _ in
                applyGameFeedbackPreferences()
            }
    }
    @ViewBuilder
    var mainContent: some View {
        switch setupStage {
        case .gameSelection:
            let _ = print("DEBUG: Showing gameSelection view")
            GameSelectionView(
                selectedGameType: $selectedGameType,
                gameTypes: availableGameTypes,
                quickStartDeckTitle: quickStartDeckTitle,
                onPlayNow: startWithDefaults,
                onConfigure: configureSelectedGame
            )
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
                    onNext: { setupStage = .sessionSummary },
                    onBack: { setupStage = .sessionConfiguration },
                    onSkipToSummary: { setupStage = .sessionSummary }
                )
            } else {
                Text("No deck selected")
            }
        case .sessionSummary:
            PreGameSummaryView(
                deckTitle: (selectedDeck?.folderName == "Virtual"
                    ? (selectedDeck?.title.replacingOccurrences(of: "Focus: ", with: "") ?? "Custom Deck")
                    : (selectedDeck?.title ?? "Unknown Deck")),
                coverImage: selectedDeck?.coverImage,
                folderName: selectedDeck?.folderName,
                language: sessionLanguage,
                level: sessionLevel,
                preset: selectedPreset,
                gameType: selectedGameType,
                duration: sessionDuration,
                cardGoal: sessionCardGoal,
                order: order,
                customConfig: customConfig,
                startButtonTitle: isStudyFlow ? "Start Study" : "Start Game",
                settingsTitle: isStudyFlow ? "Study Settings" : "Game Settings",
                onStartGame: startActiveSession,
                onBack: { setupStage = .gameSpecificConfig }
            )
        case .starting:
            let _ = print("DEBUG: Showing starting transition")
            ProgressView(isStudyFlow ? "Preparing study session..." : "Preparing game...")
                .onAppear {
                    print("DEBUG: Starting transition onAppear - will move to .playing in 0.5s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("DEBUG: Transitioning from .starting to .playing")
                        setupStage = .playing
                    }
                }
        case .playing:
            let _ = print("DEBUG: Showing ActiveSessionView for playing stage")
            if let vm = viewModel {
                // Self-contained arcade games (Word Rain, etc.) drive their own
                // session end via onFinish. They must NOT trigger endSession() via
                // onLearned/onGrade or the session ends prematurely before the
                // game's own end animation completes.
                let isSelfContained = [GameConfiguration.GameType.wordRain, .wordCrush, .linker, .memoryMatch]
                    .contains(vm.sessionConfig.gameType)
                VStack(spacing: 0) {
                    if isStudyFlow {
                        StudyDeckSessionHeader(
                            title: vm.deck?.title ?? selectedDeck?.title ?? "Study Deck",
                            subtitle: "\(vm.currentCardIndex + 1) of \(max(vm.sessionCards.count, 1))",
                            onCancel: {
                                audioManager.stopAudio()
                                vm.pauseSession()
                                dataManager.isFullScreen = false
                                dismiss()
                            }
                        )
                    }

                    ActiveSessionView(
                        errorMessage: dataManager.errorMessage,
                        deck: vm.deck,
                        sessionCards: vm.sessionCards,
                        currentCardIndex: vm.currentCardIndex,
                        learnedCount: vm.learnedCount,
                        sessionCardGoal: vm.sessionCardGoal,
                        sessionConfig: vm.sessionConfig,
                        isFlipped: Binding(
                            get: { vm.isFlipped },
                            set: { vm.isFlipped = $0 }
                        ),
                        matchMode: vm.sessionConfig.memoryMatchMode,
                        onRelearn: { vm.relearnCard() },
                        onLearned: isSelfContained ? { vm.recordWordLearned() } : { vm.learnedCard() },
                        onFinish: { vm.endSession() },
                        onNext: { vm.nextCard() },
                        onPrev: { vm.prevCard() },
                        onGrade: isSelfContained ? nil : { vm.handleGrade($0) }
                    )
                }
            }
        case .finished:
            if let vm = viewModel {
                SessionFinishView(
                    learnedCount: vm.learnedCount,
                    elapsedSeconds: vm.elapsedSeconds,
                    setupStage: $setupStage,
                    deckTitle: (selectedDeck?.folderName == "Virtual"
                        ? (selectedDeck?.title.replacingOccurrences(of: "Focus: ", with: "") ?? "Custom Deck")
                        : (selectedDeck?.title ?? "Unknown Deck")),
                    coverImage: selectedDeck?.coverImage,
                    folderName: selectedDeck?.folderName,
                    language: sessionLanguage,
                    level: sessionLevel,
                    preset: selectedPreset,
                    gameType: vm.sessionConfig.gameType,
                    duration: sessionDuration,
                    cardGoal: sessionCardGoal,
                    order: vm.sessionConfig.order,
                    primaryActionTitle: isStudyFlow ? "Study Again" : "Play Again",
                    menuActionTitle: isStudyFlow ? "Return to Deck" : "Return to Menu",
                    onReturnToMenu: isStudyFlow ? { dismiss() } : nil,
                    onPlayAgain: startActiveSession
                )
            }
        }
    }

    // MARK: - Event Handlers

    func handleAppear() {
        if viewModel == nil {
            viewModel = GameSessionViewModel(audioManager: audioManager)
            viewModel?.onSessionFinished = { [self] in
                saveActivity()
                withAnimation {
                    setupStage = .finished
                    dataManager.isFullScreen = false
                }
            }
            viewModel?.onSessionStarting = { [self] in
                print("DEBUG: About to set setupStage to .starting")
                withAnimation {
                    setupStage = .starting
                    dataManager.isFullScreen = true
                }
            }
        }
        
        // Initial setup and discovery
        if !hasInitialized {
            setupConfiguration()
        }

        applyGameFeedbackPreferences()
        
        // Only trigger discovery if availableDecks is empty or context changed
        if dataManager.availableDecks.isEmpty {
            dataManager.discoverDecks(language: sessionLanguage, proficiency: sessionLevel)
        }
    }

    var navigationTitle: String {
        switch setupStage {
        case .gameSelection: return "Choose a Game"
        case .deckSelection: return "Select Deck"
        case .sessionConfiguration: return "Session Options"
        case .gameSpecificConfig: return isStudyFlow ? "Study Settings" : "Game Settings"
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
            onSkipToSummary: startWithDefaults
        )
    }


    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var gameToolbar: some ToolbarContent {
        Group {
            ToolbarItem(placement: .topBarLeading) {
                if setupStage == .playing, let vm = viewModel {
                    HStack {
                        Button(action: {
                            if vm.isPaused {
                                vm.resumeSession()
                            } else {
                                vm.pauseSession()
                            }
                        }) {
                            Image(systemName: vm.isPaused ? "play.fill" : "pause.fill")
                                .foregroundColor(vm.isPaused ? .green : .orange)
                        }

                        Button(action: { vm.endSession() }) {
                            Image(systemName: "stop.fill")
                            .foregroundColor(.red)
                        }
                    }
                } else if setupStage != .gameSelection && setupStage != .starting && setupStage != .finished {
                    Button("Back") {
                        switch setupStage {
                        case .deckSelection:
                            setupStage = .gameSelection
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
            if let vm = viewModel {
                HStack {
                    timerView(vm: vm)
                    levelBadgeView
                }
            }
        }
    }

    private func timerView(vm: GameSessionViewModel) -> some View {
        Text(vm.formattedTimeRemaining)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(vm.isTimeLow ? .red : .primary)
            .fixedSize()
            .padding(6)
            .frame(minWidth: 60)
            .background(vm.isPaused ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                   .stroke(vm.isPaused ? Color.orange : Color.clear, lineWidth: 1)
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
            Button("Start") {
                startWithDefaults()
            }
            .disabled(selectedDeck == nil)
        }

        ToolbarItem(placement: .bottomBar) {
            Button {
                setupStage = .sessionConfiguration
            } label: {
                Label("Configure", systemImage: "slider.horizontal.3")
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

    private var quickStartDeckTitle: String? {
        guard let deck = quickStartDeck(for: selectedGameType) else { return nil }
        return deck.folderName == "Virtual"
            ? deck.title.replacingOccurrences(of: "Focus: ", with: "")
            : deck.title
    }

    private func quickStartDeck(for gameType: GameConfiguration.GameType) -> DeckMetadata? {
        if let selectedDeck, selectedDeck.supportedModes.contains(gameType) {
            return selectedDeck
        }

        return dataManager.availableDecks.first { $0.supportedModes.contains(gameType) }
    }

    private func startWithDefaults() {
        let deckToUse = quickStartDeck(for: selectedGameType)
            ?? dataManager
                .discoverDecks(language: sessionLanguage, proficiency: sessionLevel)
                .first { $0.supportedModes.contains(selectedGameType) }

        guard let deckToUse else {
            setupStage = .deckSelection
            return
        }

        selectedDeck = deckToUse
        startActiveSession(using: deckToUse)
    }

    private func configureSelectedGame() {
        if selectedDeck?.supportedModes.contains(selectedGameType) == false {
            selectedDeck = nil
        }

        setupStage = .deckSelection
    }

    func setupConfiguration() {
        print("DEBUG: setupConfiguration called. Profile: \(userProfile?.name ?? "nil"), Initialized: \(hasInitialized)")

        guard let profile = userProfile, !hasInitialized else { return }

        sessionLanguage = initialDeck?.language ?? profile.currentLanguage
        sessionLevel = initialDeck?.proficiencyLevel ?? (initialDeck?.level.map { LevelManager.shared.normalize($0) } ?? profile.proficiencyLevel)
        sessionCardGoal = profile.dailyCardGoal ?? 20
        selectedPreset = profile.defaultGamePreset
        selectedGameType = initialGameType ?? allowedGameType(for: profile.currentGameType)

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

        if let initialDeck {
            selectedDeck = initialDeck
            dataManager.discoverDecks(language: initialDeck.language, proficiency: sessionLevel)
            _ = dataManager.loadDeck(from: initialDeck)
        } else if let lastId = profile.lastSelectedDeckId {
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

    private func applyGameFeedbackPreferences() {
        GameFeedbackManager.shared.configure(
            soundEffectsEnabled: userProfile?.gameSoundEffectsEnabled ?? true,
            hapticsEnabled: userProfile?.gameHapticsEnabled ?? true
        )
    }

    private func allowedGameType(for gameType: GameConfiguration.GameType) -> GameConfiguration.GameType {
        availableGameTypes.contains(gameType) ? gameType : (availableGameTypes.first ?? .flashcards)
    }

    func startActiveSession() {
        guard let metDeck = selectedDeck else {
            print("DEBUG: ERROR - No selected deck!")
            return
        }

        startActiveSession(using: metDeck)
    }

    private func startActiveSession(using metDeck: DeckMetadata) {
        print("DEBUG: ====== startActiveSession() called ======")
        print("DEBUG: Selected deck: \(metDeck.title)")
        _ = dataManager.loadDeck(from: metDeck)

        guard let loadedDeck = deck, loadedDeck.id == metDeck.id else {
            print("DEBUG: Deck not loaded yet, VM will handle via handleDeckLoaded")
            return
        }

        viewModel?.startSession(
            deck: loadedDeck,
            selectedPreset: selectedPreset,
            customConfig: customConfig,
            gameType: selectedGameType,
            order: order,
            confirmationStyle: confirmationStyle,
            navigationStyle: navigationStyle,
            autoNextDelay: autoNextDelay,
            ttsRate: ttsRate,
            useTTSFallback: useTTSFallback,
            sessionDuration: sessionDuration,
            sessionCardGoal: sessionCardGoal
        )
    }

    func saveActivity() {
        guard let vm = viewModel else { return }
        let activity = vm.makeActivity(
            language: sessionLanguage,
            deckTitle: selectedDeck?.title,
            totalCards: deck?.cards.count,
            userID: authManager.currentUser,
            preset: selectedPreset
        )
        modelContext.insert(activity)
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

private struct StudyDeckSessionHeader: View {
    let title: String
    let subtitle: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.14))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Cancel study session")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}



#Preview {
    GameView()
        .environment(DataManager())
        .environment(YouTubeManager())
        .environment(AuthManager())
}
