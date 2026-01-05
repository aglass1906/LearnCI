import SwiftUI

struct GameConfigurationView: View {
    @Binding var sessionLanguage: Language
    @Binding var sessionLevel: LearningLevel
    @Binding var selectedDeck: DeckMetadata?
    @Binding var sessionDuration: Int
    @Binding var sessionCardGoal: Int
    @Binding var isRandomOrder: Bool
    @Binding var selectedPreset: GameConfiguration.Preset
    @Binding var customConfig: GameConfiguration
    
    let availableDecks: [DeckMetadata]
    let startAction: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                focusSelectionSection
                deckSelectionSection
                configurationSection
                adjustmentsSection
                
                if let deck = selectedDeck {
                    SessionSummaryView(
                        deckTitle: deck.title,
                        preset: selectedPreset,
                        duration: sessionDuration,
                        cardGoal: sessionCardGoal,
                        isRandom: isRandomOrder
                    )
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
                
                Spacer()
                
                Button(action: startAction) {
                    Text("Start Learn Session")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedDeck == nil ? Color.gray : Color.blue)
                        .cornerRadius(15)
                        .shadow(radius: selectedDeck == nil ? 0 : 5)
                }
                .disabled(selectedDeck == nil)
                .padding(.horizontal)
                .padding(.top, 40)
            }
            .padding(.vertical)
        }
    }
    
    private var focusSelectionSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Session Focus")
                .font(.headline)
            
            HStack {
                Menu {
                    ForEach(Language.allCases) { lang in
                        Button(action: { sessionLanguage = lang }) {
                            HStack {
                                Text("\(lang.flag) \(lang.rawValue)")
                                if sessionLanguage == lang { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("\(sessionLanguage.flag) \(sessionLanguage.rawValue)")
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
                
                Menu {
                    ForEach(LearningLevel.allCases) { level in
                        Button(action: { sessionLevel = level }) {
                            HStack {
                                Text(level.rawValue)
                                if sessionLevel == level { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(sessionLevel.rawValue)
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var deckSelectionSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Select Deck")
                .font(.headline)
            
            if availableDecks.isEmpty {
                Text("No decks found for this selection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(10)
            } else {
                VStack(spacing: 10) {
                    ForEach(availableDecks) { deck in
                        DeckSelectionRow(deck: deck, selectedDeckId: selectedDeck?.id) {
                            selectedDeck = deck
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Card Display")
                .font(.headline)
            
            Picker("Mode", selection: $selectedPreset) {
                ForEach(GameConfiguration.Preset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedPreset) { _, newValue in
                if newValue != .customize {
                    customConfig = GameConfiguration.from(preset: newValue)
                }
            }
            
            if selectedPreset == .customize {
                customizationOptionsView
            } else {
                presetSummaryView
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var customizationOptionsView: some View {
        VStack(spacing: 20) {
            GroupBox(label: Label("Word", systemImage: "textformat")) {
                VStack {
                    Picker("Text", selection: $customConfig.word.text) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text(vis.rawValue).tag(vis)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Audio", selection: $customConfig.word.audio) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text("🔊 " + vis.rawValue).tag(vis)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }
            
            GroupBox(label: Label("Sentence", systemImage: "text.bubble")) {
                VStack {
                    Picker("Text", selection: $customConfig.sentence.text) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text(vis.rawValue).tag(vis)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Audio", selection: $customConfig.sentence.audio) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text("🔊 " + vis.rawValue).tag(vis)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }
            
            GroupBox(label: Label("Image", systemImage: "photo")) {
                Picker("Visibility", selection: $customConfig.image) {
                    ForEach(ElementVisibility.allCases) { vis in
                        Text(vis.rawValue).tag(vis)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }
        }
        .padding(.top, 4)
    }
    
    @ViewBuilder
    private var presetSummaryView: some View {
        let preview = GameConfiguration.from(preset: selectedPreset)
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings:")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                Label {
                    Text(preview.word.text == .visible ? "Visible" : (preview.word.text == .hidden ? "Hidden" : "Hint"))
                } icon: {
                    Image(systemName: "textformat")
                }
                
                Label {
                    Text(preview.sentence.text == .visible ? "Visible" : (preview.sentence.text == .hidden ? "Hidden" : "Hint"))
                } icon: {
                    Image(systemName: "text.bubble")
                }
                
                Label {
                    Text(preview.image == .visible ? "Visible" : (preview.image == .hidden ? "Hidden" : "Hint"))
                } icon: {
                    Image(systemName: "photo")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
    
    private var adjustmentsSection: some View {
        GroupBox(label: Label("Session Options", systemImage: "gearshape.fill")) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Time Limit", systemImage: "clock")
                        .font(.headline)
                    
                    HStack {
                        Slider(value: Binding(get: { Double(sessionDuration) }, set: { sessionDuration = Int($0) }), in: 1...60, step: 1)
                        Text("\(sessionDuration) min")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 60)
                            .padding(6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Card Goal", systemImage: "target")
                        .font(.headline)
                    
                    Stepper(value: $sessionCardGoal, in: 5...100, step: 5) {
                        HStack {
                            Image(systemName: "square.stack.3d.up.fill")
                            Text("\(sessionCardGoal) cards")
                        }
                    }
                }
                
                Divider()
                
                Toggle(isOn: $isRandomOrder) {
                    Label("Randomize Order", systemImage: "shuffle")
                        .font(.headline)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal)
    }
}
