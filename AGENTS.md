# AGENTS.md

This file provides system context and operational guidance for AI coding agents (Antigravity, Codex, Claude, Cursor, Windsurf) working in the **LearnCI** repository.

---

## 1. Agent OS Context Index & Standards

LearnCI follows the **Agent OS** standard for context management. Prior to undertaking non-trivial code modifications, review the domain standards listed in [agent-os/standards/index.yml](agent-os/standards/index.yml):

- 📱 [SwiftUI & State Management](agent-os/standards/ios-swiftui.md) — `@Observable` state, `LearnCIApp.swift` schema, `.environment()` injection.
- 💾 [Dual Persistence & Supabase Sync](agent-os/standards/data-sync.md) — SwiftData local model rules, Supabase PostgreSQL, DTO contracts (`PushStoryDTO`), Storage paths.
- 🎮 [Game Session Lifecycle & Specs](agent-os/standards/game-engine.md) — 7-stage game lifecycle, universal vs game-specific config, `GameSessionViewModel`.
- 🤖 [AI Content Generation Pipeline](agent-os/standards/ai-pipeline.md) — Python scripts in `scripts/`, OpenAI GPT/TTS, ElevenLabs dramatized audio, Whisper timestamps, Google Veo.
- 🛠️ [Build, CLI & Testing Standards](agent-os/standards/testing-build.md) — `xcodebuild` CLI flags, simulator destinations, and verification requirements.

---

## 2. Project Overview

**LearnCI** is an iOS language learning application built with Swift and SwiftUI. It features AI-generated stories with dramatized multi-voice audio, cinematic video, word-by-word synchronized highlighting, interactive reading/quiz sessions, and 7 vocabulary game types.

Backend services use **Supabase** (Authentication, PostgreSQL Database, Storage) alongside **OpenAI**, **ElevenLabs**, and **Google Veo** APIs.

### Production Database Operations

- Prefer the Supabase MCP tools for direct SQL and schema migrations when they are available.
- The Supabase CLI is also permitted when the user explicitly authorizes a production database operation.
- Before any CLI production write, verify the linked project ref is `vuygqrbludhuywupcbma`, inspect remote migration history, and dry-run migration pushes when supported.
- Apply only the migration or SQL explicitly in scope. Never repair, revert, reset, or broaden production migration history to bypass a mismatch without separate user approval.
- After applying a migration, verify the expected tables, policies, and recorded migration version.

---

## 3. Build & Verification Commands

This is an Xcode project — CLI build and test commands must be run from the repository root:

```bash
# Build iOS App via CLI
xcodebuild build -project LearnCI.xcodeproj -scheme LearnCI -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'

# Run Unit Tests via CLI
xcodebuild test -project LearnCI.xcodeproj -scheme LearnCI -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## 4. Key Architecture Patterns

- **`@Observable` Macro**: All managers use `@Observable` (never `@Published` / `ObservableObject`).
- **Environment Injection**: Managers are instantiated in `LearnCIApp.swift` and passed via `.environment()`.
- **DTO Separation**: Never pass SwiftData models directly to Supabase client APIs. Use `StoryDTO` (pull) and `PushStoryDTO` (push). `PushStoryDTO` intentionally excludes `remote_video_path`.
- **Game Session State**: 7-stage lifecycle (`GameConfigurationView` $\rightarrow$ `SessionOptionsSheet` $\rightarrow$ `PreGameSummaryView` $\rightarrow$ game view $\rightarrow$ `SessionFinishView`).

---

## 5. Cloud Agent Handoff Protocol

When completing a feature on a cloud agent branch, **always end your final response with a copy-paste git sync block** using the exact branch pushed:

```bash
git fetch origin
git checkout <branch-name>
git pull origin <branch-name>
```

Refer to [Documentation/guides/local-dev.md](Documentation/guides/local-dev.md) for the full local workflow guide.
