# Story Player Rendering Architecture

How the five story presenter types consume Story data, drive audio playback, and render UI.

**Related:** [data_layout_presentation_separation.md](./data_layout_presentation_separation.md), [data_model.md](../pipeline/data_model.md), [data_separation_phase2_plan.md](../../architecture/data_separation_phase2_plan.md)

---

## 1. Overview

A story is rendered by one of five concrete **presenter** widgets, selected by `StoryViewFactory` based on `story.preferences.storyType`. All presenters extend the abstract `StoryPresenter` base class and are `ConsumerStatefulWidget`s that watch `audioManagerProvider` (Riverpod).

```
StoryViewFactory.build(story, layout)
  ├── StoryType.storyBook    → StoryBookPresenter     (prose scroll + word highlighting)
  ├── StoryType.dialogStory → DialogBookPresenter   (dialog script bubbles)
  ├── StoryType.audioBook    → AudioBookPresenter     (podcast-style chapter playlist)
  ├── StoryType.comic        → ComicBookPresenter     (panel grid + auto page turns)
  └── StoryType.picture      → PictureBookPresenter   (full-screen swipe spreads)
```

Each presenter receives two inputs:

| Argument | Type | Purpose |
| --- | --- | --- |
| `story` | `Story` | Content: text, audio URLs, word timings, images |
| `layout` | `StoryLayout` | Visual blueprint: panel positions, flat sequence index |

`StoryLayout` is computed by `LayoutEngine` from the story data and stored in `story.layoutJson`. For prose and audiobook modes the layout is present but mostly unused; for comic and picture modes it is the authoritative rendering contract.

---

## 2. Data model quick reference

The presenter layer reads from these types. See [data_model.md](../pipeline/data_model.md) for the full DB column contract.

### Story

```
Story
  ├── chapters: List<StoryChapter>
  ├── preferences: StoryPreferences     (storyType, betweenChapterPauseMs, …)
  ├── remoteCoverPath / remoteCoverUrl
  ├── readingMatterPages                (parsed from readingMatterPagesJson)
  ├── readingFrontMatter                (About page)
  ├── readingBackMatter                 (Appendix)
  └── assetForgeData                    (character portraits, images)
```

### StoryChapter

```
StoryChapter
  ├── id, chapterNumber, chapterType
  ├── titleTargetLanguage, titleEnglish
  ├── scenes: List<StoryScene>          (parsed from textContentJson)
  │
  ├── — Text getters —
  ├── bodyTextTargetForReading          merged narrative text (prefers textTargetLanguage, else joined scene captions)
  ├── bodyTextEnglishForReading         same in English
  ├── bodyScriptOrNarrativeForAlignment script if present, else narrative  ← used by interactive mode only
  │
  ├── — Audio getters —
  ├── bodyWordTimingsForPlayback        merged per-scene timings with cumulative offsets
  ├── chapterIntroAudioUrl              intro read-aloud clip (target language)
  ├── chapterIntroWordTimings           timings for intro clip
  ├── nativeAudioUrl                    native-language parallel audio
  ├── nativeWordTimings
  ├── hasAnyBodyNarrationAudio          → bool (any scene has audioUrl)
  └── bodyNarrationClipsCompleteForPlayback → bool (all scenes complete)
```

### StoryScene

```
StoryScene
  ├── sceneIndex                        zero-based within chapter
  ├── captionTarget, captionEnglish
  ├── dialogues: List<SceneDialogue>    [{ character, text }]
  ├── imageUrl                          per-scene generated image (or null → crop chapter cover)
  ├── audioUrl                          scene-level audio clip (Supabase path or HTTP URL)
  ├── audioDurationMs
  ├── wordTimings: List<WordTiming>     relative to clip start (seconds)
  └── scriptTargetLanguage?, scriptEnglish?
```

### StoryLayout (comic/picture modes)

```
StoryLayout
  ├── pages: List<StoryPage>
  │   └── StoryPage
  │       ├── chapterIndex, sceneIndex?
  │       └── canvases: List<StoryCanvas>
  │           └── StoryCanvas
  │               └── panels: List<PanelLayout>
  │                   └── PanelLayout
  │                       ├── chapterIndex, sceneIndex   ← key: maps panel to StoryScene
  │                       ├── x, y, width, height        ← grid position
  │                       └── cropRegion                 ← which quadrant of the image to show
  ├── flatSequence: List<PanelLayout>   all panels in global (chapter → scene) order
  └── chapterFlatOffsets: List<int>     flatSequence start index per chapter

Lookups:
  flatIndexFor(chapter, scene)             → int
  chapterAndSceneForFlatIndex(int)         → (chapter, scene)
  flatSequenceIndexForPanel(chapter, scene) → int?
```

### WordTiming

```
WordTiming { word: String, start: double, end: double }  // seconds into clip
```

---

## 3. AudioManager

`audioManagerProvider` holds an immutable `AudioManagerState` and is the single source of truth for playback. All presenters watch it; none drive audio directly.

```
AudioManagerState
  ├── isPlaying, isLoading, isInit
  ├── currentPosition        duration within the current clip
  ├── totalDuration          duration of the current clip
  ├── globalPosition         total elapsed time across the full playlist
  ├── globalTotalDuration    total duration of all clips
  ├── currentChapterIndex    chapter owning the current clip
  └── currentSequenceIndex   index in the flat clip playlist
```

### Loading audio

**Prose / interactive / audiobook** — call `audioManager.loadStoryAudio(story)`:
1. Iterates all `chapter.scenes` in order; collects every non-empty `audioUrl`
2. Builds a `ConcatenatingAudioSource` (flat playlist)
3. Maintains `_sequenceChapterIndices[i]` → which chapter owns clip `i`
4. Sets `_chapterScopedUiPosition = true`; the UI progress bar shows chapter-local position

**Comic / picture** — call `audioManager.loadPanelAudio(urls, {pauseBeforeSequenceIndices})`:
1. Takes a pre-built ordered URL list (constructed by the presenter from `layout.flatSequence`)
2. Inserts silence pauses before specified indices (e.g. between chapters)
3. Sets `_chapterScopedUiPosition = false`; UI shows global progress

### iOS position workaround

`AudioPlayer.position` freezes on iOS during active playback. `AudioManager` works around this by anchoring to the last known position when playback starts and advancing via a `Stopwatch`. On pause the position re-syncs to the actual player value.

### Between-chapter pauses

When `currentIndexStream` signals a clip transition that crosses a chapter boundary (detected via `_sequenceChapterIndices`), `AudioManager` inserts a pause of `story.preferences.betweenChapterPauseMs` (default 2200 ms) before resuming.

---

## 4. Word timing and highlighting

Word highlighting is used by **StoryBook** (prose scroll) and **InteractiveBook** (dialog) only.

### How timings are structured

Each `StoryScene.wordTimings` list contains start/end times **relative to that scene's audio clip**. When a chapter has multiple scenes, the chapter getter `bodyWordTimingsForPlayback` merges them into a single unified timeline by accumulating scene durations as offsets:

```
Chapter with 2 scenes (3 s, 4 s clips):
  Scene 0 wordTimings: { "the" 0.1–0.3, "fox" 0.3–0.6 }   (relative to scene 0 clip)
  Scene 1 wordTimings: { "ran" 0.0–0.2, "fast" 0.2–0.5 }  (relative to scene 1 clip)

bodyWordTimingsForPlayback output:
  { "the" 0.1–0.3, "fox" 0.3–0.6, "ran" 3.0–3.2, "fast" 3.2–3.5 }
                                         ↑ offset = scene 0 duration (3 s)
```

### Highlighting in StoryBook

On each `audioManagerProvider` update:
```dart
final positionSec = state.currentPosition.inMilliseconds / 1000.0;
final active = timings.indexWhere((wt) => positionSec >= wt.start && positionSec < wt.end);
// Rebuild RichText with words[active] styled in cyan (#00E6B8)
```

### Segment mapping in InteractiveBook

Interactive mode needs to highlight entire dialogue lines (not individual words). On init, `bodyScriptOrNarrativeForAlignment` is split into segments (one per speaker line). Each segment is assigned a `(start_sec, end_sec)` range by matching words to `bodyWordTimingsForPlayback`. The dialog display then finds the active segment each frame using a `Ticker` + `Stopwatch` (to avoid the iOS position freeze):

```dart
// Each frame:
final localMs = _dialogAnchorMs + _stopwatch.elapsed.inMilliseconds;
final activeSegment = _segmentIndexAtLocalMs(localMs);
// Render active segment's bubble highlighted; others dimmed
```

---

## 5. Presenter details

### 5.1 StoryBook — prose scroll + word highlighting

**Story type:** `StoryType.storyBook`

**Data reads:**

| Data | Getter / field | Used for |
| --- | --- | --- |
| Chapter text | `chapter.bodyTextTargetForReading` / `bodyTextEnglishForReading` | Scrollable body text |
| Word timings | `chapter.bodyWordTimingsForPlayback` | Per-word highlight |
| Intro clip | `chapter.chapterIntroAudioUrl` + `chapterIntroWordTimings` | Pre-chapter read-aloud |
| Reading matter | `story.readingMatterPages` | About / Appendix spreads |
| Cover image | `story.remoteCoverUrl` | Background |

**Rendering flow:**

1. Build spine from `resolvedStoryReadingSpine(story, layout)` — segments: Cover, MatterPages, Chapters
2. On chapter enter: play intro clip if `chapterIntroAudioUrl` present; then load chapter scenes into `AudioManager`
3. Scroll syncing: while playing, animate scroll position proportional to `state.currentPosition / state.totalDuration`; on chapter change, jump scroll to 0
4. Language toggle: swaps between target and English text; clears word highlighting when English is shown

**Widgets:** Chapter image background → chapter title/badge → scrollable `RichText` with live word highlight → thin progress bar → language toggle → quiz button.

---

### 5.2 InteractiveBook — dialog script bubbles

**Story type:** `StoryType.dialogStory`

**Data reads:**

| Data | Getter / field | Used for |
| --- | --- | --- |
| Script text | `chapter.bodyScriptOrNarrativeForAlignment` | Segment parsing |
| Word timings | `chapter.bodyWordTimingsForPlayback` | Segment time boundaries |
| Scene audio | `chapter.scenes[*].audioUrl` | Flat clip playlist |
| Portraits | `assetForgeData.characters[name].portraitUrl` | Full-screen character image |

**Rendering flow:**

1. Parse script into `List<StorySegmentTiming>` — each segment = one speaker line + time range
2. Load clips: `audioManager.loadStoryAudio(story)` (same scene-flatten as prose)
3. Per-frame: advance `localMs` via `Stopwatch`; find active segment; render that segment's bubble as highlighted, previous as dimmed
4. On speaker change: insert 480 ms dramatic pause, then resume at new speaker's line

**Character portrait resolution:** `CharacterPortraitResolver.fromStory(story)` looks up `story.assetForgeData.characters` by the speaker name found in the script segment. Falls back to a generic avatar if no match.

**Widgets:** Full-screen portrait → speech bubble stack (active + preview) → audio scrubber → chapter navigation.

---

### 5.3 AudioBook — podcast-style playlist

**Story type:** `StoryType.audioBook`

**Data reads:**

| Data | Getter / field | Used for |
| --- | --- | --- |
| Chapter text | `chapter.bodyTextTargetForReading` | Playlist row description |
| Scene audio | `chapter.scenes[*].audioUrl` | Concat playlist |
| Scene images | `chapter.scenes[*].imageUrl` | Storyboard gallery |
| Reading matter | `story.readingMatterPages` | Intro spreads |
| Cover | `story.remoteCoverUrl` | Story cover page |

**Rendering flow:**

1. Build playlist order from chapters in spine order
2. Load all scene clips: `audioManager.loadStoryAudio(story)`
3. Watch `currentChapterIndex` to update which row is highlighted in the playlist
4. Storyboard gallery: shows `scenes[*].imageUrl` thumbnails timed to audio clips

No word highlighting. Speed control available (1×, 1.25×, 1.5×, 2×).

**Widgets:** Story cover spread → reading matter spreads → chapter playlist (scrollable rows) → storyboard gallery → seek scrubber → playback controls.

---

### 5.4 ComicBook — panel grid with auto page turns

**Story type:** `StoryType.comic`

**Data reads:**

| Data | Getter / field | Used for |
| --- | --- | --- |
| Panel geometry | `layout.pages[*].canvases[*].panels` | Grid layout |
| Flat sequence | `layout.flatSequence` | Audio clip order |
| Chapter offsets | `layout.chapterFlatOffsets` | Chapter → flat index lookup |
| Scene image | `scene.imageUrl` (or null → crop chapter cover by `cropRegion`) | Panel image |
| Caption / dialogues | `scene.captionTarget`, `scene.dialogues` | Panel text overlay |
| Scene audio | `scene.audioUrl` | Per-panel clip |

**Flat sequence and audio mapping:**

The flat sequence is the authoritative panel order. When building the audio playlist, ComicBook iterates `layout.flatSequence` and collects clips:

```
flatSequence = [ch0.scene0, ch0.scene1, ch0.scene2, ch1.scene0, ch1.scene1]
                   clip 0       clip 1      clip 2      clip 3      clip 4

_flatSequenceToClipIndex = { 0→0, 1→1, 2→2, 3→3, 4→4 }  (sparse: only panels with audioUrl)
_clipIndexToFlatIndex    = { 0→0, 1→1, 2→2, 3→3, 4→4 }  (reverse map)
```

Calls `audioManager.loadPanelAudio(urls, pauseBeforeSequenceIndices: [3])` — silence pause injected at the chapter 1 boundary.

**Page turn sync:** On each `currentSequenceIndex` change from `AudioManager`, look up which `StoryPage` owns that flat index and jump the `PageView` to the corresponding spread.

**Panel seeking:** When user taps a panel, call `layout.flatSequenceIndexForPanel(chapter, scene)` → map to clip index → call `audioManager.seekToClip(clipIndex)`.

**Panel image fallback:** If `scene.imageUrl` is null, `ScenePanelWidget` displays the chapter cover image cropped to the region described by `PanelLayout.cropRegion` (topLeft, topRight, bottomLeft, bottomRight, full, centre).

**Widgets:** `PageView` of grid spreads → per-panel `ScenePanelWidget` (image + caption + dialogue bubbles) → play/pause → chapter navigation.

---

### 5.5 PictureBook — full-screen swipe spreads

**Story type:** `StoryType.picture`

**Data reads:**

| Data | Getter / field | Used for |
| --- | --- | --- |
| Reading matter | `story.readingMatterPages` | Front/back matter spreads |
| Scene image | `scene.imageUrl` (fallback to chapter cover) | Full-screen image |
| Caption / dialogues | `scene.captionTarget`, `scene.dialogues` | Spread text |
| Scene audio | `scene.audioUrl` | Per-scene clip |
| Layout pages | `layout.pages` | Map scene to spread index |

**Spine and clip mapping:**

`picturePlaybackSpreadSteps(story, layout)` builds an ordered list of spreads:

```
Spreads: [Cover, FrontMatter1, Scene0, Scene1, …, SceneN, BackMatter1]
Audio clips:             [clip0,   clip1,   …, clipN]           (scene spreads only)
_spreadIndexToClipIndex: { 2→0, 3→1, …, N+2→N }                (sparse: scenes only)
```

**Page turns:** On `currentSequenceIndex` change, find the spread that owns the clip via `_clipIndexToSpreadIndex` and call `PageController.jumpToPage()`.

**Manual swipe rule:** Page sync only fires while `isPlaying`. When paused, the user can freely swipe to cover or matter pages without triggering audio seeks.

**Widgets:** `PageView` of full-screen spreads → per-spread: cover image + title card, matter page (bilingual text), scene image + caption + dialogue — inline quiz spread after each chapter.

---

## 6. Chapter intro clips

All presenters support a per-chapter intro clip. The flow is identical across modes:

1. When entering a chapter, check `chapter.chapterIntroAudioUrl`
2. If present: pause main `AudioManager`; load and play the intro clip in a dedicated `_introPlayer` (`AudioPlayer` instance separate from the main narrator)
3. Apply `chapter.chapterIntroWordTimings` for word highlighting during the intro (prose and interactive modes only)
4. When the intro player fires `playerStateStream` → `completed`, resume main `AudioManager` at clip 0 of that chapter
5. Avoids text duplication: if the intro text is a prefix of `bodyTextTargetForReading`, the presenter strips it from the scroll view while the intro plays

---

## 7. Field usage by presenter type

| Field | StoryBook | Interactive | AudioBook | Comic | Picture |
| --- | :---: | :---: | :---: | :---: | :---: |
| `chapter.bodyTextTargetForReading` | ✓ | | ✓ | | ✓ |
| `chapter.bodyScriptOrNarrativeForAlignment` | | ✓ | | | |
| `chapter.bodyWordTimingsForPlayback` | ✓ | ✓ | | | |
| `chapter.chapterIntroAudioUrl` + timings | ✓ | ✓ | ✓ | ✓ | ✓ |
| `chapter.scenes[*].audioUrl` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `chapter.scenes[*].imageUrl` | | | ✓ | ✓ | ✓ |
| `chapter.scenes[*].captionTarget` | | | | ✓ | ✓ |
| `chapter.scenes[*].dialogues` | | | | ✓ | ✓ |
| `story.readingMatterPages` | ✓ | | ✓ | | ✓ |
| `story.remoteCoverUrl` | ✓ | | ✓ | | ✓ |
| `story.assetForgeData` (portraits) | | ✓ | | | |
| `layout.flatSequence` | | | | ✓ | ✓ |
| `layout.pages[*].canvases[*].panels` | | | | ✓ | |
| `layout.chapterFlatOffsets` | | | | ✓ | ✓ |

---

## 8. Key files

| File | Role |
| --- | --- |
| `lib/presenters/story_presenter.dart` | Abstract base — `story`, `layout`, `onSeekToScene` |
| `lib/presenters/story_view_factory.dart` | Selects concrete presenter from `storyType` |
| `lib/presenters/story_book_presenter.dart` | Prose scroll + word highlight |
| `lib/presenters/interactive_book_presenter.dart` | Dialog bubbles + character portraits |
| `lib/presenters/audio_book_presenter.dart` | Podcast playlist |
| `lib/presenters/comic_book_presenter.dart` | Panel grid + page turns |
| `lib/presenters/picture_book_presenter.dart` | Full-screen swipe spreads |
| `lib/services/audio_manager.dart` | Playback state, clip loading, position tracking |
| `lib/layout/story_layout.dart` | Layout blueprint (`flatSequence`, `pages`) |
| `lib/layout/story_reading_spine.dart` | Reading order segments (cover, matter, scenes, quiz) |
| `lib/layout/layout_engine.dart` | Computes `StoryLayout` from `Story` |
| `lib/models/story.dart` | `Story` + `StoryChapter` — all content fields and getters |
| `lib/models/story_scene.dart` | `StoryScene` — per-panel/beat data |
| `lib/models/word_timing.dart` | `WordTiming { word, start, end }` |
