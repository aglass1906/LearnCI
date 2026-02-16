# Game Flow Architecture Analysis

## Current Game State Flow

### The 5-Stage Flow
1. **Deck Selection** (`GameConfigurationView`)
   - User selects: Game Type, Deck, Tags (optional filtering)
   
2. **Game-Specific Config** (`GameSpecificConfigRouter`)
   - Routes to appropriate config view based on game type
   
3. **Session Options** (`SessionOptionsView`)
   - Universal settings: Duration, Card Goal, Order, Audio
   - Game-specific settings shown conditionally (e.g., Navigation/Confirmation for Flashcards only)
   
4. **Pre-Game Summary** (`PreGameSummaryView`)
   - Review all settings before starting
   
5. **Active Game** (`ActiveSessionView` → Individual Game Views)
   - Actual gameplay

---

## Game Types (7 Total)

| Game Type | Config View | Has ViewModel? | Notes |
|-----------|-------------|----------------|-------|
| `flashcards` | `FlashcardLayoutSelector` | No | Uses card-by-card iteration |
| `memoryMatch` | `MemoryMatchModeSelector` | Yes (`MemoryGameView`) | Requires multiples of 8 cards |
| `story` | `FlashcardLayoutSelector` | No | Special story reading mode |
| `multipleChoice` | `PlaceholderConfigView` | No | Card-by-card with quiz |
| `audioCloze` | `PlaceholderConfigView` | No | Card-by-card with audio |
| ~~`sentenceBuilder`~~ | ~~`PlaceholderConfigView`~~ | ~~No~~ | **REMOVED - Not implemented** |
| `linker` | `LinkerConfigView` | Yes (`LinkerGameViewModel`) | Round-based (3 rounds) |

---

## Configuration View Patterns (4 Types)

### 1. **Layout Preset Selector** (Flashcards, Story)
- **View**: `FlashcardLayoutSelector`
- **Purpose**: Choose card display presets (Customize, Input Focus, Audio Cards, etc.)
- **Config Binding**: `selectedPreset`, `customConfig`

### 2. **Mode Selector** (Memory Match)
- **View**: `MemoryMatchModeSelector`
- **Purpose**: Choose matching mode (Picture-to-Word, Word-to-Word, etc.)
- **Config Binding**: `memoryMatchMode`

### 3. **Settings View** (Linker)
- **View**: `LinkerConfigView`
- **Purpose**: Configure game-specific settings (Right Column Content)
- **Config Binding**: `customConfig.linkerTargetMode`

### 4. **Placeholder** (Multiple Choice, Audio Cloze, Sentence Builder)
- **View**: `PlaceholderConfigView`
- **Purpose**: Show game description only, no settings
- **Config Binding**: None

---

## Virtual Deck Preparation

### Different Approaches by Game:

#### **Card-by-Card Games** (Flashcards, Multiple Choice, Audio Cloze)
- Deck prepared in parent view before game starts
- `SmartSessionManager.startSession(cards: [LearningCard])` initializes queue
- Games iterate through `SmartSessionManager.activeQueue`
- **Location**: Session setup happens in parent view, cards passed to game view

#### **Round-Based Games** (Linker)
- `LinkerGameViewModel` receives:
  - Full `CardDeck` object
  - `sessionCardGoal` parameter
- Each round: `prepareItems()` shuffles and selects cards
- **Issue**: ❌ Doesn't use SmartSessionManager, implements own card selection

#### **Grid-Based Games** (Memory Match)
- `MemoryGameView` receives full deck
- Internally shuffles and creates pairs
- **Issue**: ❌ Doesn't use SmartSessionManager

### Current Deck Setup Flow:
```
GameConfigurationView (select deck)
    ↓
LoadDeck from DataManager
    ↓
Filter by tags (if selected)
    ↓
Apply OrderStrategy (Smart/Random/Sequential)
    ↓
Pass to Game View
```

---

## Session Settings Analysis

### Universal Settings (All Games)
- ✅ `sessionDuration` (time limit)
- ✅ `sessionCardGoal` (number of cards)
- ✅ `order` (Sequential, Random, Smart Queue)
- ✅ `useTTSFallback` (enable system voice)
- ✅ `ttsRate` (speech speed)

### Game-Specific Settings
- **Flashcards Only**: 
  - `navigation` (Swipe, Buttons, Auto-Next)
  - `confirmation` (Quiz, SRS, Show, Auto)
- **Memory Match**: Enforces multiples of 8 for 4x4 grid
- **Linker**: `linkerTargetMode` (English Word, Native Word)

### Missing Session Context:
- ❌ No session persistence/resume
- ❌ Timer not enforced in all games
- ❌ Scoring not centralized

---

## Identified Inconsistencies

### 1. **Deck Management**
- **Problem**: 3 different patterns for accessing cards
  - Card-by-card games use `SmartSessionManager`
  - Linker uses own selection in ViewModel
  - MemoryMatch has own internal logic
- **Impact**: Duplicated code, hard to maintain

### 2. **Configuration Flow**
- **Problem**: Inconsistent config view patterns
  - Some games have sophisticated config (Flashcards)
  - Others have simple mode selector (MemoryMatch)
  - Linker has settings form
  - 3 games have placeholder (no config)
- **Impact**: Confusing UX, uneven feature parity

### 3. **Game View Architecture**
- **Problem**: Games don't follow single pattern
  - Some are stateless views receiving cards
  - Others have ViewModels managing state
  - Mix of round-based vs card-by-card
- **Impact**: Difficult to add features consistently

### 4. **Session Settings Usage**
- **Problem**: Settings scope not clearly defined
  - Timer not implemented consistently
  - `confirmation` and `navigation` shown in all games but only apply to Flashcards
  - No clear separation of universal vs game-specific settings
- **Impact**: Confusing UX, users set options that don't affect their game

### 5. **Parameter Passing**
- **Problem**: Inconsistent signatures
  - Flashcards: receives `sessionCards`, `currentCardIndex`, `learnedCount`, `sessionCardGoal`
  - Linker: receives `deck`, `config`, `sessionCardGoal`
  - MemoryMatch: receives `deck`, `matchMode`, `onFinish`
- **Impact**: Hard to add features to all games

---

## Recommendations for Consistency

### Strategy 1: **Standardize Game Protocol**
Create a common protocol/pattern that all games follow:

```
protocol GameViewProtocol {
    - Receives: deck, config, sessionCardGoal
    - Uses: SmartSessionManager for card queue
    - Respects: All session settings (timer, navigation, confirmation)
    - Provides: Progress tracking, scoring, completion callback
}
```

### Strategy 2: **Unified Deck Preparation**
All games should use `SmartSessionManager` or similar:
- Central place for card selection
- Consistent ordering logic
- Shared progress tracking
- Reusable session state

### Strategy 3: **Configuration View Consistency**
Decide on 2 standard patterns:
1. **Settings Form** (for games with multiple options)
2. **Placeholder** (for games with no options)

Remove the "Layout Preset" and "Mode Selector" in favor of settings form.

### Strategy 4: **ViewModel Pattern**
Either:
- **Option A**: All games use ViewModels (recommended)
- **Option B**: No games use ViewModels (simpler, but less testable)

Don't mix patterns.

### Strategy 5: **Session Settings Enforcement**
Create `SessionController` that:
- Manages timer countdown
- Enforces navigation rules
- Handles confirmation flows
- Tracks progress

Games plug into controller instead of reimplementing.

---

## Architectural Decisions ✅

### Confirmed Decisions:
1. ✅ **All games use ViewModels** 
2. ✅ **All games use SmartSessionManager** (extend as needed for round-based games)
3. ✅ **Universal config settings**:
   - `sessionDuration`, `sessionCardGoal`, `order`, `useTTSFallback`, `ttsRate`
4. ✅ **Remove Sentence Builder** from GameType enum
5. ✅ **Centralize timer/scoring** in SessionController
6. ✅ **Keep 5-stage flow** (Deck → Game Config → Session Options → Summary → Game)

### Game-Specific Settings:
- **Flashcards**: `navigation`, `confirmation` (card-by-card flow)
- **Memory Match**: Card count must be multiples of 8
- **Linker**: `linkerTargetMode` (right column content)
- **Other games**: No additional settings needed

---

## Proposed Refactoring Phases

### Phase 1: Documentation & Cleanup (Low Risk)
- ✅ **Remove `sentenceBuilder`** from GameType enum and all switch statements
- **Document expected behavior** for each game:
  - Create `/LearnCI/docs/game_specifications.md` with detailed specs per game
  - Add inline code comments explaining ViewModel responsibilities
  - Document which session settings each game uses
- Separate SessionOptionsView into universal and game-specific sections
- Add warnings when settings don't apply to selected game

### Phase 2: Standardize Configuration (Medium Risk)
- Define clear config view patterns: Settings Form vs Placeholder
- Decide: Keep FlashcardLayoutSelector or convert to settings form?
- Convert MemoryMatchModeSelector to settings form (like LinkerConfigView)
- Ensure game-specific settings only appear in Game Config stage
- Universal settings only in Session Options stage

### Phase 3: Unified Session Management (High Risk)
- ✅ **Extend SmartSessionManager** to support round-based games
- ✅ **Create SessionController** for centralized timer/scoring
- Refactor Linker to use SmartSessionManager
- Refactor MemoryMatch to use SmartSessionManager
- All games report progress to SessionController

### Phase 4: ViewModel Standardization (High Risk)
- ✅ **Create BaseGameViewModel protocol**
- ✅ **All games implement ViewModels**
- Standardize game view signatures (deck, config, sessionCardGoal, callbacks)
- Consistent parameter passing across all games
- ViewModels handle SmartSessionManager integration

---

## Quick Wins (No Refactor Needed)

1. ✅ Remove duplicate linkerTargetMode from SessionOptionsView (DONE)
2. Add missing audio playback to Linker (DONE)
3. Fix Linker to use sessionCardGoal instead of hardcoded 5 (DONE)
4. Change Linker button from "Start Game" to "Next" (DONE)
5. Document which games support which session settings
6. Add TODO comments for unimplemented features
