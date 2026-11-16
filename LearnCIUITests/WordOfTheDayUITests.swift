import XCTest

final class WordOfTheDayUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testWordOfTheDayCardShowsWordAndSentence() {
        let app = Scenario.onboarded.launch()
        app.element("dashboard.wordOfDay").assertExists()

        let word = app.staticTexts["wordOfDay.word"].assertExists(timeout: 15)
        let translation = app.staticTexts["wordOfDay.translation"].assertExists()
        let sentence = app.staticTexts["wordOfDay.sentence"].assertExists()

        XCTAssertFalse(word.label.isEmpty)
        XCTAssertFalse(translation.label.isEmpty)
        XCTAssertFalse(sentence.label.isEmpty)
        XCTAssertFalse(app.staticTexts["wordOfDay.empty"].exists, "Should not show the empty state")
        XCTAssertTrue(app.staticTexts["wordOfDay.deck"].exists)
    }

    @MainActor
    func testWordIsStableAcrossRelaunchesOnSameDay() {
        let first = Scenario.onboarded.launch()
        let firstWord = first.staticTexts["wordOfDay.word"].assertExists(timeout: 15).label
        first.terminate()

        let second = Scenario.onboarded.launch()
        let secondWord = second.staticTexts["wordOfDay.word"].assertExists(timeout: 15).label
        XCTAssertEqual(firstWord, secondWord, "Word of the Day is date-seeded, so it should not change")
    }

    @MainActor
    func testAudioButtonsAreTappable() {
        let app = Scenario.onboarded.launch()
        app.staticTexts["wordOfDay.word"].assertExists(timeout: 15)

        let sentenceAudio = app.buttons["wordOfDay.sentenceAudio"].assertExists()
        XCTAssertTrue(sentenceAudio.isHittable)
        sentenceAudio.tap()
        XCTAssertTrue(app.staticTexts["wordOfDay.word"].exists, "App should survive playing audio")
    }
}
