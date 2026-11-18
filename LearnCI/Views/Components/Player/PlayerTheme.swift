import SwiftUI

/// Shared visual tokens for every audio player surface (stories, audiobooks, podcasts).
enum PlayerTheme {
    static let accent = Color(red: 0.91, green: 0.22, blue: 0.36)
    static let backgroundTop = Color(red: 0.11, green: 0.11, blue: 0.34)
    static let backgroundBottom = Color(red: 0.04, green: 0.04, blue: 0.15)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let trackBackground = Color.white.opacity(0.20)
    static let iconTint = Color.white

    static let artworkCornerRadius: CGFloat = 14
    static let playButtonDiameter: CGFloat = 72
    static let skipIconSize: CGFloat = 30
    static let trackHeight: CGFloat = 5
    static let thumbDiameter: CGFloat = 16
    static let minTapTarget: CGFloat = 44

    static let titleFont = Font.system(.title3, design: .rounded).weight(.semibold)
    static let statusFont = Font.system(.subheadline, design: .rounded)
    static let timeFont = Font.system(.subheadline, design: .rounded).monospacedDigit()
}

/// Dark gradient background; when artwork is supplied it is blurred and darkened behind the gradient.
struct PlayerBackground: View {
    var image: Image? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PlayerTheme.backgroundTop, PlayerTheme.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .opacity(0.55)
                    .overlay(Color.black.opacity(0.35))
                    .clipped()
            }
        }
        .ignoresSafeArea()
    }
}

enum PlayerTimeFormat {
    /// "04:40" or "1:02:03"
    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// "16 hrs and 48 min left"
    static func remainingPhrase(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "Finished" }
        let totalMinutes = Int((seconds / 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 { return "\(h) \(h == 1 ? "hr" : "hrs") and \(m) min left" }
        if h > 0 { return "\(h) \(h == 1 ? "hr" : "hrs") left" }
        if m > 0 { return "\(m) min left" }
        return "Less than a minute left"
    }

    static func rateLabel(_ rate: Float) -> String {
        "\(rate.formatted())x"
    }
}
