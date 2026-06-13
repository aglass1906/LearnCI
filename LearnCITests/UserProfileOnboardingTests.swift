import XCTest
@testable import LearnCI

final class UserProfileOnboardingTests: XCTestCase {
    func testCompletingOnboardingPersistsRequiredProfileValues() {
        let profile = UserProfile()
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)

        profile.completeOnboarding(
            name: "  Ada  ",
            language: .french,
            proficiencyLevel: 4,
            dailyGoalMinutes: 20,
            completedAt: completedAt
        )

        XCTAssertEqual(profile.name, "Ada")
        XCTAssertEqual(profile.currentLanguage, .french)
        XCTAssertEqual(profile.proficiencyLevel, 4)
        XCTAssertEqual(profile.currentLevel, .intermediate)
        XCTAssertEqual(profile.dailyGoalMinutes, 20)
        XCTAssertEqual(profile.onboardingVersion, UserProfile.currentOnboardingVersion)
        XCTAssertEqual(profile.onboardingCompletedAt, completedAt)
        XCTAssertTrue(profile.hasCompletedOnboarding)
    }

    func testProficiencyLevelIsClampedAndMappedToLegacyLevel() {
        let lowProfile = UserProfile()
        lowProfile.completeOnboarding(
            name: "Low",
            language: .spanish,
            proficiencyLevel: -3,
            dailyGoalMinutes: 10
        )

        let highProfile = UserProfile()
        highProfile.completeOnboarding(
            name: "High",
            language: .japanese,
            proficiencyLevel: 99,
            dailyGoalMinutes: 60
        )

        XCTAssertEqual(lowProfile.proficiencyLevel, 1)
        XCTAssertEqual(lowProfile.currentLevel, .superBeginner)
        XCTAssertEqual(highProfile.proficiencyLevel, 6)
        XCTAssertEqual(highProfile.currentLevel, .advanced)
    }
}
