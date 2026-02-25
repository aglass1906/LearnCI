import SwiftUI
import SwiftData
import Combine

struct PodcastSessionView: View {
    let initialEpisodes: [PodcastEpisode]
    let sessionMinutes: Int
    var resumingFromIndex: Int = 0

    @Environment(AudioManager.self) private var audioManager
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var episodes: [PodcastEpisode] = []
    @State private var currentIndex: Int = 0
    @State private var isPlaying = false
    @State private var sliderValue: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var sessionStartTime: Date?
    @State private var elapsedSessionMinutes: Int = 0
    @State private var sessionComplete = false
    @State private var manuallyPaused = false
    @State private var toastMessage: String?

    let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var currentEpisode: PodcastEpisode? {
        guard currentIndex >= 0 && currentIndex < episodes.count else { return nil }
        return episodes[currentIndex]
    }

    private var upNextEpisodes: [PodcastEpisode] {
        guard currentIndex + 1 < episodes.count else { return [] }
        return Array(episodes[(currentIndex + 1)...])
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Session Progress
                        sessionProgressView

                        // Current Episode Artwork
                        if let episode = currentEpisode {
                            currentEpisodeView(episode)
                        }

                        // Up Next
                        if !upNextEpisodes.isEmpty {
                            upNextView
                        }

                        // End Session
                        Button(action: endSession) {
                            Text("End Session")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        .padding(.top, 8)

                        // Spacer for player bar
                        Color.clear.frame(height: 160)
                    }
                    .padding(.top, 12)
                }

                // Sticky Player Bar
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
        .navigationTitle("Listening Session")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            episodes = initialEpisodes
            currentIndex = resumingFromIndex
            sessionStartTime = Date()
            playCurrentEpisode()
        }
        .onDisappear {
            saveCurrentEpisodeProgress()
            saveSessionState()
            audioManager.stopStream()
            logSessionActivity()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                saveCurrentEpisodeProgress()
                saveSessionState()
            }
        }
        .onReceive(timer) { _ in
            guard audioManager.streamPlayer != nil else { return }
            sliderValue = audioManager.streamCurrentTime
            isPlaying = audioManager.isStreaming

            if duration == 0 && audioManager.streamDuration > 0 {
                duration = audioManager.streamDuration
            }

            // Update session elapsed time
            if let start = sessionStartTime {
                elapsedSessionMinutes = Int(Date().timeIntervalSince(start) / 60)
            }

            // Detect episode finished (auto-advance)
            if audioManager.streamFinished && !manuallyPaused {
                audioManager.streamFinished = false
                advanceToNextEpisode()
            }

            // Check if session time is up
            if !sessionComplete && elapsedSessionMinutes >= sessionMinutes {
                sessionComplete = true
                showToast("Session goal reached! Finishing current episode...")
            }
        }
    }

    // MARK: - Views

    private var sessionProgressView: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.blue)
                Text("\(elapsedSessionMinutes) of \(sessionMinutes) min")
                    .font(.subheadline.bold())
                if sessionComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            ProgressView(value: min(Double(elapsedSessionMinutes), Double(sessionMinutes)), total: Double(sessionMinutes))
                .tint(sessionComplete ? .green : .blue)
                .padding(.horizontal, 40)

            Text("Episode \(currentIndex + 1) of \(episodes.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func currentEpisodeView(_ episode: PodcastEpisode) -> some View {
        VStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: episode.show?.artworkUrl ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(Image(systemName: "headphones").font(.system(size: 50)).foregroundColor(.secondary))
            }
            .id(episode.id)
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 6)

            VStack(spacing: 4) {
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

            // Next Episode Button
            if currentIndex + 1 < episodes.count {
                Button {
                    saveCurrentEpisodeProgress()
                    advanceToNextEpisode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                        Text("Next Episode")
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var upNextView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Up Next")
                .font(.headline)
                .padding(.horizontal)

            ForEach(Array(upNextEpisodes.enumerated()), id: \.element.id) { index, episode in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    CachedAsyncImage(url: URL(string: episode.show?.artworkUrl ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.2))
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        if let showTitle = episode.show?.title {
                            Text(showTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if episode.duration > 0 {
                        Text(formatDuration(episode.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Audio Logic

    private func playCurrentEpisode() {
        guard let episode = currentEpisode,
              let url = URL(string: episode.audioUrl) else { return }

        audioManager.streamAudio(url: url, startAt: episode.playbackPosition)
        audioManager.playStream()
        duration = episode.duration
        isPlaying = true
        manuallyPaused = false

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
                        audioManager.updateStreamNowPlayingInfo(artworkImage: image)
                    }
                }
            }
        }
    }

    private func advanceToNextEpisode() {
        // Mark current as played
        if let episode = currentEpisode {
            episode.isPlayed = true
            episode.playbackPosition = 0
            episode.isSynced = false
        }

        if currentIndex + 1 < episodes.count && !(sessionComplete && audioManager.streamFinished) {
            currentIndex += 1
            sliderValue = 0
            duration = 0
            playCurrentEpisode()
        } else {
            // Session done
            isPlaying = false
            audioManager.stopStream()
            clearSessionState()
            showToast("Session complete!")
        }

        try? modelContext.save()
    }

    private func saveCurrentEpisodeProgress() {
        guard let episode = currentEpisode else { return }
        let currentTime = audioManager.streamCurrentTime
        episode.playbackPosition = currentTime
        episode.isSynced = false

        // Mark as played if near end
        if duration > 0 && (currentTime >= duration - 30 || currentTime / duration > 0.95) {
            episode.isPlayed = true
        }

        try? modelContext.save()
    }

    private func endSession() {
        saveCurrentEpisodeProgress()
        clearSessionState()
        audioManager.stopStream()
        logSessionActivity()
        dismiss()
    }

    private func logSessionActivity() {
        guard let start = sessionStartTime else { return }
        let minutes = Int(Date().timeIntervalSince(start) / 60)
        guard minutes > 0 else { return }

        // Build comment with each episode listened to
        let episodeLines = episodes.prefix(currentIndex + 1).map { episode -> String in
            let show = episode.show?.title ?? "Unknown Show"
            return "\(show) · \(episode.title)"
        }
        let comment = episodeLines.joined(separator: "\n")

        let language = currentEpisode?.show?.language ?? .spanish

        let activity = UserActivity(
            date: start,
            minutes: minutes,
            activityType: .podcasts,
            language: language,
            userID: authManager.currentUser,
            comment: comment
        )
        modelContext.insert(activity)
        try? modelContext.save()
    }

    // MARK: - Playback Controls

    private func togglePlay() {
        if audioManager.isStreaming {
            audioManager.pauseStream()
            isPlaying = false
            manuallyPaused = true
        } else {
            audioManager.playStream()
            isPlaying = true
            manuallyPaused = false
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

    // MARK: - Helpers

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

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m) min"
    }

    // MARK: - Session State Persistence

    private func saveSessionState() {
        guard !episodes.isEmpty else { return }
        let ids = episodes.map { $0.id.uuidString }
        UserDefaults.standard.set(ids, forKey: "podcastSession.episodeIDs")
        UserDefaults.standard.set(currentIndex, forKey: "podcastSession.currentIndex")
        UserDefaults.standard.set(sessionMinutes, forKey: "podcastSession.minutes")
        if let start = sessionStartTime {
            UserDefaults.standard.set(start, forKey: "podcastSession.startTime")
        }
    }

    private func clearSessionState() {
        ["podcastSession.episodeIDs", "podcastSession.currentIndex",
         "podcastSession.minutes", "podcastSession.startTime"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }
}
