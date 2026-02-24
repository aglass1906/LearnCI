import SwiftUI

struct TagSelectionSheet: View {
    let language: Language
    let defaultLevel: LearningLevel
    @Binding var selectedDeck: DeckMetadata?
    @Environment(\.dismiss) var dismiss
    @Environment(DataManager.self) private var dataManager
    
    @State private var domainGroups: [DomainGroup] = []
    @State private var isLoading = true
    @State private var selectedTags: Set<String> = []
    
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
                                                if selectedTags.contains(tag.id) {
                                                    selectedTags.remove(tag.id)
                                                } else {
                                                    selectedTags.insert(tag.id)
                                                }
                                            } label: {
                                                let isSelected = selectedTags.contains(tag.id)
                                                VStack {
                                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "tag.fill")
                                                        .font(.title2)
                                                        .foregroundStyle(isSelected ? .white : .accentColor)
                                                        .padding(.bottom, 4)

                                                    Text(tag.id)
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundStyle(isSelected ? .white : .primary)
                                                        .multilineTextAlignment(.center)

                                                    Text("\(tag.count)")
                                                        .font(.caption2)
                                                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                                                        .padding(.top, 2)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 100)
                                                .background {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(isSelected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
                                                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 12)
                                                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
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
                        
                        if !selectedTags.isEmpty {
                            let allTags = domainGroups.flatMap { $0.tags }
                            let totalCards = allTags.filter { selectedTags.contains($0.id) }.reduce(0) { $0 + $1.count }
                            Text("\(selectedTags.count) tag\(selectedTags.count == 1 ? "" : "s"), ~\(totalCards) cards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Select one or more tags")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button(action: {
                            if !selectedTags.isEmpty {
                                confirmSelection(selectedTags)
                            } else {
                                dismiss()
                            }
                        }) {
                            Text(selectedTags.isEmpty ? "Cancel" : "Done (\(selectedTags.count))")
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
    
    private func confirmSelection(_ tags: Set<String>) {
        let limit = limitToInitialDeck ? initialDeck : nil
        let virtualDeck = dataManager.createVirtualDeck(tags: tags, language: language, level: selectedLevel, limitDeck: limit)

        let metadata = DeckMetadata(
            id: virtualDeck.id,
            title: virtualDeck.title,
            description: virtualDeck.description,
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
