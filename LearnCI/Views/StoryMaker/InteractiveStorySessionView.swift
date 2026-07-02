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
    @State private var segmentClips: [StorySceneAudioClip?] = []
    @State private var activeClipID: String?
    
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

    private var currentSegmentClip: StorySceneAudioClip? {
        guard segmentClips.indices.contains(currentSegmentIndex) else { return nil }
        return segmentClips[currentSegmentIndex]
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
        .mediaPlaybackLifecycle(
            onUserLeave: {
                audioManager.stopStream()
                isPlaying = false
            },
            onEnterBackground: { audioManager.updateStreamNowPlayingInfo() }
        )
    }
    
    private func speakerColor(for speaker: String) -> Color {
        let name = speaker.uppercased()
        if name == "NARRATOR" { return .gray }
        let hash = name.hashValue
        let colors: [Color] = [.purple, .blue, .orange, .pink, .teal, .indigo, .mint]
        return colors[abs(hash) % colors.count]
    }
    
    private func setupChapter() {
        let adapter = StoryReaderDataAdapter(story: story)
        let clipsByScene = Dictionary(
            uniqueKeysWithValues: adapter.audioClips(forChapter: currentChapterIndex).map { ($0.sceneIndex, $0) }
        )
        let sceneSegmentsAndClips = currentChapter.scenes
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .flatMap { scene -> [(StorySegmentTiming, StorySceneAudioClip?)] in
                let clip = clipsByScene[scene.sceneIndex]
                let text = scene.scriptFor(story.targetLanguageCode)
                    ?? scene.captionFor(story.targetLanguageCode)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return [] }

                let timings = scene.wordTimingsFor(story.targetLanguageCode)
                let parsed = ScriptParser.parseSegments(scriptText: trimmed, globalTimings: timings)
                if !parsed.isEmpty {
                    return parsed.map { ($0, clip) }
                }

                let fallback = StorySegmentTiming(
                    speaker: "NARRATOR",
                    text: trimmed,
                    startTime: timings.first?.start ?? 0,
                    endTime: timings.last?.end ?? 0,
                    timings: timings
                )
                return [(fallback, clip)]
            }

        segments = sceneSegmentsAndClips.map(\.0)
        segmentClips = sceneSegmentsAndClips.map(\.1)
        currentSegmentIndex = 0
        hasFinishedSegment = false
        activeClipID = nil

        // Load chapter cover image
        if let urlString = currentChapter.coverUrl,
           let url = AppConfig.chapterCoverURL(urlString) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let uiImage = UIImage(data: data) {
                    DispatchQueue.main.async { chapterUIImage = uiImage }
                }
            }.resume()
        }
        
        playCurrentSegment()
    }
    
    private func playCurrentSegment() {
        guard let segment = currentSegment else { return }
        hasFinishedSegment = false

        guard let clip = currentSegmentClip else {
            isPlaying = false
            return
        }

        if activeClipID == clip.id, audioManager.streamPlayer != nil {
            audioManager.seekStream(to: segment.startTime)
            audioManager.playStream()
            isPlaying = true
            return
        }

        activeClipID = clip.id
        isPlaying = true
        Task {
            let playbackURL = await StoryReaderDataAdapter.downloadAndCacheAudioIfNeeded(
                storyID: story.id,
                clip: clip,
                storyUpdatedAt: story.updatedAt
            ) ?? StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString)

            await MainActor.run {
                guard activeClipID == clip.id,
                      let playbackURL else {
                    isPlaying = false
                    return
                }
                audioManager.streamAudio(url: playbackURL, startAt: segment.startTime)
                audioManager.playStream()
                isPlaying = true
            }
        }
    }
    
    private func checkAutoPause() {
        guard isPlaying, let segment = currentSegment else { return }
        let currentTime = audioManager.streamCurrentTime
        
        // If we reach the end of the character's line, pause and wait for tap
        if currentTime >= segment.endTime {
            audioManager.pauseStream()
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
            if let segment = currentSegment, audioManager.streamCurrentTime > segment.startTime + 1.0 {
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
    
}
