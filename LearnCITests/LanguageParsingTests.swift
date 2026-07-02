import XCTest
@testable import LearnCI

final class LanguageParsingTests: XCTestCase {
    func testFromStoredValueAcceptsIsoCodes() {
        XCTAssertEqual(Language.fromStoredValue("fr"), .french)
        XCTAssertEqual(Language.fromStoredValue("ES"), .spanish)
    }

    func testFromStoredValueAcceptsDisplayNamesFromPublishPipeline() {
        XCTAssertEqual(Language.fromStoredValue("French"), .french)
        XCTAssertEqual(Language.fromStoredValue("spanish"), .spanish)
    }

    func testStoryResolvesPublishedFrenchRow() {
        let story = Story(
            userID: "user",
            title: "Test",
            targetLanguageText: "",
            language: .spanish,
            level: 1
        )
        story.languageRaw = "French"

        XCTAssertEqual(story.language, .french)
        XCTAssertEqual(story.targetLanguageCode, "fr")
        XCTAssertEqual(story.languageBadgeAbbrev, "FR")
    }

    func testNativeLanguageCodeResolvesDisplayName() {
        let story = Story(
            userID: "user",
            title: "Test",
            targetLanguageText: "",
            language: .french,
            nativeLanguageCode: "English",
            level: 1
        )

        XCTAssertEqual(story.nativeLanguageCode, "en")
    }
}
