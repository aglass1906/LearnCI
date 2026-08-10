# Dialog Story Player — Design Spec

## Overview

The dialog story player uses a **two-layer flow** on iOS (`DialogStoryFlowView` + `DialogSessionView`):

1. **Spine wrapper** — full-screen steps for cover, front/back reading matter, and chapter intros (before/after/between chapters).
2. **Dialogue feed** — tap-to-reveal chat bubbles for scene dialogue only (`DialogSessionView`, one chapter at a time).

Each character's line appears as a positioned speech bubble with a portrait avatar and optional audio. Dialogue progression is driven by `_visibleCount` / `visibleCount`, which controls how many bubble items are rendered at any given time.

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
