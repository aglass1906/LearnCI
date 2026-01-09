import SwiftUI

struct DeckSelectionRow: View {
    let deck: DeckMetadata
    let selectedDeckId: String?
    let action: () -> Void
    
    @Environment(DataManager.self) private var dataManager
    
    private var isSelected: Bool {
        selectedDeckId == deck.id
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Cover Image or Icon
                if let coverName = deck.coverImage,
                   let uiImage = dataManager.loadImage(folderName: deck.folderName, filename: coverName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .cornerRadius(8)
                        .clipped()
                } else {
                    Image(systemName: "menucard.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 50, height: 50)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.title)
                        .font(.subheadline.bold())
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 4) {
                        Text(deck.language.flag)
                        Text("•")
                        Text(deck.language.rawValue)
                        Text("•")
                        Text(deck.level.rawValue)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding(12)
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
