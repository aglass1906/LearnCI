import SwiftUI
import SwiftData

/// App-level now-playing bar for a podcast that kept playing after its screen was left.
struct MiniNowPlayingBar: View {
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.modelContext) private var modelContext

    private let miniPlayer = PodcastMiniPlayer.shared
    let onOpen: (UUID) -> Void

    var body: some View {
        if let context = miniPlayer.context {
            HStack(spacing: 8) {
                Button {
                    onOpen(context.episodeID)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                        Text(context.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now playing \(context.title). Open episode")

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

                controlButton("xmark", label: "Stop and close") { close(context) }
            }
            .padding(.horizontal, 12)
            .onChange(of: Int(audioManager.streamCurrentTime / 10)) { _, _ in
                persistPosition(for: context.episodeID)
            }
            .onChange(of: audioManager.streamFinished) { _, finished in
                guard finished else { return }
                persistPosition(for: context.episodeID)
                miniPlayer.clear()
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
            if let id = miniPlayer.context?.episodeID { persistPosition(for: id) }
        } else {
            audioManager.playStream()
        }
    }

    private func skip(_ delta: Double) {
        let duration = audioManager.streamDuration
        var target = audioManager.streamCurrentTime + delta
        target = max(0, target)
        if duration > 0 { target = min(duration, target) }
        audioManager.seekStream(to: target)
    }

    private func close(_ context: PodcastMiniPlayer.Context) {
        persistPosition(for: context.episodeID)
        audioManager.stopStream()
        miniPlayer.clear()
    }

    private func persistPosition(for episodeID: UUID) {
        let descriptor = FetchDescriptor<PodcastEpisode>(
            predicate: #Predicate { $0.id == episodeID }
        )
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

struct MiniPlayerRoute: Identifiable {
    let id: UUID
}
