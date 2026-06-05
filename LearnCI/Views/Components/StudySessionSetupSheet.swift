import SwiftUI

struct StudySessionSetupSheet: View {
    let blocks: [StudyBlock]
    let currentBlockIndex: Int
    let onStart: (StudySessionDefinition) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mode: SetupMode = .blockCount
    @State private var blockCount: Int = 10
    @State private var durationMinutes: Int = 5

    private enum SetupMode: String, CaseIterable, Identifiable {
        case blockCount = "Blocks"
        case duration = "Minutes"
        case full = "Full transcript"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session scope") {
                    Picker("Define by", selection: $mode) {
                        ForEach(SetupMode.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch mode {
                case .blockCount:
                    Stepper("Study next \(blockCount) blocks", value: $blockCount, in: 1...max(1, remainingBlocks))
                case .duration:
                    Stepper("Study ~\(durationMinutes) minutes", value: $durationMinutes, in: 1...30)
                case .full:
                    Text("Study the full transcript (\(blocks.count) blocks).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let preview = previewDefinition {
                    Section("Preview") {
                        LabeledContent("Start block", value: "\(preview.startIndex + 1)")
                        LabeledContent("End block", value: "\(preview.endIndex + 1)")
                        LabeledContent("Total blocks", value: "\(preview.blockCount)")
                    }
                }
            }
            .navigationTitle("Define Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        if let definition = previewDefinition {
                            onStart(definition)
                            dismiss()
                        }
                    }
                    .disabled(previewDefinition == nil)
                }
            }
        }
    }

    private var remainingBlocks: Int {
        max(1, blocks.count - currentBlockIndex)
    }

    private var previewDefinition: StudySessionDefinition? {
        switch mode {
        case .blockCount:
            return StudySessionRangeBuilder.byBlockCount(blockCount, from: currentBlockIndex, in: blocks)
        case .duration:
            return StudySessionRangeBuilder.byDurationMinutes(durationMinutes, from: currentBlockIndex, in: blocks)
        case .full:
            return StudySessionRangeBuilder.fullTranscript(in: blocks)
        }
    }
}
