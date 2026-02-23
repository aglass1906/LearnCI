import SwiftUI
import SwiftData

struct PodcastShowView: View {
    let show: PodcastShow
    @Environment(\.modelContext) private var modelContext
    @State private var podcastManager = PodcastManager()
    @State private var isRefreshing = false

    private var sortedEpisodes: [PodcastEpisode] {
        show.episodes.sorted { $0.publishedDate > $1.publishedDate }
    }

    var body: some View {
        List {
            // Header Section
            Section {
                VStack(spacing: 12) {
                    AsyncImage(url: URL(string: show.artworkUrl ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.2))
                            .overlay(Image(systemName: "headphones").font(.largeTitle).foregroundColor(.secondary))
                    }
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(show.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(show.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if !show.showDescription.isEmpty {
                        Text(show.showDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // Episodes
            Section("Episodes") {
                ForEach(sortedEpisodes) { episode in
                    NavigationLink(destination: PodcastPlayerView(episode: episode)) {
                        EpisodeRow(episode: episode)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await podcastManager.refreshEpisodes(for: show, modelContext: modelContext)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    FavoriteButton(
                        consumptionUrl: show.feedUrl,
                        type: .podcast,
                        title: show.title,
                        author: show.author,
                        imageUrl: show.artworkUrl
                    )

                    Button(action: {
                        Task {
                            isRefreshing = true
                            await podcastManager.refreshEpisodes(for: show, modelContext: modelContext)
                            isRefreshing = false
                        }
                    }) {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Episode Row

private struct EpisodeRow: View {
    let episode: PodcastEpisode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(episode.isPlayed ? .secondary : .primary)

                Spacer()

                if episode.playbackPosition > 0 && !episode.isPlayed {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
                if episode.isPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            HStack {
                Text(episode.publishedDate, style: .date)
                if episode.duration > 0 {
                    Text("·")
                    Text(formatDuration(episode.duration))
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if !episode.episodeDescription.isEmpty {
                Text(episode.episodeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m) min"
    }
}
