import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(YouTubeManager.self) private var youtubeManager
    @Environment(AuthManager.self) private var authManager
    @Environment(LocationManager.self) private var locationManager
    @Query private var allProfiles: [UserProfile]
    
    var profiles: [UserProfile] {
        allProfiles.filter { $0.userID == authManager.currentUser }
    }
    
    @State private var name: String = ""
    @State private var location: String = ""
    @State private var selectedLanguage: Language = .spanish
    @State private var selectedLevel: LearningLevel = .superBeginner
    @State private var dailyGoal: Double = 30
    @State private var dailyCardGoal: Double = 20
    @State private var selectedGamePreset: GameConfiguration.Preset = .inputFocus
    @State private var startingHours: Int = 0
    @State private var ttsRate: Float = 0.5
    @State private var isEditing: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                // ... (Existing Google Account Section)
                if let email = authManager.currentUserEmail {
                    Section(header: Text("Google Account")) {
                        LabeledContent("Email", value: email)
                        if let fullName = authManager.currentUserFullName {
                            LabeledContent("Full Name", value: fullName)
                        }
                    }
                }
                
                Section(header: Text("Public Profile")) {
                    TextField("Display Name", text: $name)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Location", text: $location)
                                .textContentType(.location)
                            
                            if isEditing {
                                Button(action: {
                                    locationManager.requestLocationAndAddress()
                                }) {
                                    Image(systemName: "location.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        
                        // ... location status text ...
                    }
                    

                }
                .disabled(!isEditing)
                
                Section(header: Text("Language Learning")) {
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
                    
                    VStack(alignment: .leading) {
                        Text("Daily Time Goal: \(Int(dailyGoal)) minutes")
                        Slider(value: $dailyGoal, in: 10...120, step: 5)
                            .tint(isEditing ? .blue : .gray) // Visual cue
                    }
                    
                    HStack {
                        Text("Starting Hours")
                        Spacer()
                        TextField("Hours", value: $startingHours, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    Text("Add your previous learning time to your total.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!isEditing)
                
                Section(header: Text("Game Settings")) {

                    
                    Stepper("Daily Card Goal: \(Int(dailyCardGoal))", value: $dailyCardGoal, in: 5...100, step: 5)
                    
                    Picker("Default Card Display", selection: $selectedGamePreset) {
                        ForEach(GameConfiguration.Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                }
                .disabled(!isEditing)
                
                Section(header: Text("Audio Settings")) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Robot Voice Speed")
                            Spacer()
                            Text(String(format: "%.1fx", ttsRate * 2))
                                .foregroundColor(.secondary)
                                .font(.callout)
                                .monospacedDigit()
                        }
                        
                        Slider(value: $ttsRate, in: 0.1...1.0, step: 0.1) {
                            Text("Confirm")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill")
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill")
                        }
                        .tint(isEditing ? .blue : .gray)
                    }
                }
                .disabled(!isEditing)
                
                Section(header: Text("YouTube Connection")) {
                    // ... (Existing YouTube, always enabled since it has its own auth flow)
                    // We keep this enabled as requested ("not sign out")
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
                                    youtubeManager.signInWithGoogle()
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
                

                
                // Save button removed as it's now in toolbar
                
                Section(header: Text("Account")) {
                    Button("Sign Out", role: .destructive) {
                        authManager.signOut()
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                     if isEditing {
                         Button("Done") {
                             saveProfile()
                             withAnimation { isEditing = false }
                         }
                         .fontWeight(.bold)
                     } else {
                         Button("Edit") {
                             withAnimation { isEditing = true }
                         }
                     }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button("Cancel") {
                            loadProfileData() // Revert
                            withAnimation { isEditing = false }
                        }
                    }
                }
            }
            .onChange(of: locationManager.locationString) { _, newLocation in
                if let loc = newLocation {
                    location = loc
                }
            }
            .onAppear {
               loadProfileData()
            }
        }
    }
    
    func loadProfileData() {
        if let profile = profiles.first {
            name = profile.name
            location = profile.location ?? ""
            selectedLanguage = profile.currentLanguage
            selectedLevel = profile.currentLevel
            dailyGoal = Double(profile.dailyGoalMinutes)
            dailyCardGoal = Double(profile.dailyCardGoal ?? 20)
            selectedGamePreset = profile.defaultGamePreset
            startingHours = profile.startingHours
            ttsRate = profile.ttsRate
        } else {
            // Create profile associated with current user
            if let userID = authManager.currentUser {
                let newProfile = UserProfile(userID: userID)
                newProfile.fullName = authManager.currentUserFullName
                newProfile.email = authManager.currentUserEmail
                newProfile.avatarUrl = authManager.currentUserAvatar
                if let googleName = authManager.currentUserFullName {
                    newProfile.name = googleName // Default display name to full name
                    name = googleName
                }
                
                modelContext.insert(newProfile)
            }
        }
    }
    
    func saveProfile() {
        if let profile = profiles.first {
            profile.name = name
            profile.location = location
            profile.currentLanguage = selectedLanguage
            profile.currentLevel = selectedLevel
            profile.dailyGoalMinutes = Int(dailyGoal)
            profile.dailyCardGoal = Int(dailyCardGoal)
            profile.defaultGamePreset = selectedGamePreset
            profile.startingHours = startingHours
            profile.ttsRate = ttsRate
            
            // Update auth fields if they were missing
            if profile.email == nil { profile.email = authManager.currentUserEmail }
            if profile.fullName == nil { profile.fullName = authManager.currentUserFullName }
            if profile.avatarUrl == nil { profile.avatarUrl = authManager.currentUserAvatar }
            
            profile.updatedAt = Date() // Mark for sync
        }
    }
}

#Preview {
    ProfileView()
        .environment(YouTubeManager())
        .environment(AuthManager())
}
