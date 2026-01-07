import SwiftUI

struct DisplayConfigurationSheet: View {
    @Binding var selectedPreset: GameConfiguration.Preset
    @Binding var customConfig: GameConfiguration
    var onSave: () -> Void = {}
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Preset Mode")) {
                    Picker("Mode", selection: $selectedPreset) {
                        ForEach(GameConfiguration.Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedPreset) { _, newValue in
                        if newValue != .customize {
                            customConfig = GameConfiguration.from(preset: newValue)
                        }
                    }
                    .onChange(of: customConfig) { _, newConfig in
                        // Auto-switch to customize if settings diverge from the selected preset's defaults
                        if selectedPreset != .customize {
                            let defaultForPreset = GameConfiguration.from(preset: selectedPreset)
                            if newConfig != defaultForPreset {
                                selectedPreset = .customize
                            }
                        }
                    }
                }
                
                Section(header: Text("Custom Settings")) {
                    customizationOptionsView
                }
                
                Section(header: Text("Configuration Summary")) {
                    // Use custom config directly since we always update relative to preset
                    DisplayConfigurationSummaryView(config: customConfig)
                }
                
                Section {
                    Button(action: {
                        onSave()
                        dismiss()
                    }) {
                        Text("Done")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Card Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                 ToolbarItem(placement: .cancellationAction) {
                     Button("Cancel") { dismiss() }
                 }
                 ToolbarItem(placement: .confirmationAction) {
                     Button("Done") {
                         onSave()
                         dismiss()
                     }
                 }
            }
        }
    }
    
    @ViewBuilder
    private var customizationOptionsView: some View {
        // Word Settings
        DisclosureGroup(
            content: {
                VStack(alignment: .leading) {
                    Picker("Text Visibility", selection: $customConfig.word.text) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text(vis.rawValue).tag(vis)
                        }
                    }
                    Picker("Audio Playback", selection: $customConfig.word.audio) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text(vis.rawValue).tag(vis)
                        }
                    }
                }
            },
            label: { Label("Word", systemImage: "textformat") }
        )
        
        // Sentence Settings
        DisclosureGroup(
            content: {
                VStack(alignment: .leading) {
                    Picker("Text Visibility", selection: $customConfig.sentence.text) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text(vis.rawValue).tag(vis)
                        }
                    }
                    Picker("Audio Playback", selection: $customConfig.sentence.audio) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text(vis.rawValue).tag(vis)
                        }
                    }
                }
            },
            label: { Label("Sentence", systemImage: "text.bubble") }
        )
        
        // Image Settings
        DisclosureGroup(
            content: {
                VStack(alignment: .leading) {
                    Picker("Visibility", selection: $customConfig.image) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text(vis.rawValue).tag(vis)
                        }
                    }
                }
            },
            label: { Label("Image", systemImage: "photo") }
        )
        
        // Back of Card Settings
        DisclosureGroup(
            content: {
                VStack(alignment: .leading) {
                    Picker("Translation", selection: $customConfig.back.translation) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text(vis.rawValue).tag(vis)
                        }
                    }
                    Picker("Sentence Meaning", selection: $customConfig.back.sentenceMeaning) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text(vis.rawValue).tag(vis)
                        }
                    }
                    Picker("Study Tools", selection: $customConfig.back.studyLinks) {
                        ForEach(ElementVisibility.allCases) { vis in
                            Text(vis.rawValue).tag(vis)
                        }
                    }
                }
            },
            label: { Label("Back of Card", systemImage: "arrow.triangle.2.circlepath") }
        )
        
        // Audio Settings
        VStack(spacing: 8) {
            Toggle(isOn: $customConfig.useTTSFallback) {
                Label("Use System Voice Fallback", systemImage: "waveform")
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            
            Divider()
                .padding(.vertical, 4)
            
            HStack {
                Label("Override Speed", systemImage: "speedometer")
                Spacer()
                Text(String(format: "%.1fx", customConfig.ttsRate * 2)) // Assuming 0.5 is 1x (normal)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            Slider(value: $customConfig.ttsRate, in: 0.1...1.0, step: 0.1) {
                Text("Rate")
            } minimumValueLabel: {
                Text("Slow")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } maximumValueLabel: {
                Text("Fast")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
