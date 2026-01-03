import SwiftUI
import SwiftData
import Combine

struct GameView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    
    @State private var audioManager = AudioManager()
    
    @State private var currentCardIndex: Int = 0
    @State private var isFlipped: Bool = false
    
    // Tracking
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionStartTime: Date?
    @State private var elapsedSeconds: Int = 0
    static let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var userProfile: UserProfile? {
        profiles.first
    }
    
    var deck: CardDeck? {
        dataManager.loadedDeck
    }
    
    var body: some View {
        NavigationView {
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
                        
                        // Card View
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(isFlipped ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                                .shadow(radius: 5)
                            
                            VStack(spacing: 20) {
                                if !isFlipped {
                                    // Front: Target Content
                                    VStack(spacing: 15) {
                                        // Target Word
                                        HStack {
                                            Text(card.targetWord)
                                                .font(.system(size: 40, weight: .bold))
                                            
                                            Button(action: {
                                                if let file = card.audioWordFile {
                                                    audioManager.playAudio(named: file)
                                                } else {
                                                    print("No audio file for card")
                                                }
                                            }) {
                                                Image(systemName: "speaker.wave.2.fill")
                                                    .font(.title)
                                            }
                                        }
                                        
                                        Divider()
                                        
                                        // Target Sentence
                                        VStack {
                                            Text(card.sentenceTarget)
                                                .font(.headline)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal)
                                            
                                            Button(action: {
                                                 if let file = card.audioSentenceFile {
                                                    audioManager.playAudio(named: file)
                                                } else {
                                                    print("No audio file for sentence")
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
                                }
                            }
                            .padding()
                        }
                        .frame(height: 400)
                        .padding()
                        .onTapGesture {
                            withAnimation(.spring()) {
                                isFlipped.toggle()
                            }
                        }
                        
                        // Controls
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
                } else {
                    ProgressView("Loading Deck...")
                }
            }
            .navigationTitle(deck?.title ?? "Learning")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                     HStack {
                         Text(formatTime(elapsedSeconds))
                             .font(.system(.body, design: .monospaced))
                             .fixedSize()
                             .padding(6)
                             .frame(minWidth: 60)
                             .background(Color.blue.opacity(0.1))
                             .cornerRadius(8)
                             
                         Text(userProfile?.currentLevel.rawValue ?? "")
                            .font(.caption)
                            .padding(6)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                     }
                }
            }
            .onAppear {
                loadDeckIfNeeded()
                startSession()
            }
            .onDisappear {
                saveSession()
            }
            .onReceive(GameView.timer) { _ in
                if scenePhase == .active && sessionStartTime != nil {
                     elapsedSeconds += 1
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    startSession()
                } else if newPhase == .background || newPhase == .inactive {
                    saveSession()
                }
            }
            .onChange(of: userProfile?.currentLanguage) { _, _ in
                loadDeckIfNeeded()
                // If language changes, maybe save previous session? 
                // Simple version: just keep tracking as "App Learning" regardless of minute-by-minute language switch, 
                // but ideally we split. For now, keep simple.
            }
        }
    }
    
    func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let sec = seconds % 60
        return String(format: "%02d:%02d", minutes, sec)
    }
    
    func startSession() {
        if sessionStartTime == nil {
            sessionStartTime = Date()
            elapsedSeconds = 0
            print("Session started at \(Date())")
        }
    }
    
    func saveSession() {
        guard let start = sessionStartTime else { return }
        
        let duration = Date().timeIntervalSince(start)
        let minutes = Int(duration / 60)
        
        // Only save if at least 1 minute (or maybe accumulated seconds if we wanted to be precise, 
        // but model is Int minutes. Let's round or just take floor)
        if minutes >= 1 {
            print("Saving session: \(minutes) mins")
            let language = userProfile?.currentLanguage ?? .spanish
            let activity = UserActivity(date: Date(), minutes: minutes, activityType: .appLearning, language: language)
            modelContext.insert(activity)
            
            // "Consume" the time by resetting start to now (remainder seconds are lost in this simple logic, or we could keep them)
            // Simpler: Just consume.
            sessionStartTime = Date() 
        } else {
             // If less than a minute, we keep sessionStartTime (don't reset) 
             // so it accumulates until we hit a minute or leave?
             // Actually if we leave (onDisappear), we might lose the 30s. 
             // That's acceptable for "minutes" resolution.
             print("Session too short: \(Int(duration)) sec")
        }
        
        // If we are disappearing/backgrounding, we should nil out logic if we want to stop tracking completely?
        // But for `saveSession` called during background, we want to restart timing when we come back.
        // So we leave sessionStartTime as Date() so next check is relative to now? 
        // NO, if we go to background, time shouldn't count.
        // So:
        if scenePhase == .background || scenePhase == .inactive {
             sessionStartTime = nil
        }
    }
    func loadDeckIfNeeded() {
        guard let profile = userProfile else { return }
        dataManager.loadCards(language: profile.currentLanguage, level: profile.currentLevel)
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
}
