import SwiftUI
import SwiftData

struct DailyFeedbackEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var feedback: DailyFeedback
    
    // moodIcon helper (duplicated for now or could be shared)
    private func moodIcon(for rating: Int) -> some View {
        let iconName: String
        let color: Color
        switch rating {
        case 1: iconName = "cloud.rain.fill"; color = .gray
        case 2: iconName = "cloud.fill"; color = .blue.opacity(0.6)
        case 3: iconName = "cloud.sun.fill"; color = .orange.opacity(0.7)
        case 4: iconName = "sun.max.fill"; color = .yellow
        case 5: iconName = "sparkles"; color = .yellow
        default: iconName = "questionmark.circle"; color = .gray
        }
        return Image(systemName: iconName).foregroundStyle(color)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Date", selection: $feedback.date, displayedComponents: .date)
                }
                
                Section("Mood") {
                    HStack {
                        ForEach(1...5, id: \.self) { rating in
                            Button(action: { feedback.rating = rating }) {
                                VStack {
                                    moodIcon(for: rating)
                                        .font(.title2)
                                        .scaleEffect(feedback.rating == rating ? 1.2 : 1.0)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 8)
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
