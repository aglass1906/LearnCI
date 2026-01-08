import SwiftUI

struct AddResourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext // For checking profile language
    
    // Inject ResourceManager from parent
    var resourceManager: ResourceManager
    var currentLanguage: String?
    
    @State private var title = ""
    @State private var author = ""
    @State private var mainUrl = ""
    @State private var description = ""
    @State private var type: ResourceType = .website
    @State private var difficulty = "All Levels"
    
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    
    let difficulties = ["Beginner", "Intermediate", "Advanced", "All Levels"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Author / Creator", text: $author)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Link (URL)", text: $mainUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Resource Details")
                } footer: {
                    Text("Please verify the link works before submitting.")
                }
                
                Section("Categorization") {
                    Picker("Type", selection: $type) {
                        ForEach(ResourceType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(difficulties, id: \.self) { diff in
                            Text(diff).tag(diff)
                        }
                    }
                    
                    if let lang = currentLanguage {
                        HStack {
                            Text("Language")
                            Spacer()
                            Text(lang.uppercased())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                
                Section {
                    Button(action: submitResource) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit for Review")
                                .frame(maxWidth: .infinity)
                                .bold()
                        }
                    }
                    .disabled(title.isEmpty || mainUrl.isEmpty || isSubmitting)
                    .listRowBackground(Color.blue)
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("Add Resource")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    func submitResource() {
        guard let url = URL(string: mainUrl), UIApplication.shared.canOpenURL(url) else {
            errorMessage = "Please enter a valid URL (including https://)"
            return
        }
        
        isSubmitting = true
        errorMessage = nil
        
        Task {
            let success = await resourceManager.submitDraftResource(
                client: authManager.supabase,
                title: title,
                author: author,
                description: description,
                mainUrl: mainUrl,
                type: type,
                difficulty: difficulty,
                language: currentLanguage ?? "es" // Default if missing
            )
            
            if success {
                dismiss()
            } else {
                errorMessage = "Failed to submit. Please try again."
                isSubmitting = false
            }
        }
    }
}

#Preview {
    AddResourceSheet(resourceManager: ResourceManager(), currentLanguage: "es")
        .environment(AuthManager())
}
