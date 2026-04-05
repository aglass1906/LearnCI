import SwiftUI
import SwiftData

// MARK: - Story Thumbnail (local-first, caches remote downloads)

private struct StoryThumbnailView: View {
    let story: Story
    @State private var localImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ZStack {
                    Color.gray.opacity(0.2)
                    ProgressView()
                }
            } else {
                ZStack {
                    Color.gray.opacity(0.2)
                    Text("📚")
                        .font(.title)
                }
            }
        }
        .frame(width: 60, height: 60)
        .cornerRadius(8)
        .task(id: story.id) {
            await loadImage()
        }
    }

    private func loadImage() async {
        // 1. Try local cover file
        if let coverFilename = story.coverArt {
            let localURL = documentsDirectory.appendingPathComponent(coverFilename)
            if let image = UIImage(contentsOfFile: localURL.path) {
                localImage = image
                return
            }
        }

        // 2. Download from remote and cache locally
        guard let remotePath = story.remoteCoverPath else { return }
        guard let remoteURL = URL(string: "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories/\(remotePath)") else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            guard let image = UIImage(data: data) else { return }

            // Cache to local documents
            let filename = "cover_\(story.id.uuidString).png"
            let localURL = documentsDirectory.appendingPathComponent(filename)
            try data.write(to: localURL)

            // Update the story model so future loads use the local file
            story.coverArt = filename

            localImage = image
        } catch {
            print("Failed to download story cover: \(error)")
        }
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Story List

struct StoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(SyncManager.self) private var syncManager
    @Query(sort: \Story.updatedAt, order: .reverse) var stories: [Story]
    
    @State private var showGenerator = false
    @State private var storyManager = StoryManager()
    @State private var hasKey = false
    @State private var showKeyAlert = false
    
    // Filters & Sorting
    @State private var sortOption: SortOption = .newest
    @State private var selectedLanguage: String = "All"
    @State private var selectedStoryType: String = "All"
    
    enum SortOption: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case alphabetical = "A-Z"
        
        var id: String { rawValue }
    }
    
    private var filteredStories: [Story] {
        var result = stories

        // Filter by Language
        if selectedLanguage != "All" {
            result = result.filter { $0.language.displayName == selectedLanguage }
        }

        // Filter by Story Type
        if selectedStoryType != "All" {
            result = result.filter { $0.preferences.storyType.rawValue == selectedStoryType }
        }

        // Sort
        switch sortOption {
        case .newest:
            result.sort { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
        case .oldest:
            result.sort { ($0.updatedAt ?? $0.createdAt) < ($1.updatedAt ?? $1.createdAt) }
        case .alphabetical:
            result.sort { $0.title < $1.title }
        }

        return result
    }

    private var isFiltered: Bool { selectedLanguage != "All" || selectedStoryType != "All" }

    private var availableLanguages: [String] {
        let langs = Set(stories.map { $0.language.displayName })
        return ["All"] + langs.sorted()
    }
    
    var body: some View {
        NavigationStack {
            List {
                if filteredStories.isEmpty {
                    ContentUnavailableView(
                        isFiltered ? "No Matching Stories" : "No Stories Yet",
                        systemImage: "book",
                        description: Text(isFiltered ? "Try clearing your filters." : "Generate your first AI audio story to get started.")
                    )
                }
                
                ForEach(filteredStories) { story in
                    NavigationLink(destination: StoryAboutView(story: story)) {
                        HStack(spacing: 12) {
                            // Cover Image Thumbnail
                            StoryThumbnailView(story: story)
                            
                            // Story Info
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(story.title)
                                        .font(.headline)
                                        
                                    let isCloud = (story.remoteAudioPath != nil || story.remoteCoverPath != nil || story.remoteVideoPath != nil)
                                    Image(systemName: isCloud ? "cloud" : "iphone")
                                        .font(.caption)
                                        .foregroundStyle(isCloud ? .blue : .gray)
                                        
                                    if story.preferences.interactiveAudio {
                                        Image(systemName: "sparkles")
                                            .font(.caption)
                                            .foregroundStyle(.purple)
                                    }
                                }
                                HStack(spacing: 4) {
                                    Text(story.language.displayName)
                                    Text("·")
                                    Text("Level \(story.level)")
                                    Text("·")
                                    Text(story.preferences.genre.rawValue)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                
                                let isDramatized = story.preferences.audioStyle == .dramatized
                                HStack(spacing: 8) {
                                    if !story.chapters.isEmpty {
                                        Label("\(story.chapters.count) ch", systemImage: "book.pages")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundStyle(.blue)
                                            .cornerRadius(4)
                                    }
                                    Label(
                                        isDramatized ? "Dramatized" : "Single Voice",
                                        systemImage: isDramatized ? "person.2.fill" : "person.fill"
                                    )
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isDramatized ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
                                    .foregroundStyle(isDramatized ? .orange : .secondary)
                                    .cornerRadius(4)
                                }
                                let storyType = story.preferences.storyType
                                let typeColor: Color = {
                                    switch storyType {
                                    case .storyBook:   return .blue
                                    case .audioBook:   return .teal
                                    case .interactive: return .purple
                                    case .standard:    return .gray
                                    }
                                }()
                                Label(storyType.rawValue, systemImage: storyType.icon)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(typeColor.opacity(0.1))
                                    .foregroundStyle(typeColor)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteStories)
            }
            .navigationTitle("AI Stories")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }

                        Divider()

                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(availableLanguages, id: \.self) { lang in
                                Text(lang).tag(lang)
                            }
                        }

                        Divider()

                        Picker("Story Type", selection: $selectedStoryType) {
                            Text("All Types").tag("All")
                            ForEach(StoryPreferences.StoryType.allCases) { type in
                                Label(type.rawValue, systemImage: type.icon).tag(type.rawValue)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                            .symbolEffect(.bounce, value: isFiltered)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Task {
                            await syncManager.syncNow(modelContext: modelContext)
                        }
                    }) {
                        if syncManager.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .symbolEffect(.bounce, value: syncManager.isSyncing)
                        }
                    }
                    .disabled(syncManager.isSyncing)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { 
                        if hasKey {
                            showGenerator = true 
                        } else {
                            showKeyAlert = true
                        }
                    }) {
                        Label("New Story", systemImage: "plus")
                    }
                }
            }
            .alert("OpenAI Key Required", isPresented: $showKeyAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please add your OpenAI API Key in your Profile settings to generate stories.")
            }
            .sheet(isPresented: $showGenerator) {
                NavigationStack {
                    StoryGeneratorView(navigationPath: .constant(NavigationPath()))
                }
            }
            .task {
                hasKey = await storyManager.hasAPIKey()
            }
        }
    }
    
    private func deleteStories(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let story = stories[index]
                // Only allow deleting own stories
                if let currentUserID = authManager.currentUser, story.userID == currentUserID {
                    storyManager.deleteStory(story, context: modelContext)
                }
            }
        }
    }
}
