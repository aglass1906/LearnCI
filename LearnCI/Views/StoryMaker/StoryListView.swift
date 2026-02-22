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
    @Query(sort: \Story.createdAt, order: .reverse) var stories: [Story]
    
    @State private var showGenerator = false
    @State private var storyManager = StoryManager()
    @State private var hasKey = false
    @State private var showKeyAlert = false
    
    init(userID: String? = nil) {
        // No filtering - show all stories
    }
    
    var body: some View {
        NavigationStack {
            List {
                if stories.isEmpty {
                    ContentUnavailableView(
                        "No Stories Yet",
                        systemImage: "book",
                        description: Text("Generate your first AI audio story to get started.")
                    )
                }
                
                ForEach(stories) { story in
                    NavigationLink(destination: StorySessionView(story: story)) {
                        HStack(spacing: 12) {
                            // Cover Image Thumbnail - prefer local file, fall back to remote
                            StoryThumbnailView(story: story)
                            
                            // Story Info
                            VStack(alignment: .leading) {
                                Text(story.title)
                                    .font(.headline)
                                HStack {
                                    Text(story.language.displayName)
                                    Text("•")
                                    Text("Level \(story.level)")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteStories)
            }
            .navigationTitle("AI Stories")
            .toolbar {
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
