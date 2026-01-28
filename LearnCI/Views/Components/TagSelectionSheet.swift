import SwiftUI

struct TagSelectionSheet: View {
    let language: Language
    @Binding var selectedDeck: DeckMetadata?
    @Environment(\.dismiss) var dismiss
    @Environment(DataManager.self) private var dataManager
    
    @State private var tags: [(name: String, count: Int)] = []
    @State private var isLoading = true
    @State private var selectedTag: String?
    
    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 12)
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    if isLoading {
                        ProgressView("Scanning decks...")
                            .padding(.top, 40)
                    } else if tags.isEmpty {
                        ContentUnavailableView("No Tags Found", systemImage: "tag.slash", description: Text("No subject tags were found for this language."))
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(tags, id: \.name) { tag in
                                Button {
                                    selectedTag = tag.name
                                } label: {
                                    VStack {
                                        Image(systemName: "tag.fill")
                                            .font(.title2)
                                            .foregroundStyle(selectedTag == tag.name ? .white : .accentColor)
                                            .padding(.bottom, 4)
                                        
                                        Text(tag.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(selectedTag == tag.name ? .white : .primary)
                                            .multilineTextAlignment(.center)
                                        
                                        Text("\(tag.count)")
                                            .font(.caption2)
                                            .foregroundStyle(selectedTag == tag.name ? .white.opacity(0.8) : .secondary)
                                            .padding(.top, 2)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 100)
                                    .background {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedTag == tag.name ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
                                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(selectedTag == tag.name ? Color.accentColor : Color.clear, lineWidth: 2)
                                            )
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
                
                // Bottom Bar
                if !isLoading && !tags.isEmpty {
                    VStack(spacing: 12) {
                        Divider()
                        
                        if let selected = selectedTag, let tagData = tags.first(where: { $0.name == selected }) {
                             Text("\(tagData.count) cards selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Select a tag")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button(action: {
                            if let tag = selectedTag {
                                confirmSelection(tag)
                            }
                        }) {
                            Text("Done")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(selectedTag != nil ? Color.accentColor : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(selectedTag == nil)
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .background(Color(UIColor.systemBackground))
                }
            }
            .navigationTitle("Select Topic")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(UIColor.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                loadTags()
            }
        }
    }
    
    private func loadTags() {
        let manager = dataManager
        Task {
            let discovered = manager.discoverTags(language: language)
            await MainActor.run {
                // Sort by count descending, then name ascending
                self.tags = discovered.map { ($0.key, $0.value) }
                    .sorted {
                        if $0.count == $1.count {
                            return $0.name < $1.name
                        }
                        return $0.count > $1.count
                    }
                self.isLoading = false
            }
        }
    }
    
    private func confirmSelection(_ tag: String) {
        let virtualDeck = dataManager.createVirtualDeck(tag: tag, language: language)
        
        let metadata = DeckMetadata(
            id: virtualDeck.id,
            title: virtualDeck.title,
            language: virtualDeck.language,
            level: virtualDeck.level,
            folderName: "Virtual",
            filename: "",
            supportedModes: virtualDeck.supportedModes ?? [],
            gameConfiguration: nil,
            coverImage: "tag.fill"
        )
        
        dataManager.registerVirtualDeck(virtualDeck)
        selectedDeck = metadata
        dismiss()
    }
}
