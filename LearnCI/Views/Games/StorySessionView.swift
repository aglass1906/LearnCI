import SwiftUI
import AVFoundation
import Combine
import SwiftData
import MediaPlayer

struct StorySessionView: View {
    let story: Story
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Playback State
    @State private var isPlaying: Bool = false
    @State private var sliderValue: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1.0
    
    // UI State
    @State private var showPromptDetails = false
    @State private var selectedLanguage: DisplayLanguage = .target
    @State private var heroImage: UIImage? = nil
    
    // Analytics
    @State private var startTime: Date?
    @State private var didPlayAudio: Bool = false
    
    enum DisplayLanguage: String, CaseIterable {
        case target = "Target Language"
        case native = "English"
    }
    
    // Timer to update scrubber
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero Cover Art
                    HeroCoverView(story: story, image: $heroImage)
                        .frame(height: 300)
                        .clipped()
                    
                    VStack(alignment: .leading, spacing: 20) {
                        Text(story.title)
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .padding(.top, 20)
                        
                        // Metadata Row
                        HStack {
                            Label(story.language.displayName, systemImage: "globe")
                            Text("•")
                            Text(LevelManager.shared.description(for: story.level))
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        
                        Divider()
                        
                        // Language Toggle
                        if story.nativeLanguageText != nil {
                            Picker("Language", selection: $selectedLanguage) {
                                ForEach(DisplayLanguage.allCases, id: \.self) { lang in
                                    Text(lang.rawValue).tag(lang)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Story Text
                        if selectedLanguage == .target {
                            Text(story.targetLanguageText)
                                .font(.system(size: 18, weight: .regular, design: .serif)) // Better reading font
                                .lineSpacing(10)
                                .textSelection(.enabled)
                        } else if let native = story.nativeLanguageText {
                            Text(native)
                                .font(.system(size: 18, weight: .regular, design: .serif))
                                .lineSpacing(10)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        
                        // Spacer for sticky bar
                        Color.clear.frame(height: 180)
                    }
                    .padding()
                }
            }
            .ignoresSafeArea(edges: .top)
            
            // Sticky Audio Player
            if story.audioFilename != nil || story.remoteAudioPath != nil {
                AudioPlayerBar(
                    isPlaying: $isPlaying,
                    sliderValue: $sliderValue,
                    duration: duration,
                    playbackRate: $playbackRate,
                    onPlayPause: togglePlay,
                    onSkipForward: skipForward,
                    onSkipBackward: skipBackward,
                    onSeek: seekTo,
                    onChangeRate: setRate
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            startTime = Date()
            setupAudio()
        }
        .onDisappear {
            cleanupSession()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: {
                        UIPasteboard.general.string = story.targetLanguageText
                    }) {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    
                    Button(action: { showPromptDetails = true }) {
                        Label("Story Info", systemImage: "info.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showPromptDetails) {
            PromptDetailsSheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .onReceive(timer) { _ in
            guard let player = audioManager.player else { return }
            if player.isPlaying {
                sliderValue = player.currentTime
                isPlaying = true
                // Sync rate if changed externally (e.g. lock screen?)
                if abs(player.rate - playbackRate) > 0.1 {
                    playbackRate = player.rate
                }
            } else {
                isPlaying = false
            }
        }
        .onChange(of: heroImage) { _, newImage in
            if let img = newImage {
                audioManager.updateNowPlayingInfo(title: story.title, artist: "LearnCI Story", artworkImage: img)
            }
        }
    }
    
    // MARK: - Audio Logic
    
    private func setupAudio() {
        guard let filename = story.audioFilename else { return }
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try audioManager.playAudio(url: fileURL)
                audioManager.player?.enableRate = true
                audioManager.player?.rate = playbackRate
                duration = audioManager.player?.duration ?? 0
                
                // Set Initial Lock Screen Info
                audioManager.updateNowPlayingInfo(
                    title: story.title,
                    artist: "LearnCI Story",
                    artworkImage: heroImage
                )
                
            } catch {
                print("Audio setup failed: \(error)")
            }
        }
    }
    
    private func cleanupSession() {
        audioManager.stopAudio()
        
        // Analytics
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
        audioManager.updateNowPlayingInfo()
    }
    
    private func skipForward() {
        guard let player = audioManager.player else { return }
        let newTime = player.currentTime + 10
        player.currentTime = min(player.duration, newTime)
        sliderValue = player.currentTime
        audioManager.updateNowPlayingInfo()
    }
    
    private func skipBackward() {
        guard let player = audioManager.player else { return }
        let newTime = player.currentTime - 10
        player.currentTime = max(0, newTime)
        sliderValue = player.currentTime
        audioManager.updateNowPlayingInfo()
    }
    
    private func seekTo(_ value: Double) {
        guard let player = audioManager.player else { return }
        player.currentTime = value
        audioManager.updateNowPlayingInfo()
    }
    
    private func setRate(_ rate: Float) {
        playbackRate = rate
        if let player = audioManager.player {
            player.enableRate = true
            player.rate = rate
            if isPlaying {
                audioManager.updateNowPlayingInfo()
            }
        }
    }
}

// MARK: - Subviews

struct HeroCoverView: View {
    let story: Story
    @Binding var image: UIImage?
    
    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            
            ZStack {
                if let validImage = image {
                    Image(uiImage: validImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height + (minY > 0 ? minY : 0))
                        .clipped()
                        .offset(y: minY > 0 ? -minY : 0)
                        
                    // Gradient Overlay for text readability
                    LinearGradient(
                        colors: [.black.opacity(0.6), .clear, .black.opacity(0.2)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                } else {
                    // Placeholder / Loading
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(ProgressView())
                }
            }
            .onAppear { loadCover() }
        }
    }
    
    private func loadCover() {
        // 1. Try Remote
        if let remotePath = story.remoteCoverPath,
           let url = URL(string: "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories/\(remotePath)") {
            
            // Simple async load (in real app, use Kingfisher or nicer cache)
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let uiImage = UIImage(data: data) {
                    DispatchQueue.main.async { self.image = uiImage }
                } else {
                    loadLocalFallback()
                }
            }.resume()
        } else {
            loadLocalFallback()
        }
    }
    
    private func loadLocalFallback() {
        if let filename = story.coverArt {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
            if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
                self.image = uiImage
            }
        }
    }
}

struct AudioPlayerBar: View {
    @Binding var isPlaying: Bool
    @Binding var sliderValue: Double
    let duration: Double
    @Binding var playbackRate: Float
    
    var onPlayPause: () -> Void
    var onSkipForward: () -> Void
    var onSkipBackward: () -> Void
    var onSeek: (Double) -> Void
    var onChangeRate: (Float) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Scrubber
            HStack(spacing: 8) {
                Text(formatTime(sliderValue))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                
                Slider(value: Binding(
                    get: { sliderValue },
                    set: { newValue in
                        sliderValue = newValue
                        onSeek(newValue)
                    }
                ), in: 0...duration)
                
                Text(formatTime(duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Controls
            HStack(spacing: 30) {
                // Speed Button
                Menu {
                    Button("0.75x") { onChangeRate(0.75) }
                    Button("1.0x") { onChangeRate(1.0) }
                    Button("1.25x") { onChangeRate(1.25) }
                    Button("1.5x") { onChangeRate(1.5) }
                } label: {
                    Text("\(String(format: "%.1f", playbackRate))x")
                        .font(.caption.bold())
                        .frame(width: 40)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
                .foregroundColor(.primary)
                
                // Skip Back
                Button(action: onSkipBackward) {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }
                .foregroundColor(.primary)
                
                // Play/Pause
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .shadow(radius: 4)
                }
                .foregroundColor(.blue)
                
                // Skip Fwd
                Button(action: onSkipForward) {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
                .foregroundColor(.primary)
                
                // Spacer to balance layout with Speed button
                Color.clear.frame(width: 40)
            }
        }
        .padding(.vertical, 20)
        .background(.thinMaterial)
        .cornerRadius(24, corners: [.topLeft, .topRight])
        .shadow(radius: 10, y: -5)
        .fixedSize(horizontal: false, vertical: true) // Prevent vertical expansion
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// Helper for rounded corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
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



