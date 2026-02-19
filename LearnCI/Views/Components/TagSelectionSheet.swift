import SwiftUI

struct TagSelectionSheet: View {
    let language: Language
    let defaultLevel: LearningLevel
    @Binding var selectedDeck: DeckMetadata?
    @Environment(\.dismiss) var dismiss
    @Environment(DataManager.self) private var dataManager
    
    @State private var domainGroups: [DomainGroup] = []
    @State private var isLoading = true
    @State private var selectedTag: String?
    
    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 12)
    ]
    
    @State private var selectedLevel: LearningLevel?
    private let initialDeck: DeckMetadata? // Capture deck at launch
    @State private var limitToInitialDeck: Bool = true
    
    init(language: Language, defaultLevel: LearningLevel, selectedDeck: Binding<DeckMetadata?>) {
        self.language = language
        self.defaultLevel = defaultLevel
        self._selectedDeck = selectedDeck
        self._selectedLevel = State(initialValue: defaultLevel)
        
        // If the current deck is a real deck (not virtual), use it as a limit
        if let current = selectedDeck.wrappedValue, !current.id.starts(with: "virtual_") {
            self.initialDeck = current
            self._limitToInitialDeck = State(initialValue: true)
        } else {
            self.initialDeck = nil
            self._limitToInitialDeck = State(initialValue: false)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Bar
                VStack(spacing: 8) {
                    // Level Picker
                    Picker("Level", selection: $selectedLevel) {
                        Text("All Levels").tag(Optional<LearningLevel>.none)
                        ForEach(LearningLevel.allCases) { level in
                            Text(level.rawValue).tag(Optional(level))
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    // Deck Scope Picker (Only if we have an initial deck)
                    if let initialDeck = initialDeck {
                        Picker("Scope", selection: $limitToInitialDeck) {
                            Text("All Decks").tag(false)
                            Text(initialDeck.title).tag(true)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: limitToInitialDeck) { _, _ in
                            loadTags()
                        }
                    }
                }
                .padding()
                .onChange(of: selectedLevel) { _, _ in
                    loadTags()
                }
                
                ScrollView {
                    if isLoading {
                        ProgressView("Scanning decks...")
                            .padding(.top, 40)
                    } else if domainGroups.isEmpty {
                        ContentUnavailableView("No Tags Found", systemImage: "tag.slash", description: Text("No subject tags were found for this language."))
                    } else {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(domainGroups, id: \.id) { domain in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Section Header
                                    Text(domain.id)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.primary)
                                    
                                    if !domain.description.isEmpty {
                                        Text(domain.description)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .padding(.bottom, 4)
                                    }
                                    
                                    // Tags Grid
                                    LazyVGrid(columns: columns, spacing: 12) {
                                        ForEach(domain.tags, id: \.id) { tag in
                                            Button {
                                                selectedTag = tag.id
                                            } label: {
                                                VStack {
                                                    Image(systemName: "tag.fill")
                                                        .font(.title2)
                                                        .foregroundStyle(selectedTag == tag.id ? .white : .accentColor)
                                                        .padding(.bottom, 4)
                                                    
                                                    Text(tag.id)
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundStyle(selectedTag == tag.id ? .white : .primary)
                                                        .multilineTextAlignment(.center)
                                                    
                                                    Text("\(tag.count)")
                                                        .font(.caption2)
                                                        .foregroundStyle(selectedTag == tag.id ? .white.opacity(0.8) : .secondary)
                                                        .padding(.top, 2)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 100)
                                                .background {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(selectedTag == tag.id ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
                                                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 12)
                                                                .stroke(selectedTag == tag.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                                        )
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
                
                // Bottom Bar
                if !isLoading && !domainGroups.isEmpty {
                    VStack(spacing: 12) {
                        Divider()
                        
                        if let selected = selectedTag {
                            // Find count across all groups
                            let count = domainGroups.flatMap { $0.tags }.first { $0.id == selected }?.count ?? 0
                             Text("\(count) cards selected")
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
                            } else {
                                dismiss()
                            }
                        }) {
                            Text("Done")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
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
        let level = selectedLevel
        let limit = limitToInitialDeck ? initialDeck : nil
        isLoading = true
        
        Task {
            let discovered = manager.discoverDomainTags(language: language, level: level, limitDeck: limit)
            await MainActor.run {
                self.domainGroups = discovered
                self.isLoading = false
            }
        }
    }
    
    private func confirmSelection(_ tag: String) {
        let limit = limitToInitialDeck ? initialDeck : nil
        let virtualDeck = dataManager.createVirtualDeck(tag: tag, language: language, level: selectedLevel, limitDeck: limit)
        
        let metadata = DeckMetadata(
            id: virtualDeck.id,
            title: virtualDeck.title,
            language: virtualDeck.language,
            level: virtualDeck.level,
            proficiencyLevel: virtualDeck.proficiencyLevel,
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
