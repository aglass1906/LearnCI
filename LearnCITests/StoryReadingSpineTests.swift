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

    func testPictureBookRendererUsesSpineOrderWithBackMatter() throws {
        let layout = StoryLayout(
            flatSequence: [
                PanelLayout(chapterIndex: 1, sceneIndex: 0),
                PanelLayout(chapterIndex: 0, sceneIndex: 1)
            ]
        )
        let story = try makeStory(
            layout: layout,
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

        let spreads = PictureBookRenderer.makeSpreads(story: story, adapter: StoryReaderDataAdapter(story: story))

        XCTAssertEqual(
            spreads.map(\.id),
            ["cover", "matter-0-about", "scene-1-0", "scene-0-1", "matter-1-appendix"]
        )
        XCTAssertEqual(spreads[2].audioClip?.sceneIndex, 0)
        XCTAssertEqual(spreads[3].audioClip?.sceneIndex, 1)
    }

    func testPictureBookRendererAttachesMatchingLayoutPanel() throws {
        let expectedPanel = PanelLayout(
            chapterIndex: 0,
            sceneIndex: 1,
            x: 10,
            y: 20,
            width: 80,
            height: 60,
            cropRegion: .topRight
        )
        let story = try makeStory(layout: StoryLayout(flatSequence: [expectedPanel]))

        let spreads = PictureBookRenderer.makeSpreads(story: story, adapter: StoryReaderDataAdapter(story: story))
        let sceneSpread = try XCTUnwrap(spreads.first { $0.id == "scene-0-1" })

        XCTAssertEqual(sceneSpread.panel, expectedPanel)
        XCTAssertEqual(sceneSpread.audioClip?.chapterIndex, 0)
        XCTAssertEqual(sceneSpread.audioClip?.sceneIndex, 1)
    }

    func testPictureBookRendererUsesLayoutPagePanelsWhenPresent() throws {
        let layout = StoryLayout(
            pages: [
                StoryPage(
                    chapterIndex: 0,
                    sceneIndex: 1,
                    canvases: [
                        StoryCanvas(panels: [
                            PanelLayout(chapterIndex: 0, sceneIndex: 1, x: 0, y: 0, width: 0.5, height: 1, cropRegion: .topLeft),
                            PanelLayout(chapterIndex: 1, sceneIndex: 0, x: 0.5, y: 0, width: 0.5, height: 1, cropRegion: .topRight)
                        ])
                    ]
                )
            ],
            flatSequence: [
                PanelLayout(chapterIndex: 0, sceneIndex: 1),
                PanelLayout(chapterIndex: 1, sceneIndex: 0)
            ]
        )
        let story = try makeStory(layout: layout)

        let spreads = PictureBookRenderer.makeSpreads(story: story, adapter: StoryReaderDataAdapter(story: story))
        let sceneSpread = try XCTUnwrap(spreads.first { $0.id == "scene-0-1" })

        XCTAssertEqual(sceneSpread.layoutPanels.map { $0.panel.sceneIndex }, [1, 0])
        XCTAssertEqual(sceneSpread.layoutPanels.map { $0.panel.chapterIndex }, [0, 1])
    }

    func testPictureBookRendererDedupesDuplicateLayoutPanels() throws {
        let layout = StoryLayout(
            flatSequence: [
                PanelLayout(chapterIndex: 0, sceneIndex: 1),
                PanelLayout(chapterIndex: 0, sceneIndex: 1),
                PanelLayout(chapterIndex: 1, sceneIndex: 0)
            ]
        )
        let story = try makeStory(layout: layout)

        let spreads = PictureBookRenderer.makeSpreads(story: story, adapter: StoryReaderDataAdapter(story: story))

        XCTAssertEqual(
            spreads.map(\.id),
            ["cover", "matter-0-about", "scene-0-1", "scene-1-0"]
        )
    }

    func testPictureBookLayoutClampsPercentAndUnitGeometry() {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let percentPanel = PanelLayout(chapterIndex: 0, sceneIndex: 0, x: 75, y: -10, width: 80, height: 120)
        let unitPanel = PanelLayout(chapterIndex: 0, sceneIndex: 0, x: 0.1, y: 0.2, width: 0.5, height: 0.4)

        let percentFrame = PictureBookLayout.panelFrame(for: percentPanel, in: frame)
        let unitFrame = PictureBookLayout.panelFrame(for: unitPanel, in: frame)

        XCTAssertGreaterThan(percentFrame.width, 0)
        XCTAssertGreaterThan(percentFrame.height, 0)
        XCTAssertGreaterThan(unitFrame.width, 0)
        XCTAssertGreaterThan(unitFrame.height, 0)
        XCTAssertGreaterThanOrEqual(percentFrame.minX, 18)
        XCTAssertLessThanOrEqual(percentFrame.maxX, 372)
        XCTAssertGreaterThanOrEqual(unitFrame.minY, 68)
        XCTAssertLessThanOrEqual(unitFrame.maxY, 544)
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

    func testContextCueFallsBackToNearestLineWhenPlaybackIsBetweenCues() {
        let track = YouTubeCaptionTrack(
            id: "es-manual",
            languageCode: "es",
            languageName: "Spanish",
            kind: .standard,
            isDefault: true
        )
        let cues = [
            YouTubeCaptionCue(index: 0, startTime: 2.0, endTime: 4.0, text: "Primero"),
            YouTubeCaptionCue(index: 1, startTime: 6.0, endTime: 8.0, text: "Segundo")
        ]
        let viewModel = YouTubeStudyViewModel(video: makeVideo())

        viewModel.applyTranscript(cues: cues, track: track)
        viewModel.updatePlayback(currentTime: 0)

        XCTAssertNil(viewModel.activeCue)
        XCTAssertEqual(viewModel.contextCue?.text, "Primero")

        viewModel.updatePlayback(currentTime: 5)
        XCTAssertNil(viewModel.activeCue)
        XCTAssertEqual(viewModel.contextCue?.text, "Segundo")
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

@MainActor
final class StudySessionViewModelTests: XCTestCase {
    func testSessionRangeBuilderByBlockCount() {
        let blocks = (0..<10).map { index in
            let start = Double(index * 5)
            return StudyBlock(
                id: "block-\(index)",
                index: index,
                targetText: "Block \(index)",
                nativeText: nil,
                mediaStart: start,
                mediaEnd: start + 4,
                cueStartIndex: nil,
                cueEndIndex: nil
            )
        }
        let definition = StudySessionRangeBuilder.byBlockCount(3, from: 2, in: blocks)
        XCTAssertEqual(definition?.startIndex, 2)
        XCTAssertEqual(definition?.endIndex, 4)
        XCTAssertEqual(definition?.blockCount, 3)
    }

    func testPlaybackControllerPausesAtBlockEnd() {
        let controller = StudyPlaybackController()
        let block = StudyBlock(id: "x", index: 0, targetText: "Hi", nativeText: nil, mediaStart: 1, mediaEnd: 3, cueStartIndex: nil, cueEndIndex: nil)
        controller.playBlockOnce()
        XCTAssertEqual(controller.boundaryAction(for: 3.2, block: block, session: nil), .pause)
        XCTAssertEqual(controller.mode, .free)
    }

    func testPlaybackControllerLoopsAtBlockEnd() {
        let controller = StudyPlaybackController()
        let block = StudyBlock(id: "x", index: 0, targetText: "Hi", nativeText: nil, mediaStart: 1, mediaEnd: 3, cueStartIndex: nil, cueEndIndex: nil)
        _ = controller.toggleBlockLoop()
        XCTAssertEqual(controller.boundaryAction(for: 3.2, block: block, session: nil), .loopToStart(1))
        XCTAssertEqual(controller.boundaryAction(for: 3.2, block: block, session: nil), .none)
        XCTAssertEqual(controller.mode, .blockLoop)
    }

    func testSessionPlaybackAdvancesBeforeSessionEnd() {
        let controller = StudyPlaybackController()
        let session = StudySessionDefinition(startIndex: 0, endIndex: 2, targetMinutes: nil)
        let block = StudyBlock(id: "x", index: 0, targetText: "Hi", nativeText: nil, mediaStart: 0, mediaEnd: 3, cueStartIndex: nil, cueEndIndex: nil)
        controller.playSessionOnce()
        XCTAssertEqual(controller.boundaryAction(for: 3.2, block: block, session: session), .advanceToNextBlock)
        XCTAssertEqual(controller.mode, .sessionOnce)
    }

    func testSessionPlaybackPausesAtSessionEnd() {
        let controller = StudyPlaybackController()
        let session = StudySessionDefinition(startIndex: 0, endIndex: 2, targetMinutes: nil)
        let block = StudyBlock(id: "x", index: 2, targetText: "End", nativeText: nil, mediaStart: 10, mediaEnd: 13, cueStartIndex: nil, cueEndIndex: nil)
        controller.playSessionOnce()
        XCTAssertEqual(controller.boundaryAction(for: 13.2, block: block, session: session), .pause)
        XCTAssertEqual(controller.mode, .free)
    }

    func testSessionLoopRestartsAtSessionEnd() {
        let controller = StudyPlaybackController()
        let session = StudySessionDefinition(startIndex: 0, endIndex: 2, targetMinutes: nil)
        let block = StudyBlock(id: "x", index: 2, targetText: "End", nativeText: nil, mediaStart: 10, mediaEnd: 13, cueStartIndex: nil, cueEndIndex: nil)
        _ = controller.toggleSessionLoop()
        XCTAssertEqual(controller.boundaryAction(for: 13.2, block: block, session: session), .loopSession)
        XCTAssertEqual(controller.mode, .sessionLoop)
    }

    func testCaptionProviderMergesThreeLinesByDefault() {
        let cues = (0..<7).map { index in
            YouTubeCaptionCue(
                index: index,
                startTime: Double(index * 2),
                endTime: Double(index * 2 + 1),
                text: "Line \(index)"
            )
        }
        let blocks = CaptionTranscriptProvider(cues: cues, translationForCue: { _ in nil }).makeBlocks()
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].captionLineCount, 3)
        XCTAssertEqual(blocks[0].targetText, "Line 0\nLine 1\nLine 2")
        XCTAssertEqual(blocks[0].mediaStart, 0)
        XCTAssertEqual(blocks[0].mediaEnd, 6)
        XCTAssertEqual(blocks[2].captionLineCount, 1)
    }

    func testStudySubtitleTextMergesLinesWithFlowingWhitespace() {
        let merged = StudySubtitleText.mergedLines([
            "Hello   world",
            "Second\tline"
        ])
        XCTAssertEqual(merged, "Hello world\nSecond line")
        XCTAssertEqual(
            StudySubtitleText.normalizeMultiline("Hello   world\n\nSecond\tline"),
            "Hello world\nSecond line"
        )
    }

    func testBlockPlaybackEndUsesNextCueStartNotPaddedEnd() {
        let cues = [
            YouTubeCaptionCue(index: 0, startTime: 0, endTime: 2.5, text: "One"),
            YouTubeCaptionCue(index: 1, startTime: 2.5, endTime: 5.0, text: "Two"),
            YouTubeCaptionCue(index: 2, startTime: 5.0, endTime: 8.0, text: "Three"),
            YouTubeCaptionCue(index: 3, startTime: 8.0, endTime: 11.0, text: "Four")
        ]
        let end = CaptionTranscriptProvider.playbackEndTime(
            forChunkFrom: 0,
            through: 2,
            in: cues,
            minimumDuration: 0.15
        )
        XCTAssertEqual(end, 8.0)
    }

    func testWhisperProviderGroupsWordsIntoSentencesAndBlocks() {
        let words = [
            WordTiming(word: "Hola", start: 0.0, end: 0.4),
            WordTiming(word: "mundo.", start: 0.5, end: 1.0),
            WordTiming(word: "Cómo", start: 1.2, end: 1.5),
            WordTiming(word: "estás?", start: 1.6, end: 2.0)
        ]

        let blocks = WhisperTranscriptProvider(
            words: words,
            translationForSentenceRange: { _, _ in nil },
            focusWindowSize: .single
        ).makeBlocks()

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].targetText, "Hola mundo.")
        XCTAssertEqual(blocks[0].mediaStart, 0.0)
        XCTAssertEqual(blocks[0].mediaEnd, 1.2)
        XCTAssertEqual(blocks[1].targetText, "Cómo estás?")
    }

    func testWhisperSentenceGroupingHandlesFinalSentenceWithoutPunctuation() {
        let words = [
            WordTiming(word: "Solo", start: 0.0, end: 0.3),
            WordTiming(word: "palabra", start: 0.4, end: 0.8)
        ]
        let sentences = WhisperTranscriptProvider.groupIntoSentences(words)
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences[0].text, "Solo palabra")
    }

    func testWhisperProviderSplitsLongMonologueIntoFocusBlocks() {
        let words = (0..<24).map { index in
            WordTiming(word: "word\(index)", start: Double(index) * 0.4, end: Double(index) * 0.4 + 0.3)
        }

        let blocks = WhisperTranscriptProvider(
            words: words,
            translationForSentenceRange: { _, _ in nil },
            focusWindowSize: .single
        ).makeBlocks()

        XCTAssertGreaterThan(blocks.count, 1)
        XCTAssertLessThanOrEqual(blocks[0].targetText.split(separator: " ").count, 8)
    }

    func testManualBlockNavigationStaysPinnedUntilPlaybackReachesBlock() {
        let blocks = (0..<3).map { index in
            let start = Double(index * 5)
            return StudyBlock(
                id: "block-\(index)",
                index: index,
                targetText: "Block \(index)",
                nativeText: nil,
                mediaStart: start,
                mediaEnd: start + 5,
                cueStartIndex: nil,
                cueEndIndex: nil
            )
        }
        let player = StudyNavigationTestMediaPlayer(currentTime: 12)
        let source = StudyNavigationTestBlockSource(blocks: blocks, player: player)
        let session = StudySessionViewModel(source: source)

        XCTAssertEqual(session.currentBlockIndex, 2)

        session.goToPreviousBlock()
        XCTAssertEqual(session.currentBlockIndex, 1)
        XCTAssertEqual(player.lastSeekTime, 5)

        session.handlePlaybackTime(12, isPlaying: false)
        XCTAssertEqual(session.currentBlockIndex, 1)

        player.currentTime = 6
        session.handlePlaybackTime(6, isPlaying: false)
        XCTAssertEqual(session.currentBlockIndex, 1)
    }
}

@MainActor
private final class StudyNavigationTestMediaPlayer: StudyMediaPlayer {
    var currentTime: Double
    var duration: Double = 100
    var isPlaying: Bool = false
    var playbackRate: Float = 1
    private(set) var lastSeekTime: Double?

    init(currentTime: Double) {
        self.currentTime = currentTime
    }

    func seek(to time: Double) {
        lastSeekTime = max(0, time)
    }

    func seekAndPlay(from time: Double) {
        lastSeekTime = max(0, time)
    }

    func play() {}
    func pause() {}
    func setPlaybackRate(_ rate: Float) {}
}

@MainActor
private struct StudyNavigationTestBlockSource: StudyBlockSource {
    let resource: StudyResourceRef
    let blocks: [StudyBlock]
    let mediaPlayer: any StudyMediaPlayer

    init(blocks: [StudyBlock], player: StudyNavigationTestMediaPlayer) {
        self.blocks = blocks
        self.mediaPlayer = player
        self.resource = StudyResourceRef.youtube(
            videoID: "test-video",
            title: "Test",
            languageCode: "es"
        )
    }
}

final class PodcastFeedTranscriptParserTests: XCTestCase {
    func testParseVTTExtractsTimedCues() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.500
        Hola mundo.

        00:00:02.500 --> 00:00:05.000
        ¿Cómo estás?
        """

        let cues = PodcastFeedTranscriptParser.parseVTT(vtt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].normalizedText, "Hola mundo.")
        XCTAssertEqual(cues[0].startTime, 0, accuracy: 0.001)
        XCTAssertEqual(cues[1].startTime, 2.5, accuracy: 0.001)
    }

    func testParseSRTExtractsTimedCues() {
        let srt = """
        1
        00:00:00,000 --> 00:00:02,500
        Hola mundo.

        2
        00:00:02,500 --> 00:00:05,000
        Como estas?
        """

        let cues = PodcastFeedTranscriptParser.parseSRT(srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].normalizedText, "Hola mundo.")
        XCTAssertEqual(cues[1].startTime, 2.5, accuracy: 0.001)
    }

    func testParseJSONSegments() throws {
        let json = """
        {
          "segments": [
            { "startTime": 0.0, "endTime": 2.5, "body": "Hola mundo." },
            { "startTime": 2.5, "endTime": 5.0, "body": "Como estas?" }
          ]
        }
        """
        let cues = try PodcastFeedTranscriptParser.parseJSON(data: Data(json.utf8))
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Hola mundo.")
    }

    func testSelectPreferredTranscriptPrefersVTTAndMatchingLanguage() {
        let links = [
            PodcastFeedTranscriptParser.TranscriptLink(url: "https://x/en.vtt", type: "text/vtt", language: "en"),
            PodcastFeedTranscriptParser.TranscriptLink(url: "https://x/es.vtt", type: "text/vtt", language: "es")
        ]

        let selected = PodcastFeedTranscriptParser.selectPreferredTranscript(
            from: links,
            preferredLanguageCode: "es-ES"
        )

        XCTAssertEqual(selected?.url, "https://x/es.vtt")
    }
}
