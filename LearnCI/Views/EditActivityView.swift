import SwiftUI
import SwiftData

struct EditActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var activity: UserActivity
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details")) {
                    DatePicker("Date", selection: $activity.date, displayedComponents: [.date, .hourAndMinute])
                    
                    Stepper(value: $activity.minutes, in: 1...1440, step: 5) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text("\(activity.minutes) min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Activity Type")) {
                    Picker("Type", selection: $activity.activityType) {
                        ForEach(ActivityType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                
                Section(header: Text("Language")) {
                    Picker("Language", selection: $activity.language) {
                        ForEach(Language.allCases) { lang in
                            Text(lang.rawValue).tag(lang)
                        }
                    }
                }
                
                Section(header: Text("Notes (Optional)")) {
                    TextField("Add a comment...", text: Binding(
                        get: { activity.comment ?? "" },
                        set: { activity.comment = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
