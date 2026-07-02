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

    func testDialogPairsTargetAndNativeRowsByIndex() throws {
        let story = try makeDialogStory()
        let adapter = StoryReaderDataAdapter(story: story)
        let scene = try XCTUnwrap(adapter.scene(for: .scene(chapterIndex: 0, sceneIndex: 1)))

        XCTAssertEqual(scene.dialoguesFor(story.targetLanguageCode).map(\.text), ["Que tal?", "Bien"])
        XCTAssertEqual(scene.dialoguesFor(story.nativeLanguageCode).map(\.text), ["How are you?", "Fine"])
    }

    private func makeDialogStory() throws -> Story {
        let chapters = [
            testChapter(
                number: 1,
                targetTitle: "Capitulo Uno",
                nativeTitle: "Chapter One",
                scenes: [
                    testScene(
                        index: 0,
                        targetCaption: "Saludo",
                        nativeCaption: "Greeting",
                        targetDialogues: [SceneDialogue(character: "LUZ", text: "Hola")],
                        nativeDialogues: [SceneDialogue(character: "LUZ", text: "Hello")]
                    ),
                    testScene(
                        index: 1,
                        targetCaption: "Encuentro",
                        nativeCaption: "Meeting",
                        targetDialogues: [
                            SceneDialogue(character: "MATEO", text: "Que tal?"),
                            SceneDialogue(character: "LUZ", text: "Bien")
                        ],
                        nativeDialogues: [
                            SceneDialogue(character: "MATEO", text: "How are you?"),
                            SceneDialogue(character: "LUZ", text: "Fine")
                        ]
                    )
                ]
            ),
            testChapter(
                number: 2,
                targetTitle: "Capitulo Dos",
                nativeTitle: "Chapter Two",
                scenes: [
                    testScene(
                        index: 0,
                        targetCaption: "Despedida",
                        nativeCaption: "Goodbye",
                        targetDialogues: [SceneDialogue(character: "LUZ", text: "Adios")],
                        nativeDialogues: [SceneDialogue(character: "LUZ", text: "Bye")]
                    )
                ]
            )
        ]

        let readingMatterPages = [
            testReadingMatterPage(id: "about", targetTitle: "Acerca", targetBody: "Intro")
        ]

        return Story(
            userID: "test-user",
            title: "Dialog Test",
            targetLanguageText: "",
            chaptersJSON: try encode(chapters),
            readingMatterPagesJSON: try encodePages(readingMatterPages),
            language: .spanish,
            nativeLanguageCode: "en",
            level: 1
        )
    }

    private func testChapter(
        number: Int,
        targetTitle: String,
        nativeTitle: String,
        scenes: [StoryScene]
    ) -> StoryChapter {
        StoryChapter(
            chapterNumber: number,
            scenes: scenes,
            title: ChapterLangEnvelope(byLanguage: [
                "es": ChapterTitleLang(text: targetTitle),
                "en": ChapterTitleLang(text: nativeTitle)
            ])
        )
    }

    private func testScene(
        index: Int,
        targetCaption: String,
        nativeCaption: String,
        targetDialogues: [SceneDialogue],
        nativeDialogues: [SceneDialogue]
    ) -> StoryScene {
        StoryScene(
            sceneIndex: index,
            byLanguage: [
                "es": SceneLanguageData(caption: targetCaption, dialogues: targetDialogues),
                "en": SceneLanguageData(caption: nativeCaption, dialogues: nativeDialogues)
            ]
        )
    }

    private func testReadingMatterPage(id: String, targetTitle: String, targetBody: String) -> ReadingMatterPage {
        ReadingMatterPage(
            id: id,
            placement: .beforeChapters,
            byLanguage: [
                "es": ReadingMatterPageLanguageData(title: targetTitle, body: targetBody)
            ]
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func encodePages(_ pages: [ReadingMatterPage]) throws -> String {
        struct Envelope: Encodable {
            let pages: [ReadingMatterPage]
        }
        return try encode(Envelope(pages: pages))
    }
}
