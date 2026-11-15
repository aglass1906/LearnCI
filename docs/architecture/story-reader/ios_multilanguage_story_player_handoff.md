# iOS Story Player — Multi-Language Architecture Handoff

**Audience:** Engineers working on the **LearnCI iOS app** story player multi-language JSON contract.

## Architecture Summary

The multi-target-language architecture provides per-language maps at scene and reading-matter page level, and grouped per-language envelopes at chapter level.

| Layer | Language-agnostic root | Per-language data |
|--------|------------------------|-------------------|
| **Story row** | `title`, `layout_json`, preferences | N/A — row represents one target language |
| **Chapter** | `chapter_number`, `plot_summary`, `scenes`, `chapter_cover_url` | `title`, `intro`, `vocabulary`, `comprehension` — each `{ "by_language": { "<code>": { … } } }` |
| **Scene** | `sceneIndex`, `contentMode`, `imageUrl`, `cropRegion` | `byLanguage[code]` → caption, script, audio, timings, dialogues |
| **Reading matter page** | `id`, `placement`, `kind` | `by_language[code]` → title, body, `structured_rows` |

## Required Swift Accessors

```swift
chapter.titleFor(targetCode)
chapter.bodyTextForLanguage(targetCode)
chapter.chapterIntroAudioUrlForLanguage(targetCode)
scene.captionFor(targetCode)
scene.scriptFor(targetCode)
scene.audioUrlForLanguage(targetCode)
page.titleFor(targetCode)
page.bodyFor(targetCode)
```
