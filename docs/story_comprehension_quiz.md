# Feature: Story Comprehension Quiz

## Context
The story feature delivers comprehensible input but has no way to verify understanding. After listening/reading, learners have no feedback loop. Adding AI-generated comprehension questions directly after a story closes this gap — turning passive consumption into active recall, a core principle of effective language learning. Questions are in the story's target language to keep learners in the language.

## Behavior
- When story audio finishes playing, a banner appears above the audio bar: "Story complete — test your comprehension"
- Quiz is also always available from the `⋯` toolbar menu
- Questions are generated on first request and stored on the Story model (no re-generation cost on re-opens)
- If questions aren't ready yet when the user taps, a loading indicator is shown inside the sheet
- Questions sync to Supabase as part of the story record (field: `comprehension_questions_json`)

---

## Implementation

### 1. `ComprehensionQuestion` struct + `comprehensionQuestionsJSON` field
**File**: `LearnCI/Models/Story.swift`

```swift
struct ComprehensionQuestion: Codable, Identifiable {
    var id: UUID = UUID()
    let question: String   // In target language
    let choices: [String]  // Exactly 4 choices, in target language
    let correctIndex: Int  // 0–3

    // Exclude `id` from Codable — GPT responses don't include it,
    // and the auto-synthesized decoder throws keyNotFound otherwise.
    enum CodingKeys: String, CodingKey {
        case question, choices, correctIndex
    }
}
```

> **Bug fix note:** The `CodingKeys` enum is required. Without it Swift's synthesized `Codable` requires an `id` key in every JSON object. Since GPT never returns one, decoding silently fails via `try?`, leaving `quizQuestions` empty → blank sheet.

Field on `Story` class:
```swift
var comprehensionQuestionsJSON: String?
```

Computed property (same `@Transient` pattern as `wordTimings`):
```swift
@Transient var comprehensionQuestions: [ComprehensionQuestion] {
    guard let json = comprehensionQuestionsJSON,
          let data = json.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([ComprehensionQuestion].self, from: data)) ?? []
}
```

No SwiftData migration needed — optional fields auto-default to nil.

---

### 2. `generateComprehensionQuestions()` in OpenAIService
**File**: `LearnCI/Managers/OpenAIService.swift`

- Model: `gpt-4o-mini`, `response_format: json_object`
- All questions and answer choices written in the target language
- Returns 4 questions by default; each has `question`, `choices` (array of 4), `correctIndex` (0–3)
- Decoded via `QuestionsWrapper { let questions: [ComprehensionQuestion] }`

---

### 3. StorySessionView changes
**File**: `LearnCI/Views/StoryMaker/StorySessionView.swift`

**State variables:**
```swift
@State private var showQuizBanner: Bool = false
@State private var showComprehensionQuiz: Bool = false
@State private var isGeneratingQuiz: Bool = false
@State private var quizQuestions: [ComprehensionQuestion] = []
```

**Audio completion detection** (in `.onReceive(timer)` else branch):
```swift
let justStopped = isPlaying
isPlaying = false
if justStopped && duration > 0 && sliderValue >= duration - 1.5 && !showQuizBanner {
    showQuizBanner = true
    preGenerateQuizIfNeeded()
}
```

**Key methods:**
- `preGenerateQuizIfNeeded()` — fires in background when banner shows; skips if questions already cached
- `openQuiz()` — loads cached questions or generates on demand with loading sheet
- `regenerateQuiz()` — clears `comprehensionQuestionsJSON` and regenerates

**New views:**
- `QuizBannerView` — slides up above `AudioPlayerBar` when audio completes
- `ComprehensionQuizSheet` — 3 states: loading → question-by-question → results with score ring

**Error/retry state** in `ComprehensionQuizSheet`:
If generation fails (empty questions, not loading, not complete), shows an error message with a "Try Again" button that calls `onRetry` → clears cache → re-runs `openQuiz()`.

---

### 4. Supabase sync
**File**: `LearnCI/Managers/SyncManager.swift`

Added `comprehension_questions_json: String?` to `StoryDTO`. Included in:
- `syncStories` — pushes field when upserting stories
- `pullStories` — maps field back on both update and insert paths

**Database migration:**
```sql
ALTER TABLE stories ADD COLUMN IF NOT EXISTS comprehension_questions_json TEXT;
```

**Sync timing:** Questions sync automatically on the next sync cycle — app foreground (`scenePhase == .active`), app launch, Dashboard appearance, Insights appearance, or post story-generation. In practice: background the app and return.

---

## Critical Files
| File | Changes |
|------|---------|
| `LearnCI/Models/Story.swift` | `ComprehensionQuestion` struct + `comprehensionQuestionsJSON` field + `CodingKeys` |
| `LearnCI/Managers/OpenAIService.swift` | `generateComprehensionQuestions()` |
| `LearnCI/Views/StoryMaker/StorySessionView.swift` | Banner, quiz sheet, menu entries, state, timer detection, error state |
| `LearnCI/Managers/SyncManager.swift` | `StoryDTO`, `syncStories`, `pullStories` |

---

## Verification
1. Build — no errors
2. Open a story with audio → play to the end → banner slides up above audio bar
3. Tap "Take Quiz →" — sheet opens with loading indicator while questions generate
4. After ~3s, 4 questions appear in target language
5. Select an answer → green/red feedback, correct answer highlighted
6. "Next →" advances; after final question → results screen with score ring
7. Close and re-open story → tap ⋯ menu → "Comprehension Quiz" → questions load instantly (no API call)
8. Tap ✕ on banner → banner dismisses; quiz still accessible from menu
9. Stories without audio — banner never appears; quiz accessible from menu only
10. Background app and return → `comprehension_questions_json` syncs to Supabase
