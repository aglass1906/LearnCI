import SwiftUI
import AVFoundation
import Combine
import SwiftData

struct StorySessionView: View {
    let story: Story
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var isPlaying: Bool = false
    @State private var startTime: Date?
    @State private var didPlayAudio: Bool = false
    @State private var sliderValue: Double = 0
    @State private var duration: Double = 0
    @State private var showPromptDetails = false
    @State private var playbackRate: Float = 1.0
    @State private var selectedLanguage: DisplayLanguage = .target
    
    enum DisplayLanguage: String, CaseIterable {
        case target = "Target Language"
        case native = "English"
    }
    
    // Timer to update scrubber
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Cover Art - Try remote first, then local
                    if let remotePath = story.remoteCoverPath {
                        // Load from Supabase Storage
                        let coverURL = URL(string: "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories/\(remotePath)")
                        AsyncImage(url: coverURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 300)
                                    .cornerRadius(12)
                                    .shadow(radius: 8)
                            case .failure(_):
                                // If remote fails, try local fallback
                                if let coverFilename = story.coverArt {
                                    let coverURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                        .appendingPathComponent(coverFilename)
                                    if FileManager.default.fileExists(atPath: coverURL.path),
                                       let uiImage = UIImage(contentsOfFile: coverURL.path) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: 300)
                                            .cornerRadius(12)
                                            .shadow(radius: 8)
                                    }
                                }
                            case .empty:
                                ZStack {
                                    Color.gray.opacity(0.2)
                                    ProgressView()
                                }
                                .frame(height: 300)
                                .cornerRadius(12)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else if let coverFilename = story.coverArt {
                        // Fallback to local file only
                        let coverURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent(coverFilename)
                        if FileManager.default.fileExists(atPath: coverURL.path),
                           let uiImage = UIImage(contentsOfFile: coverURL.path) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .cornerRadius(12)
                                .shadow(radius: 8)
                        }
                    }
                    
                    Text(story.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    // Language Toggle
                    if story.nativeLanguageText != nil {
                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(DisplayLanguage.allCases, id: \.self) { lang in
                                Text(lang.rawValue).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 8)
                    }
                    
                    // Story Text based on selection
                    if selectedLanguage == .target {
                        Text(story.targetLanguageText)
                            .font(.body)
                            .lineSpacing(8)
                    } else if let native = story.nativeLanguageText {
                        Text(native)
                            .font(.body)
                            .lineSpacing(8)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            
            // Audio Controls
            if let _ = story.audioFilename {
                HStack(spacing: 12) {
                    Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32)) // Smaller, more compact
                            .foregroundColor(.blue)
                    }
                    
                    Text(formatTime(sliderValue))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    
                    Slider(value: $sliderValue, in: 0...duration) { editing in
                        if editing {
                            audioManager.player?.pause()
                        } else {
                            if isPlaying {
                                audioManager.player?.currentTime = sliderValue
                                audioManager.player?.play()
                            } else {
                                audioManager.player?.currentTime = sliderValue
                            }
                        }
                    }
                    
                    Text(formatTime(duration))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(.regularMaterial)
                .cornerRadius(16)
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else if story.remoteAudioPath != nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Downloading Audio...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startTime = Date()
            setupAudio()
        }
        .onDisappear {
            audioManager.stopAudio()
            
            // Track Activity
            if let start = startTime {
                let end = Date()
                let interval = end.timeIntervalSince(start)
                let minutes = Int(interval / 60)
                
                if minutes > 0 {
                    let type: ActivityType = didPlayAudio ? .listening : .reading
                    let activity = UserActivity(
                        date: start,
                        minutes: minutes,
                        activityType: type,
                        language: story.language,
                        userID: story.userID.isEmpty ? nil : story.userID
                    )
                    modelContext.insert(activity)
                    try? modelContext.save()
                    print("Logged \(minutes) min of \(type.rawValue)")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("0.5x") { setRate(0.5) }
                    Button("0.75x") { setRate(0.75) }
                    Button("Default (1.0x)") { setRate(1.0) }
                    Button("1.25x") { setRate(1.25) }
                    Button("1.5x") { setRate(1.5) }
                } label: {
                    Label("Speed", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    UIPasteboard.general.string = story.targetLanguageText
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showPromptDetails = true }) {
                    Label("Info", systemImage: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showPromptDetails) {
            PromptDetailsSheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .onReceive(timer) { _ in
            if let player = audioManager.player, player.isPlaying {
                sliderValue = player.currentTime
                isPlaying = true // Sync state
            } else {
                isPlaying = false 
            }
        }
    }
    
    private func setupAudio() {
        guard let filename = story.audioFilename else { return }
        
        // We need to resolve the full path since FileManager stores it in Documents
        // AudioManager logic usually looks in Bundle, let's see if we can trick it 
        // or just extend it. For now, let's manually get the URL.
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                // Use AudioManager logic if possible, or direct AVAudioPlayer
                // Since AudioManager is designed for Bundle resources mostly,
                // let's manually play it here or add a method to AudioManager later.
                // Actually, let's try to just spin up a player here for simplicity, 
                // but better to use AudioManager for session handling.
                // Let's modify AudioManager later to accept direct URLs?
                // For now, let's just init a player here or use AudioManager's session config.
                
                try audioManager.playAudio(url: fileURL) // Assuming we add this extension or helper
                
                // Enable rate adjustment
                audioManager.player?.enableRate = true
                audioManager.player?.rate = playbackRate
                
                duration = audioManager.player?.duration ?? 0
            } catch {
                print("Audio setup failed: \(error)")
            }
        }
    }
    
    private func togglePlay() {
        didPlayAudio = true
        guard let player = audioManager.player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    private func setRate(_ rate: Float) {
        playbackRate = rate
        if let player = audioManager.player {
            player.enableRate = true
            player.rate = rate
            // If playing, it updates immediately. If paused, it will apply when played.
        }
    }
}

struct PromptDetailsSheet: View {
    let story: Story
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Story Prompt")
                        .font(.headline)
                    
                    Text(story.prompt ?? "No prompt stored for this story.")
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    
                    if let native = story.nativeLanguageText {
                        Text("Translation")
                            .font(.headline)
                        
                        Text(native)
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(8)
                    }
                    
                    Divider()
                    
                    Text("Metadata")
                        .font(.headline)
                    
                    Text("Language: \(story.language.displayName)\nLevel: \(story.level)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("Story Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}


