//
//  MemoryMatchModeSelector.swift
//  LearnCI
//
//  NOTE: This file contains MemoryConfigView.
//  The file name 'MemoryMatchModeSelector' is retained for Xcode project compatibility.
//  Ideally, this file should be renamed to MemoryConfigView.swift in Xcode.
//

import SwiftUI

struct MemoryConfigView: View {
    let deck: DeckMetadata
    @Binding var customConfig: GameConfiguration

    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Settings Form
            Form {
                Section(header: Text("Game Settings")) {
                    Picker("Match Mode", selection: $customConfig.memoryMatchMode) {
                        ForEach(GameConfiguration.MemoryMatchMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: Text("About")) {
                    Text("Match pairs of cards by finding the word and its translation or image. Test your memory and vocabulary recognition.")
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
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}
