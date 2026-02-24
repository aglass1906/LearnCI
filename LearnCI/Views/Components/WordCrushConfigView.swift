import SwiftUI

struct WordCrushConfigView: View {
    let deck: DeckMetadata
    @Binding var customConfig: GameConfiguration

    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.indigo)
                    .padding(.bottom, 8)

                Text("Word Crush")
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
                    Picker("Grid Size", selection: $customConfig.wordCrushGridSize) {
                        ForEach(GameConfiguration.WordCrushGridSize.allCases) { size in
                            Text(gridSizeLabel(size)).tag(size)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Display Mode", selection: $customConfig.wordCrushDisplayMode) {
                        ForEach(GameConfiguration.WordCrushDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("About")) {
                    Text("Match word pairs in a cascading grid. Tap two tiles that form a correct translation pair to clear them. Earn streak bonuses for consecutive matches!")
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
                .background(Color.indigo)
                .cornerRadius(12)
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func gridSizeLabel(_ size: GameConfiguration.WordCrushGridSize) -> String {
        "\(size.rawValue) (\(size.columns)×\(size.rows))"
    }
}
