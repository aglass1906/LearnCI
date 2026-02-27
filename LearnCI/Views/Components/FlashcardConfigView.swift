//
//  FlashcardLayoutSelector.swift
//  LearnCI
//
//  NOTE: This file contains FlashcardConfigView. 
//  The file name 'FlashcardLayoutSelector' is retained for Xcode project compatibility.
//  Ideally, this file should be renamed to FlashcardConfigView.swift in Xcode.
//

import SwiftUI

struct FlashcardConfigView: View {
    let gameType: GameConfiguration.GameType
    let deck: DeckMetadata
    @Binding var selectedPreset: GameConfiguration.Preset
    @Binding var customConfig: GameConfiguration
    
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Settings Form
            Form {
                Section(header: Text("Game Settings")) {
                    Picker("Card Layout", selection: $selectedPreset) {
                        ForEach(GameConfiguration.Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: Text("About")) {
                    Text("Review vocabulary with traditional flashcards. See the word, try to recall it, then flip to check your answer.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .scrollContentBackground(.hidden) 
            
            Spacer()
            
            // Next Button
            Button(action: onNext) {
                HStack {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .cornerRadius(12)
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}
