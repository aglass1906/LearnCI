# LearnCI Client Architecture Review — July 2026

Scope: the iOS client (Swift/SwiftUI, 208 source files, ~60k lines), reviewed against
`Documentation/Game_Flow_Lifecycle.md`, `docs/game_specifications.md`, and `CLAUDE.md`.
Focus areas: correctness bugs, performance, missing functionality, and usability.

Fixes applied in this review are on branch `claude/language-app-architecture-review-th6pa9`
and marked **[FIXED]**. Everything else is a recommendation.

---

## 1. Architecture Assessment

### What works well

- **Clean manager layer.** `@Observable` managers injected via `.environment()` from
  `LearnCIApp` (no singleton soup at the view layer). Responsibilities are mostly
  well-separated: auth, sync, data, audio, story generation.
- **Two-layer persistence with DTO discipline.** SwiftData locally, Supabase remotely,
  with `StoryDTO` (pull) / `PushStoryDTO` (push) keeping the server authoritative for
  video paths. `runSyncStep` with `allowMissingTable` / `continueOnError` makes the
  sync pipeline resilient to partial backend rollout.
- **Documented game flow.** The 7-stage lifecycle in `Game_Flow_Lifecycle.md` matches
  the code (`GameView.GameSetupStage`), and `GameSessionViewModel` cleanly owns runtime
  session state.

### Structural risks

- **View files are far too large.** `StorySessionView.swift` (3,729 lines),
  `AudioBookReaderView.swift` (2,435), `PictureBookReaderView.swift` (1,781),
  `PodcastPlayerView.swift` (1,645). These should be decomposed into subviews +
  view models; they are where regressions will hide.
- **Singletons undercut the DI story.** `SmartSessionManager.shared`,
  `AudioManager.shared` (an instance is *also* injected via environment — two
  potential instances), `GameFeedbackManager.shared`, `LevelManager.shared`. The code
  itself acknowledges this (comment in `GameSessionViewModel`). Pick one pattern.
- **`AudioManager` does four jobs**: file playback, TTS, ambient loops, and AVPlayer
  streaming (950 lines). Splitting streaming (podcasts) from card audio would remove
  the classes of bug where `stopAudio()` kills a podcast stream.
- **275 `print()` calls** ship in release builds, some logging user emails and auth
  events (`AuthManager`, `SyncManager`). There is a `Logger.swift` — migrate to it
  (os.Logger) and gate debug logs behind `#if DEBUG`.
- **Hardcoded developer paths** (`/Users/alanglass/...`) in `DataManager` and
  `AudioManager` dev fallbacks, and a hardcoded Supabase URL/key in `AuthManager`
  (publishable key, so not a secret — but it belongs in `AppConfig`/xcconfig alongside
  `webPortalBaseURL`).

---

## 2. Bugs

### [FIXED] Deleted stories resurrect on the next sync
`SyncManager.pullStories` treats the server catalog as the source of truth: it deletes
local stories missing from the server **and re-inserts server stories missing locally**.
`StoryManager.deleteStory` only deleted the local row, so every user-deleted story came
back on the next sync. Added `SyncManager.deleteRemoteStory(id:)` and wired it into
`StoryListView.deleteStories`.
*Remaining gap:* the remote delete is best-effort — if the device is offline at delete
time the story will still resurrect. A proper fix needs local tombstones replayed by
`syncNow`. Storage assets (audio/cover objects in the `audio-stories` bucket) are also
not removed; consider a server-side cleanup job or cascade.

### [FIXED] Story deletion not explicitly persisted
`deleteStory` relied on SwiftData autosave after `context.delete`. Now saves explicitly
and logs failures.

### [FIXED] Smart Queue session started twice per game
`GameSessionViewModel.prepareSessionCards` called `SmartSessionManager.startSession`
itself, then both callers (`startSession`, `handleDeckLoaded`) called it again with the
returned queue — resetting `masteredCards` and doing duplicate work. The caller-side
block is now the single owner.

### [FIXED] `AudioManager.playAudio(named:)` ignored `voiceGender` in its
"already playing" check, so re-requesting the same clip with a different voice was
silently dropped.

### [FIXED] Duplicate `.animation` modifier in `LearnCIApp`.

### Open bugs (not fixed — need a decision or deeper testing)

1. **`AuthManager.listenForAuthChanges`** signs the user out (`state = .unauthenticated`)
   for *any* event with a nil session other than `passwordRecovery`. If the Supabase SDK
   ever emits a transient nil-session event (e.g. a failed token refresh that later
   succeeds), the user is bounced to the login screen. Recommend only treating
   `.signedOut` / `.userDeleted` as sign-outs and re-checking the session otherwise.
2. **Two `AudioManager` instances can exist** (the `.shared` singleton and the
   environment-injected instance from `LearnCIApp`). Any code path using
   `AudioManager.shared` bypasses the instance the UI observes.
3. **Audio interruptions don't pause TTS.** `handleAudioInterruption` pauses the file
   player and stream but not `AVSpeechSynthesizer`, so a phone call can overlap TTS
   on resume.
4. **`GameView` non-smart grading discards "again" cards.** In non-smart order,
   `handleGrade` removes the card from `sessionCards` regardless of grade, so a card
   graded "again" never returns in that session. If intentional, document it; users
   expecting Anki-like behavior will be surprised.

---

## 3. Performance

### [FIXED] ~1.4s of artificial launch delay
`LearnCIApp.performInitialization` did no real work but slept 1.3–1.8s across four fake
"loading" stages, stacked in front of ContentView's real loading states (auth check,
"Preparing your learning space…"). Reduced to a single short transition.

### [FIXED] Blocking full sync on every warm launch
`ContentView.prepareAuthenticatedUser` awaited a complete `syncNow` (a dozen network
round-trips) before showing the app, even for returning users with a local profile.
Returning users now enter immediately; the sync runs in the background. First-run users
still sync first so an existing server profile isn't clobbered.

### [FIXED] Tag/virtual-deck scans re-decoded every deck JSON on every call
`discoverTags`, `createVirtualDeck`, and `fetchWordOfDay` read and decoded every deck
file from disk on each invocation (called from the tag-selection UI on the main thread),
ignoring the existing `deckCache`. Added a cache-aware `loadDeckCached` helper (which,
unlike `loadDeck(from:)`, doesn't clobber the UI-facing `loadedDeck`).

### [FIXED] Missing files triggered a full recursive bundle scan on every lookup
`DataManager.resolveURL` and `AudioManager.resolveAudioURL` cached only successful
lookups. Cards without audio files (the normal case when TTS fallback is used) caused a
recursive enumeration of the entire app bundle *per card, per play*. Negative results
are now cached.

### Remaining performance recommendations

- **Deck discovery runs on the calling thread.** `internalDiscover` enumerates the whole
  bundle and peeks every JSON synchronously — usually from `GameView.handleAppear` on the
  main thread. Move discovery to a background task and publish results back.
- **`GameView` uses `.id(setupStage)`** which tears down and rebuilds the entire stage
  view hierarchy on every stage change. It's masking an invalidation problem; removing it
  (and fixing whatever it papered over) would smooth stage transitions.
- **`findDeckMetadata(id:)` rescans everything** with nil filters to find one deck.
  Index decks by id after the first discovery.
- **Sequence audio uses fixed 0.5s `asyncAfter` gaps** and card audio is triggered via
  scattered `DispatchQueue.main.asyncAfter` delays (58 usages app-wide). Consider a
  small async/await playback queue; timing-by-delay is fragile under load.

---

## 4. Missing Functionality

1. **Memory Match ignores the session timer** (documented TODO in `MemoryGameView`).
   Stage-2 configuration lets the user set a 1–60 minute limit that this game never
   enforces. Either enforce it or hide the timer option for Memory Match.
2. **Memory Match doesn't integrate SmartSessionManager** (TODO) — smart-queue order
   silently behaves as random for this game.
3. **Offline delete queue** — see the story-resurrection fix above; deletes (stories,
   favorites) performed offline are lost. Tombstones + replay in `syncNow` would close it.
4. **No remote-storage cleanup on story delete** — DB row is now deleted, but audio,
   chapter audio, and cover objects remain in Supabase Storage forever.
5. **Google Sign-In error surface** — `signInWithGoogle` failures only `print`; the user
   gets no feedback. Route errors into an observable `errorMessage` like email auth does.

---

## 5. Usability

- **[FIXED] Launch feel**: fake splash delays + blocking sync gave three consecutive
  loading screens ("Initializing…" → "Checking session…" → "Preparing your learning
  space…") before content. Cold path is now one short splash; warm path enters the app
  immediately.
- **Setup flow depth**: reaching gameplay takes up to 5 screens (game → deck → session →
  game config → summary). "Play Now" quick-start exists — good — but consider persisting
  the *entire* last session config as the quick-start default (currently deck, game type,
  and preset are restored, but duration/goal/navigation revert per launch unless stored
  in the profile).
- **Error messaging**: most failures (deck load, sync, story generation) surface raw
  `error.localizedDescription` or just a `print`. Users can't act on
  "The data couldn't be read". Map common failures (offline, missing API key, quota) to
  friendly, actionable copy.
- **Accessibility**: outside a handful of `accessibilityLabel`s, the game views (Memory
  tiles, Word Rain, timers) have no VoiceOver support, and fixed font sizes in badges
  won't scale with Dynamic Type. Worth an a11y pass on the core play loop.
- **`GameView` session summary shows a "Back" toolbar button during setup but the
  hardware/system back gesture is unavailable inside the `NavigationStack`** because
  stages are a state switch, not pushed destinations. Consider `navigationDestination`
  or at least consistent swipe-back behavior.

---

## 6. Suggested Next Steps (priority order)

1. Tombstone-based offline deletes + Supabase Storage cleanup (finishes the resurrection fix).
2. Background deck discovery + remove `.id(setupStage)` from `GameView`.
3. Split `StorySessionView` / `AudioBookReaderView` into components with view models.
4. Replace `print` with `os.Logger`; strip PII from logs.
5. Unify on injected managers (retire `.shared` where an instance is injected).
6. Memory Match timer + smart-queue support.
7. Accessibility pass on the play loop.
