import XCTest

final class SignInUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testFreshInstallShowsPreviewThenSignIn() {
        let app = Scenario.freshInstall.launch()
        app.element("onboardingPreview.title.0").assertExists()

        app.buttons["onboardingPreview.next"].tap()
        app.buttons["onboardingPreview.next"].tap()
        app.buttons["onboardingPreview.next"].tap() // "Get Started"

        app.textFields["auth.emailField"].assertExists()
    }

    @MainActor
    func testSkippingPreviewShowsSignIn() {
        let app = Scenario.freshInstall.launch()
        app.buttons["onboardingPreview.skip"].assertExists().tap()
        app.textFields["auth.emailField"].assertExists()
    }

    @MainActor
    func testEmailContinueEnabledOnlyForValidEmail() {
        let app = Scenario.signedOut.launch()
        let field = app.textFields["auth.emailField"].assertExists()
        let button = app.buttons["auth.continueEmail"]
        XCTAssertFalse(button.isEnabled)

        field.tap()
        field.typeText("not-an-email")
        XCTAssertFalse(button.isEnabled)

        field.clearText()
        field.typeText("person@example.com")
        XCTAssertTrue(button.isEnabled)
    }

    @MainActor
    func testPasswordFormSignInMode() {
        let app = Scenario.signedOut.launch()
        app.buttons["auth.usePassword"].assertExists().tap()

        app.textFields["passwordAuth.email"].assertExists()
        app.secureTextFields["passwordAuth.password"].assertExists()
        XCTAssertFalse(app.element("passwordAuth.name").exists)
        XCTAssertFalse(app.element("passwordAuth.confirmPassword").exists)
        XCTAssertTrue(app.buttons["passwordAuth.forgot"].exists)
        XCTAssertFalse(app.buttons["passwordAuth.submit"].isEnabled)
    }

    @MainActor
    func testPasswordFormSignUpModeAddsFields() {
        let app = Scenario.signedOut.launch()
        app.buttons["auth.usePassword"].assertExists().tap()

        app.segmentedControls["passwordAuth.modePicker"].buttons["Sign Up"].assertExists().tap()
        app.textFields["passwordAuth.name"].assertExists()
        app.secureTextFields["passwordAuth.confirmPassword"].assertExists()
        XCTAssertFalse(app.buttons["passwordAuth.forgot"].exists)
    }

    @MainActor
    func testShowPasswordToggleRevealsAndHidesText() {
        let app = Scenario.signedOut.launch()
        app.buttons["auth.usePassword"].assertExists().tap()

        let secure = app.secureTextFields["passwordAuth.password"].assertExists()
        secure.tap()
        secure.typeText("hunter2hunter2")
        XCTAssertFalse(app.textFields["passwordAuth.password"].exists)

        app.buttons["passwordAuth.password.toggleVisibility"].tap()
        let plain = app.textFields["passwordAuth.password"].assertExists()
        XCTAssertEqual(plain.value as? String, "hunter2hunter2")

        app.buttons["passwordAuth.password.toggleVisibility"].tap()
        app.secureTextFields["passwordAuth.password"].assertExists()
    }

    @MainActor
    func testCancelClosesPasswordForm() {
        let app = Scenario.signedOut.launch()
        app.buttons["auth.usePassword"].assertExists().tap()
        app.buttons["passwordAuth.cancel"].assertExists().tap()
        app.textFields["auth.emailField"].assertExists()
    }
}

extension XCUIElement {
    func clearText() {
        guard let current = value as? String, !current.isEmpty else { return }
        tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    }
}
