# Story Builder Data Model

**Canonical contract** between the app and Supabase for `public.stories`, `public.story_pipeline`, and related JSON.

---

## Builder vs Player tables

| Table | Role |
| :--- | :--- |
| `public.story_pipeline` | **In-progress builder rows.** All pipeline stage JSON columns live here. The app reads and writes this table throughout production. |
| `public.stories` | **Published learner rows.** The FINAL stage copies the completed story here. The learner app and library read only this table. |

---

## 1. Central table: `public.stories`

| Column | Type | Origin / source | Description |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | Client | Primary key (RFC-4122 v4 at creation). |
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
| `generation_status` | `text` | Backend / UI | Pipeline phase status. |
| `last_error` | `text` | Backend | Last pipeline error message. |
| `preferences_json` | `jsonb` | `StoryPreferences` | Voice, art, length, quiz, ambient settings. |
| `bible_json` | `jsonb` | Generator | World, characters, locations. |
| `scene_breakdown_json` | `jsonb` | Generator | Scene breakdown. |
| `chapters` | `jsonb` | Generator | Final per-chapter listening content. |
| `reading_matter_pages_json` | `jsonb` | READ stage | N-page reading matter array. |
| `remote_audio_path` | `text` | Generation | Story-level audio path in storage. |
| `remote_cover_path` | `text` | Generation | Story cover image path. |
| `remote_video_path` | `text` | Generation | Background video path. |
| `comprehension_questions_json` | `jsonb` | Generation | MCQ set blob. |
| `ambient_sound_id` | `text` | UI | Key into `ambient_sounds`. |
