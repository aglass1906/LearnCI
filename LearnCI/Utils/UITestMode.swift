import Foundation

/// Debug-only hooks used by the UI test target. Activated purely by launch arguments,
/// so none of this exists in Release builds.
enum UITestMode {
#if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments

    /// `-uiTesting`: run against in-memory storage with no network side effects.
    static let isActive = arguments.contains("-uiTesting")
    /// `-uiTestAuthenticated`: start signed in as a fake user.
    static let startsAuthenticated = isActive && arguments.contains("-uiTestAuthenticated")
    /// `-uiTestOnboarded`: the fake user has already completed onboarding.
    static let startsOnboarded = isActive && arguments.contains("-uiTestOnboarded")
#else
    static let isActive = false
    static let startsAuthenticated = false
    static let startsOnboarded = false
#endif

    static let userID = "ui-test-user"

    /// `-uiTestResetPreview`: forget that the first-run preview was seen. A launch-argument
    /// default would override the value the app later writes, so reset the stored one instead.
    static func applyLaunchResets() {
#if DEBUG
        if isActive, arguments.contains("-uiTestResetPreview") {
            UserDefaults.standard.removeObject(forKey: "hasSeenOnboardingPreview")
        }
#endif
    }
}
