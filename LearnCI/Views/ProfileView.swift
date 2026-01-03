import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(YouTubeManager.self) private var youtubeManager
    @Query private var profiles: [UserProfile]
    
    @State private var name: String = ""
    @State private var selectedLanguage: Language = .spanish
    @State private var selectedLevel: LearningLevel = .superBeginner
    @State private var dailyGoal: Double = 30
    @State private var dailyCardGoal: Double = 20
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("User Info")) {
                    TextField("Name", text: $name)
                    
                    Picker("Target Language", selection: $selectedLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text("\(lang.flag) \(lang.rawValue)").tag(lang)
                        }
                    }
                    
                    Picker("Current Level", selection: $selectedLevel) {
                        ForEach(LearningLevel.allCases) { level in
                            Text("\(level.rawValue) (\(level.cerCode))").tag(level)
                        }
                    }
                }
                
                Section(header: Text("Goals")) {
                    VStack(alignment: .leading) {
                        Text("Daily Time Goal: \(Int(dailyGoal)) minutes")
                        Slider(value: $dailyGoal, in: 10...120, step: 5)
                    }
                    
                    Stepper("Daily Card Goal: \(Int(dailyCardGoal))", value: $dailyCardGoal, in: 5...100, step: 5)
                }
                
                Section(header: Text("YouTube Connection")) {
                    if youtubeManager.isAuthenticated {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Connected")
                                        .font(.headline)
                                    if let account = youtubeManager.youtubeAccount {
                                        Text(account)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                            
                            Button("Disconnect", role: .destructive) {
                                youtubeManager.disconnect()
                            }
                            .font(.subheadline)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if youtubeManager.isLoading {
                                HStack {
                                    ProgressView()
                                    Text("Signing in...")
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Connect your YouTube account to browse and track videos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button(action: { 
                                    Task {
                                        await youtubeManager.signInWithGoogle()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "play.rectangle.fill")
                                        Text("Sign in with Google")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                
                                if let error = youtubeManager.errorMessage {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button("Save Changes") {
                        saveProfile()
                    }
                    .disabled(profiles.isEmpty)
                }
            }
            .navigationTitle("Profile")
            .onAppear {
                if let profile = profiles.first {
                    name = profile.name
                    selectedLanguage = profile.currentLanguage
                    selectedLevel = profile.currentLevel
                    dailyGoal = Double(profile.dailyGoalMinutes)
                    dailyCardGoal = Double(profile.dailyCardGoal ?? 20)
                } else {
                    // Create default if none exists
                    let newProfile = UserProfile()
                    modelContext.insert(newProfile)
                    // We'll let the query update refresh the view on next loop or manually set it?
                    // SwiftData query updates immediately usually.
                }
            }
        }
    }
    
    func saveProfile() {
        if let profile = profiles.first {
            profile.name = name
            profile.currentLanguage = selectedLanguage
            profile.currentLevel = selectedLevel
            profile.dailyGoalMinutes = Int(dailyGoal)
            profile.dailyCardGoal = Int(dailyCardGoal)
            
            // Should auto-save context in SwiftData, but explicit sometimes helps debugging.
        }
    }
}
