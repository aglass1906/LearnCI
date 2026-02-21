import SwiftUI

struct DeckSelectionRow: View {
    let deck: DeckMetadata
    let selectedDeckId: String?
    let preferredScale: ProficiencyScale
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
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(deck.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    
                    if let description = deck.description {
                        Text(description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.bottom, 2)
                    }
                    
                    HStack(spacing: 4) {
                        Text(deck.language.flag)
                        Text("•")
                        Text(deck.language.rawValue)
                        Text("•")
                        let levelInt = deck.proficiencyLevel ?? (deck.level != nil ? LevelManager.shared.normalize(deck.level!) : 1)
                        Text(LevelManager.shared.displayString(level: levelInt, language: deck.language.code, preferredScale: preferredScale))
                    }
                    .font(.system(size: 10))
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
