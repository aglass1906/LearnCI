# LearnCI — TODO / Backlog

Tracking document for open work items. Seeded from the July 2026 architecture review
(`Documentation/Architecture_Review_2026-07.md`); add new items at the appropriate
priority and check items off (with the PR/commit) when done.

Legend: 🔴 high · 🟡 medium · 🟢 nice-to-have

## Bugs

- [ ] 🔴 Offline story deletes can resurrect: add local tombstones replayed by
      `SyncManager.syncNow` (the remote delete added in the review is best-effort only).
- [ ] 🔴 `AuthManager.listenForAuthChanges` treats any nil-session event as sign-out;
      restrict to `.signedOut` / `.userDeleted` and re-check the session otherwise.
- [ ] 🟡 Two `AudioManager` instances can coexist (`.shared` + environment-injected);
      unify on the injected instance.
- [ ] 🟡 Audio interruptions (calls, Siri) pause file/stream playback but not
      `AVSpeechSynthesizer` TTS.
- [ ] 🟢 Non-smart grading discards "again" cards for the rest of the session
      (`GameSessionViewModel.handleGrade`); confirm intended or re-queue them.

## Missing functionality

- [ ] 🔴 Memory Match: enforce the session timer or hide the timer option
      (documented TODO in `MemoryGameView.swift`).
- [ ] 🟡 Memory Match: integrate `SmartSessionManager` so Smart Queue order works.
- [ ] 🟡 Delete story: also remove Supabase Storage assets (audio, chapter audio,
      cover) — only the DB row is deleted today.
- [ ] 🟡 Surface Google Sign-In failures to the user (currently only printed).

## Performance

- [ ] 🔴 Move deck discovery (`DataManager.internalDiscover`) off the main thread.
- [ ] 🟡 Remove `.id(setupStage)` from `GameView` (full hierarchy teardown per stage)
      and fix the underlying invalidation issue it masks.
- [ ] 🟡 Index decks by id after discovery so `findDeckMetadata(id:)` stops rescanning
      the whole bundle.
- [ ] 🟢 Replace fixed `asyncAfter` audio sequencing with an async playback queue.

## Architecture / hygiene

- [ ] 🔴 Split `StorySessionView.swift` (3.7k lines) and `AudioBookReaderView.swift`
      (2.4k lines) into subviews + view models.
- [ ] 🟡 Migrate 275 `print()` calls to `os.Logger` via `Logger.swift`; strip PII
      (emails, auth events) from logs.
- [ ] 🟡 Retire `SmartSessionManager.shared` / `GameFeedbackManager.shared` in favor of
      injected instances.
- [ ] 🟢 Move hardcoded Supabase URL/key from `AuthManager` into `AppConfig`/xcconfig.
- [ ] 🟢 Remove hardcoded developer paths (`/Users/alanglass/...`) from `DataManager`
      and `AudioManager` dev fallbacks.

## Usability

- [ ] 🟡 Persist full last-session config (duration, goal, navigation style) for
      quick-start, not just deck/game/preset.
- [ ] 🟡 Map common errors (offline, missing API key, quota) to friendly, actionable
      messages instead of `error.localizedDescription`.
- [ ] 🟢 Accessibility pass on the core play loop (VoiceOver labels for game tiles,
      Dynamic Type in badges).
