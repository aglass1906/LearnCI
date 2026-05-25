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

final class YouTubeCaptionServiceTests: XCTestCase {
    func testParseCaptionTracksExtractsManualAndAutoTracks() throws {
        let tracks = try YouTubeCaptionService.parseCaptionTracks(fromWatchPageHTML: sampleWatchHTML)

        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks[0].languageCode, "es")
        XCTAssertEqual(tracks[0].languageName, "Spanish")
        XCTAssertFalse(tracks[0].isAutoGenerated)
        XCTAssertTrue(tracks[1].isAutoGenerated)
        XCTAssertEqual(tracks[0].url, "https://www.youtube.com/api/timedtext?v=test&lang=es")
    }

    func testParseCaptionTracksSkipsNullInitialPlayerResponse() throws {
        let tracks = try YouTubeCaptionService.parseCaptionTracks(fromWatchPageHTML: sampleWatchHTMLWithNullPlayerResponse)

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].languageCode, "ja")
        XCTAssertEqual(tracks[0].languageName, "Japanese")
    }

    func testParseCaptionTracksFromPlayerResponseHandlesAndroidSrv3URL() throws {
        let tracks = try YouTubeCaptionService.parseCaptionTracks(fromPlayerResponse: samplePlayerResponse)

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].id, "a.es")
        XCTAssertEqual(tracks[0].languageCode, "es")
        XCTAssertTrue(tracks[0].isAutoGenerated)
        XCTAssertEqual(
            tracks[0].url,
            "https://www.youtube.com/api/timedtext?v=test&lang=es&kind=asr&fmt=srv3"
        )
    }

    func testSelectPreferredTrackPrefersManualMatchOverAutoTrack() {
        let manual = YouTubeCaptionTrack(
            id: "es-manual",
            languageCode: "es",
            languageName: "Spanish",
            kind: .standard
        )
        let auto = YouTubeCaptionTrack(
            id: "a.es",
            languageCode: "es",
            languageName: "Spanish",
            kind: .asr
        )

        let selected = YouTubeCaptionService.selectPreferredTrack(
            from: [auto, manual],
            preferredLanguageCode: "es-MX"
        )

        XCTAssertEqual(selected?.id, manual.id)
    }

    func testSelectPreferredTrackWithoutPreferenceUsesDefaultManualTrack() {
        let auto = YouTubeCaptionTrack(
            id: "a.es",
            languageCode: "es",
            languageName: "Spanish",
            kind: .asr
        )
        let manualDefault = YouTubeCaptionTrack(
            id: "es-manual",
            languageCode: "es",
            languageName: "Spanish",
            kind: .standard,
            isDefault: true
        )

        let selected = YouTubeCaptionService.selectPreferredTrack(
            from: [auto, manualDefault],
            preferredLanguageCode: nil
        )

        XCTAssertEqual(selected?.id, manualDefault.id)
    }

    func testParseCuesNormalizesWhitespaceAndSkipsBlankEvents() throws {
        let cues = try YouTubeCaptionService.parseCues(fromJSON3Data: sampleJSON3Transcript)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Hola mundo")
        XCTAssertEqual(cues[1].text, "Como estas?")
        XCTAssertEqual(cues[0].startTime, 0, accuracy: 0.001)
        XCTAssertEqual(cues[1].endTime, 4.0, accuracy: 0.001)
    }

    func testParseCuesFallsBackFromXMLTimedText() throws {
        let cues = try YouTubeCaptionService.parseCues(fromXMLData: sampleXMLTranscript)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Hola mundo")
        XCTAssertEqual(cues[1].text, "Como estas?")
    }

    func testParseCuesParsesSrv3TimedText() throws {
        let cues = try YouTubeCaptionService.parseCues(fromXMLData: sampleSrv3XMLTranscript)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "En esta isla abandonada viven solo")
        XCTAssertEqual(cues[0].startTime, 0.12, accuracy: 0.001)
        XCTAssertEqual(cues[0].endTime, 4.52, accuracy: 0.001)
        XCTAssertEqual(cues[1].text, "[música] tres personas y decenas de")
        XCTAssertEqual(cues[1].startTime, 1.979, accuracy: 0.001)
    }

    private var sampleWatchHTML: String {
        """
        <html>
        <head></head>
        <body>
        <script>
        var ytInitialPlayerResponse = {"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[{"baseUrl":"https://www.youtube.com/api/timedtext?v=test&lang=es","name":{"simpleText":"Spanish"},"vssId":".es","languageCode":"es","isDefault":true},{"baseUrl":"https://www.youtube.com/api/timedtext?v=test&lang=es&kind=asr","name":{"runs":[{"text":"Spanish (auto-generated)"}]},"vssId":"a.es","languageCode":"es","kind":"asr"}]}}};
        </script>
        </body>
        </html>
        """
    }

    private var sampleWatchHTMLWithNullPlayerResponse: String {
        """
        <html>
        <head></head>
        <body>
        <script>
        var ytInitialPlayerResponse = null;
        </script>
        <script>
        ytInitialPlayerResponse = {"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[{"baseUrl":"https://www.youtube.com/api/timedtext?v=test&lang=ja","name":{"simpleText":"Japanese"},"vssId":".ja","languageCode":"ja","isDefault":true}]}}};
        </script>
        </body>
        </html>
        """
    }

    private var samplePlayerResponse: [String: Any] {
        [
            "captions": [
                "playerCaptionsTracklistRenderer": [
                    "captionTracks": [
                        [
                            "baseUrl": "https://www.youtube.com/api/timedtext?v=test&lang=es&kind=asr&fmt=srv3",
                            "name": ["runs": [["text": "Spanish (auto-generated)"]]],
                            "vssId": "a.es",
                            "languageCode": "es",
                            "kind": "asr"
                        ]
                    ]
                ]
            ]
        ]
    }

    private var sampleJSON3Transcript: Data {
        let json = """
        {
          "events": [
            {
              "tStartMs": 0,
              "dDurationMs": 1500,
              "segs": [
                { "utf8": "Hola\\n" },
                { "utf8": " mundo " }
              ]
            },
            {
              "tStartMs": 1800,
              "dDurationMs": 2200,
              "segs": [
                { "utf8": "   " }
              ]
            },
            {
              "tStartMs": 2200,
              "dDurationMs": 1800,
              "segs": [
                { "utf8": "Como" },
                { "utf8": " estas?" }
              ]
            }
          ]
        }
        """

        return Data(json.utf8)
    }

    private var sampleXMLTranscript: Data {
        let xml = """
        <?xml version="1.0" encoding="utf-8" ?><transcript>
          <text start="0.0" dur="1.5">Hola mundo</text>
          <text start="2.2" dur="1.8">Como estas?</text>
        </transcript>
        """

        return Data(xml.utf8)
    }

    private var sampleSrv3XMLTranscript: Data {
        let xml = """
        <?xml version="1.0" encoding="utf-8" ?><timedtext format="3"><body>
          <p t="120" d="4400"><s>En</s><s t="160"> esta</s><s t="360"> isla</s><s t="720"> abandonada</s><s t="1440"> viven</s><s t="1839"> solo</s></p>
          <p t="1979" d="5226"><s>[música]</s><s t="420"> tres</s><s t="861"> personas</s><s t="1460"> y</s><s t="1781"> decenas</s><s t="2340"> de</s></p>
        </body></timedtext>
        """

        return Data(xml.utf8)
    }
}

@MainActor
final class YouTubeStudyViewModelTests: XCTestCase {
    func testApplyTranscriptMarksStudyModeAvailable() {
        let video = makeVideo()
        let track = YouTubeCaptionTrack(
            id: "es-manual",
            languageCode: "es",
            languageName: "Spanish",
            kind: .standard,
            isDefault: true
        )
        let cues = [
            YouTubeCaptionCue(index: 0, startTime: 0, endTime: 1.5, text: "Hola"),
            YouTubeCaptionCue(index: 1, startTime: 1.5, endTime: 3.0, text: "Adios")
        ]
        let viewModel = YouTubeStudyViewModel(video: video)

        viewModel.applyTranscript(cues: cues, track: track)

        XCTAssertEqual(viewModel.captionLoadState, .loaded)
        XCTAssertEqual(viewModel.availability, .available)
        XCTAssertTrue(viewModel.canEnterStudyMode)
        XCTAssertEqual(viewModel.activeCues.count, 2)
    }

    func testSetStudyUnavailableReturnsToWatchMode() {
        let viewModel = YouTubeStudyViewModel(video: makeVideo())

        viewModel.setMode(.study)
        viewModel.setStudyUnavailable(reason: "No captions")

        XCTAssertEqual(viewModel.mode, .watch)
        XCTAssertEqual(viewModel.availability, .unavailable(reason: "No captions"))
        XCTAssertTrue(viewModel.activeCues.isEmpty)
    }

    func testRequestSeekConsumesPendingValue() {
        let viewModel = YouTubeStudyViewModel(video: makeVideo())

        viewModel.requestSeek(to: 12.5)

        XCTAssertEqual(viewModel.consumePendingSeek() ?? 0, 12.5, accuracy: 0.001)
        XCTAssertNil(viewModel.consumePendingSeek())
    }

    func testActiveCuePrefersLatestOverlappingCue() {
        let track = YouTubeCaptionTrack(
            id: "es-manual",
            languageCode: "es",
            languageName: "Spanish",
            kind: .standard,
            isDefault: true
        )
        let cues = [
            YouTubeCaptionCue(index: 0, startTime: 0.0, endTime: 2.0, text: "Primero"),
            YouTubeCaptionCue(index: 1, startTime: 1.2, endTime: 2.8, text: "Segundo")
        ]
        let viewModel = YouTubeStudyViewModel(video: makeVideo())

        viewModel.applyTranscript(cues: cues, track: track)
        viewModel.updatePlayback(currentTime: 1.5)

        XCTAssertEqual(viewModel.activeCue?.text, "Segundo")
    }

    private func makeVideo() -> YouTubeVideo {
        YouTubeVideo(
            id: "abc123",
            title: "Test Video",
            description: "Description",
            thumbnailURL: "https://example.com/thumb.jpg",
            channelTitle: "Channel",
            duration: "PT5M",
            publishedAt: Date(),
            videoStreamURL: nil,
            addedToFeedAt: nil,
            language: .spanish,
            level: .beginner
        )
    }
}
