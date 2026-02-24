# Plan: Word Crush Game

## Context
The user wants a candy-crush style vocabulary game called "Word Crush" that uses existing flashcard decks with deck/tag selection. It should follow the same mechanics and architecture as the other 6 games (flashcards, memory match, multiple choice, audio cloze, linker, story) — integrating into the 7-stage GameView setup flow, using GameSessionViewModel for scoring/timing, and routing through ActiveSessionView.

## Game Design

**Core Mechanic**: A grid of word tiles (mix of target-language and native-language words). Player taps two tiles that form a correct translation pair. Matched tiles disappear with animation, tiles above fall down (gravity), and new tiles fill in from the top. Streak bonuses for consecutive correct matches; penalty for wrong pairs.

**Grid**: 4 columns x 5 rows (20 tiles). Each tile shows a word. Roughly half target-language, half native-language, drawn from session cards.

**Scoring**: Correct match → `onMatchFound()` callback (same as MemoryGame). Wrong pair → brief shake animation, streak reset. Cascade: if new tiles falling create an auto-matchable state, highlight them as a hint.

**Session end**: When `learnedCount >= sessionCardGoal` (matches found) OR time runs out — same as other games.

**SRS integration**: On correct match → `onGrade(.good)`. On wrong attempt → no grade (only penalize streak).

## Files to Create

### 1. `LearnCI/ViewModels/WordCrushGameViewModel.swift` (NEW)
Game-specific ViewModel (follows MemoryGameViewModel / LinkerGameViewModel pattern).

**Key state:**
- `tiles: [WordCrushTile]` — flat array of 20 tiles, each with `id`, `word`, `cardId`, `isTarget` (language side), `isMatched`, `isSelected`, grid position
- `selectedTile: WordCrushTile?` — first tile of a pair attempt
- `matchesFound: Int`, `score: Int`, `streak: Int`
- `isAnimating: Bool` — lock input during gravity/fill animations

**Key types:**
```swift
struct WordCrushTile: Identifiable, Equatable {
    let id: UUID
    var word: String
    var cardId: UUID        // links back to LearningCard
    var isTarget: Bool      // true = target language, false = native
    var row: Int
    var col: Int
    var isMatched: Bool
    var isSelected: Bool
}
```

**Key methods:**
- `setupGrid(cards: [LearningCard])` — populate 20 tiles from session cards. Each card contributes 2 tiles (target + native). If fewer than 10 cards, reuse cards. Shuffle positions randomly.
- `selectTile(_ tile)` — if no selection, select it. If already selected, check if pair matches (same `cardId`, different `isTarget`). Correct → remove pair, trigger gravity + refill. Wrong → shake + deselect.
- `applyGravity()` — tiles above empty spaces fall down (animate row changes)
- `refillGrid(cards:)` — add new tiles from remaining/recycled cards at top with empty positions
- `checkGameOver()` — if no more valid pairs possible, reshuffle or end

### 2. `LearnCI/Views/Games/WordCrushGameView.swift` (NEW)
The SwiftUI view for the game (follows MemoryGameView/LinkerGameView pattern).

**Props** (matching ActiveSessionView callback pattern):
```swift
let deck: CardDeck
let sessionCards: [LearningCard]
let sessionConfig: GameConfiguration
var onFinish: () -> Void
var onGrade: ((SmartSessionManager.Grade) -> Void)?
var onMatchFound: (() -> Void)?
```

**Layout:**
- Score/streak header bar
- 4x5 grid of `WordCrushTileView` cells using `LazyVGrid`
- Each tile: rounded rect with word text, tap gesture, selection highlight, match/shake animations
- Tile colors: one color tint for target-language words, another for native-language words (helps player identify pairs)

**Animations:**
- Selection: scale + border highlight
- Correct match: tiles scale down + fade out, then gravity drop (`.transition(.scale.combined(with: .opacity))`)
- Wrong match: shake animation (offset oscillation)
- New tiles: drop in from top (`.transition(.move(edge: .top))`)

## Files to Modify

### 3. `LearnCI/Managers/GameConfiguration.swift`
- Add `case wordCrush` to `GameType` enum
- Add `icon` → `"square.grid.3x3.fill"`
- Add `description` → `"Match word pairs in a cascading grid"`
- Add decoding support in `init(from:)` for `"wordCrush"` / `"word_crush"`

### 4. `LearnCI/Views/Components/ActiveSessionView.swift`
- Add `case .wordCrush` to the switch in the game router
- Route to `WordCrushGameView` with same callback pattern as other games:
```swift
case .wordCrush:
    WordCrushGameView(
        deck: deck,
        sessionCards: sessionCards,
        sessionConfig: sessionConfig,
        onFinish: { viewModel.endSession() },
        onGrade: { grade in viewModel.handleGrade(grade) },
        onMatchFound: {
            viewModel.registerSuccess()
            viewModel.incrementLearned()
        }
    )
```

### 5. `LearnCI/Views/GameView.swift`
- Add `.wordCrush` to any game-type-specific UI in the setup stages (e.g., game-specific config stage). If no Word Crush-specific config is needed, ensure it falls through gracefully (like flashcards does).

## Reuse
- **GameSessionViewModel** (`LearnCI/ViewModels/GameSessionViewModel.swift`) — scoring, timing, card management, `registerSuccess()`, `incrementLearned()`, `handleGrade()`
- **SmartSessionManager** (`LearnCI/Managers/SmartSessionManager.swift`) — SRS grading via `onGrade` callback
- **ActiveSessionView** (`LearnCI/Views/Components/ActiveSessionView.swift`) — game routing
- **GameView** (`LearnCI/Views/GameView.swift`) — 7-stage setup flow (deck selection, config, summary, play, finish)
- **SoundManager** — `SoundManager.shared.play(.correct)` / `.wrong` for match feedback
- **DeckSelectionSheet / TagSelectionSheet** — already handled by GameView stages
- **Existing animation patterns** from MemoryGameView (card flip, match effects)

## Verification
- Select Word Crush from game picker → goes through deck selection → session config → starts game
- Grid shows 20 tiles with mix of target/native words
- Tap two matching tiles (same card, different languages) → tiles disappear, gravity applies, new tiles drop in
- Tap two non-matching tiles → shake animation, streak resets
- Score increments on correct matches with streak bonus
- Session ends when card goal reached or time expires
- Results screen shows score, matches, time
- Build succeeds with no warnings
