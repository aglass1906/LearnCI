import SwiftUI
import SwiftData

struct StoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Story.createdAt, order: .reverse) var stories: [Story]
    
    @State private var showGenerator = false
    @State private var storyManager = StoryManager()
    @State private var hasKey = false
    
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
                .onDelete(perform: deleteStories)
            }
            .navigationTitle("AI Stories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showGenerator = true }) {
                        Label("New Story", systemImage: "plus")
                    }
                    .disabled(!hasKey)
                }
                
                if !hasKey {
                    ToolbarItem(placement: .status) {
                        Text("Add OpenAI Key in Profile to Generate")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
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
