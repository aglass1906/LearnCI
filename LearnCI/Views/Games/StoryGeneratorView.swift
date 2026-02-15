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
    @State private var preferences = StoryPreferences()
    @State private var showAdvancedOptions: Bool = false
    
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
                    ForEach(1...6, id: \.self) { level in
                        Text(storyManager.describeLevel(level)).tag(level)
                    }
                }
            }
            
            Section("Story Style") {
                Picker("Cover Art Style", selection: $preferences.coverArtStyle) {
                    ForEach(StoryPreferences.CoverArtStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                
                Picker("Genre", selection: $preferences.genre) {
                    ForEach(StoryPreferences.Genre.allCases) { genre in
                        Text(genre.rawValue).tag(genre)
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("Tone: \(preferences.humorLevel < 0.3 ? "Humorous" : (preferences.humorLevel > 0.7 ? "Serious" : "Balanced"))")
                    Slider(value: $preferences.humorLevel, in: 0...1) {
                        Text("Tone")
                    } minimumValueLabel: {
                        Text("Funny")
                    } maximumValueLabel: {
                        Text("Serious")
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("Setting: \(preferences.realismLevel < 0.3 ? "Daily Life" : (preferences.realismLevel > 0.7 ? "Sci-Fi" : "Modern + Twist"))")
                    Slider(value: $preferences.realismLevel, in: 0...1) {
                        Text("Setting")
                    } minimumValueLabel: {
                        Text("Real")
                    } maximumValueLabel: {
                        Text("Sci-Fi")
                    }
                }
            }
            
            Section("Advanced Options") {
                DisclosureGroup("Show Advanced Options", isExpanded: $showAdvancedOptions) {
                    // Protagonist
                    Group {
                        Text("Protagonist").font(.caption).foregroundStyle(.secondary)
                        TextField("Protagonist Name (Optional)", text: $preferences.protagonistName)
                        Picker("Gender", selection: $preferences.protagonistGender) {
                            ForEach(StoryPreferences.Gender.allCases) { gender in
                                Text(gender.rawValue).tag(gender)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Story Structure
                    Group {
                        Text("Story Structure").font(.caption).foregroundStyle(.secondary)
                        Picker("Length", selection: $preferences.storyLength) {
                            ForEach(StoryPreferences.StoryLength.allCases) { length in
                                Text(length.rawValue).tag(length)
                            }
                        }
                        
                        Picker("Ending Style", selection: $preferences.endingType) {
                            ForEach(StoryPreferences.EndingType.allCases) { ending in
                                Text(ending.rawValue).tag(ending)
                            }
                        }
                        
                        Picker("Dialogue Amount", selection: $preferences.dialogueAmount) {
                            ForEach(StoryPreferences.DialogueAmount.allCases) { amount in
                                Text(amount.rawValue).tag(amount)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Pedagogical Controls
                    Group {
                        Text("Learning Goals").font(.caption).foregroundStyle(.secondary)
                        TextField("Target Vocabulary (comma separated)", text: $preferences.targetVocabulary)
                        TextField("Grammar Focus (e.g. Past Tense)", text: $preferences.grammarFocus)
                    }
                    
                    Divider()
                    
                    // Audio
                    Group {
                        Text("Audio Settings").font(.caption).foregroundStyle(.secondary)
                        Picker("Voice", selection: $preferences.voice) {
                            ForEach(StoryPreferences.Voice.allCases) { voice in
                                Text(voice.displayName).tag(voice)
                            }
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Audio Speed: \(String(format: "%.1fx", preferences.audioSpeed))")
                            Slider(value: $preferences.audioSpeed, in: 0.5...1.5, step: 0.1)
                        }
                        
                        Toggle("Interactive Audio (Shadowing)", isOn: $preferences.interactiveAudio)
                    }
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
                preferences: preferences,
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
