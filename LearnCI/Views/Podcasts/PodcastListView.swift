import SwiftUI
import SwiftData

enum PodcastTab: String, CaseIterable {
    case newEpisodes = "New Episodes"
    case shows = "Shows"
}

struct PodcastListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query(sort: \PodcastShow.addedAt, order: .reverse) private var shows: [PodcastShow]
    @Query(sort: \PodcastEpisode.publishedDate, order: .reverse) private var allEpisodes: [PodcastEpisode]

    @State private var podcastManager = PodcastManager()
    @State private var showAddSheet = false
    @State private var selectedTab: PodcastTab = .newEpisodes

    var body: some View {
        VStack(spacing: 0) {
            if !shows.isEmpty {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(PodcastTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Group {
                if shows.isEmpty {
                    ContentUnavailableView {
                        Label("No Podcasts", systemImage: "headphones")
                    } description: {
                        Text("Search for podcasts to subscribe.")
                    } actions: {
                        Button("Find Podcasts") { showAddSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    switch selectedTab {
                    case .newEpisodes:
                        newEpisodesView
                    case .shows:
                        showsView
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PodcastSearchSheet(
                podcastManager: podcastManager,
                modelContext: modelContext,
                subscribedFeedUrls: Set(shows.map { $0.feedUrl }),
                userID: authManager.currentUser,
                onDismiss: { showAddSheet = false }
            )
        }
    }

    // MARK: - New Episodes Tab

    private var newEpisodesView: some View {
        Group {
            if allEpisodes.isEmpty {
                ContentUnavailableView {
                    Label("No Episodes", systemImage: "waveform")
                } description: {
                    Text("Episodes from your subscribed shows will appear here.")
                }
            } else {
                List {
                    ForEach(allEpisodes) { episode in
                        NavigationLink(destination: PodcastPlayerView(episode: episode)) {
                            NewEpisodeRow(episode: episode)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Shows Tab

    private var showsView: some View {
        List {
            ForEach(shows) { show in
                NavigationLink(destination: PodcastShowView(show: show)) {
                    PodcastShowRow(show: show)
                }
            }
            .onDelete(perform: deleteShows)
        }
        .listStyle(.plain)
    }

    private func deleteShows(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(shows[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Show Row

private struct PodcastShowRow: View {
    let show: PodcastShow

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: show.artworkUrl ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(Image(systemName: "headphones").foregroundColor(.secondary))
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(show.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(show.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("\(show.episodes.count) episodes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Episode Row

private struct NewEpisodeRow: View {
    let episode: PodcastEpisode

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: episode.show?.artworkUrl ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(Image(systemName: "headphones").foregroundColor(.secondary))
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(episode.isPlayed ? .secondary : .primary)

                if let showTitle = episode.show?.title {
                    Text(showTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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
            }

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

// MARK: - Podcast Search & Add Sheet

private struct PodcastSearchSheet: View {
    var podcastManager: PodcastManager
    var modelContext: ModelContext
    let subscribedFeedUrls: Set<String>
    let userID: String?
    var onDismiss: () -> Void

    @State private var searchText = ""
    @State private var showRSSInput = false
    @State private var feedUrlInput = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var subscribingFeedUrl: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search podcasts...", text: $searchText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit { performSearch() }
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            podcastManager.searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)

                // Error message
                if let error = podcastManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                // Content
                if podcastManager.isSearching {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if podcastManager.searchResults.isEmpty && !searchText.isEmpty {
                    Spacer()
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try a different search term, or add by RSS URL.")
                    }
                    Spacer()
                } else if podcastManager.searchResults.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Search for podcasts by name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(podcastManager.searchResults) { result in
                            SearchResultRow(
                                result: result,
                                isSubscribed: subscribedFeedUrls.contains(result.feedUrl),
                                isSubscribing: subscribingFeedUrl == result.feedUrl,
                                onSubscribe: { subscribe(feedUrl: result.feedUrl) }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Find Podcasts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showRSSInput.toggle() }) {
                        Image(systemName: "link")
                    }
                }
            }
            .alert("Add by RSS URL", isPresented: $showRSSInput) {
                TextField("https://example.com/feed.xml", text: $feedUrlInput)
                    .autocapitalization(.none)
                Button("Cancel", role: .cancel) { feedUrlInput = "" }
                Button("Subscribe") {
                    let url = feedUrlInput.trimmingCharacters(in: .whitespaces)
                    feedUrlInput = ""
                    subscribe(feedUrl: url)
                }
            } message: {
                Text("Paste a podcast RSS feed URL.")
            }
            .onChange(of: searchText) { _, newValue in
                // Debounced search
                searchTask?.cancel()
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                    podcastManager.searchResults = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    await podcastManager.searchPodcasts(query: newValue)
                }
            }
        }
    }

    private func performSearch() {
        searchTask?.cancel()
        Task {
            await podcastManager.searchPodcasts(query: searchText)
        }
    }

    private func subscribe(feedUrl: String) {
        subscribingFeedUrl = feedUrl
        Task {
            await podcastManager.addPodcast(feedUrl: feedUrl, modelContext: modelContext, userID: userID)
            subscribingFeedUrl = nil
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let isSubscribing: Bool
    let onSubscribe: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: result.artworkUrl)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(Image(systemName: "headphones").foregroundColor(.secondary))
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(result.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !result.genre.isEmpty {
                    Text(result.genre)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isSubscribed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            } else if isSubscribing {
                ProgressView()
            } else {
                Button(action: onSubscribe) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
