import SwiftUI

enum SaveForStudyControlStyle {
    case star
    case compactStar
    case borderedLabel
    case toolbarLabel
    case prominentButton
}

struct SaveForStudyControl: View {
    let isSaved: Bool
    let style: SaveForStudyControlStyle
    let action: () -> Void

    private var savedColor: Color { .orange }
    private var unsavedColor: Color { .blue }

    private var activeColor: Color { isSaved ? savedColor : unsavedColor }

    var body: some View {
        Button(action: action) {
            label
        }
        .modifier(SaveForStudyButtonStyle(isBordered: style == .borderedLabel))
        .tint(activeColor)
        .accessibilityLabel(isSaved ? "Remove from saved study words" : "Save for study")
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .star:
            Image(systemName: isSaved ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(activeColor)
                .frame(width: 36, height: 36)
        case .compactStar:
            Image(systemName: isSaved ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(activeColor)
                .frame(width: 22, height: 22)
        case .borderedLabel:
            Label(
                isSaved ? "Saved" : "Save",
                systemImage: isSaved ? "star.fill" : "star"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(activeColor)
        case .toolbarLabel:
            HStack(spacing: 5) {
                Image(systemName: isSaved ? "star.fill" : "star")
                Text(isSaved ? "Saved" : "Study")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(activeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(activeColor.opacity(0.15))
            .clipShape(Capsule())
        case .prominentButton:
            Label(
                isSaved ? "Saved for study" : "Mark for study",
                systemImage: isSaved ? "star.fill" : "star"
            )
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundStyle(activeColor)
            .background(activeColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct SaveForStudyButtonStyle: ViewModifier {
    let isBordered: Bool

    func body(content: Content) -> some View {
        if isBordered {
            content.buttonStyle(.bordered)
        } else {
            content.buttonStyle(.plain)
        }
    }
}
