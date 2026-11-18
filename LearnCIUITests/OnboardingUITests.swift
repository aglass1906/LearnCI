import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNameIsRequiredBeforeContinuing() {
        let app = Scenario.needsOnboarding.launch()
        // The profile is seeded from the auth name, so clear it first.
        let field = app.textFields["onboarding.nameField"].assertExists()
        field.clearText()
        XCTAssertFalse(app.buttons["onboarding.primaryButton"].isEnabled)

        field.tap()
        field.typeText("Sam")
        XCTAssertTrue(app.buttons["onboarding.primaryButton"].isEnabled)
    }

    @MainActor
    func testCompletingOnboardingEntersApp() {
        let app = Scenario.needsOnboarding.launch()

        let field = app.textFields["onboarding.nameField"].assertExists()
        field.clearText()
        field.tap()
        field.typeText("Sam")
        app.buttons["onboarding.primaryButton"].tap()

        // Language
        app.buttons["onboarding.language.fr"].assertExists().tap()
        app.buttons["onboarding.primaryButton"].tap()

        // Level
        app.buttons["onboarding.level.3"].assertExists().tap()
        app.buttons["onboarding.primaryButton"].tap()

        // Daily goal
        app.buttons["onboarding.goal.30"].assertExists().tap()
        app.buttons["onboarding.primaryButton"].tap() // Build My Plan

        let greeting = app.staticTexts["onboarding.welcomeGreeting"].assertExists()
        XCTAssertTrue(greeting.label.contains("Sam"), "Greeting was: \(greeting.label)")

        app.buttons["onboarding.primaryButton"].tap() // Enter LearnCI
        app.element("dashboard.wordOfDay").assertExists("Should land on the dashboard after onboarding")
        XCTAssertFalse(app.textFields["onboarding.nameField"].exists)
    }

    @MainActor
    func testBackReturnsToPreviousStep() {
        let app = Scenario.needsOnboarding.launch()
        let field = app.textFields["onboarding.nameField"].assertExists()
        field.clearText()
        field.tap()
        field.typeText("Sam")
        app.buttons["onboarding.primaryButton"].tap()

        app.buttons["onboarding.language.es"].assertExists()
        app.buttons["onboarding.back"].tap()
        app.textFields["onboarding.nameField"].assertExists()
    }

    @MainActor
    func testSelectionMarksChoiceSelected() {
        let app = Scenario.needsOnboarding.launch()
        let field = app.textFields["onboarding.nameField"].assertExists()
        field.clearText()
        field.tap()
        field.typeText("Sam")
        app.buttons["onboarding.primaryButton"].tap()

        let japanese = app.buttons["onboarding.language.ja"].assertExists()
        japanese.tap()
        XCTAssertTrue(japanese.isSelected)
        XCTAssertFalse(app.buttons["onboarding.language.es"].isSelected)
    }

    @MainActor
    func testReturningUserSkipsOnboarding() {
        let app = Scenario.onboarded.launch()
        app.element("dashboard.wordOfDay").assertExists()
        XCTAssertFalse(app.textFields["onboarding.nameField"].exists)
    }
}
