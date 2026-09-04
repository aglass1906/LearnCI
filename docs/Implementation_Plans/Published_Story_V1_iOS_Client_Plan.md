# Published Story Asset Format V1 — iOS Client Plan

**Status:** Placeholder / deferred roadmap item  
**Implementation:** Not started  
**Depends on:** Flutter Builder `PublishedStoryPackageV1` schema and shared dialogue/narrative fixtures

## Purpose

Update the LearnCI iOS client to consume the additive Published Story Asset Format V1 produced by the Flutter Story Builder, while preserving full compatibility with existing published stories.

The authoritative publishing proposal is the sibling Flutter plan:

- [`Published Story Asset Format V1 Plan`](../../../LearnCI_Flutter/docs/plans/published_story_asset_format_v1_plan.md)

This document is intentionally a placeholder. Exact Swift types and database fields should not be finalized until the shared V1 JSON schema and cross-platform fixtures are approved.

## Product outcomes

The iOS client should use one published story package to support:

- reading and bilingual text;
- continuous and unit-level listening;
- synchronized word highlighting;
- shadowing and dialogue role-play;
- story-derived flashcards;
- vocabulary, audio-cloze, matching, and ordering games;
- comprehension and grammar study;
- future story remixing;
- future story creation from saved words and other study material.

## Compatibility strategy

V1 is additive. A published `stories` row initially contains both the existing fields and the new manifests.

Client selection rule:

```text
Valid published_format_version + valid V1 manifests
    → use the V1 adapter
Otherwise
    → use the current Story/StoryChapter representation
```

The legacy fallback must remain until both clients have adopted V1 and existing public stories have been migrated or intentionally retained as legacy content.

## Proposed iOS workstreams

### 1. Contract models and fixtures

- Add Swift `Codable` models matching the approved V1 schema.
- Decode stable chapters, scenes, text units, spoken units, tokens, assets, learning entries, and lineage.
- Share golden dialogue and narrative fixtures with the Flutter repository.
- Add contract tests proving Dart and Swift decode the same payloads.

Likely modules:

- `LearnCI/Models/PublishedStory/` (new)
- `LearnCITests/PublishedStoryContractTests.swift` (new)
- `LearnCITests/Fixtures/PublishedStoryV1/` (new)

### 2. Persistence and synchronization

- Extend `StoryDTO`, `Story`, and pull synchronization with format version, revision, content hash, audio manifest, learning manifest, lineage, and publication timestamp.
- Preserve the existing DTO separation between SwiftData and Supabase.
- Do not make iOS responsible for compiling or repairing malformed published packages.
- Record a safe decode/fallback reason without logging complete story payloads.

Likely modules:

- `LearnCI/Managers/SyncManager.swift`
- `LearnCI/Models/Story.swift`
- `LearnCI/LearnCIApp.swift` if new SwiftData models are introduced

### 3. Unified published-story adapter

- Introduce one client-facing adapter that exposes normalized chapters, scenes, text units, spoken units, and assets.
- Implement V1 and legacy projections behind the same interface.
- Keep story presenters unaware of Supabase column names and manifest JSON structure.
- Preserve stable unit IDs throughout navigation and progress tracking.

Likely modules:

- `LearnCI/Views/StoryMaker/StoryReaderDataAdapter.swift`
- `LearnCI/Models/StoryReaderModels.swift`
- `LearnCI/Models/StoryChapter.swift`

### 4. Audio, timings, and offline caching

- Resolve canonical speaker-turn or semantic-segment clips from the audio manifest.
- Support optional assembled chapter-track maps for continuous listening.
- Drive highlighting from clip-relative token/range timings.
- Cache by immutable asset checksum/revision instead of invalidating all media from `Story.updatedAt`.
- Download only the current/next required clips unless the learner explicitly downloads the story.
- Preserve current legacy scene-audio behavior as fallback.

Likely modules:

- `LearnCI/Managers/StoryChapterAudioPlayer.swift`
- `LearnCI/Managers/StorySupplementalAudioPlayback.swift`
- `LearnCI/Views/StoryMaker/StoryReaderDataAdapter.swift`
- `LearnCI/Views/StoryMaker/StoryAudioPlaybackView.swift`
- `LearnCI/Views/StoryMaker/StoryShadowingStageView.swift`

### 5. Story learning manifest

- Resolve vocabulary, phrases, grammar features, occurrences, question banks, and supported activity capabilities.
- Build deterministic study material from stored analysis before considering an AI request.
- Link every activity back to stable story/text/audio unit IDs.
- Keep shared story analysis separate from private learner mastery and attempts.

Potential new components:

- `StoryLearningManifestAdapter`
- `StoryStudyDeckBuilder`
- `StoryExerciseFactory`
- `StoryLearningSelectionPolicy`

### 6. Learning feature integration

Adopt V1 incrementally:

1. reading and synchronized highlighting;
2. listening and shadowing;
3. story vocabulary deck and flashcards;
4. comprehension questions;
5. audio cloze;
6. matching and word-order activities;
7. dialogue role-play and character practice;
8. grammar-focused review.

Each feature must use the manifest's declared capabilities and gracefully hide activities whose required assets are absent.

### 7. Learner-state overlay

- Store personal progress, answers, mastery, saved status, and review scheduling independently from shared published content.
- Associate learner state with stable story revision and unit IDs.
- Define what happens when a published revision removes or replaces a unit.
- Feed eligible story words into the existing saved-study-word and game systems without duplicating shared analysis.

Likely modules:

- `LearnCI/Models/StoryStudyState.swift`
- `LearnCI/Models/StoryStudyChunk.swift`
- `LearnCI/Models/StoryPathProgress.swift`
- saved-study-word and game-session managers

### 8. Future remix support

- Display origin, parent story, and attribution from lineage.
- Resolve inherited and replaced artifact references.
- Preserve progress for inherited unit IDs.
- Add a future “Remix this story” entry point that submits a bounded remix specification rather than duplicating the published package on-device.

### 9. Future “create from my words” support

- Select a bounded set of saved words, recent mistakes, grammar goals, or YouTube-study vocabulary.
- Send stable learning-item IDs and a compact generation brief to the generation service.
- Consume the resulting story through the same V1 adapter as curated and remixed stories.

## Proposed rollout

### Phase A — Contract only

- Approve the V1 JSON schema.
- Add shared dialogue and narrative fixtures.
- Implement Swift decoding and validation tests.
- No UI, database, or production behavior change.

### Phase B — Additive sync

- Add V1 fields to DTOs and local persistence.
- Sync V1 data while all readers remain on the legacy path.
- Measure decode success and payload size.

### Phase C — Read/listen pilot

- Add the compatibility adapter behind a feature flag.
- Enable V1 reading, audio resolution, highlighting, and caching for fixture stories.
- Verify legacy fallback and offline behavior.

### Phase D — Learning features

- Introduce the learning-manifest adapter.
- Enable story-derived vocabulary, flashcards, shadowing, comprehension, and games incrementally.
- Add private learner-state links to stable unit IDs.

### Phase E — Default and cleanup

- Enable V1 by default after production validation.
- Retain fallback for legacy public stories.
- Remove duplicated legacy client paths only through a separate approved cleanup plan.

### Phase F — Creation features

- Add remix lineage and inherited-asset resolution.
- Add creation from saved study material.
- Add on-device Apple Foundation Models routing for suitable private, bounded tasks, with availability and server fallback.

## Validation and testing

- Cross-platform fixture parity between Dart and Swift.
- Legacy story regression tests.
- Malformed/partial V1 fallback tests.
- Stable-ID behavior across republishing.
- Audio/timing alignment and chapter-track tests.
- Lazy download and offline-cache tests.
- Learning-manifest occurrence/range validation.
- Progress retention across inherited remix assets.
- Performance tests for large multi-chapter manifests.
- Privacy tests ensuring prompts and full payloads are not written to diagnostic logs.

## Open decisions

- Whether V1 manifests remain JSONB columns, move to Storage documents, or use a small row plus external manifests.
- Whether new manifest fields live directly on the SwiftData `Story` or in separate local models.
- Maximum inline payload size before chapter/manifests must be loaded independently.
- Exact token/range representation across Swift and Dart Unicode indexing.
- Rules for preserving IDs after manual edits, splitting, merging, and republishing.
- How published revisions migrate learner progress when semantic identity changes.
- Which study activities require precomputed builder data versus deterministic client derivation.
- Which private personalization tasks qualify for Apple on-device generation.

## First future implementation issue

**Decode the shared Published Story V1 dialogue fixture in Swift.**

Deliverables:

- approved shared schema reference;
- V1 Swift `Codable` contract types;
- one checked-in dialogue fixture with speaker-turn audio and clip-relative timings;
- decoding, validation, and round-trip tests;
- a legacy/V1 format-selection test;
- no production UI, synchronization, or database changes.

This issue should begin only after the Flutter publishing contract fixture is approved.
