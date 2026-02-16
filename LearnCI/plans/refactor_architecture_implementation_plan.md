# Implementation Plan - Linker Game (Column Connect)

## Goal Description
Implement a new "Column Connect" (Linker) game mode where users match items between two vertical columns. The game is fast-paced and focuses on vocabulary linking. It consists of 3 rounds: Word-Word, Image-Word, and Audio-Word.

## User Description
The user will see two columns of items.
- **Left Column**: Contains items in the Target Language (Spanish).
- **Right Column**: Contains matching items in English (or configured language), shuffled.
- **Interaction**: The user taps an item on the left (which plays audio if available) and then taps the matching item on the right. A line is drawn or the match clears.
- **Rounds**:
    1.  **Word**: Syncs Spanish Word to English Word.
    2.  **Image**: Syncs Image to English Word.
    3.  **Audio**: Syncs Audio Button to English Word.

## User Review Required
> [!NOTE]
> The "Left column Native to Native Word" customization mentioned in the request is interpreted as "Target Language (Spanish) to Target Language (Spanish)". Please confirm if "Native Word" meant something else.
> Assuming "Native" in the request refers to the Target Language (Spanish) if "English" is the alternate.

## Proposed Changes

### Models

#### [MODIFY] [GameConfiguration.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Models/GameConfiguration.swift)
- Add `.linker` case to `GameType` enum if it exists, or ensure the game configuration can support this new mode.
- Add `LinkerConfiguration` struct or properties to store customization (e.g., column mapping).

### Views / Games

#### [NEW] [LinkerGameView.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/Games/LinkerGameView.swift)
- **Main View**: Manages the 3 rounds and overall game state.
- **Subviews**:
    - `LinkerColumnView`: Displays a list of items (Text, Image, or Audio Button).
    - `LinkerItemView`: Individual matched item component.
- **State Management**:
    - `currentRound`: Enum (.word, .image, .audio).
    - `matches`: Set of matched pairs.
    - `selectedLeftItem`: Currently selected item for matching.
    - `shuffledRightItems`: The shuffled list for the right column.

#### [NEW] [LinkerGameViewModel.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/ViewModels/LinkerGameViewModel.swift)
- Manages the logic for:
    - Initializing rounds with specific card subsets (5 cards per round).
    - Handling selection and matching logic.
    - Playing audio when left item is tapped.
    - Drawing lines (visual state) or clearing matches.
    - Transitions between rounds.

### Component Implementation Details
- **Audio Playback**: Utilize `AudioManager` (EnvironmentObject) to play audio when left items are tapped.
- **Line Drawing**: Use `Canvas` or `Path` overlay to draw lines between selected items if "draw a line" visual is desired, or simply highlight/remove matched pairs.

## Verification Plan

### Manual Verification
1.  **Round 1 (Word)**:
    - Verify 5 Spanish words on left, 5 English words on right (shuffled).
    - Tap left word -> Audio plays.
    - Tap correct right word -> Match occurs (disappear or mark done).
    - Tap incorrect right word -> Error feedback.
2.  **Round 2 (Image)**:
    - Verify Images on left.
    - Match with English words on right.
3.  **Round 3 (Audio)**:
    - Verify Audio play buttons on left.
    - Match with English words on right.
4.  **Completion**:
    - Verify game ends after 3 rounds or transitions correctly.
