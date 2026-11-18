import SwiftUI

extension View {
    /// Calls `action` when the user drags mostly vertically over this view, so readers can
    /// collapse the audio player to its mini bar while the text is scrolled.
    func minimizesPlayerOnScroll(_ action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width),
                          abs(value.translation.height) > 12 else { return }
                    action()
                }
        )
    }
}
