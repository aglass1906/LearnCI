# LearnCI CarPlay Implementation Plan

## Product Goal

Add an audio-first CarPlay experience for narrated LearnCI stories and podcasts. The CarPlay UI must remain deliberately simpler than the phone app and support listening without exposing reading, games, quizzes, video, content generation, or account management.

Until Apple approves the managed CarPlay audio entitlement, implementation will prioritize shared playback improvements that deliver immediate value in the regular iPhone app, on the lock screen, through Bluetooth and headphones, and over AirPlay. Further CarPlay-only interface work is gated on approval.

## Current Decision and Approval Gate

The initial CarPlay vertical slice is complete and remains isolated under `LearnCI/CarPlay`. It proves scene setup, catalog loading, selection, queue playback, and Now Playing integration.

While the entitlement request is pending:

- Continue work on shared playback, queues, resume behavior, metadata, offline media, and recovery.
- Validate all shared behavior through the phone UI, lock screen, Bluetooth, headphones, and AirPlay.
- Do not add more CarPlay tabs, CarPlay-only artwork behavior, vehicle-specific navigation, release screenshots, or signing entitlements.

After approval:

- Add `com.apple.developer.carplay-audio` through Xcode's managed capability workflow.
- Test the existing vertical slice in the CarPlay Simulator.
- Resume CarPlay-specific browsing, chapter navigation, vehicle testing, and release preparation.

## Implementation Status

Completed entitlement-independent foundation:

- One shared `AudioManager` across SwiftUI and external playback entry points.
- Persistent generic playback queue with play, next, previous, reorder, remove, clear, and retry operations.
- Phone-facing Listening Queue screen.
- Phone-facing Continue Listening screen backed by existing story and podcast progress.
- Podcast-show queue preparation in the standard podcast player.
- Cached and resized Now Playing artwork for queued media.
- Shared offline download storage for queued stories and podcasts, with validation and deletion.
- Local-download preference during playback.
- Safe pause when an active audio output is disconnected.
- Audio-session recovery after media-services resets.
- Retry presentation for playback failures.
- Timed podcast sessions now publish their episode list to the shared queue while retaining ownership of session timing and completion.
- Lock-screen, Bluetooth, and Listening Queue next/previous requests are routed back through the active timed session.
- Timed-session queue changes save outgoing episode progress and synchronize the visible episode.
- Continuous story playback now publishes individual story audio clips to the controlled shared queue.
- Story next/previous and Listening Queue selections route back through `AudioBookReaderView`, preserving chapter, scene, and resume state.
- Story and podcast player screens now provide direct download controls.
- Podcast progress is persisted periodically and whenever the app backgrounds.
- Download management now includes storage totals, validation, per-item removal, and bulk cleanup.
- Persisted queue entries are re-resolved from current SwiftData stories, story clips, and podcast episodes at launch.
- Automated tests cover Continue Listening eligibility, controlled navigation, queue persistence, and invalid download cleanup.

Still appropriate for later iteration and device QA:

- Validate resume, interruption, Bluetooth, AirPlay, and download behavior on physical devices.

## MVP Navigation

- **Listen Now:** recent playable stories and resumable podcast episodes.
- **Stories:** generated stories that have local or remote audio.
- **Podcasts:** saved podcast episodes with playable feed URLs.
- **Now Playing:** system playback controls, 10-second seeking, queue navigation, and playback metadata.

Favorites, downloads, story chapter browsing, Siri/App Intents, and voice exercises follow after the vertical slice is reliable.

## Phase 1: Shared Playback Foundation

- Use one `AudioManager.shared` instance in both the SwiftUI environment and non-SwiftUI entry points.
- Introduce a generic CarPlay media item and playback queue.
- Connect next/previous remote commands to the queue.
- Keep Now Playing title, subtitle, duration, progress, rate, and artwork synchronized.
- Verify interruptions, background playback, route changes, and reconnects.

### Acceptance Criteria

- Phone, lock screen, Bluetooth, and CarPlay control the same player.
- Remote command handlers are registered only once.
- Selecting another item replaces the current queue predictably.
- Playback continues when the phone UI backgrounds.

## Phase 2: CarPlay Catalog

- Fetch stories and podcast episodes from the existing SwiftData container.
- Convert models into immutable, identifier-based CarPlay entries.
- Resolve local story audio before falling back to public Supabase audio.
- Exclude records without a valid playable URL.
- Sort recent content deterministically and keep the initial catalog small.

### Acceptance Criteria

- Catalog access does not depend on a SwiftUI view being visible.
- Missing and deleted media fail gracefully.
- Local content remains usable without a network connection.
- Empty collections display a useful CarPlay-safe message.

## Phase 3: CarPlay Scene and Templates

- Register a `CPTemplateApplicationScene` through the application delegate.
- Add a scene delegate that retains its `CPInterfaceController`.
- Build Listen Now, Stories, and Podcasts using Apple-provided list and tab templates.
- Route playable selections to the shared playback coordinator.
- Present `CPNowPlayingTemplate` only after a valid item is selected.

### Acceptance Criteria

- The CarPlay scene connects and disconnects without affecting the phone scene.
- Navigation is shallow and contains only driving-safe actions.
- Loading, empty, and unavailable states are visible.
- Both touch and rotary selection work.

## Active Phase 4: Entitlement-Independent Playback Improvements

### 4.1 Unified In-App Queue

- Expose the generic playable-media queue to the regular phone UI.
- Add a queue view showing the current item and upcoming items.
- Support next, previous, remove-from-queue, reorder, and clear actions.
- Define predictable queue-building rules for stories, chapters, podcast shows, favorites, and recent content.
- Ensure starting playback from any phone screen replaces or extends the queue intentionally.

### 4.2 Continue Listening and Resume Persistence

- Persist playback position for podcast episodes and stories.
- Save progress periodically, when pausing, when changing items, and when the app backgrounds.
- Restore progress across app launches and playback routes.
- Add a unified Continue Listening section to the phone UI.
- Define completion thresholds that remove finished items from Continue Listening.

### 4.3 Now Playing and Remote Controls

- Publish reliable title, series/story name, artwork, duration, elapsed time, media type, and playback rate.
- Keep lock-screen progress synchronized after seeking and changing rate.
- Make next/previous availability reflect the active queue.
- Ensure artwork is cached, resized, and updated without blocking playback.
- Verify controls through the lock screen, Control Center, Bluetooth, headphones, and AirPlay.

### 4.4 Offline Media

- Define a shared download record and download-state model.
- Allow users to download stories, story chapters, and podcast episodes.
- Prefer verified local files before remote URLs.
- Surface download progress, completion, failure, retry, and storage usage.
- Detect and remove orphaned or corrupt files safely.

### 4.5 Playback Recovery

- Handle network loss, timeouts, unavailable audio, and slow buffering.
- Refresh or re-resolve expired remote URLs where applicable.
- Preserve the queue and position after recoverable failures.
- Respond correctly to calls, Siri, route changes, media-service resets, and reconnects.
- Provide concise user-facing errors with retry or skip actions.

### Acceptance Criteria

- Every phone playback surface controls the same player and queue.
- Continue Listening survives app termination and accurately restores progress.
- Lock-screen and external controls show correct metadata and queue availability.
- Downloaded media works without connectivity.
- A failed item does not strand the queue in an endless loading state.
- These improvements remain fully useful if CarPlay approval never arrives.

## Approval-Gated Phase 5: Complete the CarPlay MVP

- Enable the approved managed capability and add the entitlement to signing.
- Validate the existing Listen Now, Stories, Podcasts, queue, and Now Playing vertical slice.
- Add story chapter browsing using the shared queue implementation.
- Add Favorites and Downloads using the shared catalog and download state.
- Apply the shared artwork cache to CarPlay templates.
- Refine CarPlay-specific loading, empty, offline, and error presentations.

### Acceptance Criteria

- Reconnecting resumes the same item and position.
- Downloaded media works offline.
- Streaming errors terminate loading and provide a useful message.
- Calls, Siri, and audio-route changes pause or resume according to system guidance.

## Approval-Gated Phase 6: Vehicle Validation and Release

- Request Apple's `com.apple.developer.carplay-audio` managed entitlement.
- Position LearnCI as narrated language-learning stories and podcast listening.
- Explicitly document that interactive games, reading, video, and setup are excluded from CarPlay.
- Add the entitlement only after Apple enables it for the developer account.
- Regenerate provisioning profiles and update signing.
- Test with Xcode's CarPlay simulator and physical vehicles.

## Test Matrix

- Fresh launch, warm launch, connect, disconnect, and reconnect.
- Local story, remote story, podcast stream, and unavailable URL.
- Light/dark mode and multiple display sizes.
- Touch and rotary-controller navigation.
- Long titles, missing artwork, empty libraries, and large libraries.
- Poor connectivity, airplane mode, calls, Siri, and route switching.
- Play/pause, seeking, next/previous, playback speed, and completion.

## Delivery Milestones

1. **Completed vertical slice:** shared player, catalog, CarPlay scene, and story/podcast playback.
2. **Shared listening experience:** unified in-app queue, persisted resume state, Continue Listening, and reliable metadata.
3. **Offline and recovery:** downloads, artwork caching, network recovery, and interruption handling.
4. **CarPlay approval gate:** enable the managed capability and validate the vertical slice only after approval.
5. **Complete CarPlay browsing:** chapters, favorites, downloads, and CarPlay-specific state presentation.
6. **Release:** vehicle testing, App Review notes, and production validation.

## External Dependency

Apple must approve the audio entitlement before LearnCI can appear on a real CarPlay home screen. Implementation and ordinary iOS builds can proceed without adding that entitlement to the signing configuration.

Entitlement approval is not a dependency for milestones 2 or 3. It is a dependency for milestones 4 through 6.
