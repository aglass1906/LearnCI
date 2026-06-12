import XCTest
@testable import LearnCI

@MainActor
final class DialogStoryBuilderTests: XCTestCase {
    func testBuilderProducesOnlyDialogueItemsForRequestedChapter() throws {
        let story = try makeDialogStory()
        let adapter = StoryReaderDataAdapter(story: story)
        var builder = DialogStoryBuilder(story: story, adapter: adapter)

        let chapterZero = builder.makeItems(forChapter: 0)
        XCTAssertEqual(chapterZero.sceneHeaderIndices.count, 2)
        XCTAssertTrue(chapterZero.items.allSatisfy { item in
            switch item {
            case .sceneHeader, .bubble:
                return true
            }
        })
        XCTAssertEqual(chapterZero.items.filter {
            if case .bubble = $0 { return true }
            return false
        }.count, 3)

        let chapterOne = builder.makeItems(forChapter: 1)
        XCTAssertEqual(chapterOne.sceneHeaderIndices.count, 1)
        XCTAssertEqual(chapterOne.items.filter {
            if case .bubble = $0 { return true }
            return false
        }.count, 1)
    }

    func testDialogStorySpineInterleavesChapterMarkersWithScenes() throws {
        let story = try makeDialogStory()
        XCTAssertEqual(
            StoryReadingSpine.make(for: story, mode: .dialogStory).items.map(\.id),
            [
                "cover",
                "matter-0-about",
                "chapter-0",
                "scene-0-0",
                "scene-0-1",
                "chapter-1",
                "scene-1-0"
            ]
        )
    }

    private func makeDialogStory() throws -> Story {
        let chapters = [
            StoryChapter(
                chapterNumber: 1,
                titleTargetLanguage: "Capitulo Uno",
                titleEnglish: "Chapter One",
                scenes: [
                    StoryScene(
                        sceneIndex: 0,
                        dialogues: [
                            SceneDialogue(character: "LUZ", text: "Hola", textEnglish: "Hello")
                        ]
                    ),
                    StoryScene(
                        sceneIndex: 1,
                        dialogues: [
                            SceneDialogue(character: "MATEO", text: "Que tal?", textEnglish: "How are you?"),
                            SceneDialogue(character: "LUZ", text: "Bien", textEnglish: "Fine")
                        ]
                    )
                ]
            ),
            StoryChapter(
                chapterNumber: 2,
                titleTargetLanguage: "Capitulo Dos",
                titleEnglish: "Chapter Two",
                scenes: [
                    StoryScene(
                        sceneIndex: 0,
                        dialogues: [
                            SceneDialogue(character: "LUZ", text: "Adios", textEnglish: "Bye")
                        ]
                    )
                ]
            )
        ]

        let readingMatterPages = [
            ReadingMatterPage(
                id: "about",
                placement: nil,
                titleTarget: "Acerca",
                titleNative: nil,
                bodyTarget: "Intro",
                bodyNative: nil
            )
        ]

        return Story(
            userID: "test-user",
            title: "Dialog Test",
            targetLanguageText: "",
            chaptersJSON: try encode(chapters),
            readingMatterPagesJSON: try encode(readingMatterPages),
            language: .spanish,
            level: 1
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
