import SwiftUI
import SwiftData

struct PodcastShowView: View {
    let show: PodcastShow
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaStudyStore.self) private var mediaStudyStore
    @State private var podcastManager = PodcastManager()
    @State private var isRefreshing = false
    @State private var sortedEpisodes: [PodcastEpisode] = []
    @Query private var allMediaStudyStates: [MediaStudyState]

    private func mediaStudyState(for episode: PodcastEpisode) -> MediaStudyState? {
        let resourceId = episode.id.uuidString
        return allMediaStudyStates.first {
            $0.isActive &&
            $0.resourceTypeRaw == StudyResourceType.podcast.rawValue &&
            $0.resourceId == resourceId &&
            $0.userID == authManager.currentUser
        }
    }

    var body: some View {
        List {
            // Header Section
            Section {
                VStack(spacing: 12) {
                    CachedAsyncImage(url: URL(string: show.artworkUrl ?? "")) { image in
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
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if let state = mediaStudyState(for: episode) {
                            Button {
                                mediaStudyStore.unstudy(state, in: modelContext)
                            } label: {
                                Label("Remove", systemImage: "book.pages")
                            }
                            .tint(.red)
                        } else {
                            Button {
                                mediaStudyStore.markStudying(
                                    episode: episode,
                                    userID: authManager.currentUser,
                                    in: modelContext
                                )
                            } label: {
                                Label("Study", systemImage: "text.book.closed")
                            }
                            .tint(.indigo)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateSortedEpisodes()
        }
        .onChange(of: show.episodes.count) { _, _ in
            updateSortedEpisodes()
        }
        .refreshable {
            await podcastManager.refreshEpisodes(for: show, modelContext: modelContext)
            updateSortedEpisodes()
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
                            updateSortedEpisodes()
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

    private func updateSortedEpisodes() {
        sortedEpisodes = show.episodes.sorted { $0.publishedDate > $1.publishedDate }
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
