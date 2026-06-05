# Controlled Study Mode (iOS, YouTube first)

> Saved from implementation plan — June 2026. Adapter rollout: YouTube → Stories → Podcasts → Generic media URL.

## Goal

Extend iOS study mode into a **controlled, block-by-block learning experience**:

- Show one study text block at a time
- Play only the current block (or loop at native speed)
- Prev / next block navigation
- Timeline notes and marked words
- Multi-block / multi-minute study sessions

Built on a content-agnostic `StudyBlock` layer shared across all media types.

## Architecture

### Core types

- **`StudyBlock`** — timed text unit (`targetText`, `nativeText`, `mediaStart`, `mediaEnd`)
- **`StudyResourceRef`** — stable identity (`type`, `resourceId`, `consumptionUrl`, `title`)
- **`StudyBlockSource`** — adapter protocol (blocks + media player)
- **`StudyMediaPlayer`** — seek/play/pause/rate abstraction
- **`TranscriptProvider`** — caption / authored / Whisper block producers
- **`StudySessionViewModel`** — block index, session range, notes/mark actions
- **`StudyPlaybackController`** — BlockOnce, BlockLoop, boundary watcher

### Adapter rollout

| Phase | Adapter | Blocks from | Player |
|---|---|---|---|
| 1 | `YouTubeStudyBlockSource` | 1 caption cue = 1 block | YouTube iframe bridge |
| 3 | `StoryStudyBlockSource` | Script segments / scenes | AudioManager |
| 4 | `PodcastStudyBlockSource` | Whisper on episode audio | AVPlayer |
| 5 | `GenericMediaStudyBlockSource` | Whisper on any URL | AVPlayer |

### UI shell

`StudySessionShell` — shared layout (player slot + `StudyBlockFocusView` + `StudyTransportBar`).

Hosts: `VideoDetailSheet` (Phase 1), `StoryAboutView` (3), `PodcastPlayerView` (4), Favorites (5).

### Persistence (SwiftData)

- `StudySessionRecord` — session progress
- `StudyNote` — anchored to block + media time
- `MarkedStudyWord` — saved vocabulary
- `MediaTranscriptCache` — Whisper transcripts (podcasts + URLs)

## Phased delivery

1. **Block control** — YouTube adapter, playback controller, focus UI, transport
2. **Session + artifacts** — setup sheet, notes, marked words
3. **Stories** — `StoryStudyBlockSource`
4. **Podcasts** — Whisper + `PodcastStudyBlockSource`
5. **Generic URL** — favorites / resource library
6. **Review** — SRS queue across all resource types

See full design diagrams and file list in project planning docs.
