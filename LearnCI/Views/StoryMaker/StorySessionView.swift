import SwiftUI
import AVFoundation
import AVKit
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

    // Comprehension Quiz
    @State private var showQuizBanner: Bool = false
    @State private var showComprehensionQuiz: Bool = false
    @State private var isGeneratingQuiz: Bool = false
    @State private var quizQuestions: [ComprehensionQuestion] = []

    // Scene Video Generation
    @State private var showVideoGenerator: Bool = false
    @State private var isGeneratingVideo: Bool = false
    @State private var videoGenerationError: String? = nil
    @State private var videoStatusMessage: String? = nil
    private let veoService = VeoService()
    private let openAIService = OpenAIService()

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
                        // Hero Media (video if available, cover image otherwise)
                    HeroMediaView(
                        story: story,
                        image: $heroImage,
                        isGeneratingVideo: isGeneratingVideo,
                        videoStatus: videoStatusMessage,
                        videoError: videoGenerationError,
                        onGenerateVideo: { showVideoGenerator = true }
                    )
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
            
            // Quiz Completion Banner (sits above audio bar)
            VStack(spacing: 0) {
                Spacer()
                if showQuizBanner {
                    QuizBannerView(
                        onTakeQuiz: {
                            showQuizBanner = false
                            openQuiz()
                        },
                        onDismiss: { showQuizBanner = false }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

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
            .animation(.spring(duration: 0.4), value: showQuizBanner)
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

                    Button(action: openQuiz) {
                        Label("Comprehension Quiz", systemImage: "checkmark.circle")
                    }

                    if story.comprehensionQuestionsJSON != nil {
                        Button(action: regenerateQuiz) {
                            Label("Regenerate Quiz", systemImage: "arrow.clockwise")
                        }
                    }

                    Divider()

                    if story.remoteVideoPath == nil && !isGeneratingVideo {
                        Button(action: { showVideoGenerator = true }) {
                            Label("Generate Scene Video", systemImage: "video.badge.plus")
                        }
                    }

                    if story.remoteVideoPath != nil && !isGeneratingVideo {
                        Button(action: { showVideoGenerator = true }) {
                            Label("Regenerate Scene Video", systemImage: "arrow.clockwise.circle")
                        }
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
        .sheet(isPresented: $showComprehensionQuiz) {
            ComprehensionQuizSheet(
                questions: quizQuestions,
                isLoading: isGeneratingQuiz,
                language: story.language,
                onRetry: {
                    story.comprehensionQuestionsJSON = nil
                    quizQuestions = []
                    openQuiz()
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showVideoGenerator) {
            VideoGeneratorSheet(story: story) { style in
                Task { await generateSceneVideo(style: style) }
            }
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
                let justStopped = isPlaying
                isPlaying = false
                if justStopped && duration > 0 && sliderValue >= duration - 1.5 && !showQuizBanner {
                    showQuizBanner = true
                    preGenerateQuizIfNeeded()
                }
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

    // MARK: - Comprehension Quiz

    private func preGenerateQuizIfNeeded() {
        guard story.comprehensionQuestionsJSON == nil && !isGeneratingQuiz else { return }
        isGeneratingQuiz = true
        Task {
            let level = LevelManager.shared.description(for: story.level)
            let questions = try? await OpenAIService().generateComprehensionQuestions(
                storyText: story.targetLanguageText,
                language: story.language.displayName,
                level: level
            )
            await MainActor.run {
                if let qs = questions, let data = try? JSONEncoder().encode(qs) {
                    story.comprehensionQuestionsJSON = String(data: data, encoding: .utf8)
                    try? modelContext.save()
                    quizQuestions = qs
                }
                isGeneratingQuiz = false
            }
        }
    }

    private func openQuiz() {
        if !story.comprehensionQuestions.isEmpty {
            quizQuestions = story.comprehensionQuestions
            showComprehensionQuiz = true
        } else {
            isGeneratingQuiz = true
            showComprehensionQuiz = true
            Task {
                let level = LevelManager.shared.description(for: story.level)
                let questions = try? await OpenAIService().generateComprehensionQuestions(
                    storyText: story.targetLanguageText,
                    language: story.language.displayName,
                    level: level
                )
                await MainActor.run {
                    if let qs = questions, let data = try? JSONEncoder().encode(qs) {
                        story.comprehensionQuestionsJSON = String(data: data, encoding: .utf8)
                        try? modelContext.save()
                        quizQuestions = qs
                    }
                    isGeneratingQuiz = false
                }
            }
        }
    }

    private func regenerateQuiz() {
        story.comprehensionQuestionsJSON = nil
        quizQuestions = []
        try? modelContext.save()
        openQuiz()
    }

    // MARK: - Scene Video Generation

    @MainActor
    private func generateSceneVideo(style: VideoStyle) async {
        isGeneratingVideo = true
        videoGenerationError = nil
        videoStatusMessage = "Writing cinematic prompt…"

        do {
            // 1. Generate cinematic Veo prompt — model chosen in Profile → AI Settings
            let veoPrompt: String
            if VideoPromptModel.saved == .gemini {
                veoPrompt = try await veoService.generateVeoPrompt(
                    storyText: story.targetLanguageText,
                    style: style.promptStyle
                )
            } else {
                veoPrompt = try await openAIService.generateVeoPrompt(
                    storyText: story.targetLanguageText,
                    style: style.promptStyle
                )
            }

            // 2. Save prompt + style immediately so they sync even if video generation fails
            story.videoStyle = style.rawValue
            story.videoGenPrompt = veoPrompt
            try? modelContext.save()

            // 3. Call Veo API — polls until done (up to 6 mins)
            let videoData = try await veoService.generateVideo(prompt: veoPrompt) { status in
                Task { @MainActor in self.videoStatusMessage = status }
            }

            // 4. Save video file locally — SyncManager will upload on the next sync cycle
            //    and set story.remoteVideoPath once the upload succeeds.
            videoStatusMessage = "Saving video…"
            let filename = "video_\(story.id.uuidString).mp4"
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let localURL = docs.appendingPathComponent(filename)
            try videoData.write(to: localURL)

            try? modelContext.save()
            print("[VideoGen] Scene video saved locally, pending sync: \(localURL.lastPathComponent)")

        } catch {
            videoGenerationError = error.localizedDescription
            print("[VideoGen] Error: \(error.localizedDescription)")
        }

        videoStatusMessage = nil
        isGeneratingVideo = false
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

// MARK: - HeroMediaView
// Shows looping video if available, static cover image otherwise.
// Overlays a "Generate Video" button when neither exists yet.

struct HeroMediaView: View {
    let story: Story
    @Binding var image: UIImage?
    let isGeneratingVideo: Bool
    let videoStatus: String?
    let videoError: String?
    var onGenerateVideo: () -> Void

    @State private var localVideoURL: URL? = nil

    private let supabaseBase = "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories"

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY

            ZStack(alignment: .bottomTrailing) {
                // 1. Video layer (priority)
                if let videoURL = localVideoURL {
                    LoopingVideoPlayerView(url: videoURL)
                        .frame(width: geo.size.width, height: geo.size.height + (minY > 0 ? minY : 0))
                        .clipped()
                        .offset(y: minY > 0 ? -minY : 0)

                // 2. Static cover image fallback
                } else if let validImage = image {
                    Image(uiImage: validImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height + (minY > 0 ? minY : 0))
                        .clipped()
                        .offset(y: minY > 0 ? -minY : 0)

                // 3. Placeholder while loading
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(ProgressView())
                }

                // Gradient for text readability
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear, .black.opacity(0.15)],
                    startPoint: .bottom,
                    endPoint: .top
                )

                // Video generation overlay
                if isGeneratingVideo {
                    generatingOverlay
                        .padding(12)
                } else if let err = videoError {
                    errorBadge(err)
                        .padding(12)
                } else if localVideoURL == nil {
                    generateButton
                        .padding(12)
                }
            }
            .onAppear { loadMedia() }
            .onChange(of: isGeneratingVideo) { _, generating in
                // When generation finishes, the file now exists on disk — reload.
                if !generating { loadMedia() }
            }
        }
    }

    // MARK: Overlay badges

    private var generateButton: some View {
        Button(action: onGenerateVideo) {
            Label("Generate Video", systemImage: "video.badge.plus")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .foregroundStyle(.white)
    }

    private var generatingOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().tint(.white).scaleEffect(0.8)
                Text(videoStatus ?? "Starting…")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            Text("Keep the app open · up to 6 min")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func errorBadge(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Video failed")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .foregroundStyle(.white)
    }

    // MARK: Media loading

    private func loadMedia() {
        let filename = "video_\(story.id.uuidString).mp4"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localURL = docs.appendingPathComponent(filename)

        // 1. Local file exists — show it immediately (covers both: just-generated and previously downloaded)
        if FileManager.default.fileExists(atPath: localURL.path) {
            self.localVideoURL = localURL
            return
        }

        // 2. No local file but remote path exists — download and cache it
        if let remotePath = story.remoteVideoPath,
           let remoteURL = URL(string: "\(supabaseBase)/\(remotePath)") {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: remoteURL) {
                    try? data.write(to: localURL)
                    await MainActor.run { self.localVideoURL = localURL }
                }
            }
            return
        }

        // 3. No video at all — fall back to cover image
        loadCoverImage()
    }

    private func loadCoverImage() {
        if let remotePath = story.remoteCoverPath,
           let url = URL(string: "\(supabaseBase)/\(remotePath)") {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let uiImage = UIImage(data: data) {
                    DispatchQueue.main.async { self.image = uiImage }
                } else {
                    loadLocalCoverFallback()
                }
            }.resume()
        } else {
            loadLocalCoverFallback()
        }
    }

    private func loadLocalCoverFallback() {
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

// MARK: - Quiz Banner

struct QuizBannerView: View {
    let onTakeQuiz: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Story complete!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Test your comprehension")
                    .font(.subheadline.bold())
            }
            Spacer()
            Button(action: onTakeQuiz) {
                Text("Take Quiz →")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(radius: 4, y: -2)
    }
}

// MARK: - Comprehension Quiz Sheet

struct ComprehensionQuizSheet: View {
    let questions: [ComprehensionQuestion]
    let isLoading: Bool
    let language: Language
    var onRetry: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int = 0
    @State private var selectedAnswer: Int? = nil
    @State private var score: Int = 0
    @State private var isComplete: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && questions.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("Generating questions…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isComplete {
                    quizResultsView
                } else if !questions.isEmpty {
                    questionView
                } else {
                    // Generation failed or returned empty
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Couldn't load questions")
                            .font(.headline)
                        Text("Check your connection and try again.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { onRetry?() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Comprehension Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var questionView: some View {
        let question = questions[currentIndex]
        return VStack(alignment: .leading, spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(questions.count))
                        .animation(.easeInOut, value: currentIndex)
                }
            }
            .frame(height: 4)
            .padding(.horizontal)
            .padding(.bottom, 12)

            Text("Question \(currentIndex + 1) of \(questions.count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(question.question)
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .lineSpacing(6)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(question.choices.indices, id: \.self) { idx in
                            Button {
                                guard selectedAnswer == nil else { return }
                                selectedAnswer = idx
                                if idx == question.correctIndex { score += 1 }
                            } label: {
                                HStack {
                                    Text(["A", "B", "C", "D"][idx])
                                        .font(.caption.bold())
                                        .frame(width: 24, height: 24)
                                        .background(choiceBadgeColor(idx: idx, correctIndex: question.correctIndex))
                                        .clipShape(Circle())
                                        .foregroundColor(.white)
                                    Text(question.choices[idx])
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .padding()
                                .background(choiceBackground(idx: idx, correctIndex: question.correctIndex))
                                .cornerRadius(12)
                            }
                            .disabled(selectedAnswer != nil)
                        }
                    }
                    .padding(.horizontal)

                    if selectedAnswer != nil {
                        Button {
                            if currentIndex + 1 < questions.count {
                                currentIndex += 1
                                selectedAnswer = nil
                            } else {
                                isComplete = true
                            }
                        } label: {
                            Text(currentIndex + 1 < questions.count ? "Next →" : "See Results")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedAnswer)
                .padding(.bottom, 30)
            }
        }
        .padding(.top, 8)
    }

    private var quizResultsView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / CGFloat(questions.count))
                    .stroke(score >= (questions.count * 3 / 4) ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)
                    .animation(.easeOut(duration: 0.8), value: score)
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 40, weight: .bold))
                    Text("of \(questions.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            VStack(spacing: 8) {
                Text(score >= (questions.count * 3 / 4) ? "Great job!" : "Keep practicing!")
                    .font(.title2.bold())
                Text(score >= (questions.count * 3 / 4)
                    ? "You understood the story well."
                    : "Try re-reading the story and take the quiz again.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 20)
        }
    }

    private func choiceBackground(idx: Int, correctIndex: Int) -> Color {
        guard let selected = selectedAnswer else { return Color(.secondarySystemBackground) }
        if idx == correctIndex { return Color.green.opacity(0.15) }
        if idx == selected { return Color.red.opacity(0.15) }
        return Color(.secondarySystemBackground)
    }

    private func choiceBadgeColor(idx: Int, correctIndex: Int) -> Color {
        guard let selected = selectedAnswer else { return Color.secondary.opacity(0.4) }
        if idx == correctIndex { return Color.green }
        if idx == selected { return Color.red }
        return Color.secondary.opacity(0.3)
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



