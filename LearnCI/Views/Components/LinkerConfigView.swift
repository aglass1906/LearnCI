import SwiftUI

struct LinkerConfigView: View {
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
                    Picker("Right Column Content", selection: $customConfig.linkerTargetMode) {
                        ForEach(GameConfiguration.LinkerTargetMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: Text("About")) {
                    Text("Connect items between the two columns. The left column will always show the target language (e.g., Spanish).")
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
