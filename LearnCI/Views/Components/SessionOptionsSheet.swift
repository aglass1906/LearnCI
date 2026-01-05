import SwiftUI

struct SessionOptionsSheet: View {
    @Binding var sessionDuration: Int
    @Binding var sessionCardGoal: Int
    @Binding var isRandomOrder: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Time Limit")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.blue)
                            Text("\(sessionDuration) minutes")
                                .font(.headline)
                        }
                        
                        Slider(value: Binding(get: { Double(sessionDuration) }, set: { sessionDuration = Int($0) }), in: 1...60, step: 1)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Card Goal")) {
                    Stepper(value: $sessionCardGoal, in: 5...100, step: 5) {
                        HStack {
                            Image(systemName: "target")
                                .foregroundColor(.red)
                            Text("Review \(sessionCardGoal) cards")
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    Toggle(isOn: $isRandomOrder) {
                        Label("Randomize Order", systemImage: "shuffle")
                            .foregroundColor(.orange)
                    }
                } footer: {
                    Text("Randomizing changes the order of cards for this session.")
                }
                
                Section {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Session Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                 ToolbarItem(placement: .confirmationAction) {
                     Button("Done") { dismiss() }
                 }
            }
        }
    }
}
