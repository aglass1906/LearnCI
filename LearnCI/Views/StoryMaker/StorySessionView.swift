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
    @State private var showStoryInfo = false
    @State private var showPromptDetails = false
    @State private var selectedLanguage: DisplayLanguage = .target
    @State private var heroImage: UIImage? = nil
    
    // Auto-Scroll State
    @State private var activeWordIndex: Int? = nil
    @State private var activeParagraphId: Int? = nil
    
    // Analytics
    @State private var startTime: Date?
    @State private var didPlayAudio: Bool = false

    // Word Lookup
    @State private var selectedWord: String? = nil
    @State private var selectedWordTime: Double? = nil
    @State private var wordTranslation: String? = nil
    @State private var wordPartOfSpeech: String? = nil
    @State private var isTranslatingWord: Bool = false
    @State private var showWordLookup: Bool = false
    @State private var wordTranslationCache: [String: (translation: String, pos: String)] = [:]
    
    enum DisplayLanguage: String, CaseIterable {
        case target = "Target Language"
        case native = "English"
    }
    
    // Timer to update scrubber
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
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
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(storyParagraphs) { chunk in
                                    ParagraphView(
                                        chunk: chunk,
                                        activeWordIndex: activeWordIndex,
                                        timings: story.wordTimings,
                                        wordMatches: wordMatches,
                                        onSeek: seekTo,
                                        onWordTap: lookupWord
                                    )
                                    .id(chunk.id)
                                }
                            }
                        } else if let native = story.nativeLanguageText {
                            VStack(alignment: .leading, spacing: 20) {
                                // Just simple padding for native text
                                Text(native)
                                    .font(.system(size: 18, weight: .regular, design: .serif))
                                    .lineSpacing(10)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        
                        // Spacer for sticky bar
                        Color.clear.frame(height: 180)
                            .id("BottomSpacer")
                    }
                    .padding()
                }
                .onChange(of: activeParagraphId) { _, newId in
                    if let id = newId {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            // Use .center to perfectly frame the paragraph above the play bar
                            scrollProxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.35)) 
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            } // Close ScrollViewReader
            
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
                    Button(action: { showStoryInfo = true }) {
                        Label("Story Info", systemImage: "info.circle")
                    }

                    Button(action: { showPromptDetails = true }) {
                        Label("View Prompts", systemImage: "text.viewfinder")
                    }

                    Divider()

                    Button(action: {
                        if selectedLanguage == .target {
                            UIPasteboard.general.string = story.targetLanguageText
                        } else {
                            UIPasteboard.general.string = story.nativeLanguageText ?? story.targetLanguageText
                        }
                    }) {
                        Label(
                            selectedLanguage == .target ? "Copy Story (\(story.language.displayName))" : "Copy Story (English)",
                            systemImage: "doc.on.doc"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showStoryInfo) {
            StoryInfoSheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPromptDetails) {
            StoryPromptsSheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showWordLookup) {
            WordLookupSheet(
                word: selectedWord ?? "",
                language: story.language,
                translation: wordTranslation,
                partOfSpeech: wordPartOfSpeech,
                isLoading: isTranslatingWord,
                seekTime: selectedWordTime,
                onSeek: { time in
                    seekTo(time)
                }
            )
            .presentationDetents([.fraction(0.4)])
            .presentationDragIndicator(.visible)
        }
        .onReceive(timer) { _ in
            guard let player = audioManager.player else { return }
            if player.isPlaying {
                sliderValue = player.currentTime
                isPlaying = true
                
                // Update active word and paragraph
                updateScrollState(time: sliderValue)
                
                // Sync rate if changed externally (e.g. lock screen)
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
        sliderValue = value
        updateScrollState(time: value)
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
    
    // MARK: - Word Lookup

    private func lookupWord(_ word: String, time: Double) {
        selectedWord = word
        selectedWordTime = time
        wordTranslation = nil
        wordPartOfSpeech = nil
        showWordLookup = true

        let cacheKey = "\(word.lowercased())_\(story.language.rawValue)"
        if let cached = wordTranslationCache[cacheKey] {
            wordTranslation = cached.translation
            wordPartOfSpeech = cached.pos
            return
        }

        isTranslatingWord = true
        let context = sentenceContaining(word: word)
        Task {
            do {
                let result = try await OpenAIService().translateWord(word, language: story.language.displayName, context: context)
                await MainActor.run {
                    wordTranslation = result.translation
                    wordPartOfSpeech = result.partOfSpeech
                    wordTranslationCache[cacheKey] = (result.translation, result.partOfSpeech)
                    isTranslatingWord = false
                }
            } catch {
                await MainActor.run {
                    wordTranslation = "Translation unavailable"
                    wordPartOfSpeech = ""
                    isTranslatingWord = false
                }
            }
        }
    }

    private func sentenceContaining(word: String) -> String? {
        let text = story.targetLanguageText
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
        return sentences.first(where: { $0.localizedCaseInsensitiveContains(word) })?.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Text Chunking & Auto-Scroll
    
    struct ParagraphChunk: Identifiable, Equatable {
        let id: Int
        let text: String
        let range: NSRange
    }
    
    private var storyParagraphs: [ParagraphChunk] {
        let text = story.targetLanguageText
        var chunks: [ParagraphChunk] = []
        var currentOffset = 0
        
        let components = text.components(separatedBy: "\n")
        var id = 0
        for comp in components {
            let pLength = (comp as NSString).length
            let range = NSRange(location: currentOffset, length: pLength)
            if !comp.trimmingCharacters(in: .whitespaces).isEmpty {
                chunks.append(ParagraphChunk(id: id, text: comp, range: range))
                id += 1
            }
            currentOffset += pLength + 1 // +1 for the \n
        }
        return chunks
    }
    
    private var wordMatches: [NSTextCheckingResult] {
        let regex = try? NSRegularExpression(pattern: "\\p{L}+", options: [])
        let nsString = story.targetLanguageText as NSString
        return regex?.matches(in: story.targetLanguageText, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
    }
    
    private func updateScrollState(time: Double) {
        let timings = story.wordTimings
        
        if let idx = timings.firstIndex(where: { time >= $0.start && time <= $0.end }) {
            if activeWordIndex != idx {
                activeWordIndex = idx
                
                // Determine which paragraph contains this word
                let matches = wordMatches
                if idx < matches.count {
                    let activeMatch = matches[idx]
                    // Find paragraph containing this match's range
                    if let pId = storyParagraphs.first(where: { NSLocationInRange(activeMatch.range.location, $0.range) })?.id {
                        if pId != activeParagraphId {
                            activeParagraphId = pId
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Paragraph Subview
struct ParagraphView: View {
    let chunk: StorySessionView.ParagraphChunk
    let activeWordIndex: Int?
    let timings: [WordTiming]
    let wordMatches: [NSTextCheckingResult]
    let onSeek: (Double) -> Void
    let onWordTap: (String, Double) -> Void

    var body: some View {
        Text(attributedParagraph)
            .font(.system(size: 18, weight: .regular, design: .serif))
            .lineSpacing(10)
            .tint(.primary)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "x-learnci-word",
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let word = components.queryItems?.first(where: { $0.name == "word" })?.value,
                   let tStr = components.queryItems?.first(where: { $0.name == "t" })?.value,
                   let targetTime = Double(tStr) {
                    onWordTap(word, targetTime)
                    return .handled
                }
                if url.scheme == "x-learnci-seek",
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let tStr = components.queryItems?.first(where: { $0.name == "t" })?.value,
                   let targetTime = Double(tStr) {
                    onSeek(targetTime)
                    return .handled
                }
                return .systemAction
            })
    }

    private var attributedParagraph: AttributedString {
        var attrString = AttributedString(chunk.text)

        if timings.isEmpty || chunk.text.isEmpty {
            return attrString
        }

        for (i, match) in wordMatches.enumerated() {
            guard i < timings.count else { break }
            let timing = timings[i]

            // Focus only on matches inside this chunk
            if NSLocationInRange(match.range.location, chunk.range) {
                let localRange = NSRange(location: match.range.location - chunk.range.location, length: match.range.length)

                if let swiftRange = Range(localRange, in: chunk.text),
                   let lowerBound = AttributedString.Index(swiftRange.lowerBound, within: attrString),
                   let upperBound = AttributedString.Index(swiftRange.upperBound, within: attrString) {

                    let attrRange = lowerBound..<upperBound

                    // Word lookup link (includes word text + timestamp)
                    let encoded = timing.word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? timing.word
                    attrString[attrRange].link = URL(string: "x-learnci-word://?word=\(encoded)&t=\(timing.start)")

                    // Highlight active
                    if i == activeWordIndex {
                        attrString[attrRange].foregroundColor = .blue
                        attrString[attrRange].font = .system(size: 19, weight: .bold, design: .serif)
                    }
                }
            }
        }
        return attrString
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

// MARK: - Story Info Sheet

struct StoryInfoSheet: View {
    let story: Story
    @Environment(\.dismiss) private var dismiss

    private var preferences: StoryPreferences {
        guard let json = story.preferencesJSON, let data = json.data(using: .utf8) else {
            return StoryPreferences()
        }
        return (try? JSONDecoder().decode(StoryPreferences.self, from: data)) ?? StoryPreferences()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    infoRow(label: "Title", value: story.title)

                    // Language & Level
                    infoRow(label: "Language", value: story.language.displayName)
                    infoRow(label: "Level", value: "\(story.level) - \(LevelManager.shared.description(for: story.level))")

                    // Topic
                    if let prompt = story.prompt, !prompt.isEmpty {
                        infoRow(label: "Topic", value: prompt)
                    }

                    Divider()

                    // Preferences
                    Text("Story Settings")
                        .font(.headline)

                    let prefs = preferences
                    infoRow(label: "Genre", value: prefs.genre.rawValue)
                    infoRow(label: "Length", value: prefs.storyLength.rawValue)
                    infoRow(label: "Ending", value: prefs.endingType.rawValue)
                    infoRow(label: "Dialogue", value: prefs.dialogueAmount.rawValue)
                    infoRow(label: "Voice", value: prefs.voice.displayName)
                    infoRow(label: "Cover Style", value: prefs.coverArtStyle.rawValue)

                    if !prefs.protagonistName.isEmpty {
                        infoRow(label: "Protagonist", value: "\(prefs.protagonistName) (\(prefs.protagonistGender.rawValue))")
                    }

                    // Keywords / Vocabulary
                    if !prefs.targetVocabulary.isEmpty {
                        infoRow(label: "Target Vocabulary", value: prefs.targetVocabulary)
                    }

                    if !prefs.grammarFocus.isEmpty {
                        infoRow(label: "Grammar Focus", value: prefs.grammarFocus)
                    }

                    Divider()

                    // Date
                    infoRow(label: "Created", value: story.createdAt.formatted(date: .long, time: .shortened))
                }
                .padding()
            }
            .navigationTitle("Story Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Word Lookup Sheet

struct WordLookupSheet: View {
    let word: String
    let language: Language
    let translation: String?
    let partOfSpeech: String?
    let isLoading: Bool
    let seekTime: Double?
    let onSeek: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    // Word + language badge
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(word)
                            .font(.system(size: 32, weight: .bold, design: .serif))
                        Text(language.displayName)
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    // Part of speech
                    if let pos = partOfSpeech, !pos.isEmpty {
                        Text(pos)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()
                    .padding(.vertical, 16)

                // Translation
                Group {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Translating…")
                                .foregroundColor(.secondary)
                        }
                    } else if let t = translation {
                        Text(t)
                            .font(.system(size: 22, weight: .regular))
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Seek button
                if let time = seekTime {
                    Button {
                        onSeek(time)
                        dismiss()
                    } label: {
                        Label("Jump to this word in audio", systemImage: "arrow.right.circle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Word Lookup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Story Prompts Sheet

struct StoryPromptsSheet: View {
    let story: Story
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var localTextPrompt: String?
    @State private var localImagePrompt: String?
    @State private var isRecreating: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    promptSection(title: "User Topic", content: story.prompt ?? "N/A")

                    Divider()

                    promptSection(
                        title: "Text Generation Prompt",
                        content: localTextPrompt ?? story.textGenPrompt ?? "Not saved."
                    )

                    promptSection(
                        title: "Image Generation Prompt",
                        content: localImagePrompt ?? story.imageGenPrompt ?? "Not saved."
                    )

                    Button(action: recreatePrompts) {
                        HStack {
                            if isRecreating {
                                ProgressView()
                                    .padding(.trailing, 5)
                            }
                            Text("Recreate Prompts from Preferences")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                    .disabled(isRecreating)
                }
                .padding()
            }
            .navigationTitle("AI Prompts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func promptSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = content
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            Text(content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .textSelection(.enabled)
        }
    }

    private func recreatePrompts() {
        isRecreating = true
        Task {
            let decoder = JSONDecoder()
            let prefs: StoryPreferences
            if let json = story.preferencesJSON, let data = json.data(using: .utf8) {
                prefs = (try? decoder.decode(StoryPreferences.self, from: data)) ?? StoryPreferences()
            } else {
                prefs = StoryPreferences()
            }

            let service = OpenAIService()

            let textPrompt = await service.constructStoryPrompt(
                topic: story.prompt ?? "",
                language: story.language.displayName,
                level: LevelManager.shared.description(for: story.level),
                preferences: prefs
            )

            let imagePrompt = service.constructCoverArtPrompt(
                title: story.title,
                topic: story.prompt ?? "",
                style: prefs.coverArtStyle
            )

            await MainActor.run {
                self.localTextPrompt = textPrompt
                self.localImagePrompt = imagePrompt

                if story.textGenPrompt == nil { story.textGenPrompt = textPrompt }
                if story.imageGenPrompt == nil { story.imageGenPrompt = imagePrompt }
                try? modelContext.save()

                isRecreating = false
            }
        }
    }
}



