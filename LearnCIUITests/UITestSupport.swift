import XCTest

/// Launch scenarios for the app. All run against in-memory storage with no network.
enum Scenario {
    /// Fresh install: first-run onboarding preview, signed out.
    case freshInstall
    /// Past the preview, signed out (shows the sign-in screen).
    case signedOut
    /// Signed in as a new user who has not finished onboarding.
    case needsOnboarding
    /// Signed in with onboarding complete (Spanish, level 1).
    case onboarded

    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        switch self {
        case .freshInstall:
            app.launchArguments += ["-uiTestResetPreview"]
        case .signedOut:
            app.launchArguments += ["-hasSeenOnboardingPreview", "YES"]
        case .needsOnboarding:
            app.launchArguments += ["-uiTestAuthenticated"]
        case .onboarded:
            app.launchArguments += ["-uiTestAuthenticated", "-uiTestOnboarded"]
        }
        app.launch()
        return app
    }
}

extension XCUIApplication {
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

extension XCUIElement {
    @discardableResult
    func assertExists(_ message: String = "", timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), message.isEmpty ? "Missing element: \(self)" : message, file: file, line: line)
        return self
    }
}
