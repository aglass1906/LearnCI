import SwiftUI

/// Title, optional subtitle, "% complete | time left" status, and a tappable chapter chip.
struct PlayerStatusLine: View {
    let title: String
    var subtitle: String? = nil
    var fractionComplete: Double? = nil
    var timeRemaining: TimeInterval? = nil
    var chapterLabel: String? = nil
    var onTapChapter: (() -> Void)? = nil

    private var statusText: String? {
        var parts: [String] = []
        if let fractionComplete {
            parts.append("\(Int((fractionComplete * 100).rounded()))% complete")
        }
        if let timeRemaining {
            parts.append(PlayerTimeFormat.remainingPhrase(timeRemaining))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  |  ")
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(PlayerTheme.titleFont)
                .foregroundStyle(PlayerTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(PlayerTheme.statusFont)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .lineLimit(1)
            }

            if let chapterLabel {
                chapterChip(chapterLabel)
            }

            if let statusText {
                Text(statusText)
                    .font(PlayerTheme.statusFont)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func chapterChip(_ label: String) -> some View {
        if let onTapChapter {
            Button(action: onTapChapter) {
                HStack(spacing: 4) {
                    Text(label).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(PlayerTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PlayerPressStyle())
            .accessibilityHint("Opens the chapter list")
        } else {
            Text(label)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(PlayerTheme.secondaryText)
                .lineLimit(1)
        }
    }
}
