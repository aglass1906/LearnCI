import SwiftUI
import SwiftData

struct DailyFeedbackEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var feedback: DailyFeedback
    
    // moodIcon helper (duplicated for now or could be shared)

    

    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Date", selection: $feedback.date, displayedComponents: .date)
                }
                
                Section("Mood") {
                    HStack(spacing: 0) { // spacing 0 to allow flexible frames to fill
                        ForEach(1...5, id: \.self) { rating in
                            Button(action: { 
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    feedback.rating = rating
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: DailyFeedback.moodIconName(for: rating))
                                        .foregroundStyle(DailyFeedback.moodColor(for: rating))
                                        .font(.title2)
                                        .scaleEffect(feedback.rating == rating ? 1.1 : 1.0)
                                    
                                    Text(DailyFeedback.moodLabel(for: rating)) // Use shared model logic
                                        .font(.caption2)
                                        .fontWeight(feedback.rating == rating ? .bold : .regular)
                                        .foregroundColor(feedback.rating == rating ? .primary : .secondary)
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(feedback.rating == rating ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(feedback.rating == rating ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Note") {
                    TextField("Add a note...", text: Binding(
                        get: { feedback.note ?? "" },
                        set: { feedback.note = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...5)
                }
            }
            .navigationTitle("Edit Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { 
                        try? modelContext.save()
                        dismiss() 
                    }
                }
            }
            .onChange(of: feedback.rating) { _, _ in
                feedback.isSynced = false
                try? modelContext.save()
            }
            .onChange(of: feedback.note) { _, _ in
                feedback.isSynced = false
            }
        }
    }
}
