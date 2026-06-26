import SwiftUI
import SwiftData
import Supabase

enum PodcastTab: String, CaseIterable {
    case newEpisodes = "New Episodes"
    case shows = "Shows"
}

enum PodcastSortOption: String, CaseIterable, Identifiable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case durationLongest = "Duration (Longest)"
    case durationShortest = "Duration (Shortest)"
    case showName = "Show Name"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .newest: return "calendar.badge.clock"
        case .oldest: return "calendar"
        case .durationLongest: return "clock.arrow.2.circlepath"
        case .durationShortest: return "clock"
        case .showName: return "text.justify.left"
        }
    }
}

struct PodcastListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AuthManager.self) private var authManager
    @Query(sort: \PodcastShow.addedAt, order: .reverse) private var shows: [PodcastShow]
    @Query(sort: \PodcastEpisode.publishedDate, order: .reverse) private var allEpisodes: [PodcastEpisode]
    @Query(sort: \Favorite.createdAt, order: .reverse) private var allFavorites: [Favorite]

    @State private var podcastManager = PodcastManager()
    @State private var showAddSheet = false
    @State private var showSessionSetup = false
    @State private var sessionEpisodes: [PodcastEpisode]?
    @State private var sessionMinutes: Int = 30
    @State private var sessionResumeIndex: Int = 0
    @State private var resumableSession: (episodeIDs: [String], currentIndex: Int, minutes: Int)? = nil
    @State private var selectedTab: PodcastTab = .newEpisodes
    @State private var isRefreshing = false
    @State private var filterUnplayedOnly = false
    @State private var filterFavoritesOnly = false
    @State private var sortOption: PodcastSortOption = .newest
    @State private var selectedEpisodeID: PodcastEpisode.ID?
    @State private var selectedShowID: PodcastShow.ID?

    private var usesMasterDetail: Bool {
        AdaptiveLayoutPolicy.usesLibraryMasterDetail(horizontalSizeClass: horizontalSizeClass)
    }

    private var userShows: [PodcastShow] {
        guard let userID = authManager.currentUser else { return [] }
        let normalizedUserID = userID.lowercased()
        return shows.filter { $0.userID?.lowercased() == normalizedUserID }
    }

    private var userEpisodes: [PodcastEpisode] {
        let showIDs = Set(userShows.map(\.id))
        return allEpisodes.filter { episode in
            guard let showID = episode.show?.id else { return false }
            return showIDs.contains(showID)
        }
    }

    private var selectedEpisode: PodcastEpisode? {
        if let selectedEpisodeID,
           let episode = userEpisodes.first(where: { $0.id == selectedEpisodeID }) {
            return episode
        }
        return nil
    }

    private var selectedShow: PodcastShow? {
        if let selectedShowID,
           let show = userShows.first(where: { $0.id == selectedShowID }) {
            return show
        }
        return nil
    }

    private var hasActiveListFilter: Bool {
        filterUnplayedOnly || filterFavoritesOnly
    }

    private var podcastFavoritesIndex: PodcastFavoriteURL.Index {
        guard let userID = authManager.currentUser else { return .init() }
        return PodcastFavoriteURL.Index.build(from: allFavorites, userID: userID)
    }

    private var listRefreshToken: String {
        [
            selectedTab.rawValue,
            sortOption.rawValue,
            filterFavoritesOnly ? "fav" : "all",
            filterUnplayedOnly ? "unplayed" : "any",
            String(userEpisodes.count),
            String(userShows.count),
            String(allFavorites.count),
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !userShows.isEmpty {
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
                if userShows.isEmpty {
                    ContentUnavailableView {
                        Label("No Podcasts", systemImage: "headphones")
                    } description: {
                        Text("Search for podcasts to subscribe.")
                    } actions: {
                        Button("Find Podcasts") { showAddSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    if usesMasterDetail {
                        podcastMasterDetailContent
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
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button(action: { Task { await refreshAllPodcasts(showProgress: true) } }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    
                    Menu {
                        Section("Filter") {
                            Toggle("Favorites Only", isOn: $filterFavoritesOnly)
                            Toggle("Unplayed Only", isOn: $filterUnplayedOnly)
                        }
                        
                        Section("Sort") {
                            ForEach(PodcastSortOption.allCases) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    if sortOption == option {
                                        Label(option.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(option.rawValue)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: hasActiveListFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(hasActiveListFilter ? .blue : .primary)
                    }
                    
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PodcastSearchSheet(
                podcastManager: podcastManager,
                modelContext: modelContext,
                subscribedFeedUrls: Set(userShows.map { $0.feedUrl }),
                userID: authManager.currentUser,
                onDismiss: { showAddSheet = false }
            )
        }
        .sheet(isPresented: $showSessionSetup) {
            PodcastSessionSetupSheet(
                shows: userShows,
                onStart: { episodes, minutes in
                    showSessionSetup = false
                    sessionMinutes = minutes
                    sessionResumeIndex = 0
                    sessionEpisodes = episodes
                },
                onDismiss: { showSessionSetup = false }
            )
        }
        .navigationDestination(isPresented: Binding(
            get: { sessionEpisodes != nil },
            set: { if !$0 { sessionEpisodes = nil } }
        )) {
            if let episodes = sessionEpisodes {
                PodcastSessionView(
                    initialEpisodes: episodes,
                    sessionMinutes: sessionMinutes,
                    resumingFromIndex: sessionResumeIndex
                )
            }
        }
        .onAppear {
            checkForResumableSession()
            reconcilePodcastSelection()
        }
        .task {
            await refreshAllPodcastsIfStale()
        }
        .onChange(of: selectedTab) { _, _ in
            reconcilePodcastSelection()
        }
        .onChange(of: filteredEpisodes.map(\.id)) { _, _ in
            reconcilePodcastSelection()
        }
        .onChange(of: filteredShows.map(\.id)) { _, _ in
            reconcilePodcastSelection()
        }
        .refreshable {
            await refreshAllPodcasts(showProgress: false)
        }
    }

    private static let lastFullRefreshKey = "podcastLastFullRefresh"
    private static let fullRefreshInterval: TimeInterval = 30 * 60

    // MARK: - New Episodes Tab

    private var podcastMasterDetailContent: some View {
        HStack(spacing: 0) {
            podcastSidebarContent
                .frame(width: 390)

            Divider()

            Group {
                switch selectedTab {
                case .newEpisodes:
                    if let selectedEpisode {
                        PodcastPlayerView(episode: selectedEpisode)
                            .id(selectedEpisode.id)
                    } else {
                        ContentUnavailableView(
                            "Select an Episode",
                            systemImage: "waveform",
                            description: Text("Choose an episode to listen or study.")
                        )
                    }
                case .shows:
                    if let selectedShow {
                        PodcastShowView(show: selectedShow)
                            .id(selectedShow.id)
                    } else {
                        ContentUnavailableView(
                            "Select a Show",
                            systemImage: "headphones",
                            description: Text("Choose a show to browse episodes.")
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var podcastSidebarContent: some View {
        Group {
            switch selectedTab {
            case .newEpisodes:
                masterDetailEpisodesList
            case .shows:
                masterDetailShowsList
            }
        }
    }

    private var masterDetailEpisodesList: some View {
        Group {
            if userEpisodes.isEmpty {
                ContentUnavailableView {
                    Label("No Episodes", systemImage: "waveform")
                } description: {
                    Text("Episodes from your subscribed shows will appear here.")
                }
            } else if filteredEpisodes.isEmpty && hasActiveListFilter {
                ContentUnavailableView {
                    Label("No Matching Episodes", systemImage: filterFavoritesOnly ? "heart.slash" : "waveform")
                } description: {
                    Text(filterFavoritesOnly
                         ? "Favorite episodes from the player toolbar will appear here."
                         : "Try turning off filters to see more episodes.")
                }
            } else {
                List {
                    podcastSessionActionsSection

                    Section {
                        ForEach(filteredEpisodes) { episode in
                            Button {
                                selectedEpisodeID = episode.id
                            } label: {
                                NewEpisodeRow(episode: episode)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                selectedEpisodeID == episode.id
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                        }
                    }
                }
                .id(listRefreshToken)
                .listStyle(.plain)
            }
        }
    }

    private var masterDetailShowsList: some View {
        Group {
            if filteredShows.isEmpty && filterFavoritesOnly {
                ContentUnavailableView {
                    Label("No Favorite Shows", systemImage: "heart.slash")
                } description: {
                    Text("Favorite a show from its detail page to see it here.")
                }
            } else {
                List {
                    ForEach(filteredShows) { show in
                        Button {
                            selectedShowID = show.id
                        } label: {
                            PodcastShowRow(show: show)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedShowID == show.id
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                    }
                    .onDelete(perform: deleteShows)
                }
                .id(listRefreshToken)
                .listStyle(.plain)
            }
        }
    }

    private var newEpisodesView: some View {
        Group {
            if userEpisodes.isEmpty {
                ContentUnavailableView {
                    Label("No Episodes", systemImage: "waveform")
                } description: {
                    Text("Episodes from your subscribed shows will appear here.")
                }
            } else if filteredEpisodes.isEmpty && hasActiveListFilter {
                ContentUnavailableView {
                    Label("No Matching Episodes", systemImage: filterFavoritesOnly ? "heart.slash" : "waveform")
                } description: {
                    Text(filterFavoritesOnly
                         ? "Favorite episodes from the player toolbar will appear here."
                         : "Try turning off filters to see more episodes.")
                }
            } else {
                List {
                    podcastSessionActionsSection

                    // Episodes
                    Section {
                        ForEach(filteredEpisodes) { episode in
                            NavigationLink(destination: PodcastPlayerView(episode: episode)) {
                                NewEpisodeRow(episode: episode)
                            }
                        }
                    }
                }
                .id(listRefreshToken)
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var podcastSessionActionsSection: some View {
        if let saved = resumableSession {
            Section {
                HStack(spacing: 12) {
                    Button { resumeSession() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Resume Session")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Episode \(saved.currentIndex + 1) of \(saved.episodeIDs.count) · \(saved.minutes) min goal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    Button {
                        discardSavedSession()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        Section {
            Button {
                showSessionSetup = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start Listening Session")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Pick shows & set a time goal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Shows Tab

    private var filteredEpisodes: [PodcastEpisode] {
        var result = userEpisodes

        if filterFavoritesOnly {
            let index = podcastFavoritesIndex
            result = result.filter { index.matchesFavoritedEpisode($0) }
        }

        if filterUnplayedOnly {
            result = result.filter { !$0.isPlayed }
        }

        result.sort { lhs, rhs in
            switch sortOption {
            case .newest:
                if lhs.publishedDate != rhs.publishedDate {
                    return lhs.publishedDate > rhs.publishedDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .oldest:
                if lhs.publishedDate != rhs.publishedDate {
                    return lhs.publishedDate < rhs.publishedDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .durationLongest:
                if lhs.duration != rhs.duration {
                    return lhs.duration > rhs.duration
                }
                return lhs.publishedDate > rhs.publishedDate
            case .durationShortest:
                if lhs.duration != rhs.duration {
                    return lhs.duration < rhs.duration
                }
                return lhs.publishedDate > rhs.publishedDate
            case .showName:
                let left = lhs.show?.title ?? ""
                let right = rhs.show?.title ?? ""
                if left != right {
                    return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
                }
                return lhs.publishedDate > rhs.publishedDate
            }
        }

        return result
    }

    private var filteredShows: [PodcastShow] {
        var result = userShows

        if filterFavoritesOnly {
            let index = podcastFavoritesIndex
            result = result.filter { index.matches($0) }
        }

        result.sort { lhs, rhs in
            switch sortOption {
            case .newest:
                if lhs.addedAt != rhs.addedAt {
                    return lhs.addedAt > rhs.addedAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .oldest:
                if lhs.addedAt != rhs.addedAt {
                    return lhs.addedAt < rhs.addedAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .durationLongest:
                let leftCount = lhs.episodes.count
                let rightCount = rhs.episodes.count
                if leftCount != rightCount {
                    return leftCount > rightCount
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .durationShortest:
                let leftCount = lhs.episodes.count
                let rightCount = rhs.episodes.count
                if leftCount != rightCount {
                    return leftCount < rightCount
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .showName:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        return result
    }

    private var showsView: some View {
        Group {
            if filteredShows.isEmpty && filterFavoritesOnly {
                ContentUnavailableView {
                    Label("No Favorite Shows", systemImage: "heart.slash")
                } description: {
                    Text("Favorite a show from its detail page to see it here.")
                }
            } else {
                List {
                    ForEach(filteredShows) { show in
                        NavigationLink(destination: PodcastShowView(show: show)) {
                            PodcastShowRow(show: show)
                        }
                    }
                    .onDelete(perform: deleteShows)
                }
                .id(listRefreshToken)
                .listStyle(.plain)
            }
        }
    }

    private func refreshAllPodcastsIfStale() async {
        let lastRefresh = UserDefaults.standard.object(forKey: Self.lastFullRefreshKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastRefresh) > Self.fullRefreshInterval else { return }
        await refreshAllPodcasts(showProgress: false)
        UserDefaults.standard.set(Date(), forKey: Self.lastFullRefreshKey)
    }

    private func refreshAllPodcasts(showProgress: Bool) async {
        guard !isRefreshing else { return }
        if showProgress { isRefreshing = true }
        defer { if showProgress { isRefreshing = false } }

        // Sequential refresh — ModelContext is not thread-safe.
        for show in userShows {
            await podcastManager.refreshEpisodes(for: show, modelContext: modelContext)
        }
    }

    private func checkForResumableSession() {
        guard let ids = UserDefaults.standard.stringArray(forKey: "podcastSession.episodeIDs"),
              !ids.isEmpty else {
            resumableSession = nil
            return
        }
        let index = UserDefaults.standard.integer(forKey: "podcastSession.currentIndex")
        let minutes = UserDefaults.standard.integer(forKey: "podcastSession.minutes")
        resumableSession = (episodeIDs: ids, currentIndex: index, minutes: minutes > 0 ? minutes : 30)
    }

    private func resumeSession() {
        guard let saved = resumableSession else { return }
        let idSet = Set(saved.episodeIDs)
        let episodeMap = Dictionary(
            uniqueKeysWithValues: userEpisodes
                .filter { idSet.contains($0.id.uuidString) }
                .map { ($0.id.uuidString, $0) }
        )
        let orderedEpisodes = saved.episodeIDs.compactMap { episodeMap[$0] }
        guard !orderedEpisodes.isEmpty else {
            discardSavedSession()
            return
        }
        resumableSession = nil
        sessionMinutes = saved.minutes
        sessionResumeIndex = min(saved.currentIndex, orderedEpisodes.count - 1)
        sessionEpisodes = orderedEpisodes
    }

    private func discardSavedSession() {
        ["podcastSession.episodeIDs", "podcastSession.currentIndex",
         "podcastSession.minutes", "podcastSession.startTime"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
        resumableSession = nil
    }

    private func reconcilePodcastSelection() {
        switch selectedTab {
        case .newEpisodes:
            let visibleIDs = Set(filteredEpisodes.map(\.id))
            if let selectedEpisodeID, visibleIDs.contains(selectedEpisodeID) {
                return
            }
            selectedEpisodeID = filteredEpisodes.first?.id
        case .shows:
            let visibleIDs = Set(filteredShows.map(\.id))
            if let selectedShowID, visibleIDs.contains(selectedShowID) {
                return
            }
            selectedShowID = filteredShows.first?.id
        }
    }

    private func deleteShows(at offsets: IndexSet) {
        for index in offsets {
            let show = filteredShows[index]
            let showId = show.id
            modelContext.delete(show)

            // Delete from Supabase so it doesn't come back on sync
            Task {
                try? await authManager.supabase.from("podcast_episodes")
                    .delete()
                    .eq("show_id", value: showId)
                    .execute()
                try? await authManager.supabase.from("podcast_shows")
                    .delete()
                    .eq("id", value: showId)
                    .execute()
            }
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

                HStack(spacing: 6) {
                    Text(episode.publishedDate, style: .date)
                    if episode.duration > 0 {
                        Text("·")
                        Text(formatDuration(episode.duration))
                    }
                    Spacer(minLength: 0)
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
                .font(.caption)
                .foregroundColor(.secondary)
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
