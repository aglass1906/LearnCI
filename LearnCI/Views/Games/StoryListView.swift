import SwiftUI
import SwiftData

struct StoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Story.createdAt, order: .reverse) var stories: [Story]
    
    @State private var showGenerator = false
    @State private var storyManager = StoryManager()
    @State private var hasKey = false
    @State private var showKeyAlert = false
    
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
                            // Cover Image Thumbnail
                            if let remotePath = story.remoteCoverPath {
                                let coverURL = URL(string: "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories/\(remotePath)")
                                AsyncImage(url: coverURL) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    ZStack {
                                        Color.gray.opacity(0.2)
                                        ProgressView()
                                    }
                                }
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                            } else {
                                // Fallback if no remote cover
                                ZStack {
                                    Color.gray.opacity(0.2)
                                    Text("📚")
                                        .font(.title)
                                }
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                            }
                            
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
                storyManager.deleteStory(story, context: modelContext)
            }
        }
    }
}
