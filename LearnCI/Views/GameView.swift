import SwiftUI
import SwiftData
import Combine

struct GameView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allProfiles: [UserProfile]
    
    @State private var audioManager = AudioManager()
    
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
    
    static let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var userProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }
    
    var deck: CardDeck? {
        dataManager.loadedDeck
    }
    
    var body: some View {
        NavigationView {
            Group {
                switch gameState {
                case .configuration:
                    configurationView
                case .active:
                    activeGameView
                case .finished:
                    finishView
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
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
                             Text(formatTime(remainingSeconds))
                                 .font(.system(.body, design: .monospaced))
                                 .foregroundColor(remainingSeconds < 30 ? .red : .primary)
                                 .fixedSize()
                                 .padding(6)
                                 .frame(minWidth: 60)
                                 .background(isPaused ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
                                 .cornerRadius(8)
                                 .overlay {
                                     if isPaused {
                                         RoundedRectangle(cornerRadius: 8)
                                             .stroke(Color.orange, lineWidth: 1)
                                     }
                                 }
                             
                             Text(sessionLevel.rawValue)
                                .font(.caption)
                                .padding(6)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                         }
                    }
                }
            }
            .onAppear {
                if gameState == .configuration {
                    setupConfiguration()
                    // Initial discovery
                    dataManager.discoverDecks(language: sessionLanguage, level: sessionLevel)
                }
            }
            .onChange(of: sessionLanguage) { _, newValue in
                dataManager.discoverDecks(language: newValue, level: sessionLevel)
                selectedDeck = nil // Reset selection when language changes
            }
            .onChange(of: sessionLevel) { _, newValue in
                dataManager.discoverDecks(language: sessionLanguage, level: newValue)
                selectedDeck = nil // Reset selection when level changes
            }
            .onReceive(GameView.timer) { _ in
                handleTimerTick()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if gameState == .active {
                    if newPhase == .background || newPhase == .inactive {
                        isPaused = true
                    }
                }
            }
            .onChange(of: isPaused) { _, newValue in
                if newValue {
                    audioManager.stopAudio()
                } else {
                    playCurrentCardAudio()
                }
            }
            .onChange(of: currentCardIndex) { _, _ in
                playCurrentCardAudio()
            }
            .onChange(of: isFlipped) { _, newValue in
                if !newValue { // When flipped back to front
                    playCurrentCardAudio()
                } else {
                    audioManager.stopAudio() // Stop word/sentence audio when showing meaning
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    var navigationTitle: String {
        switch gameState {
        case .configuration: return "Configure Session"
        case .active: return deck?.title ?? "Learning"
        case .finished: return "Session Complete"
        }
    }
    
    var configurationView: some View {
        ScrollView {
            VStack(spacing: 25) {
                focusSelectionSection
                deckSelectionSection
                adjustmentsSection
                
                Spacer()
                
                Button(action: startActiveSession) {
                    Text("Start Learn Session")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedDeck == nil ? Color.gray : Color.blue)
                        .cornerRadius(15)
                        .shadow(radius: selectedDeck == nil ? 0 : 5)
                }
                .disabled(selectedDeck == nil)
                .padding(.horizontal)
                .padding(.top, 40)
            }
            .padding(.vertical)
        }
    }
    
    private var focusSelectionSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Session Focus")
                .font(.headline)
            
            HStack {
                Menu {
                    ForEach(Language.allCases) { lang in
                        Button(action: { sessionLanguage = lang }) {
                            HStack {
                                Text("\(lang.flag) \(lang.rawValue)")
                                if sessionLanguage == lang { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("\(sessionLanguage.flag) \(sessionLanguage.rawValue)")
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
                
                Menu {
                    ForEach(LearningLevel.allCases) { level in
                        Button(action: { sessionLevel = level }) {
                            HStack {
                                Text(level.rawValue)
                                if sessionLevel == level { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(sessionLevel.rawValue)
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var deckSelectionSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Select Deck")
                .font(.headline)
            
            if dataManager.availableDecks.isEmpty {
                Text("No decks found for this selection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(10)
            } else {
                VStack(spacing: 10) {
                    ForEach(dataManager.availableDecks) { deck in
                        Button(action: { selectedDeck = deck }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(deck.title)
                                        .font(.subheadline.bold())
                                    Text("\(deck.language.rawValue) • \(deck.level.rawValue)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedDeck?.id == deck.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(selectedDeck?.id == deck.id ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedDeck?.id == deck.id ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var adjustmentsSection: some View {
        VStack(spacing: 25) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Time Limit")
                    .font(.headline)
                
                HStack {
                    Image(systemName: "clock")
                    Slider(value: Binding(get: { Double(sessionDuration) }, set: { sessionDuration = Int($0) }), in: 1...60, step: 1)
                    Text("\(sessionDuration) min")
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 60)
                }
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Card Goal")
                    .font(.headline)
                
                Stepper(value: $sessionCardGoal, in: 5...100, step: 5) {
                    HStack {
                        Image(systemName: "square.stack.3d.up.fill")
                        Text("\(sessionCardGoal) cards")
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    
    var activeGameView: some View {
        VStack {
            if let error = dataManager.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Data Loading Issue")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding()
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            if let deck = deck {
                if deck.cards.isEmpty {
                    Text("No cards available.")
                } else {
                    let card = deck.cards[currentCardIndex]
                    
                    // Progress Header
                    VStack(spacing: 12) {
                        HStack {
                            Text("Session Progress")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(learnedCount) / \(sessionCardGoal) cards")
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)
                        }
                        
                        ProgressView(value: Double(learnedCount), total: Double(sessionCardGoal))
                            .tint(.blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Card View
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isFlipped ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                            .shadow(radius: 5)
                        
                        VStack(spacing: 20) {
                            if !isFlipped {
                                    // Front: Target Content
                                    VStack(spacing: 15) {
                                        // Optional Image
                                        if let image = resolveImage(card.imageFile, folder: deck.baseFolderName) {
                                            image
                                                .resizable()
                                                .scaledToFit()
                                                .frame(maxHeight: 180)
                                                .cornerRadius(10)
                                        }
                                        
                                        HStack {
                                            Text(card.targetWord)
                                                .font(.system(size: 40, weight: .bold))
                                            
                                            Button(action: {
                                                if let file = card.audioWordFile {
                                                    audioManager.playAudio(named: file, folderName: deck.baseFolderName)
                                                }
                                            }) {
                                                Image(systemName: "speaker.wave.2.fill")
                                                    .font(.title)
                                            }
                                        }
                                        
                                        Divider()
                                        
                                        VStack {
                                            Text(card.sentenceTarget)
                                                .font(.headline)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal)
                                            
                                            Button(action: {
                                                 if let file = card.audioSentenceFile {
                                                    audioManager.playAudio(named: file, folderName: deck.baseFolderName)
                                                }
                                            }) {
                                                HStack {
                                                    Image(systemName: "speaker.wave.2.circle.fill")
                                                    Text("Play Sentence")
                                                }
                                                .font(.subheadline)
                                                .padding(8)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(10)
                                            }
                                        }
                                    }
                            } else {
                                // Back: Translations
                                VStack(spacing: 15) {
                                    Text("Meaning:")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    Text(card.nativeTranslation)
                                        .font(.title)
                                        .foregroundColor(.secondary)
                                    
                                    Divider()
                                    
                                    Text("Sentence Meaning:")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        
                                    Text(card.sentenceNative)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .scaleEffect(x: -1, y: 1)
                            }
                        }
                        .padding()
                    }
                    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    .frame(height: 350)
                    .padding()
                    .onTapGesture {
                        withAnimation(.spring()) {
                            isFlipped.toggle()
                        }
                    }
                    
                    // Learning Success Controls
                    if isFlipped {
                        HStack(spacing: 20) {
                            Button(action: relearnCard) {
                                VStack {
                                    Image(systemName: "arrow.counterclockwise.circle.fill")
                                        .font(.system(size: 44))
                                    Text("Relearn")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(12)
                            }
                            
                            Button(action: learnedCard) {
                                VStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 44))
                                    Text("Learned")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        // Navigation Controls
                        HStack {
                            Button(action: prevCard) {
                                Image(systemName: "arrow.left.circle")
                                    .font(.system(size: 50))
                            }
                            .disabled(currentCardIndex == 0)
                            
                            Spacer()
                            
                            Button(action: nextCard) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 50))
                            }
                            .disabled(currentCardIndex >= deck.cards.count - 1)
                        }
                        .padding(.horizontal, 40)
                    }
                }
            } else {
                ProgressView("Loading Deck...")
            }
        }
    }
    
    var finishView: some View {
        VStack(spacing: 30) {
            Image(systemName: "medal.fill")
                .font(.system(size: 100))
                .foregroundColor(.yellow)
                .padding(.top, 40)
            
            Text("Sesión Terminada!")
                .font(.largeTitle.bold())
            
            VStack(spacing: 20) {
                StatRow(label: "Cards Learned", value: "\(learnedCount)", icon: "square.stack.3d.up.fill", color: .blue)
                StatRow(label: "Time Spent", value: formatTime(elapsedSeconds), icon: "clock.fill", color: .orange)
                StatRow(label: "Language", value: sessionLanguage.rawValue, icon: "globe", color: .green)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(20)
            .padding(.horizontal)
            
            Spacer()
            
            Button(action: { gameState = .configuration }) {
                Text("Start New Session")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(15)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Logic
    
    func setupConfiguration() {
        if let profile = userProfile {
            sessionLanguage = profile.currentLanguage
            sessionLevel = profile.currentLevel
            sessionCardGoal = profile.dailyCardGoal ?? 20
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
        
        withAnimation {
            gameState = .active
        }
        
        // Delay slightly to ensure view is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            playCurrentCardAudio()
        }
    }
    
    func playCurrentCardAudio() {
        guard gameState == .active, !isPaused, !isFlipped, let deck = deck, currentCardIndex < deck.cards.count else { return }
        let card = deck.cards[currentCardIndex]
        
        var sequence: [String] = []
        if let wordFile = card.audioWordFile { sequence.append(wordFile) }
        if let sentenceFile = card.audioSentenceFile { sequence.append(sentenceFile) }
        
        if !sequence.isEmpty {
            audioManager.playSequence(filenames: sequence, folderName: deck.baseFolderName)
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
        let activity = UserActivity(date: Date(), minutes: minutes, activityType: .appLearning, language: language, userID: authManager.currentUser)
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
    
    func resolveImage(_ filename: String?, folder: String?) -> Image? {
        guard let name = filename else { return nil }
        let fm = FileManager.default

        // 1. Try Local Resources Path (Developer/Mac Only)
        if let folder = folder {
            let localPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Data/\(folder)/\(name)"
            if let uiImage = UIImage(contentsOfFile: localPath) {
                return Image(uiImage: uiImage)
            }
        }
        
        // 2. Try Bundle with subdirectories
        let baseName = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.isEmpty ? nil : (name as NSString).pathExtension
        
        if let folder = folder {
            if let url = Bundle.main.url(forResource: baseName, withExtension: ext, subdirectory: "Data/\(folder)") ??
                        Bundle.main.url(forResource: baseName, withExtension: ext, subdirectory: "Resources/Data/\(folder)") {
                if let uiImage = UIImage(contentsOfFile: url.path) {
                    return Image(uiImage: uiImage)
                }
            }
        }
        
        // 3. Try Bundle standard locations
        if let url = Bundle.main.url(forResource: baseName, withExtension: ext) {
            if let uiImage = UIImage(contentsOfFile: url.path) {
                return Image(uiImage: uiImage)
            }
        }
        
        // 4. Robust recursive search in bundle
        let bundleURL = Bundle.main.bundleURL
        if let enumerator = fm.enumerator(at: bundleURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == name {
                    if let uiImage = UIImage(contentsOfFile: fileURL.path) {
                        return Image(uiImage: uiImage)
                    }
                }
            }
        }
        
        // System fallback if name looks like a system icon
        if name.contains("system:") {
            let systemName = name.replacingOccurrences(of: "system:", with: "")
            return Image(systemName: systemName)
        }
        
        return nil
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
