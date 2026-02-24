import SwiftUI

struct GameSelectionView: View {
    @Binding var selectedGameType: GameConfiguration.GameType
    let onGameSelected: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(GameConfiguration.GameType.allCases) { gameType in
                    GameTileView(
                        gameType: gameType,
                        isSelected: selectedGameType == gameType
                    )
                    .onTapGesture {
                        selectedGameType = gameType
                        onGameSelected()
                    }
                }
            }
            .padding()
        }
    }
}

struct GameTileView: View {
    let gameType: GameConfiguration.GameType
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            // Image or SF Symbol fallback
            if let uiImage = UIImage(named: gameType.imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 50)
            } else {
                Image(systemName: gameType.icon)
                    .font(.system(size: 36))
                    .foregroundColor(gameType.tileColor)
            }

            Text(gameType.rawValue)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(gameType.description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? gameType.tileColor.opacity(0.15) : Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? gameType.tileColor : Color.clear, lineWidth: 2.5)
        )
        .contentShape(Rectangle())
    }
}
