# Listening Challenge (Audio Cloze) Implementation Plan

# Goal Description
Implement a new game mode: **Listening Challenge** (Audio Cloze).
This mode enhances comprehensible input by forcing the user to "fill in the gaps" using audio context.
The user listens to a sentence, sees the text with a missing word (`____`), and selects the correct word from a set of options.

## User Review Required
> [!NOTE]
> **Cloze Generation Strategy**: We will initially use a **Client-Side Random Strategy**. The app will select a random word from the sentence (filtering out short words/particles if possible) to become the "Cloze". This allows the mode to work with *all* existing content immediately without new JSON data.
> **Audio Playback**: The audio will play the *full* sentence. The challenge is matching the sound to the missing text.

## Proposed Changes

### Logic & Models

#### [MODIFY] [GameConfiguration.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Managers/GameConfiguration.swift)
- Add `.audioCloze` to `GameType` enum.
- Add `.audioCloze` icon and label.

#### [NEW] [ClozeManager.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Managers/ClozeManager.swift)
- **Responsibility**: Generate a `ClozeChallenge` from a `LearningCard`.
- **Functions**:
    - `generateChallenge(for card: LearningCard, distractors: [LearningCard]) -> ClozeChallenge`
    - Logic to pick a non-trivial word (length > 3) if possible.
    - Logic to pick random distractors from the deck.

### UI Components

#### [NEW] [AudioClozeGameView.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/Games/AudioClozeGameView.swift)
- **Top**: Progress Bar.
- **Center**:
    - Large Play Button (Auto-plays on visual).
    - Sentence Text View: "El perro ____ agua." (Underscore for missing word).
- **Bottom**:
    - Grid of 4 Buttons (1 Correct + 3 Distractors).
    - Correct selection fills the blank and plays success sound.
    - Incorrect selection shakes/highlights red.

#### [MODIFY] [ActiveSessionView.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/Components/ActiveSessionView.swift)
- Add case for `.audioCloze` to render `AudioClozeGameView`.

## Verification Plan

### Manual Verification
1.  **Configuration**: Functionality to select "Listening Challenge" in Game Configuration.
2.  **Gameplay**:
    - Start a session.
    - Verify audio plays automatically.
    - Verify sentence text is shown with one word hidden.
    - Verify 4 options are shown.
    - Verify tapping correct option fills blank and advances (or shows "Correct").
    - Verify tapping incorrect option shows error state.
3.  **Edge Cases**:
    - Sentences with few words (ensure graceful fallback if no good cloze word found).
