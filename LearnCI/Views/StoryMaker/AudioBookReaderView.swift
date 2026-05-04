import SwiftUI
import Combine

struct AudioBookReaderView: View {
    let story: Story

    @State private var currentClipIndex = 0
    @State private var isPlaying = false
    @State private var isDownloadingAudio = false
    @State private var sliderValue = 0.0
    @State private var duration = 0.0
    @State private var playbackRate: Float = 1.0

    private var audioManager = AudioManager.shared
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(story: Story) {
        self.story = story
    }

    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    private var spineItems: [StoryReadingSpineItem] {
        adapter.items(for: .audioBook)
    }

    private var readingMatterItems: [StoryReadingSpineItem] {
        spineItems.filter {
            if case .readingMatterPage = $0 { return true }
            return false
        }
    }

    private var chapterItems: [StoryReadingSpineItem] {
        spineItems.filter {
            if case .chapter = $0 { return true }
            return false
        }
    }

    private var clips: [StorySceneAudioClip] {
        adapter.audioClips(for: .audioBook)
    }

    var body: some View {
        Group {
            if let issue = adapter.requirementIssue(for: .audioBook) {
                StoryReaderUnavailableView(title: issue.title, message: issue.message)
            } else {
                audioBookBody
            }
        }
        .navigationTitle("Audio Book")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            audioManager.stopAudio()
        }
        .onReceive(timer) { _ in
            guard !clips.isEmpty else { return }

            if audioManager.streamFinished {
                advanceAfterClipFinished()
                return
            }

            if audioManager.streamPlayer != nil {
                sliderValue = audioManager.streamCurrentTime
                if audioManager.streamDuration > 0 {
                    duration = audioManager.streamDuration
                }
                isPlaying = audioManager.isStreaming
            }
        }
    }

    private var audioBookBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if spineItems.contains(.cover) {
                        coverHeader
                    }

                    if !readingMatterItems.isEmpty {
                        readingMatterSection
                    }

                    playlistSection
                    storyboardSection

                    Color.clear.frame(height: 120)
                }
                .padding(18)
            }

            playerBar
        }
    }

    private var coverHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(story.title)
                .font(.system(size: 30, weight: .bold, design: .serif))
            Text("\(story.language.displayName) · Level \(story.level)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readingMatterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading Matter")
                .font(.headline)
            ForEach(readingMatterItems) { item in
                if let page = adapter.readingMatterPage(for: item) {
                VStack(alignment: .leading, spacing: 6) {
                    if let title = page.titleTarget?.nilIfEmptyAudioBook {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                    }
                    if let body = page.bodyTarget?.nilIfEmptyAudioBook {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
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

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chapter Playlist")
                .font(.headline)

            ForEach(chapterItems) { item in
                if let chapter = adapter.chapter(for: item),
                   let chapterIndex = chapterIndex(for: item),
                   let firstClipIndex = firstClipIndex(forChapter: chapterIndex) {
                Button {
                    playClip(at: firstClipIndex, autoplay: true)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: currentChapterIndex == chapterIndex && isPlaying ? "speaker.wave.2.fill" : "play.circle")
                            .font(.title3)
                            .foregroundStyle(currentChapterIndex == chapterIndex ? Color.accentColor : .secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(chapter.titleTargetLanguage.isEmpty ? "Chapter \(chapterIndex + 1)" : chapter.titleTargetLanguage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(chapter.bodyTextTargetForReading)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()
                        Text("\(clipsForChapter(chapterIndex).count) scenes")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                }
            }
        }
    }

    private var storyboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storyboard")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        Button {
                            playClip(at: index, autoplay: true)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                AsyncImage(url: clip.imageURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    case .failure:
                                        Color(.secondarySystemBackground)
                                    case .empty:
                                        Color(.secondarySystemBackground).overlay { ProgressView() }
                                    @unknown default:
                                        Color(.secondarySystemBackground)
                                    }
                                }
                                .frame(width: 132, height: 88)
                                .clipped()

                                Text("Scene \(clip.sceneIndex + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.black.opacity(0.45))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(index == currentClipIndex ? Color.accentColor : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var playerBar: some View {
        VStack(spacing: 10) {
            if isDownloadingAudio {
                ProgressView()
            }

            HStack {
                Button(action: previousClip) {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }

                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                }

                Button(action: nextClip) {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                }

                Slider(value: Binding(
                    get: { sliderValue },
                    set: { newValue in
                        sliderValue = newValue
                        audioManager.seekStream(to: newValue)
                    }
                ), in: 0...max(duration, 1))

                Menu {
                    Button("0.75x") { setRate(0.75) }
                    Button("1.0x") { setRate(1.0) }
                    Button("1.25x") { setRate(1.25) }
                    Button("1.5x") { setRate(1.5) }
                } label: {
                    Text("\(String(format: "%.1f", playbackRate))x")
                        .font(.caption.bold())
                        .frame(width: 44)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(.thinMaterial)
    }

    private func togglePlay() {
        if audioManager.streamPlayer == nil {
            playClip(at: currentClipIndex, autoplay: true)
            return
        }

        if audioManager.isStreaming {
            audioManager.pauseStream()
            isPlaying = false
        } else {
            audioManager.playStream()
            isPlaying = true
        }
    }

    private func playClip(at index: Int, autoplay: Bool) {
        guard clips.indices.contains(index) else { return }
        currentClipIndex = index
        let clip = clips[index]
        let localURL = adapter.localAudioURL(for: clip)

        if let cachedURL = adapter.cachedAudioURL(for: clip) {
            print("[AudioBook] Playing cached scene audio: \(cachedURL.lastPathComponent)")
            playLocal(url: cachedURL, clip: clip, autoplay: autoplay)
            return
        }

        print("[AudioBook] Downloading scene audio: chapter \(clip.chapterIndex), scene \(clip.sceneIndex)")
        isDownloadingAudio = true
        Task { await downloadAndPlay(clip: clip, localURL: localURL, autoplay: autoplay) }
    }

    private func playLocal(url: URL, clip: StorySceneAudioClip, autoplay: Bool) {
        audioManager.streamAudio(url: url)
        audioManager.setStreamRate(playbackRate)
        duration = clip.duration ?? audioManager.streamDuration
        sliderValue = 0
        audioManager.updateStreamNowPlayingInfo(title: clip.title, artist: story.title, artworkImage: nil)
        if autoplay {
            audioManager.playStream()
            isPlaying = true
        }
    }

    private func downloadAndPlay(clip: StorySceneAudioClip, localURL: URL, autoplay: Bool) async {
        guard let url = StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString) else {
            await MainActor.run { isDownloadingAudio = false }
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 else {
                await MainActor.run { isDownloadingAudio = false }
                return
            }

            let isWAV = data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46])
            let correctURL = localURL.deletingPathExtension().appendingPathExtension(isWAV ? "wav" : "mp3")
            try data.write(to: correctURL)

            await MainActor.run {
                isDownloadingAudio = false
                playLocal(url: correctURL, clip: clip, autoplay: autoplay)
            }
        } catch {
            await MainActor.run { isDownloadingAudio = false }
        }
    }

    private func advanceAfterClipFinished() {
        audioManager.streamFinished = false
        guard currentClipIndex < clips.count - 1 else {
            isPlaying = false
            return
        }
        playClip(at: currentClipIndex + 1, autoplay: true)
    }

    private func nextClip() {
        guard currentClipIndex < clips.count - 1 else { return }
        playClip(at: currentClipIndex + 1, autoplay: isPlaying)
    }

    private func previousClip() {
        guard currentClipIndex > 0 else {
            audioManager.seekStream(to: 0)
            return
        }
        playClip(at: currentClipIndex - 1, autoplay: isPlaying)
    }

    private func setRate(_ rate: Float) {
        playbackRate = rate
        audioManager.setStreamRate(rate)
    }

    private var currentChapterIndex: Int? {
        guard clips.indices.contains(currentClipIndex) else { return nil }
        return clips[currentClipIndex].chapterIndex
    }

    private func chapterIndex(for item: StoryReadingSpineItem) -> Int? {
        guard case .chapter(let index) = item else { return nil }
        return index
    }

    private func firstClipIndex(forChapter chapterIndex: Int) -> Int? {
        clips.firstIndex { $0.chapterIndex == chapterIndex }
    }

    private func clipsForChapter(_ chapterIndex: Int) -> [StorySceneAudioClip] {
        clips.filter { $0.chapterIndex == chapterIndex }
    }
}

private extension String {
    var nilIfEmptyAudioBook: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
