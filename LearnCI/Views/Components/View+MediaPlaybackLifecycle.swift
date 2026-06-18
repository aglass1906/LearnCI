import SwiftUI

/// Prevents media teardown when the app backgrounds (lock screen, app switcher).
/// Only runs `onUserLeave` when the view disappears while the scene is still active.
struct MediaPlaybackLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let onUserLeave: () -> Void
    var onEnterBackground: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .onDisappear {
                if scenePhase == .active {
                    onUserLeave()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    onEnterBackground?()
                }
            }
    }
}

extension View {
    func mediaPlaybackLifecycle(
        onUserLeave: @escaping () -> Void,
        onEnterBackground: (() -> Void)? = nil
    ) -> some View {
        modifier(
            MediaPlaybackLifecycleModifier(
                onUserLeave: onUserLeave,
                onEnterBackground: onEnterBackground
            )
        )
    }
}
