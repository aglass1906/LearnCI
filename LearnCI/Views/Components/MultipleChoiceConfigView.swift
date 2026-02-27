import SwiftUI

struct MultipleChoiceConfigView: View {
    let deck: DeckMetadata
    @Binding var customConfig: GameConfiguration

    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Form {
                Section(header: Text("Answer Options")) {
                    Picker("Number of Options", selection: $customConfig.multipleChoiceOptionCount) {
                        Text("2 Options").tag(2)
                        Text("3 Options").tag(3)
                        Text("4 Options").tag(4)
                    }
                    .pickerStyle(.segmented)

                    Text("Fewer options makes the challenge easier — good for beginners.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("After Correct Answer")) {
                    Toggle("Show Translation", isOn: $customConfig.multipleChoiceShowTranslation)

                    if customConfig.multipleChoiceShowTranslation {
                        Text("The native language sentence meaning will appear after you pick the right answer, then the game advances automatically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("About")) {
                    Text("Hear a sentence in the target language and choose the correct translation from the options shown.")
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
                    .background(Color.green)
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
