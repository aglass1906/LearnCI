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
    @Binding var selectedMode: GameConfiguration.MemoryMatchMode
    
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.bottom, 8)
                    
                Text("Memory Match")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Customize your game")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            // Settings Form
            Form {
                Section(header: Text("Game Settings")) {
                    Picker("Match Mode", selection: $selectedMode) {
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
