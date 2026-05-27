# Dialog Story Player — Design Spec

## Overview

The dialog story player (`DialogStoryPresenter`) renders a story as a sequential, tap-to-reveal chat feed — similar to Duolingo's dialogue exercises. Each character's line appears as a positioned speech bubble with a portrait avatar and optional audio. The entire experience is driven by a single state variable, `_visibleCount`, which controls how many items in a flat list are rendered at any given time.

---

## Data Model

### `SceneDialogue`

The atomic unit of the dialog player. Lives inside `StoryScene.dialogues[]`.

| JSON key | Type | Purpose |
|---|---|---|
| `character` | String | Speaker name — matched against character assets |
| `text` | String | Target-language line |
| `textEnglish` | String? | English translation (for EN toggle) |
| `audioUrl` | String? | Supabase storage path to the per-line audio clip |

### `StoryScene` fields used by the dialog presenter

| JSON key | Type | Purpose |
|---|---|---|
| `sceneIndex` | int | Sort order within the chapter |
| `dialogues` | List\<SceneDialogue\> | Structured dialogue lines (primary source) |
| `scriptTargetLanguage` | String? | Tagged script text — fallback when `dialogues` is empty |
| `scriptEnglish` | String? | English tagged script — paired with above |
| `audioUrl` | String? | Scene-level clip — used only when no per-line audio exists |
| `imageUrl` | String? | Scene storyboard image shown in the scene header |

### `StoryPreferences` fields relevant to dialog stories

| Field | Default | Purpose |
|---|---|---|
| `audioStyle` | `dramatized` | Informs generation; not used at runtime by presenter |
| `dialogAutoPlayAudio` | `false` | Flag exists, not yet wired to the presenter |
| `audioSpeed` | `1.0` | Passed to AudioManager for playback speed |

---

## Flat List Architecture

The presenter builds one flat `List<_Item>` once on `initState` and never rebuilds it. A `ListView.builder` renders the first `_visibleCount` entries.

### Item types

```
_CoverItem          — story cover spread (one per story)
_ReadingMatterItem  — front/back matter pages from READ stage
_SceneHeader        — per-scene block: chapter badge + storyboard image
_BubbleItem         — one dialogue line: character, text, color, side, portrait
```

### Build order

The presenter walks the **reading spine** produced by `computeStoryReadingSpine()`, which yields steps typed by kind. Dialog stories respond to:

```
cover               → _CoverItem
metaReadingMatter   → _ReadingMatterItem
scene               → _SceneHeader
                      + one _BubbleItem per SceneDialogue
```

The index of every `_SceneHeader` in the list is saved in `_sceneHeaderIndices[]` for scene navigation.

### Dialogue source selection

For each scene, the presenter picks dialogue lines in this priority order:

1. **`scene.dialogues`** — pre-structured per-line data from the pipeline. Used directly.
2. **`_parseTaggedScript(scene.scriptTargetLanguage, scene.scriptEnglish)`** — fallback when `dialogues` is empty. Parses the raw script format:

   ```
   [LUZ] (happy) I'm so excited to be here!
   ```

   Regex: `^\[([^\]]+)\]\s*(?:\([^)]*\))?\s*(.+)$` — captures speaker (group 1) and text (group 2), discards the tone marker. English lines are paired by index.

---

## Character Identity & Layout

### Color and side assignment

On first encounter, each unique character name gets:

- **Color** — cycled from a 7-color palette (cyan → orange → purple → green → deep orange → magenta → red)
- **Side** — alternates left/right by encounter order (`charOrder % 2 == 1` = right)

These assignments are stable for the session; the same character always appears on the same side in the same color.

### Portrait resolution

`CharacterPortraitResolver` resolves a portrait URL per speaker:

1. Normalize speaker name to uppercase key (e.g. `"Luz"` → `"LUZ"`)
2. If key is `NARRATOR`: use chapter cover → story cover as portrait
3. Otherwise: match against `bibleJson` character list, then `assetForgeJson` character registry
4. Fall back to the character's initial rendered in their assigned color

---

## Tap-to-Reveal Interaction

### State

`_visibleCount` (int) is the only piece of mutable state controlling progression.

- Starts at `1` (cover auto-revealed on first frame)
- Each tap increments by 1
- `ListView.builder(itemCount: _visibleCount)` renders exactly that many items

### Tap handling

A `GestureDetector` wraps the entire screen. Any tap anywhere calls `_advanceOne()`:

```
_advanceOne()
  if _visibleCount >= _items.length → return (story complete)
  _visibleCount++
  _maybeStartAudioForItem(_visibleCount - 1)
  _scrollToBottom()
```

When the last item is revealed, the tap hint is replaced by a "Done" button.

### Reveal animation

The newest item (`index == _visibleCount - 1`) animates in via `TweenAnimationBuilder`:
- Opacity: `0 → 1`
- Vertical translate: `14px → 0`
- Duration: 220ms, easeOut curve

All prior items render statically.

---

## Per-Bubble Audio

### Audio index map

During list construction, the presenter builds two parallel structures:

- `_audioUrls[]` — flat list of resolved audio clip URLs
- `_itemToAudioIndex{}` — maps `_BubbleItem` list index → index into `_audioUrls`

**Per-line audio** (`dlg.audioUrl` on `SceneDialogue`): each bubble maps to its own clip. This is the primary mode for dialog stories with generated audio.

**Scene-level audio** (`scene.audioUrl`): used only when no bubble in that scene has a `dlg.audioUrl`. The entire scene maps to one clip triggered on the first bubble reveal.

### Playback

When a bubble is revealed:

```
_maybeStartAudioForItem(itemIdx)
  clipIdx = _itemToAudioIndex[itemIdx]
  if no clip → return
  mgr.loadPanelAudio([_audioUrls[clipIdx]])  ← single-item playlist
  mgr.play()
```

Loading a single-item playlist ensures each clip plays independently and stops at the end with no chaining to subsequent bubbles. This differs from other presenters that load full chapter playlists and seek within them.

---

## Scene Navigation

Available when the story has more than one scene (`_sceneHeaderIndices.length > 1`).

### Bottom bar controls

```
[← Prev]   Scene 2 / 5   [Next →]
```

### Jump behavior

```
_goToScene(sceneIdx)
  _visibleCount = _sceneHeaderIndices[sceneIdx] + 1
  _scrollToTop()
```

Setting `_visibleCount` to the scene header's index + 1 reveals exactly the header and nothing below it — the user taps to progressively reveal that scene's bubbles.

---

## Progress & Scroll

- **Progress bar**: `_visibleCount / _items.length` rendered as a `LinearProgressIndicator` across the top
- **Auto-scroll on advance**: `_scrollToBottom()` animates to `maxScrollExtent` over 280ms so the newly revealed bubble is always in view
- **Scene jump scroll**: `_scrollToTop()` snaps instantly to the top so the scene header is visible

---

## English Toggle

A header button toggles `_showEnglish` (bool). When true:

- `_BubbleItem` text field switches from `item.text` to `item.textEnglish`
- `_SceneHeader` caption switches from target to native
- The toggle persists for the session but is not saved across sessions

---

## Rendering Tree

```
GestureDetector(onTap: _advanceOne)
  SafeArea
    Column
      _buildHeader()           title, back, EN toggle
      _buildProgressBar()      0.0 → 1.0 as items reveal
      Expanded
        ListView.builder(itemCount: _visibleCount)
          _CoverItem           → StoryVirtualCoverSpread
          _ReadingMatterItem   → StoryVirtualReadingMatterSpread
          _SceneHeader         → chapter badge, 1/3-width scene image, caption
          _BubbleItem          → avatar + max-65%-width bubble
                                 TweenAnimationBuilder on newest item only
      _buildBottomBar()
        _buildSceneNavRow()    prev/next if >1 scene
        _buildTapHint()        blinking touch icon while canAdvance
        _buildDoneButton()     shown when _visibleCount == _items.length
```

---

## Key Design Decisions

**Single `_visibleCount` drives everything.** No separate "revealed" set, no per-item state. This keeps scene jumping trivial — set the index, rebuild.

**Flat list, built once.** The list is computed on `initState` from the spine and never recomputed. All items exist in memory; `itemCount` controls visibility.

**Single-item audio playlists per bubble.** Prevents clips from chaining. Each tap is an independent playback event.

**`dialogues` beats `scriptTargetLanguage`.** Structured per-line data is always preferred. The tagged-script parser is a fallback for stories that have script text but haven't had per-line dialogue JSON generated yet.

**No session persistence.** Closing and reopening resets to the cover. `_visibleCount` is ephemeral.
