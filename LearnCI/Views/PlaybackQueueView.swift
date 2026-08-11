import SwiftUI
import SwiftData

struct PlaybackQueueView: View {
    @Environment(PlaybackQueueManager.self) private var queue
    @Environment(MediaDownloadManager.self) private var downloads
    @Environment(AudioManager.self) private var audioManager
    @Environment(AuthManager.self) private var authManager
    @Query(sort: \MediaPlaybackState.updatedAt, order: .reverse) private var mediaPlaybackStates: [MediaPlaybackState]
    @State private var selectedVideo: YouTubeVideo?

    private var videoQueue: [MediaPlaybackState] {
        mediaPlaybackStates.filter {
            $0.userID == authManager.currentUser &&
            $0.resourceType == .youtube &&
            MediaPlaybackStore.canResume($0)
        }
    }

    var body: some View {
        Group {
            if queue.items.isEmpty && videoQueue.isEmpty {
                ContentUnavailableView {
                    Label("Queue Is Empty", systemImage: "text.line.first.and.arrowtriangle.forward")
                } description: {
                    Text("Start a story, podcast, or video to build your media queue.")
                }
            } else {
                List {
                    if let error = audioManager.streamLoadError {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Playback interrupted", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Retry") { queue.retryCurrent() }
                            }
                        }
                    }
                    if !queue.items.isEmpty {
                        Section("Audio · Background & CarPlay") {
                            ForEach(queue.items) { item in
                                Button {
                                    queue.play(item)
                                } label: {
                                    audioRow(for: item)
                                }
                            }
                            .onDelete(perform: queue.remove)
                            .onMove(perform: queue.move)
                        }
                    }

                    if !videoQueue.isEmpty {
                        Section {
                            ForEach(videoQueue) { state in
                                Button {
                                    selectedVideo = makeVideo(from: state)
                                } label: {
                                    videoRow(for: state)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Video · Plays While Open")
                        } footer: {
                            Text("YouTube videos pause when the player is closed and are not sent to CarPlay.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Media Queue")
        .sheet(item: $selectedVideo) { video in
            VideoDetailSheet(
                video: video,
                onWatch: { openInYouTube(video) },
                onLogTime: { _ in }
            )
        }
        .toolbar {
            if !queue.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Clear Queue", role: .destructive) { queue.clear() }
                        Spacer()
                        Menu {
                            Text("\(downloads.downloadedCount) downloads · \(formattedStorage)")
                            Button("Validate Downloads") { downloads.cleanUpInvalidDownloads() }
                            Button("Delete All Downloads", role: .destructive) { downloads.deleteAll() }
                        } label: {
                            Label("Downloads", systemImage: "externaldrive.fill")
                        }
                    }
                }
            }
        }
    }

    private func audioRow(for item: CarPlayMediaItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .story ? "book.fill" : "mic.fill")
                .frame(width: 28)
                .foregroundStyle(item.id == queue.currentItem?.id ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            if item.id == queue.currentItem?.id {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.blue)
            }
            downloadStatus(for: item)
        }
    }

    private func videoRow(for state: MediaPlaybackState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .frame(width: 28)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(state.subtitle ?? "YouTube")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: state.progressFraction)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func makeVideo(from state: MediaPlaybackState) -> YouTubeVideo {
        YouTubeVideo(
            id: state.resourceId,
            title: state.title,
            description: "",
            thumbnailURL: state.artworkUrl ?? "https://img.youtube.com/vi/\(state.resourceId)/mqdefault.jpg",
            channelTitle: state.subtitle ?? "YouTube",
            duration: "PT\(max(0, Int(state.durationSeconds.rounded())))S",
            publishedAt: state.startedAt
        )
    }

    private func openInYouTube(_ video: YouTubeVideo) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(video.id)") else { return }
        UIApplication.shared.open(url)
    }

    private var formattedStorage: String {
        ByteCountFormatter.string(fromByteCount: downloads.storageBytes, countStyle: .file)
    }

    @ViewBuilder
    private func downloadStatus(for item: CarPlayMediaItem) -> some View {
        switch downloads.state(for: item) {
        case .notDownloaded, .failed:
            Button {
                Task { await downloads.download(item) }
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .downloaded:
            Button {
                downloads.delete(item)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
        }
    }
}
