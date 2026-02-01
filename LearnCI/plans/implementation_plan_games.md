# Learn Flow Refactor Plan

The objective is to split the `GameView` into three distinct states: `Configuration`, `Active`, and `Finished`.

## Proposed Changes

### [GameView.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Views/GameView.swift)

#### State Enum
```swift
enum GameState {
    case configuration
    case active
    case finished
}
```

#### New State Variables
- `gameState: GameState`
- `sessionDuration: Int` (minutes, from slider)
- `sessionCardGoal: Int` (from stepper)
- `sessionLanguage: Language`
- `sessionLevel: LearningLevel`
- `remainingSeconds: Int` (countdown)
- `sessionLearnedCount: Int`
- `sessionStartTime: Date?`

#### UI Components
1. **ConfigurationView**:
   - Time Slider (1-60 mins)
   - Card Goal Stepper
   - Language/Level Pickers (synced with profile defaults initially)
   - "Start Session" Button

2. **ActiveGameView**: (Refactored current GameView)
   - Countdown timer in toolbar
   - Play/Pause/Stop controls
   - Flashcards
   - "Learned" / "Relearn" buttons

3. **FinishView**:
   - Total cards learned
   - Time spent
   - Accuracy (if we add failure tracking)
   - "Back to Config" or "Finish" buttons

## Verification Plan

### Manual Verification
- Start a 1-minute session with 5 cards.
- Verify timer counts down and stops at 0.
- Verify stop button takes user to Finish screen.
- Verify stats on Finish screen are accurate.
- Verify saving session only happens once at finish.
