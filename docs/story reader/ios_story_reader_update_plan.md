# iOS Story Reader Update Plan

Plan for updating the LearnCI iOS story player to use the published story spine,
chapter scene data, layout data, and scene-level audio contract described in:

- `docs/story reader/story_player_rendering.md`
- `docs/story reader/data_model.md`

This plan is intentionally iOS/SwiftUI-focused. The reference docs describe a
Flutter presenter architecture, but the implementation target here is the
existing SwiftUI app.

## Goals

- Move the iOS story reader from chapter-audio-first playback to spine and
  scene-driven playback.
- Support scene-level audio, scene art, captions, dialogue lines, and merged
  word timings.
- Make the new reader depend on the published spine, layout, scene, and
  scene-audio contract instead of preserving chapter-audio-only behavior.
- Rename the interactive reader concept from "karaoke" to "dialog".

## Current iOS State

- `StorySessionView` is the main prose reader. It plays one chapter audio file
  at a time from `StoryChapter.audioUrl`.
- `StoryChapter` currently models chapter-level text, script, audio, intro
  audio, cover image, and word timings, but does not yet model `StoryScene`.
- `Story` currently decodes `chaptersJSON` and `preferencesJSON`, but does not
  yet expose reader fields such as `layout_json`, reading matter, or
  `asset_forge_json`.
- `AudioManager` supports local/streamed single audio, simple sequences,
  ambient audio, lock-screen controls, and playback rate, but does not yet have
  first-class story playlist state such as current chapter, scene, clip index,
  local position, and global position.
- `KaraokeSessionView` and `InteractiveStorySessionView` overlap conceptually;
  they should converge into one dialog reader.

## Implementation Plan

### 1. Add the missing reader data layer

Extend `Story` to decode and expose:

- `layout_json`
- `reading_matter_pages_json`
- `asset_forge_json`

Do not add iOS reader support for `reading_front_matter_json` or
`reading_back_matter_json`. The iOS reader should use `reading_matter_pages_json`
as the only reading-matter source.

Extend `StoryChapter` with:

- `scenes: [StoryScene]`
- `nativeAudioUrl`
- `nativeWordTimings`
- computed getters:
  - `bodyTextTargetForReading`
  - `bodyTextEnglishForReading`
  - `bodyScriptOrNarrativeForAlignment`
  - `bodyWordTimingsForPlayback`
  - `hasAnyBodyNarrationAudio`
  - `bodyNarrationClipsCompleteForPlayback`

Add Swift models for:

- `StoryScene`
- `SceneDialogue`
- `StoryLayout`
- `StoryPage`
- `StoryCanvas`
- `PanelLayout`
- `CropRegion`
- `ReadingMatterPage`
- `StoryReadingSpineItem`

Reader data rule: the updated story reader should require scene data for
playback and rendering. Do not synthesize scene data from legacy chapter-level
audio as a compatibility path.

### 2. Create a Swift reading spine adapter

Build one canonical `StoryReadingSpine` from `Story` plus optional
`StoryLayout`.

The spine should produce ordered steps such as:

- cover
- reading matter page
- chapter intro
- chapter body or scene
- chapter quiz
- comic page
- picture spread

The spine becomes the shared navigation source for prose, audio story, dialog,
comic book, and picture book readers.

Important rule: layout and spine items should not own audio. They should point
to `chapterIndex` and optional `sceneIndex`; audio should resolve from the
corresponding `StoryScene` or `StoryChapter`.

### 3. Upgrade audio from chapter player to scene playlist

Add a story playlist mode to `AudioManager`.

Introduce a lightweight model like `StoryAudioClip`:

- `chapterIndex`
- `sceneIndex`
- `url`
- `duration`
- `pauseBefore`
- optional display metadata

Expose playlist state:

- `isPlaying`
- `isLoading`
- `currentClipIndex`
- `currentChapterIndex`
- `currentSceneIndex`
- `localPosition`
- `localDuration`
- `globalPosition`
- `globalDuration`

Add playlist actions:

- load story scene clips in spine/layout order
- play/pause
- seek within current clip
- seek to clip
- seek to chapter and scene
- skip forward/backward
- set playback rate

Reuse the existing remote download/cache behavior, but move path resolution into
a reusable helper so chapter audio, scene audio, native audio, and intro audio
use the same rules.

Keep chapter intro clips separate from the main playlist:

1. When entering a chapter, check `chapterIntroAudioUrl`.
2. Pause the main playlist.
3. Play the intro clip with a dedicated intro player.
4. Resume the playlist at that chapter's first scene.

### 4. Refactor the prose reader first

Treat `StorySessionView` as the first migrated presenter: the iOS Story Book
reader.

Changes:

- Replace direct `currentChapter.audioUrl` playback with scene playlist
  playback.
- Use `bodyWordTimingsForPlayback` for merged multi-scene word highlighting.
- Drive chapter title, scene art, and scroll position from playlist state.
- Use the spine for cover, reading matter pages, chapter body, and quiz.
- Keep existing behavior for:
  - word lookup
  - target/English language toggle
  - ambient sound
  - playback rate
  - lock-screen controls
  - quiz navigation

Availability behavior:

- If scene audio exists, use scene playlist.
- If scene audio is missing, show a production-incomplete state instead of
  falling back to chapter-level audio.
- If word timings are missing, keep scene playback available but disable word
  highlighting.

### 5. Rename and update interactive mode to dialog mode

Rename the conceptual mode from "karaoke" to "dialog".

Target direction:

- `KaraokeSessionView` -> `DialogStorySessionView`
- karaoke state names -> dialog state names
- "karaoke highlighting" -> "active dialog line"
- UI labels should say "Dialog" or "Interactive Dialog", not "Karaoke".

Converge `KaraokeSessionView` and `InteractiveStorySessionView` into one dialog
reader rather than maintaining two separate interactive readers.

The dialog reader should use:

- `chapter.bodyScriptOrNarrativeForAlignment`
- `chapter.bodyWordTimingsForPlayback`
- current playlist clip position
- `StoryScene.dialogues`
- character portraits from `asset_forge_json`
- scene art from `StoryScene.imageUrl`, falling back to chapter/story cover

Expected behavior:

- Active speaker line advances with audio.
- Previous and upcoming lines may be dimmed.
- Users can seek by tapping a dialog line.
- Speaker changes can optionally insert short dramatic pauses if the audio
  playlist model supports pause points.

### 6. Add story reader factory routing

Add a Swift equivalent of `StoryViewFactory`.

Initial routing:

- `.storyBook` -> prose story reader
- `.audioStory` -> audio playlist reader
- `.interactiveStory` -> dialog reader
- `.comicBook` -> comic book reader
- `.pictureBook` -> picture book reader

Routing requirements:

- Do not route `.standard` as a reader fallback.
- Do not include `vocabularyBuilder` in story reader factory routing.
- Add iOS enum support for comic book and picture book story types, using raw
  values aligned with the published data contract.

### 7. Add scene visual rendering

Create shared scene image resolution:

1. Use `scene.imageUrl` when present.
2. Fall back to `chapter.coverUrl`.
3. Fall back to `story.remoteCoverPath` / `coverArt`.
4. Show a neutral placeholder only when no visual exists.

For comic book and picture book readers:

- `layout.flatSequence` is the authoritative scene order.
- `PanelLayout.chapterIndex + sceneIndex` maps to a `StoryScene`.
- Panel taps map panel -> flat index -> clip index -> audio seek.
- If a scene has no image, crop the chapter cover according to
  `PanelLayout.cropRegion`.

### 8. Add required-data and incomplete-production rules

The updated reader should target published stories that have the new scene,
layout, and spine-ready data contract. Do not preserve chapter-audio-only reader
behavior as a fallback.

Rules:

- No `layout_json` for comic book or picture book: show an incomplete layout
  state.
- No `scenes`: show an incomplete story data state.
- No scene audio: show an incomplete audio state.
- No word timings: disable highlighting but keep scene playback.
- English display: disable target-language word highlighting.
- Missing scene art: fall back to chapter/story cover.
- Missing asset forge portraits: use a generic speaker avatar or text-only
  dialog bubble.

### 9. Add comic book reader

Create a dedicated comic book reader that uses `StoryLayout` as the rendering
contract.

Data and behavior:

- Render pages from `layout.pages[*].canvases[*].panels`.
- Resolve each panel to `StoryScene` by `chapterIndex` and `sceneIndex`.
- Use `layout.flatSequence` to build the scene audio playlist.
- Use `layout.chapterFlatOffsets` for chapter navigation.
- On playlist clip changes, jump to the owning comic page.
- On panel tap, seek to the mapped scene clip.
- Render panel image, caption, and dialogue overlays.
- If scene art is missing, crop the chapter cover using `PanelLayout.cropRegion`.

### 10. Add picture book reader

Create a dedicated picture book reader for full-screen swipe spreads.

Data and behavior:

- Build spreads from cover, reading matter pages, scene spreads, and quiz
  spreads.
- Use scene spreads only for the audio playlist.
- Map spread index to clip index and clip index back to spread index.
- While playing, sync page turns to the active scene clip.
- While paused, allow free manual swiping without forcing audio seeks.
- Render scene image, caption, and dialogue in a full-screen presentation.
- Use the same scene image fallback chain as the comic book reader.

### 11. Validate with targeted test stories

Use at least these fixtures or manual test rows:

- New story with multiple chapters and multiple scene clips per chapter.
- Story with chapter intro audio.
- Story with scene images and captions.
- Story with dialog script and multiple speakers.
- Comic book story with `layout.pages`, panel geometry, and `flatSequence`.
- Picture book story with full-screen scene spreads.
- Story with missing scene image fallback.
- Story with missing timings.

Validation checklist:

- New scene-audio stories play all scenes in order.
- Chapter transitions update title, art, and text.
- Word highlighting stays aligned across multiple scene clips.
- Chapter intro plays before body audio and resumes correctly.
- Lock-screen controls still control the active story playlist.
- Ambient audio pauses/resumes with narration.
- English toggle disables target-language highlighting cleanly.
- Dialog reader shows the active dialog line and can seek by line.
- Comic book reader renders panel pages and seeks by panel.
- Picture book reader syncs scene spreads while playing and allows manual
  swiping while paused.

## Recommended Order

1. Data models and compatibility decoding.
2. Spine builder.
3. Story playlist support in `AudioManager`.
4. Prose reader migration in `StorySessionView`.
5. Dialog reader rename and migration.
6. Reader factory routing.
7. Scene visual resolver.
8. Comic book reader.
9. Picture book reader.

This order makes the first milestone useful quickly: new scene-audio stories
become playable first, then each presenter can migrate onto the same spine,
layout, and playlist foundation.
