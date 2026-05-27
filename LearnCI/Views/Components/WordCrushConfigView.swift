import SwiftUI

struct WordCrushConfigView: View {
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

            VStack(spacing: 12) {
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

                Button(action: onSkipToSummary) {
                    Label("Use Defaults", systemImage: "play.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func gridSizeLabel(_ size: GameConfiguration.WordCrushGridSize) -> String {
        "\(size.rawValue) (\(size.columns)×\(size.rows))"
    }
}
