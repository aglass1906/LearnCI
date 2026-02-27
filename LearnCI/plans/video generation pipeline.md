# Video Generation Pipeline

Two separate pipelines generate videos — the iOS app (on-device, deferred sync) and the Python CLI script (desktop, direct upload).

Both write to the **`story_videos`** Supabase Storage bucket. `remote_video_path` always stores a **relative storage path** (not a full URL). Public URLs are derived at display time via `getPublicUrl()`.

---

## App-Generated Video Flow

| Step | Code | Detail |
|---|---|---|
| 1. Select style | `StorySessionView` → style picker UI | User picks from `VideoStyle` enum (Pixar 3D, Ghibli, etc.) |
| 2. Generate LLM prompt | `VeoService.generateVeoPrompt()` or `OpenAIService.generateVeoPrompt()` | Uses Gemini 2.5 Pro or GPT-4o; model chosen in Profile → AI Settings |
| 3. Save prompt + style | `story.videoStyle`, `story.videoGenPrompt` | Persisted immediately so they sync even if generation fails |
| 4. Call Veo API | `VeoService.generateVideo()` | Submits to Veo 3.1 preview, polls until done (up to 6 min) |
| 5. Save locally | `docs/video_{UUID}.mp4` | Written to app's Documents directory; `remoteVideoPath` stays `nil` |
| 6. Display immediately | `HeroMediaView.loadMedia()` | **If `remoteVideoPath` is nil**: local generated file shown as looping hero video |
| 7. Sync upload | `SyncManager.syncStories()` | On next sync, finds `video_{UUID}.mp4` + `remoteVideoPath == nil` → uploads |
| 8. Correct bucket | `supabase.storage.from("story_videos")` | ✅ |
| 9. Standard path | `{storyID}/{timestamp}_{styleSlug}.mp4` | e.g. `78d4906b.../1740614448_pixar_3d.mp4` |
| 10. Store path | `story.remoteVideoPath = remotePath` | Relative path saved to local model + pushed to DB in next metadata upsert |
| 11. After sync | `HeroMediaView.loadMedia()` | `remoteVideoPath` now set → downloads to `video_{UUID}_remote.mp4` and shows that instead |
| 12. Other devices | `HeroMediaView.loadMedia()` | No local file → derives URL from `supabaseVideoBase + remotePath` → downloads + caches to `_remote.mp4` |
| 13. New video uploaded | `SyncManager.pullStories()` | Server `remoteVideoPath` changes → old `_remote.mp4` deleted → fresh download on next open |

**Key files:** `StorySessionView.swift` · `SyncManager.swift` · `HeroMediaView` (in `StorySessionView.swift`)

---

## Script-Generated Video Flow (`generate_video.py`)

| Step | Code | Detail |
|---|---|---|
| 1. Select story | `list_stories()` → `get_story_details()` | Fetches from `stories` table (newest 50); user picks by number |
| 2. Select action | `input("[1] Generate / [2] Resume")` | Option 2 resumes a long-running job by its Operation Name (Job ID) |
| 3. Select style | `STYLES` dict | 9 options: Pixar 3D, Ghibli, Cinematic, Tim Burton, Watercolor, Claymation, 1930s Cartoon, Oil Painting, Line Drawing |
| 4. Derive path | `{storyID}/{timestamp}_{styleSlug}.mp4` | Style name normalized to snake_case for filename |
| 5. Generate LLM prompt | `generate_prompt()` | Gemini 2.5 Pro with cinematographer system prompt; uses story title + full text |
| 6. Save prompt + style to DB | `supabase.table("stories").update(...)` | Saves `video_gen_prompt` + `video_style` immediately (before video generation starts) |
| 7. Confirm + submit | `generate_veo_video()` | User confirms API credit spend; submits to `veo-3.1-generate-preview` at 16:9 |
| 8. Poll for completion | `operations.get()` loop, 10s intervals | Max 90 min; prints `.` per poll; user can extend if limit hit |
| 9. Download video | `gemini_client.files.download()` | Downloads bytes from Gemini Files API |
| 10. Save locally | `LearnCI/Resources/Video/{timestamp}_{style}.mp4` | Saved to repo's Resources/Video directory |
| 11. Upload to storage | `supabase.storage.from_("story_videos").upload()` | Bucket: `story_videos` · Path: `{storyID}/{timestamp}_{styleSlug}.mp4` |
| 12. Store path in DB | `supabase.table("stories").update({"remote_video_path": storage_path})` | Relative path only — **not** the public URL |
| 13. Print public URL | `get_public_url(storage_path)` | Printed to console for convenience; not stored |

**Key files:** `scripts/generate_video.py`

---

## AI Prompting Strategy

Before calling Veo, an LLM converts the story text into a cinematic visual prompt. Both the app and the script follow the same pattern but use slightly different system instructions.

### iOS App (`VeoService.generateVeoPrompt()`)

**Model:** Gemini 2.0 Flash (always uses Google API key) or OpenAI GPT-4o-mini (user preference)

**System instruction:**
> "You write short cinematic video prompts for AI video generation. Focus on setting, lighting, camera angle, and atmosphere. No dialogue, no text overlays, no abstract concepts. 1–2 sentences maximum."

**User message:**
> "Write a cinematic video prompt in this visual style: `{promptStyle}`. Based on this story excerpt: `{first 500 chars of story text}`"

### Python Script (`generate_prompt()`)

**Model:** Gemini 2.5 Pro

**System instruction:**
> "You are an expert film director and cinematographer. Read the following story title and excerpt and write a highly detailed, 1-2 sentence visual prompt for an AI video generator. The prompt MUST capture the core essence and main setting of the story. Describe the main character's action, setting, lighting, camera angle, and movement. Do not include dialogue. Ensure the style matches a `{style_description}`."

**User message:**
> `Story Title: {title}` + `Story Excerpt: {full story text}` + `"Write the visual prompt:"`

### Key differences
| | iOS App | Python Script |
|---|---|---|
| LLM model | Gemini Flash / GPT-4o-mini | Gemini 2.5 Pro |
| Story context | First 500 characters | Full story text |
| Prompt detail | 1–2 sentences, brevity-focused | Highly detailed, cinematographer framing |

---

## Video Styles

All 9 styles are available in both the iOS app and the Python script. The `rawValue` / style name and the prompt description are kept in sync.

| # | Style Name | `promptStyle` sent to Veo |
|---|---|---|
| 1 | **Photorealistic Cinematic** | hyper-detailed, photorealistic cinematic grade shot on a 35mm lens |
| 2 | **Pixar 3D** | highly detailed, expressive, and colorful Pixar 3D animation aesthetic |
| 3 | **Studio Ghibli 2D Anime** | highly atmospheric, hand-drawn 2D Studio Ghibli anime aesthetic |
| 4 | **Tim Burton Stop-Motion** | moody, atmospheric, stylized, highly detailed Tim Burton stop-motion aesthetic |
| 5 | **Watercolor Storybook** | soft, gentle, hand-painted watercolor illustration aesthetic, like a classic children's book brought to life |
| 6 | **Claymation** | highly tactile, physical claymation stop-motion aesthetic, with visible textures, fingerprints, and studio lighting |
| 7 | **Vintage 1930s Cartoon** | classic 1930s rubber-hose cartoon animation aesthetic, expressive bouncy movements, vintage film grain |
| 8 | **Living Oil Painting** | living, breathing oil painting aesthetic, thick textured brushstrokes, vibrant colors, classical art style |
| 9 | **Simple Line Drawing** | minimalist hand-drawn aesthetic, caricature style with simple distinct black lines on textured white paper |

**Key files:** `VeoService.swift` (`VideoStyle` enum) · `generate_video.py` (`STYLES` dict)

---

## Storage Convention

| Field | Value |
|---|---|
| **Bucket** | `story_videos` |
| **Path format** | `{storyID}/{timestamp}_{styleSlug}.mp4` |
| **DB field** | `stories.remote_video_path` = relative path |
| **URL derivation** | `getPublicUrl(path)` at display time |
| **Legacy fallback** | If `remote_video_path` starts with `https://`, used as-is |

---

## How the Video is Shown to the User

### Entry Point: `StorySessionView`

When a user opens a story, the top 300pt of the screen is the **hero media area** — a full-bleed parallax region that shows either the looping video or the cover image.

```
┌─────────────────────────────────┐
│  HeroMediaView (300pt tall)     │  ← looping video or cover image
│  [gradient overlay]             │
│  [Generate Video] button        │  ← shown if no video yet
└─────────────────────────────────┘
│  Story title                    │
│  Language · Level               │
│  Story text (word-highlighted)  │
│  ...                            │
└─────────────────────────────────┘
[Audio play bar — sticky bottom]
```

### `HeroMediaView` Decision Logic

| Priority | Condition | What's Shown |
|---|---|---|
| 1st | `remoteVideoPath` is set + `_remote.mp4` cached locally | Cached remote video (looping, muted) |
| 2nd | `remoteVideoPath` is set + no local cache | Downloads `_remote.mp4` in background; shows cover image meanwhile |
| 3rd | `remoteVideoPath` is nil + `video_{UUID}.mp4` exists | Locally generated video (looping, muted) |
| 4th | No video at all | Cover art image (downloaded from `audio-stories` bucket) |

### `LoopingVideoPlayerView`

Wraps `AVPlayer` with these characteristics:
- **Muted** — ambient visual only, no audio conflict with the story narration
- **Loops indefinitely** — `AVPlayerItemDidPlayToEndTime` → seek to zero + play
- **Aspect fill** — fills the 300pt hero frame; `resizeAspectFill` + parallax clip
- **Pauses on disappear** — when the user navigates away, playback stops

**Key files:** `VideoGeneratorSheet.swift` (contains `LoopingVideoPlayerView`) · `StorySessionView.swift` (`HeroMediaView`)

### Generating a Video from the Story Screen

Users can trigger generation from two places:
1. **Hero area** — "Generate Video" button overlay (shown when no video exists)
2. **Overflow menu (···)** — "Generate Scene Video" / "Regenerate Scene Video"

Both open `VideoGeneratorSheet`, which:
- Checks for a Google API key (`VeoService.hasKey()`)
- If no key → explains setup (Profile → AI Settings → Google API Key)
- If key present → shows 9 style options + cost warning (~$0.35–$0.70 / 8s clip, charged to Google Cloud)
- On confirm → calls `generateSceneVideo(style:)` in `StorySessionView`
- While generating → hero area shows an animated progress overlay with live status message