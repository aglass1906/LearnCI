import SwiftUI

struct AudioClozeConfigView: View {
    let deck: DeckMetadata
    @Binding var customConfig: GameConfiguration

    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Form {
                Section(header: Text("Answer Options")) {
                    Picker("Number of Options", selection: $customConfig.audioClozeOptionCount) {
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
                    Toggle("Show Translation", isOn: $customConfig.audioClozeShowTranslation)

                    if customConfig.audioClozeShowTranslation {
                        Text("The native language sentence meaning will appear after you fill in the blank correctly.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("About")) {
                    Text("Listen to a sentence and fill in the missing word from the options. The word and sentence audio play automatically.")
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
                    .background(Color.pink)
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
