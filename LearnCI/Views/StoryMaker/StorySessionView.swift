import SwiftUI
import AVFoundation
import AVKit
import Combine
import SwiftData
import MediaPlayer

struct StorySessionView: View {
    let story: Story
    @Environment(AudioManager.self) private var audioManager
    @Environment(AmbientSoundManager.self) private var ambientSoundManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Playback State
    @State private var isPlaying: Bool = false
    @State private var sliderValue: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var ambientVolume: Float = 0.15
    @State private var isDownloadingAudio = false
    @State private var currentChapterIndex: Int = 0
    @State private var currentSceneClipIndex: Int = 0

    // UI State
    @State private var showStoryInfo = false
    @State private var selectedLanguage: DisplayLanguage = .target
    @State private var heroImage: UIImage? = nil
    
    // Auto-Scroll State
    @State private var activeWordIndex: Int? = nil
    @State private var activeParagraphId: Int? = nil
    
    // Analytics
    @State private var startTime: Date?
    @State private var didPlayAudio: Bool = false

    // Chapter Intro Card
    @State private var showingChapterCard: Bool = true

    // Comprehension Quiz
    @State private var navigateToQuiz: Bool = false
    @State private var isGeneratingQuiz: Bool = false
    @State private var quizQuestions: [ComprehensionQuestion] = []

    // Word Lookup (openAIService also used for word translation)
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
    
    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    private var storyBookSpineItems: [StoryReadingSpineItem] {
        adapter.items(for: .storyBook)
    }

    private var storyBookChapterItems: [StoryReadingSpineItem] {
        storyBookSpineItems.filter {
            if case .chapter = $0 { return true }
            return false
        }
    }

    private var storyBookReadingMatterItems: [StoryReadingSpineItem] {
        storyBookSpineItems.filter {
            if case .readingMatterPage = $0 { return true }
            return false
        }
    }

    var body: some View {
        Group {
            if let issue = adapter.requirementIssue(for: .storyBook) {
                StoryReaderUnavailableView(title: issue.title, message: issue.message)
            } else {
                readerBody
            }
        }
    }

    private var readerBody: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if storyBookSpineItems.contains(.cover) {
                            coverSection
                        }
                    
                    VStack(alignment: .leading, spacing: 20) {
                        Text(story.title)
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .padding(.top, 20)
                        
                        // Metadata Row
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                        readingMatterSection
                        
                        chapterHeaderView
                        
                        Divider()
                        
                        storyTextView
                        
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
            
            stickyPlayerView

            if showingChapterCard, let chapter = currentChapter {
                ChapterInfoCardView(
                    chapter: chapter,
                    heroImage: heroImage,
                    languageCode: story.languageRaw
                ) {
                    showingChapterCard = false
                    setupAudio(autoplay: true)
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Programmatic navigation to quiz on audio completion or overflow menu tap
        .navigationDestination(isPresented: $navigateToQuiz) {
            StoryQuizView(story: story, preloadedQuestions: quizQuestions.isEmpty ? nil : quizQuestions)
        }
        .onAppear {
            startTime = Date()
            ambientVolume = story.ambientVolume
            // When a chapter intro card will be shown, defer audio setup until Continue
            // is tapped so AVSpeechSynthesizer can use the audio session uninterrupted.
            if currentChapter == nil {
                setupAudio()
            }
            loadChapterImage()
        }
        .onDisappear {
            cleanupSession()
        }
        .onChange(of: currentChapterIndex) { _, _ in
            loadChapterImage()
        }
        .onChange(of: ambientVolume) { _, newValue in
            audioManager.setAmbientVolume(newValue)
            story.ambientVolume = newValue
            try? modelContext.save()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showStoryInfo = true }) {
                        Label("Story Info", systemImage: "info.circle")
                    }

                    Divider()

                    Button(action: openQuiz) {
                        Label("Comprehension Quiz", systemImage: "checkmark.circle")
                    }

                    Divider()

                    Button(action: {
                        if selectedLanguage == .target {
                            UIPasteboard.general.string = storyBookChapterItems.compactMap { adapter.chapter(for: $0)?.bodyTextTargetForReading }.joined(separator: "\n\n")
                        } else {
                            UIPasteboard.general.string = storyBookChapterItems.compactMap { adapter.chapter(for: $0)?.bodyTextEnglishForReading }.joined(separator: "\n\n")
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
            if audioManager.streamFinished {
                advanceAfterSceneClipFinished()
                return
            }

            if audioManager.streamPlayer != nil {
                let streamCurrent = audioManager.streamCurrentTime
                let streamDur = audioManager.streamDuration
                let localChapterTime = currentClipStartOffset + streamCurrent

                sliderValue = localChapterTime
                
                // Keep duration updated as AVPlayer loads the exact size asynchronously
                let resolvedDuration = adapter.duration(forChapter: currentChapterIndex, fallback: streamDur)
                if resolvedDuration > 0 && abs(duration - resolvedDuration) > 0.5 {
                    duration = resolvedDuration
                }
                
                isPlaying = audioManager.isStreaming
                
                // Update active word and paragraph
                updateScrollState(time: sliderValue)
                
                // Sync rate if changed externally (e.g. lock screen)
                if let streamPlayer = audioManager.streamPlayer {
                    if abs(streamPlayer.rate - playbackRate) > 0.1 && streamPlayer.rate != 0 {
                        playbackRate = streamPlayer.rate
                    }
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
    
    private func setupAudio(autoplay: Bool = false, sceneClipIndex: Int? = nil, startAt: Double = 0) {
        guard adapter.requirementIssue == nil else { return }
        let clips = currentChapterClips
        guard !clips.isEmpty else {
            print("[StorySession] No scene audio available for chapter \(currentChapterIndex)")
            return
        }

        currentSceneClipIndex = min(max(sceneClipIndex ?? currentSceneClipIndex, 0), clips.count - 1)
        let clip = clips[currentSceneClipIndex]
        let localURL = StoryReaderDataAdapter.localAudioURL(storyID: story.id, clip: clip)

        if FileManager.default.fileExists(atPath: localURL.path) {
            print("[StorySession] Playing scene audio: chapter \(clip.chapterIndex), scene \(clip.sceneIndex)")
            playLocalAudio(url: localURL, clip: clip, startAt: startAt, autoplay: autoplay)
            return
        }

        print("[StorySession] Downloading scene audio from remote: \(clip.urlString)")
        isDownloadingAudio = true
        Task { await downloadAndPlayAudio(clip: clip, localURL: localURL, startAt: startAt, autoplay: autoplay) }
    }

    /// Plays an already-local audio file using the AVPlayer stream interface.
    private func playLocalAudio(url: URL, clip: StorySceneAudioClip, startAt: Double = 0, autoplay: Bool = false) {
        audioManager.streamAudio(url: url, startAt: startAt)
        audioManager.setStreamRate(playbackRate)
        duration = adapter.duration(forChapter: currentChapterIndex, fallback: audioManager.streamDuration)
        sliderValue = clip.startOffset + startAt
        audioManager.updateStreamNowPlayingInfo(
            title: clip.title,
            artist: story.title,
            artworkImage: heroImage
        )
        if autoplay {
            startAmbient()
            audioManager.playStream()
            isPlaying = true
        }
    }

    /// Downloads audio from Supabase Storage, saves it locally with the correct extension, then plays it.
    /// - Parameters:
    ///   - remotePath: Path in Supabase Storage (or full https URL).
    ///   - localURL: Base destination URL (extension may be corrected after inspecting magic bytes).
    ///   - derivedFilename: If non-nil and `story.audioFilename` is nil, saves detected filename back
    ///     to `story.audioFilename` so future opens use the cached local file without re-downloading.
    private func downloadAndPlayAudio(clip: StorySceneAudioClip, localURL: URL, startAt: Double = 0, autoplay: Bool = false) async {
        guard let url = StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString) else {
            await MainActor.run { isDownloadingAudio = false }
            return
        }

        do {
            print("[StorySession] Downloading audio from \(url.absoluteString.prefix(80))…")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 else {
                print("[StorySession] Audio download failed — HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0), \(data.count) bytes")
                await MainActor.run { isDownloadingAudio = false }
                return
            }

            // Detect actual format by magic bytes — legacy uploads stored WAV content with .mp3 path.
            // AVAudioPlayer uses the file extension to choose its parser, so the extension MUST match.
            let isWAV = data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]) // "RIFF"
            let correctExt = isWAV ? "wav" : "mp3"
            let correctURL = localURL.deletingPathExtension().appendingPathExtension(correctExt)

            try data.write(to: correctURL)
            print("[StorySession] Audio downloaded (\(data.count / 1024)KB, format=\(correctExt)) — playing")

            await MainActor.run {
                isDownloadingAudio = false
                playLocalAudio(url: correctURL, clip: clip, startAt: startAt, autoplay: autoplay)
            }
        } catch {
            print("[StorySession] Audio download error: \(error)")
            await MainActor.run { isDownloadingAudio = false }
        }
    }

    private func startAmbient() {
        guard let soundId = story.ambientSoundId,
              soundId != "none",
              let sound = AmbientSound.catalog.first(where: { $0.id == soundId }) else { return }

        Task {
            do {
                let url = try await ambientSoundManager.ensureDownloaded(sound)
                await MainActor.run {
                    audioManager.playAmbient(url: url, volume: story.ambientVolume)
                }
            } catch {
                print("[StorySession] Ambient sound unavailable: \(error)")
            }
        }
    }
    
    private func cleanupSession() {
        audioManager.stopAmbient()
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

        if audioManager.streamPlayer == nil {
            setupAudio(autoplay: true)
            return
        }

        if audioManager.isStreaming {
            audioManager.pauseStream()
            isPlaying = false
            audioManager.pauseAmbient()
        } else {
            audioManager.playStream()
            isPlaying = true
            audioManager.resumeAmbient()
        }
        audioManager.updateStreamNowPlayingInfo()
    }
    
    private func skipForward() {
        let newTime = sliderValue + 10
        let maxDur = max(duration, 10.0)
        let safeTime = min(maxDur, newTime)
        seekTo(safeTime)
        audioManager.updateStreamNowPlayingInfo()
    }
    
    private func skipBackward() {
        let newTime = sliderValue - 10
        let safeTime = max(0, newTime)
        seekTo(safeTime)
        audioManager.updateStreamNowPlayingInfo()
    }
    
    private func seekTo(_ value: Double) {
        guard let target = adapter.clipIndex(forChapter: currentChapterIndex, localTime: value) else { return }
        if target.index == currentSceneClipIndex {
            audioManager.seekStream(to: target.offset)
            sliderValue = value
            updateScrollState(time: value)
        } else {
            let shouldResume = isPlaying
            setupAudio(autoplay: shouldResume, sceneClipIndex: target.index, startAt: target.offset)
        }
        audioManager.updateStreamNowPlayingInfo()
    }
    
    private func setRate(_ rate: Float) {
        playbackRate = rate
        audioManager.setStreamRate(rate)
        if isPlaying {
            audioManager.updateStreamNowPlayingInfo()
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
        let text = currentChapter?.bodyTextTargetForReading ?? ""
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
                storyText: storyBookChapterItems.compactMap { adapter.chapter(for: $0)?.bodyTextTargetForReading }.joined(separator: "\n\n"),
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
        // Load any pre-cached questions then navigate to the full-screen quiz
        if !story.comprehensionQuestions.isEmpty {
            quizQuestions = story.comprehensionQuestions
        }
        navigateToQuiz = true
    }

    private func regenerateQuiz() {
        story.comprehensionQuestionsJSON = nil
        quizQuestions = []
        try? modelContext.save()
        openQuiz()
    }

    // MARK: - Text Chunking & Auto-Scroll

    private var coverSection: some View {
        HeroMediaView(
            story: story,
            image: $heroImage,
            isGeneratingVideo: false,
            videoStatus: nil,
            videoError: nil,
            onGenerateVideo: {}
        )
        .frame(height: 300)
        .clipped()
    }
    
    @ViewBuilder
    private var readingMatterSection: some View {
        if !storyBookReadingMatterItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(storyBookReadingMatterItems) { item in
                    if let page = adapter.readingMatterPage(for: item) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let title = readerMatterText(page.titleTarget) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                        }
                        if let body = readerMatterText(page.bodyTarget) {
                            Text(body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func readerMatterText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    private var chapterHeaderView: some View {
        if !storyBookChapterItems.isEmpty {
            HStack {
                Text("Chapter \(currentChapterPosition + 1) of \(storyBookChapterItems.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                if let title = currentChapter?.titleTargetLanguage, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .italic()
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var storyTextView: some View {
        if let currentChapter, !currentChapter.bodyTextEnglishForReading.isEmpty {
            Picker("Language", selection: $selectedLanguage) {
                ForEach(DisplayLanguage.allCases, id: \.self) { lang in
                    Text(lang.rawValue).tag(lang)
                }
            }
            .pickerStyle(.segmented)
        }
        if selectedLanguage == .target {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(storyParagraphs) { chunk in
                    ParagraphView(
                        chunk: chunk,
                        activeWordIndex: activeWordIndex,
                        timings: currentChapter?.bodyWordTimingsForPlayback ?? [],
                        wordMatches: wordMatches,
                        onSeek: seekTo,
                        onWordTap: lookupWord
                    )
                    .id(chunk.id)
                }
            }
        } else if let currentChapter {
            let nativeText = currentChapter.bodyTextEnglishForReading
            VStack(alignment: .leading, spacing: 20) {
                Text(nativeText)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .lineSpacing(10)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var stickyPlayerView: some View {
        if isDownloadingAudio {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Downloading audio…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.blue)
            .cornerRadius(24, corners: [.topLeft, .topRight])
            .shadow(radius: 10, y: -5)
            .ignoresSafeArea(edges: .bottom)
        } else if !storyBookChapterItems.isEmpty {
            AudioPlayerBar(
                isPlaying: $isPlaying,
                sliderValue: $sliderValue,
                duration: duration,
                playbackRate: $playbackRate,
                ambientVolume: $ambientVolume,
                isAmbientPlaying: audioManager.isAmbientPlaying,
                onPlayPause: togglePlay,
                onSkipForward: skipForward,
                onSkipBackward: skipBackward,
                onSeek: seekTo,
                onChangeRate: setRate,
                onNextChapter: nextChapterIndex != nil ? {
                    if isPlaying { togglePlay() }
                    moveToChapter(nextChapterIndex)
                    activeWordIndex = nil
                    activeParagraphId = nil
                    sliderValue = 0
                    currentSceneClipIndex = 0
                    setupAudio()
                    showingChapterCard = true
                } : nil,
                onPreviousChapter: previousChapterIndex != nil ? {
                    if isPlaying { togglePlay() }
                    moveToChapter(previousChapterIndex)
                    activeWordIndex = nil
                    activeParagraphId = nil
                    sliderValue = 0
                    currentSceneClipIndex = 0
                    setupAudio()
                    showingChapterCard = true
                } : nil
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var currentChapter: StoryChapter? {
        guard let item = storyBookChapterItems.first(where: { chapterIndex(for: $0) == currentChapterIndex }) else { return nil }
        return adapter.chapter(for: item)
    }

    private var currentChapterPosition: Int {
        storyBookChapterItems.firstIndex { chapterIndex(for: $0) == currentChapterIndex } ?? 0
    }

    private var nextChapterIndex: Int? {
        chapterIndex(atChapterSpineOffset: 1)
    }

    private var previousChapterIndex: Int? {
        chapterIndex(atChapterSpineOffset: -1)
    }

    private func chapterIndex(for item: StoryReadingSpineItem) -> Int? {
        guard case .chapter(let index) = item else { return nil }
        return index
    }

    private func chapterIndex(atChapterSpineOffset offset: Int) -> Int? {
        let targetPosition = currentChapterPosition + offset
        guard storyBookChapterItems.indices.contains(targetPosition) else { return nil }
        return chapterIndex(for: storyBookChapterItems[targetPosition])
    }

    private func moveToChapter(_ chapterIndex: Int?) {
        guard let chapterIndex else { return }
        currentChapterIndex = chapterIndex
    }

    private var currentChapterClips: [StorySceneAudioClip] {
        adapter.audioClips(forChapter: currentChapterIndex)
    }

    private var currentClipStartOffset: Double {
        let clips = currentChapterClips
        guard clips.indices.contains(currentSceneClipIndex) else { return 0 }
        return clips[currentSceneClipIndex].startOffset
    }

    private func advanceAfterSceneClipFinished() {
        guard audioManager.streamFinished else { return }
        audioManager.streamFinished = false

        let clips = currentChapterClips
        if currentSceneClipIndex < clips.count - 1 {
            currentSceneClipIndex += 1
            setupAudio(autoplay: true)
            return
        }

        if let nextChapterIndex {
            currentChapterIndex = nextChapterIndex
            currentSceneClipIndex = 0
            activeWordIndex = nil
            activeParagraphId = nil
            sliderValue = 0
            showingChapterCard = true
            return
        }

        isPlaying = false
        if !navigateToQuiz {
            navigateToQuiz = true
        }
    }

    private func loadChapterImage() {
        guard let urlString = currentChapter?.coverUrl,
              let url = AppConfig.chapterCoverURL(urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let uiImage = UIImage(data: data) {
                DispatchQueue.main.async { heroImage = uiImage }
            }
        }.resume()
    }

    struct ParagraphChunk: Identifiable, Equatable {
        let id: Int
        let text: String
        let range: NSRange
    }
    
    private var storyParagraphs: [ParagraphChunk] {
        let text = currentChapter?.bodyTextTargetForReading ?? ""
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
        let text = currentChapter?.bodyTextTargetForReading ?? ""
        let nsString = text as NSString
        return regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
    }
    
    private func updateScrollState(time: Double) {
        let timings = currentChapter?.bodyWordTimingsForPlayback ?? []
        
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
    /// Set to false to hide the "Generate Video" overlay badge (e.g. when the action
    /// is surfaced via a menu instead). The generating progress overlay still shows.
    var showGenerateButton: Bool = true

    @State private var localVideoURL: URL? = nil

    private let supabaseBase = "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories"
    private let supabaseVideoBase = "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories"

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
                } else if localVideoURL == nil && showGenerateButton {
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
        let storyLabel = "\(story.title) (\(story.id.uuidString.prefix(8))…)"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Generated video: written by VeoService, uploaded by SyncManager
        let generatedURL = docs.appendingPathComponent("video_\(story.id.uuidString).mp4")
        // Remote cache: downloaded copy of the current remote version (always refreshed when remoteVideoPath changes)
        let remoteCacheURL = docs.appendingPathComponent("video_\(story.id.uuidString)_remote.mp4")

        let hasLocalGenerated = FileManager.default.fileExists(atPath: generatedURL.path)
        let remoteCacheSize   = (try? FileManager.default.attributesOfItem(atPath: remoteCacheURL.path)[.size] as? Int) ?? 0
        let hasValidRemoteCache = remoteCacheSize > 10_000  // treat < 10KB as a corrupt/empty download

        print("[HeroMedia] \(storyLabel)")
        print("[HeroMedia]   remoteVideoPath : \(story.remoteVideoPath ?? "nil")")
        print("[HeroMedia]   local generated : \(hasLocalGenerated ? "✅ exists" : "❌ none")")
        print("[HeroMedia]   remote cache    : \(remoteCacheSize > 0 ? "✅ \(remoteCacheSize / 1024)KB" : "❌ none") \(hasValidRemoteCache ? "" : remoteCacheSize > 0 ? "(⚠️ too small — discarding)" : "")")

        // Discard corrupt/empty remote cache so we re-download
        if remoteCacheSize > 0 && !hasValidRemoteCache {
            print("[HeroMedia]   ⚠️ Deleting corrupt remote cache and re-downloading…")
            try? FileManager.default.removeItem(at: remoteCacheURL)
        }

        // 1. Remote path is set → remote (DB) is the source of truth.
        //    Use the cached download if it exists; otherwise download fresh.
        if let remotePath = story.remoteVideoPath {
            if hasValidRemoteCache {
                print("[HeroMedia]   → showing remote cache (DB is source of truth)")
                self.localVideoURL = remoteCacheURL
                return
            }
            // Build the remote URL (handle legacy full URL or new relative path)
            let remoteURL: URL?
            if remotePath.hasPrefix("https://") {
                remoteURL = URL(string: remotePath)
            } else {
                remoteURL = URL(string: "\(supabaseVideoBase)/\(remotePath)")
            }
            if let url = remoteURL {
                // Show local generated file immediately as fallback while download is in flight
                if hasLocalGenerated {
                    print("[HeroMedia]   → showing local fallback while remote downloads…")
                    self.localVideoURL = generatedURL
                } else {
                    print("[HeroMedia]   → no local fallback, waiting for remote download…")
                }
                print("[HeroMedia]   → downloading: \(url.absoluteString.prefix(80))…")
                Task {
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        guard statusCode == 200 else {
                            print("[HeroMedia]   ❌ HTTP \(statusCode) — not a valid video response")
                            if !hasLocalGenerated { await MainActor.run { self.loadCoverImage() } }
                            return
                        }
                        guard data.count > 10_000 else {
                            print("[HeroMedia]   ❌ downloaded only \(data.count) bytes — not a valid video")
                            if !hasLocalGenerated { await MainActor.run { self.loadCoverImage() } }
                            return
                        }
                        try data.write(to: remoteCacheURL)
                        print("[HeroMedia]   ✅ remote download succeeded (\(data.count / 1024)KB) — switching to remote cache")
                        await MainActor.run { self.localVideoURL = remoteCacheURL }
                    } catch {
                        print("[HeroMedia]   ❌ download error: \(error.localizedDescription)")
                        if !hasLocalGenerated { await MainActor.run { self.loadCoverImage() } }
                    }
                }

                return
            }
        }

        // 2. No remote path yet — show the locally generated file while sync is pending
        if hasLocalGenerated {
            print("[HeroMedia]   → no remote path, showing local generated (pending sync)")
            self.localVideoURL = generatedURL
            return
        }

        // 3. No video at all — fall back to cover image
        print("[HeroMedia]   → no video, loading cover image")
        loadCoverImage()
    }

    /// Call this to force a fresh download of the remote video (e.g. after user uploads a new one).
    func invalidateRemoteVideoCache() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let remoteCacheURL = docs.appendingPathComponent("video_\(story.id.uuidString)_remote.mp4")
        try? FileManager.default.removeItem(at: remoteCacheURL)
        localVideoURL = nil
        loadMedia()
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
    @Binding var ambientVolume: Float
    let isAmbientPlaying: Bool

    var onPlayPause: () -> Void
    var onSkipForward: () -> Void
    var onSkipBackward: () -> Void
    var onSeek: (Double) -> Void
    var onChangeRate: (Float) -> Void
    
    var onNextChapter: (() -> Void)? = nil
    var onPreviousChapter: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            // Ambient volume row — only visible while ambient audio is active
            if isAmbientPlaying {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Slider(value: $ambientVolume, in: 0...1)
                        .tint(.secondary)
                    Image(systemName: "music.note.list")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }

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
            HStack(spacing: 20) {
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
                
                Spacer()

                // Previous Chapter
                if let onPrev = onPreviousChapter {
                    Button(action: onPrev) {
                        Image(systemName: "backward.end.fill")
                            .font(.title3)
                    }
                    .foregroundColor(.primary)
                }
                
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

                // Next Chapter
                if let onNext = onNextChapter {
                    Button(action: onNext) {
                        Image(systemName: "forward.end.fill")
                            .font(.title3)
                    }
                    .foregroundColor(.primary)
                }

                Spacer()
                
                // Placeholder to balance the speed button
                Color.clear.frame(width: 40)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background(
            Rectangle()
                .fill(.thinMaterial)
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(radius: 10, y: -5)
        .fixedSize(horizontal: false, vertical: true)
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
