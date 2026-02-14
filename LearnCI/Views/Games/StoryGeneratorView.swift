import SwiftUI
import SwiftData

struct StoryGeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(SyncManager.self) private var syncManager // Added SyncManager to environment
    
    @Binding var navigationPath: NavigationPath
    
    @State private var storyManager = StoryManager()
    @State private var topic: String = ""
    @State private var selectedLevel: Int = 2
    @State private var selectedLanguage: Language = .spanish
    
    var body: some View {
        Form {
            Section("Story Details") {
                TextField("Topic (e.g. 'Ordering Coffee')", text: $topic)
                
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                
                Picker("Level", selection: $selectedLevel) {
                    Text("Beginner (A1/A2)").tag(1)
                    Text("Intermediate (B1/B2)").tag(3)
                    Text("Advanced (C1/C2)").tag(5)
                }
            }
            
            Section {
                Button(action: generate) {
                    if storyManager.isGenerating {
                        HStack {
                            ProgressView()
                            Text("Generating...")
                        }
                    } else {
                        Text("Generate Story")
                    }
                }
                .disabled(topic.isEmpty || storyManager.isGenerating)
            }
            
            if let error = storyManager.errorMessage {
                Section("Error") {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("New AI Story")
        .task {
            // Pre-select based on last usage or profile?
            // For now, defaults are fine.
        }
    }
    
    private func generate() {
        Task {
            guard let userID = authManager.currentUser else {
                // Should potentially show an error or redirect to login
                return
            }
            
            if let story = await storyManager.generateStory(
                topic: topic, 
                language: selectedLanguage, 
                level: selectedLevel, 
                context: modelContext,
                userID: userID
            ) {
                // Success! valid story object created.
                // Navigation should happen via the path binding in the parent view
                // or we push to the stack here if we can.
                // For simplicity in this architecture, we might just dismiss or push.
                // Let's verify how the path works or just use a boolean trigger.
                
                // Assuming we want to read it immediately:
                // We'll rely on the parent updating the list, or push manually if we have the path.
                await syncManager.syncNow(modelContext: modelContext) // Call syncNow after story created
                dismiss() 
            }
        }
    }
}
