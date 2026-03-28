# LearnCI Development Mandates

This file contains foundational mandates for Gemini CLI when working on the LearnCI project. These instructions take precedence over general defaults.

## Project Overview
**LearnCI** is an iOS language learning app built with Swift/SwiftUI, utilizing SwiftData for local persistence and Supabase for backend services (Auth, DB, Storage). It features AI-powered story and audio generation.

## Architectural Standards

### State Management
- **Managers:** All managers must use the `@Observable` macro (not `ObservableObject`).
- **Dependency Injection:** Managers are instantiated in `LearnCIApp.swift` and injected into the environment via `.environment(manager)`. Access them in views using `@Environment(Manager.self)`.
- **Singletons:** Avoid singletons for managers; prefer environment injection.

### Data Persistence & Sync
- **Local:** SwiftData is the source of truth for local user data.
- **Remote:** Supabase PostgreSQL.
- **DTOs:** Never pass SwiftData models directly to Supabase. Use Data Transfer Objects (DTOs) like `StoryDTO` or `PushStoryDTO` for synchronization via `SyncManager`.
- **Storage:** Use specific paths for Supabase Storage as defined in `CLAUDE.md` (e.g., `audio-stories/{userID}/{storyID}/...`).

### UI & Styling
- **SwiftUI:** Use modern SwiftUI patterns.
- **Formatting:** Adhere to standard Swift API Design Guidelines.
- **Components:** Reuse existing components in `LearnCI/Views/Components/`.

## Key Workflows

### Story Generation
1. GPT-4o-mini (Text) -> GPT-4 (Translation)
2. DALL-E 3 (Images)
3. OpenAI TTS/ElevenLabs (Audio)
4. Whisper (Timings)
5. Google Veo (Video - optional)
6. `SyncManager` (Upload/Sync)

### Game Sessions
- Follow the 7-stage flow documented in `Documentation/Game_Flow_Lifecycle.md`.
- Use `GameSessionViewModel` for state management.

## Python Scripts (`scripts/`)
- Used for AI generation pipelines.
- Requires `scripts/venv` and `scripts/.env`.
- Always verify asset completeness using `python3 check_media.py`.

## Testing & Validation
- **Xcode:** Primary testing via Xcode (⌘+U).
- **CLI:** `xcodebuild test -project LearnCI.xcodeproj -scheme LearnCI -destination 'platform=iOS Simulator,name=iPhone 16'`.
- **Asset Validation:** Always run `check_media.py` after modifying generation pipelines.
