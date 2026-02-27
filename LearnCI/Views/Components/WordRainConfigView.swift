import SwiftUI

struct WordRainConfigView: View {
    let deck: DeckMetadata
    @Binding var customConfig: GameConfiguration

    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 8) {
                Image(systemName: "cloud.rain.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.teal)
                    .padding(.bottom, 8)

                Text("Word Rain")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Customize your game")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)

            // Settings Form
            Form {
                Section(header: Text("Fall Speed")) {
                    Picker("Fall Speed", selection: $customConfig.wordRainSpeed) {
                        ForEach(GameConfiguration.WordRainSpeed.allCases) { speed in
                            Text(speed.rawValue).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Difficulty")) {
                    Picker("Difficulty", selection: $customConfig.wordRainDifficulty) {
                        ForEach(GameConfiguration.WordRainDifficulty.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(customConfig.wordRainDifficulty.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut, value: customConfig.wordRainDifficulty)
                }

                Section(header: Text("Words on Screen")) {
                    Stepper(value: $customConfig.wordRainWordCount, in: 2...5) {
                        HStack {
                            Text("Words on Screen")
                            Spacer()
                            Text("\(customConfig.wordRainWordCount)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("About")) {
                    Text("Words fall from the top of the screen. Tap the word that matches the translation shown at the bottom before it escapes. Earn streak bonuses for consecutive correct answers!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .scrollContentBackground(.hidden)

            Spacer()

            // Navigation Buttons
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
                    .background(Color.teal)
                    .cornerRadius(12)
                }

                Button(action: onSkipToSummary) {
                    Text("Skip to Summary")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}
