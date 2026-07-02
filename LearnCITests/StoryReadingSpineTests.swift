import XCTest
@testable import LearnCI

@MainActor
final class StoryReadingSpineTests: XCTestCase {
    func testCanonicalChapterSceneAndReadingMatterDecode() throws {
        let chapterJSON = """
        {
          "chapter_number": 1,
          "title": { "by_language": { "es": { "text": "Capitulo Uno" }, "en": { "text": "Chapter One" } } },
          "intro": { "by_language": { "es": { "text": "Antes de empezar", "audio_url": "a/intro.m4a" } } },
          "vocabulary": { "by_language": { "es": { "note": "ojo = eye" } } },
          "comprehension": { "by_language": { "es": { "questions": [{ "question": "Que paso?", "choices": ["A", "B", "C", "D"], "correct_index": 0 }] } } },
          "scenes": [
            {
              "sceneIndex": 0,
              "byLanguage": {
                "es": { "caption": "Hola mundo", "script": "[LUZ] Hola mundo", "audioUrl": "a/scene.m4a", "wordTimings": [{ "word": "Hola", "start": 0.0, "end": 0.4 }], "audioDurationMs": 1200, "dialogues": [{ "character": "LUZ", "text": "Hola" }] },
                "en": { "caption": "Hello world", "dialogues": [{ "character": "LUZ", "text": "Hello" }] }
              }
            }
          ]
        }
        """
        let chapter = try JSONDecoder().decode(StoryChapter.self, from: Data(chapterJSON.utf8))

        XCTAssertEqual(chapter.titleFor("es"), "Capitulo Uno")
        XCTAssertEqual(chapter.chapterIntroAudioUrlForLanguage("es"), "a/intro.m4a")
        XCTAssertEqual(chapter.vocabularyNoteForLanguage("es"), "ojo = eye")
        XCTAssertEqual(chapter.comprehensionQuestionsForLanguage("es").count, 1)
        XCTAssertEqual(chapter.bodyTextForLanguage("es"), "Hola mundo")
        XCTAssertEqual(chapter.bodyScriptForLanguage("es"), "[LUZ] Hola mundo")
        XCTAssertEqual(chapter.scenes[0].audioUrlForLanguage("es"), "a/scene.m4a")
        XCTAssertEqual(chapter.scenes[0].wordTimingsFor("es").first?.word, "Hola")
        XCTAssertEqual(chapter.scenes[0].audioDurationMsFor("es"), 1200)
        XCTAssertEqual(chapter.scenes[0].dialoguesFor("en").first?.text, "Hello")

        let pagesJSON = """
        {
          "pages": [
            {
              "id": "characters",
              "kind": "characters",
              "placement": "beforeChapters",
              "by_language": {
                "es": {
                  "title": "Personajes",
                  "body": "LUZ es curiosa.",
                  "audio_url": "a/characters.m4a",
                  "word_timings": [{ "word": "Personajes", "start": 0.0, "end": 0.5 }, { "word": "LUZ", "start": 0.5, "end": 0.8 }],
                  "structured_rows": { "rows": [{ "name": "LUZ", "role": "Hero", "bio": "Curious", "relationships": "Mateo" }] }
                }
              }
            }
          ]
        }
        """
        let story = Story(
            userID: "test-user",
            title: "Decode Test",
            targetLanguageText: "",
            chaptersJSON: try encode([chapter]),
            readingMatterPagesJSON: pagesJSON,
            language: .spanish,
            nativeLanguageCode: "en",
            level: 1
        )

        let page = try XCTUnwrap(story.readingMatterPages.first)
        XCTAssertEqual(page.titleFor("es"), "Personajes")
        XCTAssertEqual(page.audioUrlFor("es"), "a/characters.m4a")
        XCTAssertEqual(page.bodyWordTimingsFor("es").map(\.word), ["LUZ"])
        XCTAssertEqual(page.characterRowsFor("es").first?.name, "LUZ")
    }

    func testStoryBookSpineUsesCoverReadingMatterAndChapterSupplements() throws {
        let story = try makeStory(
            chapters: [
                testChapter(
                    number: 1,
                    targetTitle: "Capitulo Uno",
                    scenes: [testScene(index: 0, caption: "Escena uno", audio: "a/scene_0.m4a")],
                    vocab: "ojo = eye"
                ),
                testChapter(
                    number: 2,
                    targetTitle: "Capitulo Dos",
                    scenes: [testScene(index: 0, caption: "Escena dos", audio: "a/scene_1.m4a")],
                    questions: [ComprehensionQuestion(question: "Que paso?", choices: ["A", "B", "C", "D"], correctIndex: 1)]
                )
            ],
            pages: [testReadingPage(id: "about", title: "Acerca", body: "Intro", placement: .beforeChapters)]
        )

        XCTAssertEqual(
            StoryReadingSpine.make(for: story, mode: .storyBook).items.map(\.id),
            ["cover", "matter-0-about", "chapter-0", "vocab-0", "chapter-1", "quiz-1"]
        )
    }

    func testPictureBookSpineInsertsChapterIntroBeforeFirstScene() throws {
        let story = try makeStory(
            chapters: [
                testChapter(
                    number: 1,
                    targetTitle: "Capitulo Uno",
                    intro: "Antes de empezar",
                    introAudio: "a/intro.m4a",
                    scenes: [testScene(index: 0, caption: "Escena uno", audio: "a/scene_0.m4a")]
                )
            ],
            layout: StoryLayout(flatSequence: [PanelLayout(chapterIndex: 0, sceneIndex: 0)])
        )

        XCTAssertEqual(
            StoryReadingSpine.make(for: story, mode: .pictureBook).items.map(\.id),
            ["cover", "chapter-0", "scene-0-0"]
        )
    }

    func testReadingMatterAudioClipUsesRequestedLanguage() throws {
        let page = testReadingPage(
            id: "about",
            title: "Acerca",
            body: "Intro",
            audio: "a/about_es.m4a",
            nativeTitle: "About",
            nativeBody: "Intro native",
            nativeAudio: "a/about_en.m4a"
        )
        let story = try makeStory(pages: [page])
        let adapter = StoryReaderDataAdapter(story: story)

        let targetClip = try XCTUnwrap(adapter.readingMatterAudioClip(pageIndex: 0, page: page, preferNative: false))
        let nativeClip = try XCTUnwrap(adapter.readingMatterAudioClip(pageIndex: 0, page: page, preferNative: true))

        XCTAssertEqual(targetClip.urlString, "a/about_es.m4a")
        XCTAssertEqual(nativeClip.urlString, "a/about_en.m4a")
    }

    func testChapterBodyAndTimingOffsetsJoinScenesByLanguage() {
        let chapter = testChapter(
            number: 1,
            targetTitle: "Capitulo Uno",
            scenes: [
                testScene(
                    index: 0,
                    caption: "Uno",
                    script: "[LUZ] Uno",
                    audio: "a/one.m4a",
                    timings: [WordTiming(word: "Uno", start: 0.0, end: 0.5)],
                    durationMs: 1_000
                ),
                testScene(
                    index: 1,
                    caption: "Dos",
                    script: "[LUZ] Dos",
                    audio: "a/two.m4a",
                    timings: [WordTiming(word: "Dos", start: 0.0, end: 0.5)],
                    durationMs: 2_000
                )
            ]
        )

        XCTAssertEqual(chapter.bodyTextForLanguage("es"), "Uno\n\nDos")
        XCTAssertEqual(chapter.bodyScriptForLanguage("es"), "[LUZ] Uno\n\n[LUZ] Dos")
        XCTAssertEqual(chapter.bodyWordTimingsForLanguage("es").map { $0.start }, [0.0, 1.0])
    }

    func testRequirementIsIncompleteWhenTargetSceneAudioIsMissing() throws {
        let story = try makeStory(
            chapters: [
                testChapter(
                    number: 1,
                    targetTitle: "Capitulo Uno",
                    scenes: [testScene(index: 0, caption: "Escena uno", audio: nil)]
                )
            ]
        )

        XCTAssertEqual(StoryReaderDataAdapter(story: story).requirementIssue(for: .storyBook), .incompleteSceneAudio)
    }

    func testChapterIntroSpeakableTextUsesRequestedLanguageOnly() {
        let chapter = testChapter(
            number: 1,
            targetTitle: "Capitulo Uno",
            nativeTitle: "Chapter One",
            intro: "Antes de empezar",
            nativeIntro: "Before starting"
        )

        XCTAssertEqual(
            StorySupplementalAudioPlayback.chapterIntroSpeakableText(
                chapter: chapter,
                preferNative: false,
                targetCode: "es",
                nativeCode: "en"
            ),
            "Antes de empezar"
        )
        XCTAssertEqual(
            StorySupplementalAudioPlayback.chapterIntroSpeakableText(
                chapter: chapter,
                preferNative: true,
                targetCode: "es",
                nativeCode: "en"
            ),
            "Before starting"
        )
    }

    func testDialogAccessorsPairTargetAndNativeByIndex() {
        let scene = testScene(
            index: 0,
            caption: "Dialogo",
            targetDialogues: [
                SceneDialogue(character: "LUZ", text: "Hola"),
                SceneDialogue(character: "MATEO", text: "Vamos")
            ],
            nativeDialogues: [
                SceneDialogue(character: "LUZ", text: "Hello"),
                SceneDialogue(character: "MATEO", text: "Let's go")
            ]
        )

        XCTAssertEqual(scene.dialoguesFor("es")[1].text, "Vamos")
        XCTAssertEqual(scene.dialoguesFor("en")[1].text, "Let's go")
    }

    func testStructuredGlossaryRowsDecodeFromCanonicalPage() {
        let page = ReadingMatterPage(
            id: "glossary",
            placement: .afterChapters,
            kind: .glossary,
            byLanguage: [
                "es": ReadingMatterPageLanguageData(
                    title: "Glosario",
                    body: "ojo means eye",
                    structuredRowsJson: """
                    { "rows": [{ "targetWord": "ojo", "nativeGloss": "eye", "partOfSpeech": "noun", "exampleTarget": "El ojo", "exampleNative": "The eye", "firstChapterIndex": 0 }] }
                    """
                )
            ]
        )

        XCTAssertEqual(page.glossaryRowsFor("es").first?.targetWord, "ojo")
        XCTAssertEqual(page.bodyFor("es"), "ojo means eye")
    }

    private func makeStory(
        chapters: [StoryChapter]? = nil,
        pages: [ReadingMatterPage] = [],
        layout: StoryLayout? = nil
    ) throws -> Story {
        let resolvedChapters = chapters ?? [
            testChapter(
                number: 1,
                targetTitle: "Capitulo Uno",
                scenes: [testScene(index: 0, caption: "Escena", audio: "a/scene.m4a")]
            )
        ]
        return Story(
            userID: "test-user",
            title: "Spine Test",
            targetLanguageText: "",
            chaptersJSON: try encode(resolvedChapters),
            layoutJSON: try layout.map(encode),
            readingMatterPagesJSON: try encodePages(pages),
            language: .spanish,
            nativeLanguageCode: "en",
            level: 1
        )
    }

    private func testChapter(
        number: Int,
        targetTitle: String,
        nativeTitle: String = "Chapter",
        intro: String? = nil,
        nativeIntro: String? = nil,
        introAudio: String? = nil,
        scenes: [StoryScene] = [],
        vocab: String? = nil,
        questions: [ComprehensionQuestion] = []
    ) -> StoryChapter {
        var introLanguages: [String: ChapterIntroLang] = [:]
        if let intro {
            introLanguages["es"] = ChapterIntroLang(text: intro, audioUrl: introAudio)
        }
        if let nativeIntro {
            introLanguages["en"] = ChapterIntroLang(text: nativeIntro)
        }

        var vocabLanguages: [String: ChapterVocabLang] = [:]
        if let vocab {
            vocabLanguages["es"] = ChapterVocabLang(note: vocab)
        }

        var comprehensionLanguages: [String: ChapterComprehensionLang] = [:]
        if !questions.isEmpty {
            comprehensionLanguages["es"] = ChapterComprehensionLang(questions: questions)
        }

        return StoryChapter(
            chapterNumber: number,
            scenes: scenes,
            title: ChapterLangEnvelope(byLanguage: [
                "es": ChapterTitleLang(text: targetTitle),
                "en": ChapterTitleLang(text: nativeTitle)
            ]),
            intro: ChapterLangEnvelope(byLanguage: introLanguages),
            vocabulary: ChapterLangEnvelope(byLanguage: vocabLanguages),
            comprehension: ChapterLangEnvelope(byLanguage: comprehensionLanguages)
        )
    }

    private func testScene(
        index: Int,
        caption: String,
        script: String? = nil,
        audio: String? = "a/scene.m4a",
        timings: [WordTiming] = [],
        durationMs: Int = 0,
        targetDialogues: [SceneDialogue] = [],
        nativeDialogues: [SceneDialogue] = []
    ) -> StoryScene {
        StoryScene(
            sceneIndex: index,
            byLanguage: [
                "es": SceneLanguageData(
                    caption: caption,
                    script: script,
                    audioUrl: audio,
                    wordTimings: timings,
                    audioDurationMs: durationMs,
                    dialogues: targetDialogues
                ),
                "en": SceneLanguageData(
                    caption: "Native \(caption)",
                    dialogues: nativeDialogues
                )
            ]
        )
    }

    private func testReadingPage(
        id: String,
        title: String,
        body: String,
        placement: ReadingMatterPlacement = .beforeChapters,
        audio: String? = nil,
        nativeTitle: String = "",
        nativeBody: String = "",
        nativeAudio: String? = nil
    ) -> ReadingMatterPage {
        ReadingMatterPage(
            id: id,
            placement: placement,
            byLanguage: [
                "es": ReadingMatterPageLanguageData(title: title, body: body, audioUrl: audio),
                "en": ReadingMatterPageLanguageData(title: nativeTitle, body: nativeBody, audioUrl: nativeAudio)
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
