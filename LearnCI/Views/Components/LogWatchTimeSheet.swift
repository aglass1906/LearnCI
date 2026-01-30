import SwiftUI

struct LogActivitySheet: View {
    @Binding var minutes: Double
    @Binding var comment: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Watch Duration")) {
                    VStack(alignment: .leading) {
                        Text("Minutes: \(Int(minutes))")
                            .foregroundStyle(.secondary)
                        Slider(value: $minutes, in: 1...120, step: 1)
                    }
                }
                
                Section(header: Text("Notes (Optional)")) {
                    TextField("Add or edit comment...", text: $comment, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Log Watch Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
