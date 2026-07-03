# iOS Story Player — Multi-Language Architecture Handoff

**Audience:** AI agent (or engineer) updating the **LearnCI iOS app** story player to the **clean-sheet multi-language JSON contract**.

**Primary specs (read first):**

| Topic | Doc |
|--------|-----|
| Multi-language redesign (Part 9) | `LearnCI_Flutter/docs/plans/multi_target_language_story_generation_plan.md` — §0, §1, §3, §4, §5.5, §9 |
| **Chapter v10 grouped blocks (Part 10)** | `LearnCI_Flutter/docs/plans/chapter_language_grouping_v10.md` |
| **Reading matter kinds + structured rows** | `LearnCI_Flutter/docs/plans/reading_matter_structured_templates_plan.md` |
| Canonical DB contract | `LearnCI_Flutter/docs/story builder/pipeline/data_model.md` §3 + reading-matter notes |

**Repo to implement:** `LearnCI` (Swift / SwiftUI).  
**Reference implementation (behavioral spec):** `LearnCI_Flutter` learner app + pipeline on **`main`** (as of 2026-07-02).

**Flutter / backend status:** Part 9 (per-language maps), Part 10 (chapter grouping), F5 SQL strip of legacy root keys, publish trim, and reading-matter structured templates are **shipped** on Flutter. iOS is **not** migrated.

---

## 0. Hard rules for this iOS task

1. **No backward compatibility.** Do not decode, read, or fall back to legacy bilingual root fields. Do not add “lift legacy into maps in `init(from:)`” shims. If JSON lacks the expected v10 / Part 9 shapes, treat content as **missing** (empty / incomplete-production UI)—not an excuse to read `captionTarget` or flat chapter `by_language`.

2. **Prose lives at the scene level.** Chapter body text and dramatized script are **never stored** on the chapter root. Presenters **join** `scenes[i].byLanguage[code].caption` / `.script` on demand.

3. **Chapter language data is grouped (v10).** Per-language chapter fields live under four domain envelopes — `title`, `intro`, `vocabulary`, `comprehension` — each with its own nested `by_language[code]`. There is **no** flat `by_language` bag on the chapter root after migration.

4. **Native is just another language code.** Gloss is `…by_language[nativeCode]`, not a separate axis (`titleEnglish`, `captionNative`, `textEnglish`, `dialogues[].textEnglish` are **gone**).

5. **Explicit language on every read.** Accessors take `langCode: String`. Resolve once per session:
   - `targetCode` = this library row’s language (`story.language` → ISO 639-1, lowercased)
   - `nativeCode` = `story.native_language` (default `"en"`)

6. **One library card = one target language.** Multi-target stories appear as **sibling `stories` rows** (Spanish card, French card). In-app “switch language” = open the sibling story, not remap codes on one row.

7. **Match the shipped Flutter contract**, not pre-migration JSON. After F5 + v10 migration, Supabase rows have **no** legacy chapter/scene/page root language fields and **no** flat chapter `by_language`.

8. **Reading matter: prose is the playback contract.** For all page kinds (`prose`, `characters`, `glossary`), render and narrate via `page.bodyFor(langCode)` / `page.titleFor(langCode)`. Structured rows (`structured_rows`) are optional richer data for future UI; they must not replace the derived `body` for audio-book spine playback.

---

## 1. Architecture summary (full redesign, not a partial patch)

The multi-target-language effort replaces the original **asymmetric single-primary** schema with a **symmetric per-language map** at scene and reading-matter page level, and **grouped per-language envelopes** at chapter level (v10).

| Layer | Language-agnostic root | Per-language data |
|--------|------------------------|-------------------|
| **Story row** | `title`, `layout_json`, preferences, … | N/A — row *is* one target language |
| **Chapter** | `chapter_number`, `plot_summary`, `scenes`, `chapter_cover_url`, beats, setting, … | **v10:** `title`, `intro`, `vocabulary`, `comprehension` — each `{ "by_language": { "<code>": { … } } }` |
| **Scene** | `sceneIndex`, `contentMode`, `imageUrl`, `cropRegion`, `characters` | `byLanguage[code]` → caption, script, audio, timings, dialogues |
| **Reading matter page** | `id`, `placement`, `kind` | `by_language[code]` → title, body, `structured_rows` (optional), optional audio |

### 1.1 Chapter v10 grouped blocks

Each envelope owns its own `by_language` map:

| Envelope | `by_language[code]` fields |
|----------|----------------------------|
| `title` | `text` |
| `intro` | `text`, `audio_url`, `word_timings` |
| `vocabulary` | `note` |
| `comprehension` | `questions` (`id`, `question`, `choices`, `correct_index`) |

**Public accessors** (mirror Flutter `StoryChapter`) read through these envelopes — callers still use `titleFor(targetCode)`, `chapterIntroTextForLanguage(targetCode)`, etc. Only the **JSON decode path** changes.

### 1.2 Reading matter page kinds

| `kind` | Root `kind` in JSON | Structured data | Playback / display |
|--------|---------------------|-----------------|-------------------|
| `prose` | omitted (default) | none | `bodyFor(code)` |
| `characters` | `"characters"` | `by_language[code].structured_rows` → `{ "rows": […] }` | **`bodyFor(code)`** (derived prose); rows optional for card UI |
| `glossary` | `"glossary"` | same | **`bodyFor(code)`** (derived prose); rows optional for list UI |

Default spine (5 pages): **About This Book** · **Meet the Characters** · **Setting & Background** (before chapters) · **Cultural Notes** · **Glossary** (after chapters). See `defaultReadingMatterPageRequests()` in Flutter.

**What was deleted (never reintroduce on iOS):**

| Old (chapter root) | New location (v10) |
|--------------------|-------------------|
| Flat `by_language[code].title` | `title.by_language[code].text` |
| `chapter_intro_text` | `intro.by_language[code].text` |
| `chapter_intro_audio_url`, `chapter_intro_word_timings` | `intro.by_language[targetCode].audio_url` / `.word_timings` |
| `vocabulary_note` | `vocabulary.by_language[targetCode].note` |
| `comprehension_questions` | `comprehension.by_language[targetCode].questions` |
| `title_target_language`, `title_english` | `title.by_language[code].text` |
| `script_target_language`, `script_english` | **Not stored** — join `scenes[].byLanguage[code].script` |
| `text_target_language`, `text_english` | **Not stored** — join `scenes[].byLanguage[code].caption` |
| `native_audio_url`, `native_word_timings` | Removed (native narration is per-scene or unused) |
| `plot_summary_target` / `plot_summary_english` | Single `plot_summary` |

| Old (scene root) | New location |
|------------------|--------------|
| `captionTarget`, `captionNative` | `byLanguage[code].caption` |
| `scriptTargetLanguage`, `scriptEnglish` | `byLanguage[code].script` |
| `audioUrl`, `wordTimings`, `audioDurationMs` | `byLanguage[code].…` |
| `dialogues` + `textEnglish` | `byLanguage[code].dialogues[]` (each line has `text` in that language) |

| Old (reading matter page) | New location |
|---------------------------|--------------|
| `titleTarget`, `titleNative`, `bodyTarget`, `bodyNative` | `by_language[code].title` / `.body` |
| Root `audioUrl`, `wordTimings` | `by_language[code].audio_url` / `word_timings` |
| Root `structured` | `by_language[code].structured_rows` |

**JSON key naming (shipped):**

- Chapter grouped envelopes + reading-matter pages: snake_case `by_language`; inner fields snake_case (`audio_url`, `word_timings`, `correct_index`, `structured_rows`).
- Scenes: camelCase `byLanguage` with camelCase inner keys (`audioUrl`, `wordTimings`, `audioDurationMs`). Decode exactly those keys.

---

## 2. Example payloads (canonical only)

### 2.1 Chapter + scene (v10 grouped)

```json
{
  "id": "ch-1",
  "chapter_number": 1,
  "chapter_type": "chapter",
  "plot_summary": "Kipper visits the park.",
  "chapter_cover_url": "story-covers/…/cover.jpg",
  "title": {
    "by_language": {
      "es": { "text": "Capítulo uno" },
      "en": { "text": "Chapter one" }
    }
  },
  "intro": {
    "by_language": {
      "es": {
        "text": "Hoy vamos al parque…",
        "audio_url": "audio-stories/…/intro.m4a",
        "word_timings": [{ "word": "Hoy", "start": 0.0, "end": 0.3 }]
      },
      "en": { "text": "Today we go to the park…" }
    }
  },
  "vocabulary": {
    "by_language": {
      "es": { "note": "📝 parque — park" }
    }
  },
  "comprehension": {
    "by_language": {
      "es": {
        "questions": [
          {
            "id": "q1",
            "question": "¿Adónde va Kipper?",
            "choices": ["al parque", "a casa", "a la escuela", "al mar"],
            "correct_index": 0
          }
        ]
      }
    }
  },
  "scenes": [
    {
      "sceneIndex": 0,
      "contentMode": "prose",
      "imageUrl": null,
      "byLanguage": {
        "es": {
          "caption": "Kipper camina al parque.",
          "script": "[NARRATOR] (neutral) Kipper camina al parque.",
          "audioUrl": "audio-stories/…/chapter_01_scene_01.m4a",
          "audioDurationMs": 4200,
          "wordTimings": [{ "word": "Kipper", "start": 0.0, "end": 0.4 }],
          "dialogues": []
        },
        "en": {
          "caption": "Kipper walks to the park.",
          "script": "[NARRATOR] (neutral) Kipper walks to the park."
        }
      }
    }
  ]
}
```

**Decode note:** `ComprehensionQuestion` accepts `correct_index` (snake_case, canonical on wire) or `correctIndex` when decoding — always **encode** `correct_index`.

### 2.2 Reading matter envelope

Storage column `reading_matter_pages_json` wraps pages:

```json
{
  "pages": [
    {
      "id": "uuid-about",
      "placement": "beforeChapters",
      "by_language": {
        "es": { "title": "Antes de empezar", "body": "Este cuento trata de…" },
        "en": { "title": "Before you begin", "body": "This story is about…" }
      }
    },
    {
      "id": "uuid-characters",
      "placement": "beforeChapters",
      "kind": "characters",
      "by_language": {
        "es": {
          "title": "Conoce a los personajes",
          "body": "Daniela — Protagonista\nEs valiente y curiosa.",
          "structured_rows": {
            "rows": [
              {
                "name": "Daniela",
                "role": "Protagonist",
                "bio": "Es valiente y curiosa.",
                "relationships": "Amiga de Marco."
              }
            ]
          }
        },
        "en": {
          "title": "Meet the Characters",
          "body": "Daniela — Protagonist\nShe is brave and curious.",
          "structured_rows": {
            "rows": [
              {
                "name": "Daniela",
                "role": "Protagonist",
                "bio": "She is brave and curious.",
                "relationships": "Marco's friend."
              }
            ]
          }
        }
      }
    },
    {
      "id": "uuid-glossary",
      "placement": "afterChapters",
      "kind": "glossary",
      "by_language": {
        "es": {
          "title": "Glosario",
          "body": "casa (n.) — house. Mi casa es grande.",
          "structured_rows": {
            "rows": [
              {
                "targetWord": "casa",
                "nativeGloss": "house",
                "partOfSpeech": "n.",
                "exampleTarget": "Mi casa es grande.",
                "exampleNative": "My house is big.",
                "firstChapterIndex": 0
              }
            ]
          },
          "audio_url": "audio-stories/…/reading_glossary.m4a",
          "word_timings": [{ "word": "casa", "start": 0.0, "end": 0.5 }],
          "audio_duration_ms": 12000
        },
        "en": {
          "title": "Glossary",
          "body": "casa (n.) — house. Mi casa es grande."
        }
      }
    }
  ]
}
```

**Character row fields:** `name` (proper noun, not translated), `role` (language-agnostic label), `bio`, `relationships` — each localized under that language’s `structured_rows.rows[]`.

**Glossary row fields:** `targetWord`, `nativeGloss`, `partOfSpeech`, `exampleTarget`, `exampleNative`, `firstChapterIndex` (optional).

**Prose derivation (must match server):** Flutter `renderCharactersProse` / `renderGlossaryProse` in `reading_matter.dart` — iOS should produce identical `body` text if it ever re-derives from rows on save; for playback, trust persisted `body`.

### 2.3 Published story row

After `publish_story_pipeline` trim, each row keeps only **`[targetCode, nativeCode]`** in every nested `by_language` / `byLanguage` map (e.g. Spanish library card: `es` + `en`, not `fr`). Trim walks:

- `chapters[i].title|intro|vocabulary|comprehension.by_language`
- `chapters[i].scenes[j].byLanguage`
- `reading_matter_pages_json.pages[k].by_language`

Sync fields iOS must map: `language` / `language_code`, `native_language`, `chapters`, `layout_json`, `reading_matter_pages_json`, `asset_forge_json`.

---

## 3. Flutter reference map (copy behavior)

| Concern | File |
|---------|------|
| Plan (full redesign) | `LearnCI_Flutter/docs/plans/multi_target_language_story_generation_plan.md` |
| **Chapter v10 grouping** | `LearnCI_Flutter/docs/plans/chapter_language_grouping_v10.md` |
| **Chapter envelope types** | `LearnCI_Flutter/lib/models/chapter_language_blocks.dart` |
| Chapter model + accessors | `LearnCI_Flutter/lib/models/story.dart` → `StoryChapter` |
| Scene model + accessors | `LearnCI_Flutter/lib/models/story_scene.dart` |
| Reading matter | `LearnCI_Flutter/lib/models/reading_matter.dart` |
| Reading matter structured spec | `LearnCI_Flutter/docs/plans/reading_matter_structured_templates_plan.md` |
| Player architecture | `LearnCI_Flutter/docs/story builder/architecture/story_player_rendering.md` |
| Pipeline data model | `LearnCI_Flutter/docs/story builder/pipeline/data_model.md` |
| Publish trim | `LearnCI_Flutter/supabase/functions/publish_story_pipeline/index.ts` |
| Presenters (all types) | `LearnCI_Flutter/lib/presenters/*_presenter.dart` |
| Reader data / spine | `LearnCI_Flutter/lib/services/story_manager.dart` (read paths only) + layout/spine utils |

**Accessor pattern to mirror in Swift** (unchanged public API; v10 changes decode only for chapters):

```swift
// Every read passes langCode — no implicit "primary"
chapter.titleFor(targetCode)
chapter.bodyTextForLanguage(targetCode)       // joins scenes
chapter.bodyScriptForLanguage(targetCode)     // joins scenes; dramatized
chapter.chapterIntroTextForLanguage(targetCode)
chapter.chapterIntroAudioUrlForLanguage(targetCode)
chapter.chapterIntroWordTimingsForLanguage(targetCode)
chapter.vocabularyNoteForLanguage(targetCode)
chapter.comprehensionQuestionsForLanguage(targetCode)
scene.captionFor(targetCode)
scene.scriptFor(targetCode)
scene.audioUrlForLanguage(targetCode)
scene.wordTimingsFor(targetCode)
scene.dialoguesFor(targetCode)
page.titleFor(targetCode)
page.bodyFor(targetCode)
page.audioUrlFor(targetCode)
page.wordTimingsFor(targetCode)
page.characterRowsFor(targetCode)   // optional structured UI
page.glossaryRowsFor(targetCode)    // optional structured UI
```

**Flutter rule:** accessors return empty / nil when the map entry is missing—**no** fallback to legacy root fields or flat chapter `by_language`.

**Reading spine helpers to mirror:**

- `readingMatterPagesWithContentByPlacement(story)` — splits before/after chapter pages
- `appearsOnReadingSpineFor(targetCode, nativeCode)` — title **or** body counts (titled placeholders show before AI fill)
- `hasContentFor(targetCode, nativeCode)` — body-only (stricter export checks)
- `readingMatterPageChipLabel(page, targetCode, nativeCode)` — segment tab label

---

## 4. Current iOS state (must be replaced, not extended)

### 4.1 Models to rewrite (not patch)

| File | Problem |
|------|---------|
| `LearnCI/Models/StoryChapter.swift` | Legacy-shaped (`titleTargetLanguage`, flat `byLanguage` bag, root intro/audio/quiz, chapter-level script/text). Needs v10 `title` / `intro` / `vocabulary` / `comprehension` envelopes. |
| `LearnCI/Models/StoryReaderModels.swift` → `StoryScene` | Root `captionTarget`, `audioUrl`, `scriptTargetLanguage`, `dialogues[].textEnglish`. |
| `LearnCI/Models/StoryReaderModels.swift` → `ReadingMatterPage` | Root `titleTarget` / `bodyTarget` / root audio; missing `kind`, `structured_rows`, snake_case audio keys. |
| `LearnCI/Models/Story.swift` | Ensure `native_language` code is synced; parse `reading_matter_pages_json` as `{pages:[…]}` envelope. |

**Do not** keep legacy stored properties “for now.” Replace with clean models + accessors only.

### 4.2 Player layer (grep and rewrite reads)

| Area | Files |
|------|--------|
| Spine / clips / requirements | `StoryReaderDataAdapter.swift` |
| Prose | `StorySessionView.swift` |
| Interactive / script segments | `InteractiveStorySessionView.swift` |
| Audio book + reading matter | `AudioBookReaderView.swift` |
| Dialog | `DialogSessionView.swift`, `DialogStoryFlowView.swift` |
| Comic / picture | `ComicBookReaderView.swift`, `PictureBookReaderView.swift` |
| Supplemental intro audio | `StorySupplementalAudioPlayback.swift` |
| Factory / routing | `StoryReaderFactoryView.swift` |
| UI chrome | `ChapterInfoCardView.swift`, `StoryAboutView.swift` |
| Sync | `SyncManager.swift` — decode new shapes via `StoryDTO`; no flattening |
| Tests | `LearnCITests/StoryReadingSpineTests.swift`, `DialogStoryBuilderTests.swift` — **canonical fixtures only** |

Prior doc `ios_story_reader_update_plan.md` describes spine/scene **playlist** architecture (largely already on iOS). **This handoff** is the **language/data contract** migration on top of that spine work.

---

## 5. Required Swift model shapes

### 5.1 `ChapterLangEnvelope<T>` (generic)

Wrapper: `{ "by_language": { "<code>": T } }`. Method `forCode(_ langCode: String) -> T?` lowercases codes.

### 5.2 Grouped chapter language payloads

| Type | Fields | JSON keys |
|------|--------|-----------|
| `ChapterTitleLang` | `text` | `text` |
| `ChapterIntroLang` | `text`, `audioUrl`, `wordTimings` | `text`, `audio_url`, `word_timings` |
| `ChapterVocabLang` | `note` | `note` |
| `ChapterComprehensionLang` | `questions` | `questions` → `[ComprehensionQuestion]` |

### 5.3 `ComprehensionQuestion`

Fields: `id`, `question`, `choices`, `correctIndex`. Decode `correct_index` or `correctIndex`; encode `correct_index`.

### 5.4 `SceneLanguageData` / `SceneDialogue`

Unchanged from Part 9: `caption`, `script`, `audioUrl`, `wordTimings`, `audioDurationMs`, `dialogues` with `character`, `text`, `audioUrl` — **no `textEnglish`**.

### 5.5 `ReadingMatterPageLanguageData`

Fields: `title`, `body`, `audioUrl`, `wordTimings`, `audioDurationMs`, `structuredRowsJson` (optional). JSON: snake_case `audio_url`, `word_timings`, `audio_duration_ms`, `structured_rows` (object `{rows:[…]}` or bare array).

### 5.6 `ReadingMatterKind`

Enum: `prose` (default, omit from JSON), `characters`, `glossary`.

### 5.7 `CharacterPageRow` / `GlossaryPageRow`

Match Flutter `reading_matter.dart` field names. Implement `renderCharactersProse` / `renderGlossaryProse` if iOS ever re-derives body on edit.

### 5.8 `StoryChapter` (final root fields)

`id`, `chapterNumber`, `chapterType`, `plotSummary`, `setting`, `locations`, `charactersInvolved`, `sceneBeats`, `scenes`, `coverUrl`, plus v10:

- `title: ChapterLangEnvelope<ChapterTitleLang>`
- `intro: ChapterLangEnvelope<ChapterIntroLang>`
- `vocabulary: ChapterLangEnvelope<ChapterVocabLang>`
- `comprehension: ChapterLangEnvelope<ChapterComprehensionLang>`

**Do not** store flat `byLanguage: [String: ChapterLanguageData]` on the chapter root.

Computed (all take `langCode`):

- `bodyTextForLanguage` — sorted scenes → `captionFor` → join `\n\n`
- `bodyScriptForLanguage` — sorted scenes → `scriptFor` → join
- `bodyWordTimingsForLanguage` — merge scene timings with cumulative offset from `audioDurationMsFor`
- `hasSceneAudioForLanguage` / `bodyNarrationClipsCompleteForLanguage`
- `titleFor`, intro / vocab / quiz accessors via grouped envelopes

### 5.9 `StoryScene` (final root fields)

`sceneIndex`, `contentMode`, `imageUrl`, `cropRegion`, `characters`, `byLanguage: [String: SceneLanguageData]`.

Update `spokenTranscriptText(preferences:targetCode:)` and related helpers to require `targetCode`.

### 5.10 `ReadingMatterPage` (final root fields)

`id`, `placement` (`beforeChapters` | `afterChapters`), `kind`, `byLanguage: [String: ReadingMatterPageLanguageData]`.

---

## 6. Player migration by story type

Thread `targetCode` and `nativeCode` from `Story` everywhere. Target/native UI toggle = those two codes, not hard-coded English.

| Story type | iOS entry | Key reads |
|------------|-----------|-----------|
| Story book | `StorySessionView` | Scene playlist from `audioUrlForLanguage(targetCode)`; highlight from `wordTimingsFor(targetCode)`; text toggle uses `bodyTextForLanguage` ×2 |
| Audio story | `AudioBookReaderView` | Same clips; reading matter via `page.bodyFor` / `page.audioUrlFor`; spine segments for all `appearsOnReadingSpineFor` pages (up to 5 defaults) |
| Dialog | `DialogSessionView` | `dialoguesFor(targetCode)` + `dialoguesFor(nativeCode)` by **index** |
| Interactive | `InteractiveStorySessionView` | `bodyScriptForLanguage(targetCode)` or per-scene `scriptFor` for segment parser |
| Comic | `ComicBookReaderView` | Panel caption/audio from scene accessors; layout unchanged |
| Picture | `PictureBookReaderView` | Full-screen scene text/audio from accessors |

**Dramatized TTS text:** `preferences.audioStyle == .dramatized` → prefer `scriptFor(targetCode)`, else `captionFor(targetCode)` (match Flutter `panel_text_helpers` / scene audio helpers).

**Chapter intro:** separate clip from `chapterIntroAudioUrlForLanguage(targetCode)` — reads `intro.by_language[targetCode].audio_url`, not merged into scene body.

**Reading matter audio:** optional per-page clip from `page.audioUrlFor(targetCode)` with `wordTimingsFor(targetCode)`; use `bodyFor` for on-screen text even when `kind` is `characters` or `glossary`.

**Incomplete production:** if `bodyNarrationClipsCompleteForLanguage(targetCode)` is false, show incomplete state (existing pattern in adapter)—do **not** fall back to chapter-level `audioUrl`.

---

## 7. Sync and local cache

- **Supabase pull:** `SyncManager` decodes `chapters` JSON into v10 grouped models and `reading_matter_pages_json` as `{pages:[…]}`. No server-side flattening on iOS.
- **Local SwiftData:** Stories synced **after** pipeline publish use canonical JSON only. **Out of scope:** upgrading old on-device rows that still have legacy JSON—users re-sync from server or those rows show incomplete. **Do not** build legacy decode paths for them.

---

## 8. Testing

### 8.1 Unit tests

- New fixtures: **canonical JSON only** (§2 examples).
- Decode tests for v10 chapter envelopes, scene maps, reading-matter pages (prose + characters + glossary).
- `bodyWordTimingsForLanguage` offset math across two scenes.
- Requirement checks fail when `byLanguage[targetCode].audioUrl` missing.
- Reading matter: `characterRowsFor` / `glossaryRowsFor` decode `structured_rows`; `bodyFor` matches persisted body.

### 8.2 Manual smoke

Use a **newly published** pipeline story (post F5 + v10):

1. Open each applicable reader type from library.
2. Scene audio plays in order; word highlight aligned.
3. Target ↔ native text toggle works; native never falls back to target.
4. Chapter intro → scene 1 handoff (intro audio from `intro.by_language`).
5. Reading matter (audio book): before-chapter pages (About, Characters, Setting) and after-chapter pages (Cultural Notes, Glossary) appear on spine when titled or bodied.
6. Chapter quiz loads from `comprehension.by_language[targetCode].questions`.

### 8.3 SQL sanity check

```sql
SELECT id, language, native_language,
       chapters->0->'title'->'by_language' AS ch_title_lang,
       chapters->0->'intro'->'by_language' AS ch_intro_lang,
       chapters->0->'by_language' AS flat_by_lang_should_be_null,
       chapters->0->'scenes'->0->'byLanguage' AS scene_lang,
       reading_matter_pages_json->'pages'->1->'kind' AS rm_kind,
       reading_matter_pages_json->'pages'->1->'by_language' AS rm_lang
FROM stories
ORDER BY created_at DESC
LIMIT 1;
```

Expect: grouped `title` / `intro` maps present; **flat** `chapters[i].by_language` **absent**; reading-matter `kind` = `characters` or `glossary` where applicable.

---

## 9. Implementation order (clean-sheet)

1. **Delete legacy model fields** — replace `StoryChapter` (v10 envelopes), `StoryScene`, `ReadingMatterPage` with canonical structs (compile will break; fix top-down).
2. **`Story` + `SyncManager`** — `native_language`, language code resolution, `{pages:[]}` reading-matter envelope.
3. **`StoryReaderDataAdapter`** — clips, spine requirements, reading matter (single choke point).
4. **Presenters** — `StorySessionView` → audio book → dialog → interactive → comic → picture.
5. **UI chrome + tests** — canonical fixtures only (include v10 chapter + structured reading-matter samples).
6. **Grep gate** — zero legacy identifiers (see §10).

---

## 10. Verification

```bash
xcodebuild build -project LearnCI.xcodeproj -scheme LearnCI -configuration Debug

xcodebuild test -project LearnCI.xcodeproj -scheme LearnCI \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Must be zero matches** (no exceptions for “decode-only”):

```bash
rg 'captionTarget|captionNative|titleTargetLanguage|titleEnglish|scriptTargetLanguage|scriptEnglish|chapterIntroTextEnglish|textEnglish|text_target_language|nativeAudioUrl|bodyTextTargetForReading|chapter_intro_text|chapter_intro_audio_url|vocabulary_note|comprehension_questions' \
  LearnCI/Models LearnCI/Views/StoryMaker LearnCITests
```

Also verify chapters do **not** decode a flat root `by_language` bag — only `title` / `intro` / `vocabulary` / `comprehension` envelopes.

Replace reads with `*ForLanguage` / `*For(_:)` accessors.

---

## 11. Out of scope

- Flutter pipeline, edge functions, SQL migrations (done on Flutter repo).
- Web portal (`LearnCI-web`).
- Story **generation** on iOS.
- Legacy JSON support, migration shims, or dual-read code paths.
- Switching target language inside one story row (sibling library cards instead).
- Rich structured UI for character/glossary rows (optional future work — v1 uses derived `body` prose).

---

## 12. FAQ (when blocked, match Flutter)

| Question | Answer |
|----------|--------|
| Where is chapter title? | `title.by_language[targetCode].text` via `titleFor(targetCode)`. |
| Where is chapter body text? | Join `scenes[].byLanguage[targetCode].caption` — never a chapter root field. |
| Where is dramatized script? | Join `scenes[].byLanguage[targetCode].script`. |
| Where is chapter intro text/audio? | `intro.by_language[targetCode].text` / `.audio_url` / `.word_timings`. |
| Where is vocab note / quiz? | `vocabulary.by_language[targetCode].note` / `comprehension.by_language[targetCode].questions`. |
| Flat `by_language` on chapter? | **Removed in v10.** Use grouped envelopes only. |
| English toggle code? | `nativeCode` from `story.native_language`. |
| Dialog bilingual display? | `dialoguesFor(targetCode)[i]` + `dialoguesFor(nativeCode)[i]`. |
| Reading matter characters page? | `kind: "characters"`; playback uses `bodyFor(code)`; optional `structured_rows` per language. |
| Reading matter glossary page? | `kind: "glossary"`; same pattern; rows use `targetWord`, `nativeGloss`, etc. |
| Missing native entry? | Empty / hide — **never** substitute target text. |
| Missing audio? | Incomplete production UI — **never** chapter-level `audioUrl`. |

---

**Document version:** 2026-07-02 — v10 chapter grouping + structured reading matter (no backward compatibility).  
**Flutter reference:** `LearnCI_Flutter` **`main`**.  
**Supersedes:** `ios_part9_language_architecture_handoff.md` and the 2026-06-30 draft of this file (flat chapter `by_language`).
