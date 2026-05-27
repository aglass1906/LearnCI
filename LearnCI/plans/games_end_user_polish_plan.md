# Games End-User Polish Plan

## Summary

Improve the LearnCI games experience around faster play entry, consistent feedback polish, and clearer in-game navigation. The first implementation should keep the existing game logic intact, but add a shared polish layer so sounds, haptics, celebrations, and progress states feel consistent across Flashcards, Multiple Choice, Audio Cloze, Memory Match, Column Connect, Word Crush, and Word Rain.

The plan intentionally starts with low-risk UX and feedback improvements before adding persisted user preferences or deeper game refactors.

## Current Findings

- The current setup flow is linear: choose game, choose deck, session options, game-specific settings, review, then play. This makes configuration feel required even when the user just wants to start.
- `GameView` already has skip-to-summary hooks in several places, but there is no true quick-start path that applies defaults and starts cleanly.
- `SoundManager` exists and supports `flip`, `match`, `mismatch`, `win`, and `click`, but only `sfx_match.wav` and `sfx_win.wav` are currently bundled.
- Word Rain and Word Crush already have the strongest polish, including score, streaks, celebrations, shake feedback, and match/mismatch sounds.
- Memory Match has basic flip/match/mismatch/win sounds, but its round progress, transitions, and matched-pair feedback are comparatively plain.
- Column Connect has minimal end-user polish: limited sound feedback, no final celebration handoff until its local game-over view, and an in-game dismiss button that competes with the shared playing toolbar.
- Audio Cloze uses haptics directly instead of `SoundManager`; Multiple Choice uses `win` for each correct answer, which makes ordinary success feel like final completion.
- Progress displays vary by game, so the same session goal can feel different depending on the game type.

## Recommended Changes

- Add a quick-start path in `GameView`: after game selection, if a compatible saved or default deck exists, show primary `Play Now` and secondary `Configure` actions.
- Let `Play Now` use existing defaults and jump directly to `startActiveSession` after validating deck availability and clamping the card goal.
- Replace "Skip to Summary" wording with a clearer default-oriented action such as `Use Defaults`.
- Add a `Start` action from the deck step once a deck is selected, so users can bypass optional session and game-specific configuration.
- Add a shared game feedback helper around `SoundManager` for success, mistake, flip, tap, and completion feedback.
- Route sounds and haptics through the shared helper instead of having each game mix its own sound and haptic behavior.
- Add missing bundled SFX files for `sfx_flip`, `sfx_mismatch`, and `sfx_click`; keep current system-sound fallback for safety.
- Standardize feedback behavior:
  - Correct answer: success haptic, match sound, brief scale or glow.
  - Wrong answer: error haptic, mismatch sound, shake.
  - Session or game complete: win sound, completion haptic, short celebration.
- Upgrade Memory Match with animated matched-pair glow, round transition banner, clearer `Round X` and matched-pairs progress, and shared feedback routing.
- Upgrade Column Connect with match/mismatch sounds, selected-state affordance, round transition animation, cleaner finish flow, and shared feedback routing.
- Align Audio Cloze and Multiple Choice with the shared feedback behavior.
- Keep Word Rain and Word Crush mostly intact, but route feedback through the shared helper and clean up any inconsistent celebration behavior.

## Interfaces And State

- Prefer a first pass without SwiftData profile schema changes.
- Add a lightweight helper, for example `GameFeedbackManager`, that exposes methods such as `tap()`, `flip()`, `correct()`, `incorrect()`, `match()`, and `complete()`.
- Keep `SoundManager` as the low-level audio implementation, while the new helper decides which sound and haptic should fire for a game event.
- Design the helper so future user settings can be added without touching every game again.
- If persisted preferences are added later, use defaults equivalent to:
  - `soundEffectsEnabled: true`
  - `hapticsEnabled: true`
- Add a helper method in `GameView`, such as `startWithDefaults()`, that validates deck availability, clamps card count, applies current game-specific defaults, and calls `startActiveSession()`.

## Test Plan

- Build with:

```bash
xcodebuild build -project LearnCI.xcodeproj -scheme LearnCI -configuration Debug
```

- Manually test each game type:
  - Flashcards
  - Memory Match
  - Multiple Choice
  - Listening Challenge
  - Column Connect
  - Word Crush
  - Word Rain

- Verify navigation:
  - Select game, then `Play Now` starts without visiting all config screens.
  - `Configure` still exposes the existing options.
  - A selected deck can start with defaults.
  - Existing back navigation still works through setup.
  - Pause and stop toolbar controls still work during play.

- Verify feedback:
  - Correct, incorrect, match, mismatch, tap, flip, and completion feedback fire once per event.
  - Sounds fall back safely when custom SFX are missing.
  - Haptics do not duplicate on a single answer.
  - Completion sound is reserved for final game or session completion.

- Verify session behavior:
  - Memory Match advances through batches and completes.
  - Column Connect progresses through word, image, and audio rounds, then finishes through the shared session flow.
  - Smart Queue grading still works for flashcards, multiple choice, audio cloze, and arcade games that report progress.
  - Session activity saving still records learned count, elapsed time, game type, and deck.

## Assumptions

- Save this as a new Markdown file rather than modifying an existing plan.
- Use `LearnCI/plans` because it matches the repo's current app implementation-plan convention.
- Keep this document implementation-ready, but do not change app code as part of saving the document.
- The first engineering pass should prioritize quick-start navigation and shared feedback consistency over larger visual redesigns.
- Existing native SwiftUI styling should remain, with restrained polish rather than a full game UI redesign.

## Recommended Phased Implementation Plan

### Phase 1: Navigation and quick-start

- Add `Play Now` and `Configure` paths after game selection.
- Let selected deck plus defaults start a game without visiting every setup screen.
- Add a `Start` action from deck selection when a compatible deck is selected.
- Rename skip actions to clearer default-oriented language, such as `Use Defaults`.
- Keep the current full configuration path available for users who want control.

### Phase 2: Shared feedback system

- Add a centralized game feedback helper around `SoundManager`.
- Route sounds and haptics through one place.
- Add missing bundled SFX assets for flip, mismatch, and click.
- Update Audio Cloze to use the shared helper instead of direct haptic-only helpers.
- Update Multiple Choice to use match feedback for correct answers and completion feedback only at session end.

### Phase 3: Game-by-game polish

- Upgrade Memory Match with round/progress feedback and matched-pair animations.
- Upgrade Column Connect with match/mismatch feedback, cleaner finish flow, and round transitions.
- Align Audio Cloze and Multiple Choice answer reveal animations with the shared feedback behavior.
- Keep Word Rain and Word Crush mostly intact, with feedback routing cleanup.
- Review all games for duplicated local controls that conflict with the shared playing toolbar.

### Phase 4: Preference and settings polish

- Add optional sound and haptic toggles only after the shared helper is in place.
- Persist preferences in profile settings if users need control over audio or haptics.
- Add a concise user-facing game settings area later rather than expanding the first implementation.
- Keep defaults enabled so existing users get the improved experience automatically.

### Phase 5: Verification pass

- Build via `xcodebuild`.
- Manually test quick-start and configure paths for all game types.
- Verify sounds, haptics, completion flow, progress counts, and session activity saving.
- Regression-test smart queue behavior and game-specific completion paths.
- Capture any remaining polish gaps as follow-up issues rather than expanding the first pass.
