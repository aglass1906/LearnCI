import SwiftUI
import AVKit
import Combine
import Observation

struct InteractiveStorySessionView: View {
    let story: Story
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentChapterIndex = 0
    @State private var currentSegmentIndex = 0
    @State private var segments: [StorySegmentTiming] = []
    
    @State private var audioManager = AudioManager.shared
    @State private var isPlaying = false
    @State private var hasFinishedSegment = false
    @State private var chapterUIImage: UIImage? = nil
    
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    var currentChapter: StoryChapter {
        story.chapters[min(currentChapterIndex, story.chapters.count - 1)]
    }
    
    var currentSegment: StorySegmentTiming? {
        guard currentSegmentIndex < segments.count else { return nil }
        return segments[currentSegmentIndex]
    }
    
    var body: some View {
        ZStack {
            // Background (Scene Image)
            GeometryReader { geo in
                if let bgImage = chapterUIImage {
                    Image(uiImage: bgImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 5)
                        .overlay(Color.black.opacity(0.3))
                } else {
                    Color.black.edgesIgnoringSafeArea(.all)
                }
            }
            
            VStack {
                // Top Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    VStack {
                        Text(story.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Chapter \(currentChapterIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    // Settings or Info button
                    Button(action: { /* Show info */ }) {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding()
                
                Spacer()
                
                // Character Portrait & Dialog
                if let segment = currentSegment {
                    VStack {
                        Spacer()
                        
                        // Placeholder for character portrait
                        characterPortrait(for: segment.speaker)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                            .id("portrait_\(segment.speaker)")
                        
                        // Dialog Box
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(segment.speaker)
                                    .font(.headline.bold())
                                    .foregroundStyle(speakerColor(for: segment.speaker))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(speakerColor(for: segment.speaker).opacity(0.2))
                                    .cornerRadius(6)
                                Spacer()
                                
                                if hasFinishedSegment {
                                    Image(systemName: "chevron.right.circle.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                        .symbolEffect(.pulse)
                                }
                            }
                            
                            Text(segment.text)
                                .font(.system(size: 20, weight: .medium, design: .serif))
                                .foregroundStyle(.white)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 60)
                    }
                    .animation(.spring(duration: 0.4), value: segment.speaker)
                }
            }
            
            // Interaction Layer
            HStack(spacing: 0) {
                // Left 30%: Previous
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { navigateSegment(forward: false) }
                    .frame(width: 120)
                
                // Right 70%: Next
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { navigateSegment(forward: true) }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            setupChapter()
        }
        .onChange(of: currentChapterIndex) {
            setupChapter()
        }
        .onReceive(timer) { _ in
            checkAutoPause()
        }
        .onDisappear {
            audioManager.stopAudio()
            isPlaying = false
        }
    }
    
    private func speakerColor(for speaker: String) -> Color {
        let name = speaker.uppercased()
        if name == "NARRATOR" { return .gray }
        let hash = name.hashValue
        let colors: [Color] = [.purple, .blue, .orange, .pink, .teal, .indigo, .mint]
        return colors[abs(hash) % colors.count]
    }
    
    private func setupChapter() {
        // 1. Parse Script into character segments
        // Prioritize the speaker-tagged script if available
        let script = currentChapter.scriptTargetLanguage ?? currentChapter.bodyScriptOrNarrativeForAlignment
        let timings = currentChapter.bodyWordTimingsForPlayback

        segments = ScriptParser.parseSegments(scriptText: script, globalTimings: timings)
        currentSegmentIndex = 0
        hasFinishedSegment = false

        // Load chapter cover image
        if let urlString = currentChapter.coverUrl,
           let url = AppConfig.chapterCoverURL(urlString) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let uiImage = UIImage(data: data) {
                    DispatchQueue.main.async { chapterUIImage = uiImage }
                }
            }.resume()
        }
        
        // 2. Load Audio but don't play yet if it's the start
        if let url = audioURL {
            try? audioManager.playAudio(url: url)
            // Play first segment immediately
            playCurrentSegment()
        }
    }
    
    private func playCurrentSegment() {
        guard let segment = currentSegment else { return }
        hasFinishedSegment = false
        
        // Seek to start
        audioManager.seek(to: segment.startTime)
        audioManager.player?.play()
        isPlaying = true
    }
    
    private func checkAutoPause() {
        guard isPlaying, let segment = currentSegment, let currentTime = audioManager.currentTime else { return }
        
        // If we reach the end of the character's line, pause and wait for tap
        if currentTime >= segment.endTime {
            audioManager.player?.pause()
            isPlaying = false
            hasFinishedSegment = true
        }
    }
    
    private func navigateSegment(forward: Bool) {
        if forward {
            if currentSegmentIndex + 1 < segments.count {
                withAnimation {
                    currentSegmentIndex += 1
                }
                playCurrentSegment()
            } else {
                // Next chapter
                if currentChapterIndex + 1 < story.chapters.count {
                    withAnimation {
                        currentChapterIndex += 1
                    }
                } else {
                    dismiss()
                }
            }
        } else {
            // If we are halfway through a line, restart the line
            if let time = audioManager.currentTime, let segment = currentSegment, time > segment.startTime + 1.0 {
                playCurrentSegment()
            } else if currentSegmentIndex > 0 {
                withAnimation {
                    currentSegmentIndex -= 1
                }
                playCurrentSegment()
            } else {
                // Restart chapter
                playCurrentSegment()
            }
        }
    }
    
    @ViewBuilder
    private func characterPortrait(for speaker: String) -> some View {
        // In a real implementation, we'd check a StoryBible or Assets
        // For now, let's look for an image named like the speaker
        if let image = UIImage(named: speaker.lowercased()) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 400)
        } else {
            // generic placeholder
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .foregroundStyle(.gray.opacity(0.5))
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .padding(.bottom, 20)
        }
    }
    
    private var audioURL: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 1. Try resolving chapter-specific audio downloaded by SyncManager
        let chapterID = currentChapter.id.uuidString
        let storyID = story.id.uuidString
        
        // Check for .mp3 first, then .wav
        let mp3Filename = "story_\(storyID)_chapter_\(chapterID).mp3"
        let mp3URL = docs.appendingPathComponent(mp3Filename)
        if FileManager.default.fileExists(atPath: mp3URL.path) {
            return mp3URL
        }
        
        let wavFilename = "story_\(storyID)_chapter_\(chapterID).wav"
        let wavURL = docs.appendingPathComponent(wavFilename)
        if FileManager.default.fileExists(atPath: wavURL.path) {
            return wavURL
        }
        
        // 2. Fall back to the chapter's raw audioUrl if it's an absolute file path or filename
        if let chapterAudio = currentChapter.audioUrl, !chapterAudio.isEmpty {
            if chapterAudio.hasPrefix("http") {
                return URL(string: chapterAudio)
            }
            let url = docs.appendingPathComponent(chapterAudio)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        // 3. Last fallback: main story audio
        if let mainAudio = story.audioFilename {
            let url = docs.appendingPathComponent(mainAudio)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        return nil
    }
}
