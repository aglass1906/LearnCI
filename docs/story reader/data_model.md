# Story Builder Data Model

**Canonical contract** between the Flutter app and Supabase for `public.stories`, `public.story_pipeline`, and related JSON. This file merges the former pipeline overview and the architecture-contract doc into **one source of truth**.

**Supersedes:** content previously only in [`../data models/data_model.md`](../data%20models/data_model.md) (that file now redirects here).

**Related:** [Asset Forge 2.0 plan](../asset%20forge/asset_forge_2_plan.md), [implementation checklist](../asset%20forge/asset_forge_2_todo.md), [data separation architecture](../../architecture/data_separation_phase2_plan.md).

---

## Builder vs Player tables

| Table | Role |
| :--- | :--- |
| `public.story_pipeline` | **In-progress builder rows.** All pipeline stage JSON columns live here. The app reads and writes this table throughout production. |
| `public.stories` | **Published learner rows.** The FINAL stage copies the completed story here. The learner app and library read only this table. |

These tables share the same column shape for content fields; `story_pipeline` additionally carries pipeline-only columns (`pipeline_timestamps_json`, stage JSON blobs) that are never copied to `stories`.

---

## 1. Central table: `public.stories`

| Column | Type | Origin / source | Description |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | Client (Flutter) | Primary key (RFC-4122 v4 at creation). |
| `user_id` | `uuid` | Supabase Auth | Story owner. |
| `title` | `text` | User / AI | Display title. |
| `target_text` | `text` | Legacy / optional | Short target-language summary text. |
| `native_text` | `text` | Optional | Native-language summary. |
| `language` | `text` | Phase 0 UI | Target language (e.g. `"Spanish"`). |
| `level` | `integer` | Phase 0 UI | CEFR index (1 = A1 … 6 = C2). |
| `created_at` | `timestamptz` | DB | Created. |
| `updated_at` | `timestamptz` | DB | Last update. |
| `is_favorite` | `boolean` | UI | Library favorite. |
| `prompt` | `text` | UI | Optional user prompt / notes. |
| `generation_status` | `text` | Backend / UI | Pipeline phase: `drafting`, `bibleReady`, `treatmentReady`, `completed`, etc. |
| `last_error` | `text` | Backend | Last pipeline error message. |
| `preferences_json` | `jsonb` | `StoryPreferences` | Voice, art, length, quiz, ambient (see §2.1). |
| `parameters_json` | `jsonb` | Phase 0 UI | Premise options, high-level setup. |
| `ci_profile_json` | `jsonb` | `generate_story_parameters` | Pedagogical rules (may overlap nested `ciProfile` in parameters). |
| `story_type_profile_json` | `jsonb` | Pipeline | Story-type metadata. |
| `bible_json` | `jsonb` | `generate_story_bible` | World, characters, locations (see §2.2). |
| `treatment_json` | `jsonb` | `generate_story_treatment` | 3-act treatment. |
| `scene_breakdown_json` | `jsonb` | `generate_scene_breakdown` | Chapter/scene breakdown (see §2.3). |
| `chapters` | `jsonb` | Script / production | Final per-chapter listening content (see §3). |
| `outline_json` | `jsonb` | Pipeline | Outline / planning blob. |
| `prompts_json` | `jsonb` | Pipeline | Extra prompt overrides. |
| `speaker_voices_json` | `jsonb` | Phase 6 UI | Name → TTS voice mapping. |
| `ci_analysis_json` | `jsonb` | `optimize_ci` | Pedagogical optimization history (see §2.4). |
| `asset_forge_json` | `jsonb` | Asset Forge UI | Visual asset registry: characters, style, and (AF 2.0) locations, chapters, scenes, story cover (see §4). |
| `generation_prompts_json` | `jsonb` | Pipeline | Stored generation prompts snapshot. |
| `post_production_json` | `jsonb` | POST-PRODUCTION stages | Post-pipeline UI state: audio role assignments, video flags, production notes. |
| `layout_json` | `jsonb` | LAYOUT stage | `StoryLayout` blob — panel geometry for comic/picture-book types. |
| `pipeline_timestamps_json` | `jsonb` (map) | Pipeline | `{ stageName: ISO-timestamp }` — updated when each stage completes. |
| `reading_matter_pages_json` | `jsonb` | READ stage | N-page reading matter array `[{ id, placement, titleTarget, titleNative, bodyTarget, bodyNative }]`. |
| `reading_front_matter_json` | `jsonb` | READ stage | Bilingual About block `{ titleTarget, titleEnglish, bodyTarget, bodyEnglish }`. |
| `reading_back_matter_json` | `jsonb` | READ stage | Appendix `{ sections: [{ titleTarget, titleEnglish, bodyTarget, bodyEnglish }] }`. |
| `remote_audio_path` | `text` | Generation | Legacy / story-level audio path in storage. |
| `remote_cover_path` | `text` | Generation | Story cover image path (mirrors `story_cover` in AF 2.0 when wired). |
| `text_gen_prompt` | `text` | UI | Text generation prompt. |
| `image_gen_prompt` | `text` | UI | Cover / image prompt. |
| `video_style` | `text` | UI | Video style token. |
| `video_gen_prompt` | `text` | UI | Video generation prompt. |
| `remote_video_path` | `text` | Generation | Background video path. |
| `pending_video_operation` | `text` | Backend | In-flight video job id/state. |
| `word_timings_json` | `jsonb` | Legacy | Story-level word timings if stored at row level. |
| `comprehension_questions_json` | `jsonb` | Legacy | Story-level MCQ blob if stored at row level. |
| `tagged_target_text` | `text` | Pipeline | Tagged story text. |
| `ambient_sound_id` | `text` | UI | Key into `ambient_sounds`. |
| `ambient_volume` | `double` | UI | BGM volume. |

*Note: Column presence should match migrations; treat this table as the intended contract aligned with [`lib/models/story.dart`](../../../lib/models/story.dart).*

---

## 2. JSONB attribute definitions

### 2.1 `preferences_json`

*Source: [`lib/models/story_preferences.dart`](../../../lib/models/story_preferences.dart)*

Includes (non-exhaustive): `humorLevel`, `realismLevel`, `genre`, `dialogueAmount`, `voice`, `coverArtStyle`, `storyLength`, `endingType`, `protagonistName`, `protagonistGender`, `targetVocabulary`, `grammarFocus`, `audioSpeed`, `interactiveAudio`, `audioStyle`, `audioProvider`, `elevenLabsVoiceId`, `ambientSoundId`, `ambientVolume`, `generateQuiz`, `quizQuestionCount`, `chapterCount`.

### 2.2 `bible_json`

*Source: `generate_story_bible` edge function; Bible workspace.*

- `characters` (array): narrative fields; stable **`id`** / `character_id` where used for Asset Forge linkage; optional `imagePath` for portraits.
- `worldBuilding` (object):
  - `setting`, `rules`, `historicalEchoes`, etc.
  - `locations` (array): each location should have stable **`id`** (string) for Asset Forge 2.0—seed if missing (`loc_<uuid>` style). Fields such as `name`, `subTitle`, `sight`, `sound`, `smell`, `imagePath` / `imageUrl`.
- `coreConflict` (string).

### 2.3 `scene_breakdown_json`

*Source: `generate_scene_breakdown`; see also scene breakdown helpers in app code.*

- `chapters` (array), each item typically includes:
  - `chapterNumber`, `title`, `setting`, `locations`, `charactersInvolved`, `plotSummary`, `sceneBeats` (legacy) and/or structured `scenes[]` with `sceneIndex`, beats, etc.
  - `chapterImagePrompt`, `chapterImagePath` — mirrored from Asset Forge chapter asset when dual-writing.
  - **`chapter_image_asset_id`** — registry **`asset_id`** for the chapter master image (e.g. `af_ch_2`); lets UIs resolve the master via the registry (see Asset Forge 2.0 plan).
  - Per-scene image fields (e.g. `sceneImagePath`) where used; **Asset Forge 2.0** adds **`asset_id`** on each `scenes[]` row used for visuals (stable id, not only a storage path).

### 2.4 `ci_analysis_json`

*Source: `optimize_ci` edge function.*

History of runs (e.g. latest runs): `runAt`, `trigger`, per-chapter `editorNotes`, `optimizedScript`, `optimizedText`, `changesMade`.

---

## 3. The `chapters` data contract

The `chapters` column stores the listening-ready chapter array.

| Key | Type | Description |
| :--- | :--- | :--- |
| `id` | `text` | Chapter id. |
| `chapter_number` | `int` | Order (1-based in UI; may align with prologue handling). |
| `chapter_type` | `text` | e.g. prologue vs standard. |
| `title_target_language` / `title_english` | `text` | Titles. |
| `text_target_language` / `text_english` | `text` | Clean reading text. |
| `script_target_language` / `script_english` | `text` | Tagged script. |
| `audio_url` | `text` | Main chapter audio. |
| `word_timings` | `array` | `{ word, start, end }` for highlighting. |
| `chapter_cover_url` | `text` | Chapter card image (resolved via AF `asset_id` when wired). |
| `chapter_intro_audio_url` | `text` | Intro read-aloud clip (target language); generated at POST AUD. |
| `chapter_intro_word_timings` | `array` | Word timings for intro clip. |
| `native_audio_url` | `text` | Native-language narrator audio; generated at POST AUD alongside target audio. |
| `native_word_timings` | `array` | Word timings for native audio. |
| `comprehension_questions` | `array` | MCQ set. |
| `key_vocabulary` | `array` | Terms. |
| `prompts_json` | `jsonb` | Per-chapter prompt overrides. |
| … | … | See [`StoryChapter`](../../../lib/models/story.dart) for the full field list. |

**Audio ownership rule:** Scene-beat audio lives in `StoryScene`; chapter narrator and intro audio live in `StoryChapter`; ambient/background audio lives in `Story` preferences. `PanelLayout` / `StoryLayout` must never own audio fields — they resolve audio by looking up the `StoryScene` at a given `sceneIndex`.

---

## 4. `asset_forge_json` — visual asset registry (Asset Forge 2.0)

Stored as a single JSON object. **v1 persistence:** everything in this column (no separate `asset_forge_v2` column for the first wave).

### 4.1 Top-level keys (target shape)

| Key | Type | Description |
| :--- | :--- | :--- |
| `style_profile` | `string` | Global art-style anchor for generation. |
| `characters` | `array` | Existing character asset records (`character_id`, prompts, `master_images`, `variations`, `visual_profile`, …). |
| `locations` | `array` | **AF 2.0:** one record per Bible location (by `locations[].id`). |
| `chapters` | `array` | **AF 2.0:** one record per listening chapter slot. |
| `scenes` | `array` | **AF 2.0:** one record per breakdown `scenes[]` row (visuals). |
| `story_cover` | `object` | **AF 2.0:** single story-level cover asset. |

*Dart types will evolve in [`lib/models/asset_forge.dart`](../../../lib/models/asset_forge.dart); unknown keys should be preserved on merge.*

### 4.2 Registry record — common fields

Each visual asset (non-exhaustive; exact optional fields per `kind`):

| Field | Type | Description |
| :--- | :--- | :--- |
| `asset_id` | `string` | Stable id within the story (see §4.3). |
| `kind` | `string` | `character` \| `location` \| `chapter` \| `scene` \| `story_cover` (extensible). |
| `display_name` | `string` | UI label. |
| `pipeline_refs` | `object` | Links to Bible / breakdown / chapter indices (see plan). |
| `prompt_state` | `object` | Prompt text, blocks, “needs regen” flags, etc. |
| `images` | `object` | Master path(s), `variations` array, thumbnails as needed. |
| `metadata` | `object` | Provider, seed, aspect ratio, notes. |

**Location** records additionally carry a full **environment profile** (structured fields)—exact property names are workshop-TBD; see Asset Forge 2.0 plan.

### 4.3 `asset_id` formats (normative)

| Kind | Pattern | Notes |
| :--- | :--- | :--- |
| Character | Bible `character_id` | Same id as Story Bible character. |
| Location | e.g. `af_loc_<slug>` or aligned to `locations[].id` | Bible `locations[].id` required for AF-managed images. |
| Story cover | **`af_story_<storyId>`** | Canonical id; single cover per story (`story.id`). |
| Chapter | `af_ch_<listeningIndex>` | **0-based** index into merged `StoryChapter` / breakdown chapter list. `pipeline_refs` holds `chapterNumber`, `isPrologue` for display; **update refs on reorder**. |
| Scene | **`af_sc_<listeningIndex>_<sceneIndex>`** | **`listeningIndex`** matches the owning chapter asset **`af_ch_<listeningIndex>`**; breakdown `scenes[].asset_id` uses this pattern. |

### 4.4 Storage layout (`audio-stories` bucket)

Namespace: `userId/storyId/...`. Recommended:

`assets/<asset_id>/master.<ext>`  
`assets/<asset_id>/variations/<variant>.<ext>`

### 4.5 Variations policy (implementation)

- At most **5 non-master** variations per asset: when full, **do not hard-block** the UI—use **non-blocking** hints or soft prompts to delete a variation first (no automatic oldest-first deletion).
- User-initiated delete removes registry entry and storage object when confirmed. Master is never auto-deleted.

---

## 5. Pipeline stage → column mapping

`PipelineNavigator` (`lib/utils/pipeline_navigator.dart`) defines 14 stages in 7 phases. Each stage's output is written to a dedicated column on `story_pipeline`.

| Phase | Stage | Workspace screen | Output column(s) |
| :--- | :--- | :--- | :--- |
| 1: Story Idea | IDEA | `ParametersWorkspaceScreen` | `parameters_json` |
| 1: Story Idea | PROFILE | `CIProfileWorkspaceScreen` | `ci_profile_json` |
| 1: Story Idea | LORE | `BibleWorkspaceScreen` | `bible_json` |
| 2: Story Script | ACTS | `TreatmentWorkspaceScreen` | `treatment_json` |
| 2: Story Script | SCENES | `BreakdownWorkspaceScreen` | `scene_breakdown_json` |
| 2: Story Script | SCRIPTS | `ScriptWorkspaceScreen` | `chapters` (text + script fields) |
| 3: Create The Arts | FORGE | `AssetForgeWorkspaceScreen` | `asset_forge_json` |
| 4: Story Optimization | OPT | `OptimizeWorkspaceScreen` | `ci_analysis_json` |
| 5: Story Layout | READ | `ReadingPagesWorkspaceScreen` | `reading_matter_pages_json`, `reading_front_matter_json`, `reading_back_matter_json` |
| 5: Story Layout | LAYOUT | `LayoutWorkspaceScreen` | `layout_json` |
| 6: Post Production | POST GFX | `PostGraphicsWorkspaceScreen` | `post_production_json` + chapter cover image fields |
| 6: Post Production | POST AUD | `PostAudioWorkspaceScreen` | `chapters[].audio_url`, `chapter_intro_audio_url`, `native_audio_url` + timings |
| 6: Post Production | POST VID | `PostVideoWorkspaceScreen` | `remote_video_path`, `video_gen_prompt`, `pending_video_operation` |
| 7: Final | FINAL | `FinaleWorkspaceScreen` | Publish row to `stories` table |

`pipeline_timestamps_json` is updated at the end of each stage (key = stage name, value = ISO timestamp).

Navigation uses `PageRouteBuilder` with zero transition duration so the header and left rail stay visually fixed while the workspace body swaps.

---

## 6. Supporting tables

### `public.ambient_sounds`

| Column | Type |
| :--- | :--- |
| `id` | `text` |
| `display_name` | `text` |
| `supabase_path` | `text` |
| `genre_ids` | `text[]` |

---

## Appendix A — Minimal `asset_forge_json` examples (AF 2.0)

Illustrative only; field names must match shipped Dart `toJson` / migrations.

### A.1 `story_cover`

```json
{
  "asset_id": "af_story_550e8400-e29b-41d4-a716-446655440000",
  "kind": "story_cover",
  "display_name": "Story cover",
  "pipeline_refs": {},
  "prompt_state": { "last_prompt": "…" },
  "images": { "master_path": "userId/storyId/assets/af_story_550e8400-e29b-41d4-a716-446655440000/master.png" },
  "metadata": {}
}
```

### A.2 `locations[]` entry

```json
{
  "asset_id": "af_loc_mercado",
  "kind": "location",
  "display_name": "Mercado",
  "pipeline_refs": { "bible_location_id": "loc_01H…" },
  "prompt_state": { "last_prompt": "…" },
  "images": { "master_path": "userId/storyId/assets/af_loc_mercado/master.png", "variations": [] },
  "metadata": { "environment_profile_version": 1 }
}
```

### A.3 `chapters[]` entry

```json
{
  "asset_id": "af_ch_2",
  "kind": "chapter",
  "display_name": "Chapter 3 — The Market",
  "pipeline_refs": {
    "listening_index": 2,
    "chapter_number": 3,
    "is_prologue": false
  },
  "prompt_state": { "last_prompt": "…" },
  "images": { "master_path": "userId/storyId/assets/af_ch_2/master.png" },
  "metadata": {}
}
```

### A.4 `scenes[]` entry

```json
{
  "asset_id": "af_sc_3_2",
  "kind": "scene",
  "display_name": "Market confrontation",
  "pipeline_refs": {
    "breakdown": { "chapter_index": 2, "scene_index": 2 },
    "location_asset_id": "af_loc_mercado"
  },
  "prompt_state": { "last_prompt": "…" },
  "images": { "master_path": "userId/storyId/assets/af_sc_3_2/master.png", "variations": [] },
  "metadata": {}
}
```

### A.5 Tiny full blob (shape only)

```json
{
  "style_profile": "children's watercolor, soft edges",
  "characters": [],
  "locations": [],
  "chapters": [],
  "scenes": [],
  "story_cover": null
}
```

---

## Changelog (this doc)

| Date | Note |
| :--- | :--- |
| 2026-05-01 | Added missing columns from migrations: `layout_json`, `post_production_json`, `reading_matter_pages_json`, `reading_front_matter_json`, `reading_back_matter_json`. Added §5 Pipeline Stage → Column Mapping table (14 stages, 7 phases). Expanded §3 `chapters` contract with POST AUD audio separation fields (`chapter_intro_audio_url`, `native_audio_url`, timings). Added Builder vs Player tables note. |
| 2026-04-10 | Merged pipeline + architecture data model into this file; expanded `public.stories` columns; added §4 `asset_forge_json` / AF 2.0 registry, §4.3 ids, storage, variation policy; Appendix A examples. |
| 2026-04-10 | Aligned with plan: **`af_story_<storyId>`**, scene **`af_sc_<listeningIndex>_<sceneIndex>`**, **`chapter_image_asset_id`** on breakdown, **non-blocking** variation at-cap UX. |
