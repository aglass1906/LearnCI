# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**LearnCI** is an iOS language learning app built with Swift/SwiftUI. It features AI-powered story generation with dramatized audio, cinematic visuals, interactive reading/quiz sessions, and 7 vocabulary game types. Backend is Supabase (auth, database, storage) with OpenAI/ElevenLabs for AI generation.

## Build & Run

This is an Xcode project — primary development is done through Xcode.

```bash
# Build from CLI
xcodebuild build -project LearnCI.xcodeproj -scheme LearnCI -configuration Debug

# Archive for release
xcodebuild archive -project LearnCI.xcodeproj -scheme LearnCI -archivePath build/LearnCI.xcarchive
```

Run tests via Xcode (⌘+U) or:
```bash
xcodebuild test -project LearnCI.xcodeproj -scheme LearnCI -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Python Scripts

Located in `scripts/`. Used for AI generation pipelines (run independently of the iOS app):

```bash
cd scripts
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

python3 generate_audio.py        # TTS via OpenAI / ElevenLabs
python3 generate_images.py       # Cover art via DALL-E 3
python3 generate_video.py        # Video via Google Veo
python3 generate_ambient_sounds.py
python3 check_media.py           # Verify asset completeness
```

Requires `scripts/.env` with `OPENAI_API_KEY`, `ELEVENLABS_API_KEY`, `SUPABASE_URL`, `SUPABASE_KEY`, `GEMINI_API_KEY`.

## Architecture

### App Entry & Environment Injection

`LearnCIApp.swift` is the entry point. All managers are instantiated here and injected via `.environment()` — this is how Views access shared state (not singletons).

```swift
// SwiftData schema registered here:
Schema([UserActivity, UserProfile, DailyFeedback, CoachingCheckIn, Favorite, Story, PodcastShow, PodcastEpisode])
```

### Manager Layer (Orchestration)

All managers use `@Observable`. Key managers and their responsibilities:

| Manager | Role |
|---|---|
| `AuthManager` | Google SignIn + Supabase JWT session management |
| `SyncManager` | Bidirectional sync between SwiftData and Supabase DB |
| `StoryManager` | End-to-end story generation pipeline |
| `OpenAIService` | GPT text gen, TTS, DALL-E images, Whisper timings |
| `DataManager` | Card deck loading, caching, virtual deck creation |
| `AudioManager` | Playback queue, audio session management |
| `AmbientSoundManager` | Ambient loop fetching from Supabase Storage |

### Data Persistence: Two-Layer Strategy

- **SwiftData** (local): All models listed in `LearnCIApp.swift` schema. Source of truth for local user data.
- **Supabase PostgreSQL** (remote): `SyncManager` syncs up/down. Uses `StoryDTO` (pull) vs `PushStoryDTO` (push) — the push DTO intentionally omits `remote_video_path` so the server remains the authority for video paths.

### Supabase Storage Paths

```
audio-stories/{userID}/{storyID}/audio.m4a
audio-stories/{userID}/{storyID}/chapter_{n}.m4a   # chapter audio
story-covers/{userID}/{storyID}/cover.jpg
story-videos/{userID}/{storyID}/video.mp4
```

### Story Generation Pipeline (StoryManager)

1. GPT-4o-mini → story text (target language)
2. GPT-4 → English translation
3. DALL-E 3 → cover art
4. OpenAI TTS (single voice) or ElevenLabs (dramatized, multi-voice with speaker tags)
5. Whisper API → word-level timings for synchronized highlighting
6. Google Veo → cinematic video (optional)
7. `SyncManager` → upload assets to Supabase Storage, upsert DB record

### Game Session Flow (7 Stages)

Documented in `Documentation/Game_Flow_Lifecycle.md`. Entry: `GameConfigurationView` → `SessionOptionsSheet` → game-specific config → `PreGameSummaryView` → game view → `SessionFinishView`. State is managed by `GameSessionViewModel` (and game-specific ViewModels for Memory, WordRain, Linker, WordCrush).

### Environment Config

`AppConfig.swift` provides `webPortalBaseURL`:
- Debug: `http://localhost:3000`
- Release: `https://learn-ci-web.vercel.app`

## Key Patterns

- **`@Observable`** for all managers (not `ObservableObject`/`@Published`)
- **DTOs for sync**: Never pass SwiftData models directly to Supabase — use `StoryDTO`/`PushStoryDTO`
- **Virtual decks**: `DataManager.createVirtualDeck()` filters cards by tag without creating a DB record
- **Chapter audio**: Stored as `StoryChapter` objects within a `Story`; chapters have their own remote audio paths

## Supabase MCP

`.mcp.json` configures Supabase MCP server for direct DB access from Claude Code. Use `mcp__supabase__execute_sql` for queries and `mcp__supabase__apply_migration` for schema changes.

## Cloud Agent Handoff

When a cloud agent finishes a feature, **always end the summary with a copy-paste git sync block** so the user can pull the work locally. Use the exact branch name that was pushed:

```bash
git fetch origin
git checkout <branch-name>
git pull origin <branch-name>
```

Include the PR link when one was created. See `docs/local-dev.md` for the full local workflow.
