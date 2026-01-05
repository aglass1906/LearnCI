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
                            
                            Button(action: {
                                locationManager.requestLocationAndAddress()
                            }) {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        if locationManager.isLoading {
                            Text("Locating...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let error = locationManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
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
                
                Section(header: Text("Game Settings")) {
                    Picker("Default Card Display", selection: $selectedGamePreset) {
                        ForEach(GameConfiguration.Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                }
                
                Section(header: Text("YouTube Connection")) {
                    // ... (Existing YouTube Section)
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
                
                Section(header: Text("Learning History")) {
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
                
                Section {
                    Button("Save Changes") {
                        saveProfile()
                    }
                    .disabled(profiles.isEmpty)
                }
                
                Section(header: Text("Account")) {
                    Button("Sign Out", role: .destructive) {
                        authManager.signOut()
                    }
                }
            }
            .navigationTitle("Profile")
            .onChange(of: locationManager.locationString) { _, newLocation in
                if let loc = newLocation {
                    location = loc
                }
            }
            .onAppear {
                if let profile = profiles.first {
                    name = profile.name
                    location = profile.location ?? ""
                    selectedLanguage = profile.currentLanguage
                    selectedLevel = profile.currentLevel
                    dailyGoal = Double(profile.dailyGoalMinutes)
                    dailyCardGoal = Double(profile.dailyCardGoal ?? 20)
                    selectedGamePreset = profile.defaultGamePreset
                    startingHours = profile.startingHours
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
