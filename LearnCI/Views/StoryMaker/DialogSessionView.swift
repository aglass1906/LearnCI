import SwiftUI
import Combine

struct DialogSessionView: View {
    let story: Story
    
    @State private var currentChapterIndex: Int = 0
    @State private var segments: [StorySegmentTiming] = []
    
    // Playback state
    @State private var localTimeMs: Double = 0
    @State private var activeSegmentIndex: Int = 0
    @State private var isPlaying: Bool = false
    
    // Chapter Card State
    @State private var showingChapterCard: Bool = true
    
    // Timed Narration Hold variables
    @State private var holdGeneration: Int = 0
    @State private var isHoldInProgress: Bool = false
    
    var audioManager = AudioManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // 20Hz UI Update Timer
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            if showingChapterCard, let chapter = currentChapter {
                // Dimissible Chapter Card Overlay
                ChapterInfoCardView(
                    chapter: chapter,
                    heroImage: nil, // TODO: AsyncImage resolution from URL
                    languageCode: story.languageRaw
                ) {
                    // Start playback on continue
                    showingChapterCard = false
                    startAudioPlayback(for: chapter)
                }
                .transition(.opacity)
                .zIndex(10)
            }
            
            VStack {
                // Header (Navigation / Controls)
                HStack {
                    Button(action: {
                        stopAudio()
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .padding()
                    }
                    
                    Spacer()
                    
                    if let chapter = currentChapter {
                        Text(chapter.titleTargetLanguage)
                            .font(.headline)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        togglePlayback()
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)
                            .padding()
                    }
                }
                
                // Chapter Art Background (blurred)
                ZStack {
                    Rectangle()
                        .fill(Color(.systemGroupedBackground)) // Fallback
                    
                    // The dialog focused view
                    if activeSegmentIndex < segments.count {
                        let segment = segments[activeSegmentIndex]
                        
                        VStack(spacing: 24) {
                            // Speaker name (Phase 2 includes character portrait)
                            Text(segment.speaker)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .padding(.top, 40)
                            
                            // Dialogue chunk with word-level highlights
                            TimedTextView(segment: segment, currentTime: localTimeMs / 1000.0)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .transition(.slide) // Slide between speakers
                        .id(activeSegmentIndex) // Forces redraw on speaker change
                    } else if !segments.isEmpty {
                        Text("End of Chapter")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    } else if isDownloadingAudio {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading audio…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Loading Script...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding()
                
                // Line Navigation Segment
                HStack {
                    Button(action: skipToPreviousLine) {
                        Image(systemName: "backward.end.fill")
                            .padding()
                            .background(Circle().fill(Color.secondary.opacity(0.2)))
                    }
                    
                    Spacer()
                    
                    Button(action: skipToNextLine) {
                        Image(systemName: "forward.end.fill")
                            .padding()
                            .background(Circle().fill(Color.secondary.opacity(0.2)))
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            initializeChapter(at: 0)
        }
        .onDisappear {
            stopAudio()
            timer.upstream.connect().cancel()
        }
        .onReceive(timer) { _ in
            updateLocalTime()
        }
        .onChange(of: currentChapterIndex) { newIndex in
            initializeChapter(at: newIndex)
            showingChapterCard = true
        }
    }
    
    // MARK: - Logic & Properties
    
    private var currentChapter: StoryChapter? {
        let chapters = story.chapters
        guard currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }
    
    private func initializeChapter(at index: Int) {
        let chapters = story.chapters
        guard index < chapters.count else { return }
        let chapter = chapters[index]
        
        // Parse segments using ScriptParser
        let scriptText = chapter.scriptTargetLanguage ?? ""
        let isScriptEmpty = scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let script = isScriptEmpty ? (chapter.textTargetLanguage ?? "") : scriptText
        let timings = chapter.wordTimings ?? []
        self.segments = ScriptParser.parseSegments(scriptText: script, globalTimings: timings)
        
        print("Parsed \(self.segments.count) segments for chapter \(index).")
        
        self.localTimeMs = 0
        self.activeSegmentIndex = 0
        self.isPlaying = false
    }
    
    @State private var isDownloadingAudio: Bool = false

    private func startAudioPlayback(for chapter: StoryChapter) {
        let remotePath = chapter.audioUrl ?? ""
        guard !remotePath.isEmpty else {
            print("[DialogSession] No audio URL for chapter \(currentChapterIndex)")
            return
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ext = (remotePath as NSString).pathExtension
        let finalExt = ext.isEmpty ? "mp3" : ext
        let filename = "dialog_chapter_\(chapter.id.uuidString).\(finalExt)"
        let fileURL = docs.appendingPathComponent(filename)

        // Use cached local file if available
        if FileManager.default.fileExists(atPath: fileURL.path) {
            print("[DialogSession] Playing cached chapter audio: \(filename)")
            playLocalAudio(url: fileURL)
            return
        }

        // Download then play
        print("[DialogSession] Downloading chapter audio from: \(remotePath)")
        isDownloadingAudio = true
        Task { await downloadAndPlayAudio(remotePath: remotePath, localURL: fileURL) }
    }

    private func playLocalAudio(url: URL) {
        audioManager.streamAudio(url: url)
        bumpHoldGeneration()
        // 1.5-second pause after Continue before audio begins — gives the user a
        // moment to settle before the story dialogue starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.audioManager.playStream()
            self.isPlaying = true
        }
    }

    private func downloadAndPlayAudio(remotePath: String, localURL: URL) async {
        let supabaseAudioBase = "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories"
        let remoteURL: URL?
        if remotePath.hasPrefix("https://") {
            remoteURL = URL(string: remotePath)
        } else {
            remoteURL = URL(string: "\(supabaseAudioBase)/\(remotePath)")
        }

        guard let url = remoteURL else {
            await MainActor.run { isDownloadingAudio = false }
            return
        }

        do {
            print("[DialogSession] Downloading audio from \(url.absoluteString.prefix(80))…")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 else {
                print("[DialogSession] Audio download failed — HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0), \(data.count) bytes")
                await MainActor.run { isDownloadingAudio = false }
                return
            }

            // Detect actual format by magic bytes (WAV vs MP3)
            let isWAV = data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46])
            let correctExt = isWAV ? "wav" : "mp3"
            let correctURL = localURL.deletingPathExtension().appendingPathExtension(correctExt)
            try data.write(to: correctURL)
            print("[DialogSession] Downloaded (\(data.count / 1024)KB, \(correctExt)) — playing")

            await MainActor.run {
                isDownloadingAudio = false
                playLocalAudio(url: correctURL)
            }
        } catch {
            print("[DialogSession] Audio download error: \(error)")
            await MainActor.run { isDownloadingAudio = false }
        }
    }

    private func stopAudio() {
        bumpHoldGeneration()
        audioManager.stopAudio()
        self.isPlaying = false
    }
    
    private func togglePlayback() {
        bumpHoldGeneration()
        if isPlaying {
            audioManager.pauseStream()
            isPlaying = false
        } else {
            audioManager.playStream()
            isPlaying = true
        }
    }
    
    // MARK: - Wall Clock Tracking (Spec §6 & §7)
    
    private func updateLocalTime() {
        guard isPlaying, audioManager.isStreaming else { return }
        
        // Calculate new local time
        let rawCurrentSecs = audioManager.streamCurrentTime
        let newLocalMs = rawCurrentSecs * 1000.0
        
        // Active segment mapping (Spec §7)
        var newActiveIndex = segments.count - 1
        for (i, segment) in segments.enumerated() {
            let endMs = segment.endTime * 1000.0
            if newLocalMs < endMs {
                newActiveIndex = i
                break
            }
        }
        
        // Enforce Timed Narration Hold (Inter-character)
        if newActiveIndex > activeSegmentIndex {
            let prevSpeaker = segments[activeSegmentIndex].speaker
            let newSpeaker = segments[newActiveIndex].speaker
            
            if prevSpeaker != newSpeaker && !isHoldInProgress {
                print("Speaker changed. Triggering inter-character hold.")
                // Pass newActiveIndex so hold advances the segment upon completion,
                // preventing the same speaker-change from re-triggering the hold.
                triggerNarratorHold(duration: 0.450, advanceTo: newActiveIndex)
            }
        }
        
        // Check for end of chapter (when audio stops naturally)
        if newActiveIndex == segments.count - 1 && audioManager.streamDuration > 0 && 
            rawCurrentSecs >= audioManager.streamDuration - 0.5 {
            advanceToNextChapter()
        }
        
        // Update time and non-hold segment index
        self.localTimeMs = newLocalMs
        if !isHoldInProgress {
            self.activeSegmentIndex = newActiveIndex
        }
    }
    
    // MARK: - Navigation
    
    private func skipToNextLine() {
        guard activeSegmentIndex < segments.count - 1 else {
            advanceToNextChapter()
            return
        }
        
        bumpHoldGeneration()
        let targetIndex = activeSegmentIndex + 1
        let targetStartTime = max(0, segments[targetIndex].startTime - 0.05) // 50ms pre-roll
        
        audioManager.seekStream(to: targetStartTime)
        self.activeSegmentIndex = targetIndex
        self.localTimeMs = targetStartTime * 1000.0
    }
    
    private func skipToPreviousLine() {
        guard activeSegmentIndex > 0 else {
            audioManager.seekStream(to: 0)
            self.localTimeMs = 0
            return
        }
        
        bumpHoldGeneration()
        let targetIndex = activeSegmentIndex - 1
        let targetStartTime = max(0, segments[targetIndex].startTime - 0.05) // 50ms pre-roll
        
        audioManager.seekStream(to: targetStartTime)
        self.activeSegmentIndex = targetIndex
        self.localTimeMs = targetStartTime * 1000.0
    }
    
    private func advanceToNextChapter() {
        let chapters = story.chapters
        guard currentChapterIndex < chapters.count - 1 else { return }
        stopAudio()
        // Pause 2 seconds after the chapter ends before showing the next chapter card
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.currentChapterIndex += 1
        }
    }
    
    // MARK: - Timed Narration Holds (Spec §8.4)
    
    private func bumpHoldGeneration() {
        holdGeneration += 1
        isHoldInProgress = false
    }
    
    private func triggerNarratorHold(duration: TimeInterval, advanceTo targetIndex: Int) {
        let currentGeneration = holdGeneration
        isHoldInProgress = true
        audioManager.pauseStream()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard self.holdGeneration == currentGeneration else { return }
            // Advance the segment FIRST so the next timer tick won't re-detect
            // the same speaker change and trigger another hold.
            self.activeSegmentIndex = targetIndex
            self.isHoldInProgress = false
            if self.isPlaying {
                self.audioManager.playStream()
            }
        }
    }
}
