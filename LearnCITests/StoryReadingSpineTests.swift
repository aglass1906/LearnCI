import XCTest
@testable import LearnCI

@MainActor
final class StoryReadingSpineTests: XCTestCase {
    func testStoryBookSpineUsesCoverReadingMatterAndChapters() throws {
        let story = try makeStory(layout: nil)

        XCTAssertEqual(
            StoryReadingSpine.make(for: story, mode: .storyBook).items.map(\.id),
            ["cover", "matter-0-about", "chapter-0", "chapter-1"]
        )
    }

    func testStoryBookSpinePlacesBackMatterAfterChapters() throws {
        let story = try makeStory(
            layout: nil,
            readingMatterPages: [
                ReadingMatterPage(
                    id: "about",
                    placement: "front",
                    titleTarget: "Acerca",
                    titleNative: nil,
                    bodyTarget: "Intro",
                    bodyNative: nil
                ),
                ReadingMatterPage(
                    id: "appendix",
                    placement: "back",
                    titleTarget: "Apendice",
                    titleNative: nil,
                    bodyTarget: "Back matter",
                    bodyNative: nil
                )
            ]
        )

        XCTAssertEqual(
            StoryReadingSpine.make(for: story, mode: .storyBook).items.map(\.id),
            ["cover", "matter-0-about", "chapter-0", "chapter-1", "matter-1-appendix"]
        )
    }

    func testDialogStorySpinePlacesBackMatterAfterScenes() throws {
        let story = try makeStory(
            layout: nil,
            readingMatterPages: [
                ReadingMatterPage(
                    id: "about",
                    placement: nil,
                    titleTarget: "Acerca",
                    titleNative: nil,
                    bodyTarget: "Intro",
                    bodyNative: nil
                ),
                ReadingMatterPage(
                    id: "credits",
                    placement: "appendix",
                    titleTarget: "Creditos",
                    titleNative: nil,
                    bodyTarget: "Credits",
                    bodyNative: nil
                )
            ]
        )

        XCTAssertEqual(
            StoryReadingSpine.make(for: story, mode: .dialogStory).items.map(\.id),
            ["cover", "matter-0-about", "chapter-0", "chapter-1", "scene-0-0", "scene-0-1", "scene-1-0", "matter-1-credits"]
        )
    }

    func testDialogStorySpineRecognizesBackMatterPlacementVariants() throws {
        let story = try makeStory(
            layout: nil,
            readingMatterPages: [
                ReadingMatterPage(
                    id: "about",
                    placement: "ABOUT_READING_MATTER",
                    titleTarget: "Acerca",
                    titleNative: nil,
                    bodyTarget: "Intro",
                    bodyNative: nil
                ),
                ReadingMatterPage(
                    id: "reader-guide",
                    placement: "reading-back-matter",
                    titleTarget: "Guia",
                    titleNative: nil,
                    bodyTarget: "Back matter",
                    bodyNative: nil
                ),
                ReadingMatterPage(
                    id: "credits",
                    placement: nil,
                    titleTarget: "Credits",
                    titleNative: nil,
                    bodyTarget: "Credits",
                    bodyNative: nil
                )
            ]
        )

        XCTAssertEqual(
            StoryReadingSpine.make(for: story, mode: .dialogStory).items.map(\.id),
            ["cover", "matter-0-about", "chapter-0", "chapter-1", "scene-0-0", "scene-0-1", "scene-1-0", "matter-1-reader-guide", "matter-2-credits"]
        )
    }

    func testAudioBookSpineAddsScenesAfterChapterSections() throws {
        let story = try makeStory(layout: nil)

        XCTAssertEqual(
            StoryReadingSpine.make(for: story, mode: .audioBook).items.map(\.id),
            ["cover", "matter-0-about", "chapter-0", "chapter-1", "scene-0-0", "scene-0-1", "scene-1-0"]
        )
    }

    func testPictureBookSpinePrefersLayoutFlatSequence() throws {
        let layout = StoryLayout(
            flatSequence: [
                PanelLayout(chapterIndex: 1, sceneIndex: 0),
                PanelLayout(chapterIndex: 0, sceneIndex: 1)
            ]
        )
        let story = try makeStory(layout: layout)

        XCTAssertEqual(
            StoryReadingSpine.make(for: story, mode: .pictureBook).items.map(\.id),
            ["cover", "matter-0-about", "scene-1-0", "scene-0-1"]
        )
    }

    func testPictureBookSpineFallsBackToChapterSceneOrderWithoutFlatSequence() throws {
        let story = try makeStory(layout: StoryLayout())

        XCTAssertEqual(
            StoryReadingSpine.make(for: story, mode: .pictureBook).items.map(\.id),
            ["cover", "matter-0-about", "scene-0-0", "scene-0-1", "scene-1-0"]
        )
    }

    private func makeStory(
        layout: StoryLayout?,
        readingMatterPages: [ReadingMatterPage]? = nil
    ) throws -> Story {
        let chapters = [
            StoryChapter(
                chapterNumber: 1,
                titleTargetLanguage: "Capitulo Uno",
                titleEnglish: "Chapter One",
                scenes: [
                    StoryScene(sceneIndex: 1, captionTarget: "Escena dos", captionNative: "Scene two", audioUrl: "a/scene_1.mp3"),
                    StoryScene(sceneIndex: 0, captionTarget: "Escena uno", captionNative: "Scene one", audioUrl: "a/scene_0.mp3")
                ]
            ),
            StoryChapter(
                chapterNumber: 2,
                titleTargetLanguage: "Capitulo Dos",
                titleEnglish: "Chapter Two",
                scenes: [
                    StoryScene(sceneIndex: 0, captionTarget: "Escena tres", captionNative: "Scene three", audioUrl: "a/scene_2.mp3")
                ]
            )
        ]
        let defaultReadingMatterPages = [
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
            title: "Test Story",
            targetLanguageText: "",
            chaptersJSON: try encode(chapters),
            layoutJSON: try layout.map(encode),
            readingMatterPagesJSON: try encode(readingMatterPages ?? defaultReadingMatterPages),
            language: .spanish,
            level: 1
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
