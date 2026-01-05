import SwiftUI

struct DeckSelectionRow: View {
    let deck: DeckMetadata
    let selectedDeckId: String?
    let action: () -> Void
    
    private var isSelected: Bool {
        selectedDeckId == deck.id
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(deck.title)
                        .font(.subheadline.bold())
                    Text("\(deck.language.rawValue) • \(deck.level.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
