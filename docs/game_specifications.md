# Game Specifications

This document provides detailed specifications for each game type in LearnCI. Use this as a reference when implementing new features, debugging issues, or planning refactors.

---

## 1. Flashcards

**Purpose**: Classic vocabulary review with spaced repetition  
**Mechanics**: Card-by-card review with flip interaction

### Session Settings Used
- ✅ **Universal Settings**: `sessionDuration`, `sessionCardGoal`, `order`, `useTTSFallback`, `ttsRate`
- ✅ **Game-Specific Settings**: `navigation` (Swipe/Buttons/Auto-Next), `confirmation` (Quiz/SRS/Show/Auto)

### Technical Details
- **ViewModel**: No (stateless view)
- **Deck Management**: Uses `SmartSessionManager` for card queueing
- **Progress Tracking**: Counts learned vs remaining cards
- **Layout**: Uses `FlashcardLayoutSelector` for preset configuration

### Card Flow
1. Show front (target word or native word based on config)
2. User flips card
3. User grades: Relearn/Learned or Hard/Good/Easy (depends on confirmation style)
4. SmartSessionManager handles re-insertion based on grade
5. Continue until queue empty or time limit reached

---

## 2. Memory Match

**Purpose**: Matching pairs to test memory and vocab recognition 
**Mechanics**: Grid-based card matching (4x4 default)

### Session Settings Used
- ✅ **Universal Settings**: `sessionDuration`, `sessionCardGoal`, `order`, `useTTSFallback`, `ttsRate`
- ❌ **Game-Specific Settings**: None (but card goal must be multiples of 8)

### Technical Details
- **ViewModel**: Yes (`MemoryGameView` has internal state management)
- **Deck Management**: Does NOT use SmartSessionManager (internal shuffling)
- **Progress Tracking**: Counts matched pairs
- **Layout**: Uses `MemoryMatchModeSelector` for mode configuration

### Card Constraints
- Card goal must be multiples of 8 (for 4x4 grid)
- Creates pairs (word-translation, word-image, etc.)

### Match Modes
- Picture-to-Word
- Word-to-Word  
- Word-to-Picture
- Picture-to-Picture

---

## 3. Story Mode

**Purpose**: Reading immersive stories with audio support  
**Mechanics**: Linear story reading with page-by-page progression

### Session Settings Used
- ✅ **Universal Settings**: `sessionDuration`, `useTTSFallback`, `ttsRate`
- ❌ `sessionCardGoal`, `order` do not apply (story progression is linear)
- ❌ **Game-Specific Settings**: Navigation/Confirmation do not apply

### Technical Details
- **ViewModel**: No (reuses `FlashcardGameView` in linear mode)
- **Deck Management**: Does NOT use SmartSessionManager (story pages are sequential)
- **Progress Tracking**: Page progress through story
- **Layout**: Uses `FlashcardLayoutSelector` (shares config with Flashcards)

### Story Flow
1. Show story page with text + optional image
2. Play audio (if available)
3. User advances to next page
4. Continue until story complete

---

## 4. Multiple Choice

**Purpose**: Test comprehension with 4-option quizzes  
**Mechanics**: Card-by-card with multiple choice answers

### Session Settings Used
- ✅ **Universal Settings**: `sessionDuration`, `sessionCardGoal`, `order`, `useTTSFallback`, `ttsRate`
- ❌ **Game-Specific Settings**: Navigation/Confirmation do not apply (always shows 4 options)

### Technical Details
- **ViewModel**: No (stateless view)
- **Deck Management**: Uses `SmartSessionManager` for card queueing (expected future refactor)
- **Progress Tracking**: Counts correct/incorrect selections
- **Layout**: Uses `PlaceholderConfigView` (no game-specific config yet)

### Quiz Flow
1. Show question (word, sentence, or image)
2. Display 4 answer choices
3. User selects answer
4. Show correct/incorrect feedback
5. Continue to next card

---

## 5. Audio Cloze (Listening Challenge)

**Purpose**: Improve listening skills with fill-in-the-blank  
**Mechanics**: Listen to audio, identify missing word

### Session Settings Used
- ✅ **Universal Settings**: `sessionDuration`, `sessionCardGoal`, `order`, `useTTSFallback`, `ttsRate`
- ❌ **Game-Specific Settings**: Navigation/Confirmation do not apply

### Technical Details
- **ViewModel**: No (stateless view)
- **Deck Management**: Uses `SmartSessionManager` for card queueing (expected future refactor)
- **Progress Tracking**: Counts correct/incorrect answers
- **Layout**: Uses `PlaceholderConfigView` (no game-specific config yet)

### Game Flow
1. Play sentence audio with one word missing
2. Show multiple choice options or text input
3. User selects/types missing word
4. Show correct/incorrect feedback
5. Continue to next sentence

---

## 6. Column Connect (Linker)

**Purpose**: Connect matching items between columns  
**Mechanics**: Round-based (3 rounds: Word, Image, Audio)

### Session Settings Used
- ✅ **Universal Settings**: `sessionDuration`, `sessionCardGoal`, `order`, `useTTSFallback`, `ttsRate`
- ✅ **Game-Specific Settings**: `linkerTargetMode` (English Word or Native Word for right column)

### Technical Details
- **ViewModel**: Yes (`LinkerGameViewModel`)
- **Deck Management**: Does NOT use SmartSessionManager (own card selection per round)
- **Progress Tracking**: Counts correct matches, score accumulation across rounds
- **Layout**: Uses `LinkerConfigView` for game-specific settings

### Round Structure
Each round uses `sessionCardGoal` cards:
1. **Round 1 - Word**: Match native words (left) to English words (right)
2. **Round 2 - Image**: Match images (left) to English words (right)
3. **Round 3 - Audio**: Match audio (left) to English words (right)

### Game Flow
1. User taps item in left column
2. User taps matching item in right column
3. System validates if cards match
4. Continue until all pairs matched
5. Proceed to next round
6. Final score after 3 rounds

---

## Session Settings Reference

### Universal Settings (All Games)
- `sessionDuration`: Time limit in minutes
- `sessionCardGoal`: Number of cards to review
- `order`: Card ordering strategy (Sequential, Random, Smart Queue)
- `useTTSFallback`: Enable system voice when audio files missing
- `ttsRate`: Text-to-speech playback speed

### Game-Specific Settings

#### Flashcards Only
- `navigation`: How to navigate cards (Swipe, Buttons, Auto-Next)
- `confirmation`: How to mark cards (Quiz, SRS, Show, Auto)

#### Column Connect Only
- `linkerTargetMode`: Right column content (English Word, Native Word)

#### Memory Match Constraints
- `sessionCardGoal` must be multiples of 8

---

## Future Refactoring Notes

### Phase 2 Goals
- Standardize all config views (Settings Form or Placeholder only)
- Clearly separate universal vs game-specific settings in UI

### Phase 3 Goals
- Extend `SmartSessionManager` to support round-based games
- Migrate Memory Match and Linker to use SmartSessionManager
- Create `SessionController` for centralized timer/scoring

### Phase 4 Goals
- Implement ViewModels for all games
- Standardize game view signatures
- Consistent parameter passing (deck, config, sessionCardGoal, callbacks)
