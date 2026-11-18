import SwiftUI
import SwiftData

/// App-level now-playing bar for a podcast or story that kept playing after its screen was left.
struct MiniNowPlayingBar: View {
    @Environment(AudioManager.self) private var audioManager
    @Environment(PlaybackQueueManager.self) private var playbackQueue
    @Environment(\.modelContext) private var modelContext

    private let session = BackgroundPlaybackSession.shared
    let onOpen: (MiniPlayerRoute) -> Void

    private var target: BackgroundPlaybackSession.Target? {
        session.target(currentQueueItem: playbackQueue.currentItem)
    }

    private var displayTitle: String {
        playbackQueue.currentItem?.title ?? session.context?.title ?? ""
    }

    private var displaySubtitle: String {
        playbackQueue.currentItem?.subtitle ?? session.context?.subtitle ?? ""
    }

    var body: some View {
        if session.context != nil {
            HStack(spacing: 8) {
                Button {
                    if let target { onOpen(MiniPlayerRoute(target: target)) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayTitle)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                        Text(displaySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now playing \(displayTitle). Open")

                controlButton("gobackward.10", label: "Back 10 seconds") { skip(-10) }

                Button(action: togglePlay) {
                    Image(systemName: audioManager.isStreaming ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(PlayerTheme.accent, in: Circle())
                }
                .buttonStyle(PlayerPressStyle())
                .accessibilityLabel(audioManager.isStreaming ? "Pause" : "Play")

                controlButton("goforward.10", label: "Forward 10 seconds") { skip(10) }

                controlButton("xmark", label: "Stop and close") { close() }
            }
            .padding(.horizontal, 12)
            .onChange(of: Int(audioManager.streamCurrentTime / 10)) { _, _ in
                persistPodcastPosition()
            }
            .onChange(of: audioManager.streamFinished) { _, finished in
                guard finished, playbackQueue.hasNext == false else { return }
                persistPodcastPosition()
                session.clear()
            }
            .onChange(of: audioManager.streamPlayer == nil) { _, isGone in
                if isGone { session.clear() }
            }
        }
    }

    private func controlButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: PlayerTheme.minTapTarget, height: PlayerTheme.minTapTarget)
        }
        .buttonStyle(PlayerPressStyle())
        .accessibilityLabel(label)
    }

    private func togglePlay() {
        if audioManager.isStreaming {
            audioManager.pauseStream()
            persistPodcastPosition()
        } else {
            audioManager.playStream()
        }
    }

    private func skip(_ delta: Double) {
        let duration = audioManager.streamDuration
        var seconds = max(0, audioManager.streamCurrentTime + delta)
        if duration > 0 { seconds = min(duration, seconds) }
        audioManager.seekStream(to: seconds)
    }

    private func close() {
        persistPodcastPosition()
        audioManager.onStreamFinished = nil
        audioManager.stopStream()
        session.clear()
    }

    /// Only podcast episodes keep a per-episode resume position here.
    private func persistPodcastPosition() {
        guard let target, target.kind == .podcast else { return }
        let id = target.id
        let descriptor = FetchDescriptor<PodcastEpisode>(predicate: #Predicate { $0.id == id })
        guard let episode = try? modelContext.fetch(descriptor).first else { return }
        episode.playbackPosition = audioManager.streamCurrentTime
        episode.isSynced = false
        try? modelContext.save()
    }
}

/// Sheet used to reopen the full podcast player from the mini bar.
struct PodcastMiniPlayerSheet: View {
    let episodeID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let episode = fetchEpisode() {
                PodcastPlayerView(episode: episode)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { dismiss() }
                        }
                    }
            } else {
                ContentUnavailableView("Episode not found", systemImage: "waveform")
            }
        }
    }

    private func fetchEpisode() -> PodcastEpisode? {
        let id = episodeID
        let descriptor = FetchDescriptor<PodcastEpisode>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}

/// Sheet used to reopen a story's listen player from the mini bar.
struct StoryMiniPlayerSheet: View {
    let storyID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let story = fetchStory() {
                StoryAudioPlaybackView(story: story)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { dismiss() }
                        }
                    }
            } else {
                ContentUnavailableView("Story not found", systemImage: "headphones")
            }
        }
    }

    private func fetchStory() -> Story? {
        let id = storyID
        let descriptor = FetchDescriptor<Story>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}

struct MiniPlayerRoute: Identifiable {
    let target: BackgroundPlaybackSession.Target

    var id: String {
        switch target.kind {
        case .podcast: return "podcast:\(target.id.uuidString)"
        case .story: return "story:\(target.id.uuidString)"
        }
    }
}
