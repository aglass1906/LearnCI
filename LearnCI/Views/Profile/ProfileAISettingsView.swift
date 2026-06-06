import SwiftUI

struct ProfileAISettingsView: View {
    @Bindable var profile: UserProfile
    @State private var openAIKey: String = ""
    @State private var openAISaved: Bool = false
    @State private var googleKey: String = ""
    @State private var googleSaved: Bool = false
    @AppStorage(VideoPromptModel.userDefaultsKey) private var videoPromptModel: String = VideoPromptModel.openAI.rawValue

    var body: some View {
        Form {
            // MARK: OpenAI
            Section {
                TextField("sk-...", text: $openAIKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text("Used for story text, audio, cover art, and comprehension quizzes. Stored on-device only.")
            }

            Section {
                Button(action: saveOpenAIKey) {
                    HStack {
                        Text(openAISaved ? "Key Saved" : "Save Key")
                        if openAISaved {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(openAIKey.isEmpty)

                Button("Clear Key", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: "OpenAI_API_Key")
                    openAIKey = ""
                    openAISaved = false
                }
            }

            // MARK: Google / Veo
            Section {
                TextField("AIza...", text: $googleKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Google API Key")
            } footer: {
                Text("Used for AI scene video generation (Veo 3). Charged at \(VideoStyle.ratePerSecond) — approx. \(VideoStyle.estimatedCostRange) per 8-second clip. Stored on-device only.")
            }

            Section {
                Button(action: saveGoogleKey) {
                    HStack {
                        Text(googleSaved ? "Key Saved" : "Save Key")
                        if googleSaved {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(googleKey.isEmpty)

                Button("Clear Key", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: VeoService.userDefaultsKey)
                    googleKey = ""
                    googleSaved = false
                }
            }

            // MARK: Prompt Writing AI
            Section {
                Picker("Prompt Writing AI", selection: $videoPromptModel) {
                    ForEach(VideoPromptModel.allCases) { model in
                        Label(model.rawValue, systemImage: model.icon)
                            .tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Prompt Writing AI")
            } footer: {
                Text("Chooses which AI writes the cinematic text description sent to Veo 3 for video generation. Gemini uses your Google key at no extra cost. OpenAI uses your OpenAI key.")
            }
        }
        .navigationTitle("AI Settings")
        .onAppear {
            if let existing = UserDefaults.standard.string(forKey: "OpenAI_API_Key") {
                openAIKey = existing
                openAISaved = true
            }
            if let existing = UserDefaults.standard.string(forKey: VeoService.userDefaultsKey) {
                googleKey = existing
                googleSaved = true
            }
        }
    }

    private func saveOpenAIKey() {
        UserDefaults.standard.set(openAIKey, forKey: "OpenAI_API_Key")
        openAISaved = true
    }

    private func saveGoogleKey() {
        UserDefaults.standard.set(googleKey, forKey: VeoService.userDefaultsKey)
        googleSaved = true
    }
}
