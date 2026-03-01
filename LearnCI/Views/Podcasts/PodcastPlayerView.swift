import SwiftUI
import SwiftData
import Combine

struct PodcastPlayerView: View {
    let episode: PodcastEpisode
    @Environment(AudioManager.self) private var audioManager
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isPlaying = false
    @State private var sliderValue: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var startTime: Date?
    @State private var artworkImage: UIImage?
    @State private var toastMessage: String?

    let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Artwork
                        AsyncImage(url: URL(string: episode.show?.artworkUrl ?? "")) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                                    .onAppear {
                                        // Capture UIImage for now-playing
                                        let renderer = ImageRenderer(content: image.resizable().scaledToFill().frame(width: 300, height: 300))
                                        artworkImage = renderer.uiImage
                                    }
                            default:
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.secondary.opacity(0.2))
                                    .overlay(Image(systemName: "headphones").font(.system(size: 60)).foregroundColor(.secondary))
                            }
                        }
                        .frame(width: 280, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 8)

                        // Title & Show Name
                        VStack(spacing: 6) {
                            Text(episode.title)
                                .font(.title3.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(3)

                            if let showTitle = episode.show?.title {
                                Text(showTitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)

                        // Episode description
                        if !episode.episodeDescription.isEmpty {
                            Text(episode.episodeDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(6)
                                .padding(.horizontal)
                        }

                        // Spacer for player bar
                        Color.clear.frame(height: 160)
                    }
                    .padding(.top, 20)
                }

                // Sticky Player Bar
                AudioPlayerBar(
                    isPlaying: $isPlaying,
                    sliderValue: $sliderValue,
                    duration: duration,
                    playbackRate: $playbackRate,
                    ambientVolume: .constant(0),
                    isAmbientPlaying: false,
                    onPlayPause: togglePlay,
                    onSkipForward: skipForward,
                    onSkipBackward: skipBackward,
                    onSeek: seekTo,
                    onChangeRate: setRate
                )
            }

            // Toast
            if let message = toastMessage {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startTime = Date()
            setupStream()
        }
        .onDisappear {
            cleanupSession()
        }
        .onReceive(timer) { _ in
            guard audioManager.streamPlayer != nil else { return }
            sliderValue = audioManager.streamCurrentTime
            isPlaying = audioManager.isStreaming

            if duration == 0 && audioManager.streamDuration > 0 {
                duration = audioManager.streamDuration
            }
        }
    }

    // MARK: - Audio Logic

    private func setupStream() {
        guard let url = URL(string: episode.audioUrl) else { return }

        audioManager.streamAudio(url: url, startAt: episode.playbackPosition)
        duration = episode.duration

        // Set now-playing info
        audioManager.updateStreamNowPlayingInfo(
            title: episode.title,
            artist: episode.show?.title ?? "Podcast"
        )

        // Load artwork for lock screen / Dynamic Island
        if let artworkUrlStr = episode.show?.artworkUrl,
           let artworkUrl = URL(string: artworkUrlStr) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: artworkUrl),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        artworkImage = image
                        audioManager.updateStreamNowPlayingInfo(artworkImage: image)
                    }
                }
            }
        }
    }

    private func cleanupSession() {
        // Save playback position
        let currentTime = audioManager.streamCurrentTime
        episode.playbackPosition = currentTime
        episode.isSynced = false

        // Mark as played if near end (within 30 seconds or past 95%)
        if duration > 0 && (currentTime >= duration - 30 || currentTime / duration > 0.95) {
            episode.isPlayed = true
        }

        try? modelContext.save()

        audioManager.stopStream()

        // Log podcast activity for input hours
        if let start = startTime {
            let minutes = Int(Date().timeIntervalSince(start) / 60)
            if minutes > 0 {
                let activity = UserActivity(
                    date: start,
                    minutes: minutes,
                    activityType: .podcasts,
                    language: episode.show?.language ?? .spanish,
                    userID: authManager.currentUser,
                    comment: "\(episode.show?.title ?? "Podcast") — \(episode.title)"
                )
                modelContext.insert(activity)
                try? modelContext.save()

                showToast("+\(minutes) min of podcast listening logged")
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut(duration: 0.3)) {
                toastMessage = nil
            }
        }
    }

    private func togglePlay() {
        if audioManager.isStreaming {
            audioManager.pauseStream()
            isPlaying = false
        } else {
            audioManager.playStream()
            isPlaying = true
        }
        audioManager.updateStreamNowPlayingInfo()
    }

    private func skipForward() {
        let newTime = min(duration, audioManager.streamCurrentTime + 10)
        audioManager.seekStream(to: newTime)
        sliderValue = newTime
        audioManager.updateStreamNowPlayingInfo()
    }

    private func skipBackward() {
        let newTime = max(0, audioManager.streamCurrentTime - 10)
        audioManager.seekStream(to: newTime)
        sliderValue = newTime
        audioManager.updateStreamNowPlayingInfo()
    }

    private func seekTo(_ value: Double) {
        audioManager.seekStream(to: value)
        sliderValue = value
        audioManager.updateStreamNowPlayingInfo()
    }

    private func setRate(_ rate: Float) {
        playbackRate = rate
        audioManager.setStreamRate(rate)
        audioManager.updateStreamNowPlayingInfo()
    }
}
