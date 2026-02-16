# Implementation Plan - Game Refactor Phase 1: Documentation & Cleanup

## Goal Description
Phase 1 focuses on low-risk cleanup and documentation improvements. We'll remove the unimplemented `sentenceBuilder` game type, create comprehensive game specifications documentation, and refactor `SessionOptionsView` to only show settings that are relevant to the selected game type.

## User Description
Users currently see session settings (like Navigation and Confirmation) for all games, even though these only apply to Flashcards. After this refactor:
- Sentence Builder option removed from game selection
- Universal settings (Duration, Card Goal, Order, Audio) shown for all games
- Game-specific settings (Navigation, Confirmation) only shown when playing Flashcards
- Clear documentation of what each game does and which settings it uses

## User Review Required

> [!IMPORTANT]
> This phase removes the Sentence Builder game type entirely. Confirm this game is not planned for future implementation.

## Proposed Changes

### Phase 1A: Remove Sentence Builder

---

#### [MODIFY] [GameConfiguration.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Managers/GameConfiguration.swift)
- Remove `.sentenceBuilder` case from `GameType` enum
- Remove associated icon, description, and any related logic

#### [MODIFY] [GameSpecificConfigRouter.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/Components/GameSpecificConfigRouter.swift)
- Remove `.sentenceBuilder` from switch statement

#### [MODIFY] [PlaceholderConfigView.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/Components/PlaceholderConfigView.swift)
- Remove `.sentenceBuilder` case from gameDescription switch

#### [MODIFY] [ActiveSessionView.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/Components/ActiveSessionView.swift)
- Remove `.sentenceBuilder` case if present in game routing

---

### Phase 1B: Create Game Specifications Document

---

#### [NEW] [game_specifications.md](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/docs/game_specifications.md)
- Document all 6 remaining game types
- For each game, specify:
  - **Purpose**: What learning objective it serves
  - **Mechanics**: How the game works
  - **Session Settings Used**: Which universal and game-specific settings apply
  - **ViewModel**: Whether it uses ViewModel pattern
  - **Deck Management**: How it selects/orders cards
  - **Progress Tracking**: How completion is measured

---

### Phase 1C: Refactor SessionOptionsView

---

#### [MODIFY] [SessionOptionsView.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/Components/SessionOptionsView.swift)

**Changes:**
1. **Remove Navigation/Confirmation sections** (lines ~73-103)
2. **Move them to Flashcard-only conditional block**
3. **Add game type parameter** to view if not present
4. **Reorganize Form sections**:
   - Universal Settings (always shown)
   - Game-Specific Settings (conditional)

**New Structure:**
```swift
Form {
    // Universal Settings (All Games)
    Section("Universal Settings") {
        // Time Limit
        // Card Goal  
        // Card Order
    }
    
    // Audio Settings (All Games)
    Section("Audio Options") {
        // TTS Fallback
        // TTS Rate
    }
    
    // Game-Specific Settings (Conditional)
    if gameType == .flashcards {
        Section("Flashcard Settings") {
            // Navigation Style
            // Confirmation Style
        }
    }
}
```

#### [MODIFY] [SessionOptionsSheet.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/Components/SessionOptionsSheet.swift)
- Same conditional logic for Navigation/Confirmation sections
- Ensure gameType parameter is passed correctly

---

### Phase 1D: Add Inline Documentation

---

#### [MODIFY] [LinkerGameViewModel.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/ViewModels/LinkerGameViewModel.swift)
- Add header comments explaining ViewModel responsibilities
- Document session settings usage

#### [MODIFY] [MemoryGameView.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/Games/MemoryGameView.swift)
- Add TODO comment about future ViewModel refactor
- Document card count constraint (multiples of 8)

#### [MODIFY] [FlashcardGameView.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/Games/FlashcardGameView.swift)
- Document navigation/confirmation setting usage

## Verification Plan

### Automated Tests
- Build the project to ensure no compilation errors
- Verify no references to `.sentenceBuilder` remain

### Manual Verification
1. **Game Selection**:
   - Open app and start new session
   - Verify Sentence Builder no longer appears in game type picker
   - All 6 remaining games selectable

2. **Session Options - Flashcards**:
   - Select Flashcards game
   - Navigate to Session Options
   - Verify Navigation and Confirmation settings appear

3. **Session Options - Other Games**:
   - Select Memory Match
   - Navigate to Session Options
   - Verify Navigation and Confirmation settings DO NOT appear
   - Repeat for MultipleChoice, AudioCloze, Linker, Story

4. **Documentation**:
   - Review `game_specifications.md` for completeness
   - Verify all 6 games documented
   - Check that settings usage is clearly specified
