import SwiftUI

struct ProfileAISettingsView: View {
    @Bindable var profile: UserProfile
    @State private var apiKey: String = ""
    @State private var isSaved: Bool = false
    
    var body: some View {
        Form {
            Section {
                SecureField("sk-...", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text("Your API key is stored securely on device and used only for generating stories.")
            }
            
            Section {
                Button(action: saveKey) {
                    HStack {
                        Text(isSaved ? "Key Saved" : "Save Key")
                        if isSaved {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(apiKey.isEmpty)
                
                Button("Clear Key", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: "OpenAI_API_Key")
                    apiKey = ""
                    isSaved = false
                }
            }
        }
        .navigationTitle("AI Settings")
        .onAppear {
            if let existing = UserDefaults.standard.string(forKey: "OpenAI_API_Key") {
                apiKey = existing
                isSaved = true
            }
        }
    }
    
    private func saveKey() {
        UserDefaults.standard.set(apiKey, forKey: "OpenAI_API_Key")
        isSaved = true
    }
}
