# Dual Persistence & Supabase Sync Standard

**Scope:** Local SwiftData persistence, remote Supabase PostgreSQL database, and Supabase Storage asset management.

---

## 1. Two-Layer Persistence Architecture

- **Local Layer (SwiftData)**: Acts as the local source of truth for user activity, offline playback, and local UI state.
- **Remote Layer (Supabase PostgreSQL)**: Stores synchronized user state, story catalogs, and media references.
- **Sync Orchestrator (`SyncManager`)**: Handles bidirectional synchronization between SwiftData and Supabase.

---

## 2. DTO Sync Contracts (Crucial Safety Rule)

- **NEVER** pass SwiftData models directly to Supabase client calls.
- **Always use explicit DTOs** for network payloads:
  - `StoryDTO`: Used for pulling story records from Supabase into local SwiftData models.
  - `PushStoryDTO`: Used for pushing local story edits up to Supabase.

> [!IMPORTANT]
> `PushStoryDTO` MUST intentionally omit `remote_video_path` to ensure the server remains the sole authority for video paths generated via server/python background tasks.

---

## 3. Supabase Storage Path Conventions

All media uploaded or fetched from Supabase Storage must adhere strictly to these URI formats:

```text
audio-stories/{userID}/{storyID}/audio.m4a           # Full story audio
audio-stories/{userID}/{storyID}/chapter_{n}.m4a      # Chapter-specific audio
story-covers/{userID}/{storyID}/cover.jpg            # Cover art image
story-videos/{userID}/{storyID}/video.mp4            # Cinematic video
```

---

## 4. Supabase Project Credentials & Config

- **Project Ref**: `vuygqrbludhuywupcbma`
- **API URL**: `https://vuygqrbludhuywupcbma.supabase.co`
- **Database Migrations**: Located in `supabase/migrations/`
- Direct SQL execution and schema migrations during automated agent tasks must use Supabase MCP tools (`mcp__supabase__execute_sql` / `mcp__supabase__apply_migration`).
