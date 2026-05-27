import UIKit

@MainActor
final class GameFeedbackManager {
    static let shared = GameFeedbackManager()

    var soundEffectsEnabled = true
    var hapticsEnabled = true

    private init() {}

    func tap() {
        play(.click)
        selectionChanged()
    }

    func flip() {
        play(.flip)
        impact(.light)
    }

    func match() {
        play(.match)
        notification(.success)
    }

    func correct() {
        match()
    }

    func incorrect() {
        play(.mismatch)
        notification(.error)
    }

    func complete() {
        play(.win)
        notification(.success)
    }

    private func play(_ sound: SoundManager.SoundType) {
        guard soundEffectsEnabled else { return }
        SoundManager.shared.play(sound)
    }

    private func selectionChanged() {
        guard hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
