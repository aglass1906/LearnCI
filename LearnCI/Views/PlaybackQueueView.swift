import SwiftUI

struct PlaybackQueueView: View {
    @Environment(PlaybackQueueManager.self) private var queue
    @Environment(MediaDownloadManager.self) private var downloads
    @Environment(AudioManager.self) private var audioManager

    var body: some View {
        Group {
            if queue.items.isEmpty {
                ContentUnavailableView {
                    Label("Queue Is Empty", systemImage: "text.line.first.and.arrowtriangle.forward")
                } description: {
                    Text("Start a story or podcast to build your listening queue.")
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
                    ForEach(queue.items) { item in
                        Button {
                            queue.play(item)
                        } label: {
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
                    }
                    .onDelete(perform: queue.remove)
                    .onMove(perform: queue.move)
                }
            }
        }
        .navigationTitle("Listening Queue")
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
