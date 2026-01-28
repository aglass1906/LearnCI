import SwiftUI

struct TagSelectionSheet: View {
    let language: Language
    @Binding var selectedDeck: DeckMetadata?
    @Environment(\.dismiss) var dismiss
    @Environment(DataManager.self) private var dataManager
    
    @State private var tags: [String] = []
    @State private var isLoading = true
    
    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 12)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView("Scanning decks...")
                        .padding(.top, 40)
                } else if tags.isEmpty {
                    ContentUnavailableView("No Tags Found", systemImage: "tag.slash", description: Text("No subject tags were found for this language."))
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                selectTag(tag)
                            } label: {
                                VStack {
                                    Image(systemName: "tag.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .padding(.bottom, 4)
                                    
                                    Text(tag)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                                .background {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.accentColor.gradient)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Select Topic")
            .navigationBarTitleDisplayMode(.inline)
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
        // Run in background to avoid blocking UI if many files
        let manager = dataManager
        Task {
            let discovered = manager.discoverTags(language: language)
            await MainActor.run {
                self.tags = discovered
                self.isLoading = false
            }
        }
    }
    
    private func selectTag(_ tag: String) {
        // Create the virtual deck
        let virtualDeck = dataManager.createVirtualDeck(tag: tag, language: language)
        
        // We need to pass this back. 
        // Problem: `selectedDeck` expects `DeckMetadata`, but `createVirtualDeck` returns `CardDeck`.
        // We must cache it in DataManager so it can be found by ID, or...
        // DataManager.discoverDecks returns Metadata.
        // We can create a fake Metadata for it.
        
        // Better implementation: 
        // 1. DataManager should probably cache this virtual deck in `availableDecks` momentarily?
        // 2. Or providing a special constructor for DeckMetadata from a CardDeck?
        
        // For now, let's inject it into DataManager's loaded cache if possible, or creates a Metadata wrapper.
        
        // Let's assume we can create metadata for it.
        let metadata = DeckMetadata(
            id: virtualDeck.id,
            title: virtualDeck.title,
            language: virtualDeck.language,
            level: virtualDeck.level,
            folderName: "Virtual", // Special marker
            filename: "",
            supportedModes: virtualDeck.supportedModes ?? [],
            gameConfiguration: nil,
            coverImage: "tag.fill" // SF Symbol name or similar as placeholder?
        )
        
        // IMPORTANT: The GameView will try to LOAD this deck using resolveURL.
        // "Virtual" folderName will fail resolveURL.
        // DataManager needs to handle Loading of virtual decks specially IF it relies on loading from file.
        // But `createVirtualDeck` returns the `CardDeck` object directly!
        // We need a way to pass the *OBJECT* to the game, NOT just the metadata/ID.
        // OR DataManager.loadDeck(id) needs to know about virtual decks.
        
        // Since I can't easily change the entire DataManager architecture right now to support memory-only decks without file backing...
        // I will focus on updating DataManager to handle `loadDeck` for virtual IDs if they are cached in memory.
        
        // For this step, I'll assume I can pass it back. I will add a `virtualDecks` cache to DataManager in a fix-up step if needed.
        // But first, let's stick to the UI creation.
        
        selectedDeck = metadata
        
        // Also, we need to ensure DataManager "knows" this deck exists so loadDeck works.
        // I'll add a quick static cache or something in DataManager in the next step or right here.
        dataManager.registerVirtualDeck(virtualDeck)
        
        dismiss()
    }
}
