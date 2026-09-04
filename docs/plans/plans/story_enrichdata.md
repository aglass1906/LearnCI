# Story Feature Overhaul Implementation Plan

## Goal Description
Enhance the Story feature to support richer, more interactive learning experiences. Key improvements include:
- **Bilingual Text**: Target and native language side-by-side or togglable per section.
- **Structured AI Output**: Use JSON to ensure consistent formatting for title, content, grammar points, and quizzes.
- **Flexible Playback**: Support for "pages" or sections, allowing for focused audio playback and highlighting.
- **Educational Elements**: Integration of grammar focus notes and comprehension questions.

## User Description
When a user generates a story, instead of a plain block of text, the app will create a structured "Story Book".
1. **Creation**: The AI generates a JSON structure containing the full story broken into pages/sections, along with a quiz.
2. **Playback**: Users can read the story page-by-page.
   - Each page has the target language text and hidden/revealable native translation.
   - Audio can be played per-page for better practice (shadowing).
   - Key grammar points are highlighted or noted.
3. **Assessment**: After the story, a short quiz tests comprehension.

## User Review Required
> [!IMPORTANT]
> **Audio Generation Change**: Transitioning from single-file audio to per-page or per-section audio to enable granular playback control. This may increase generation time slightly but improves the learning experience significantly.

> [!WARNING]
> **Data Migration**: Existing stories will remain as legacy "plain text" stories. New stories will use the new `contentJSON` format. The UI will need to handle both formats or we migrate old stories (parsing them would be hard). I propose supporting both formats in the UI for now.

## Proposed Changes

### Models
#### [NEW] `StoryModels.swift`
Create new Codable structs to represent the structured data.
```swift
struct StoryContent: Codable {
    let title: String
    let topic: String
    let style: String
    let pages: [StoryPage]
    let questions: [QuizQuestion]
}

struct StoryPage: Codable, Identifiable {
    var id: UUID = UUID()
    let pageNumber: Int
    let targetText: String
    let nativeText: String
    let grammarPoint: String? // Optional note for this page
    let keywords: [String] // Words to highlight
    var audioFilename: String? // Local filename
    var imagePrompt: String? // For generating illustration
    var imageFilename: String? // Local filename
}

struct QuizQuestion: Codable, Identifiable {
    var id: UUID = UUID()
    let question: String
    let options: [String]
    let correctOptionIndex: Int
    let explanation: String
}
```

#### [MODIFY] `Story.swift`
- Add `contentJSON: String?` (or `Data`) to store the `StoryContent`.
- Keep existing fields for backward compatibility, but `targetLanguageText` might just be a concatenation of pages for legacy views if needed.

### Managers
#### [MODIFY] `OpenAIService.swift`
- Update `generateStory` to request `response_format: { type: "json_object" }` (which it already does, but we need a stricter schema).
- **Prompt Engineering**: meticulously design the system prompt to return the `StoryContent` JSON structure.
- **Helpers**: Add methods to generate audio for specific text segments (pages).

#### [MODIFY] `StoryManager.swift`
- Update `generateStory` workflow:
    1. Call OpenAI for `StoryContent` JSON.
    2. Parse JSON.
    3. (Parallel) Generate audio for each page.
    4. (Parallel) Generate cover image (and optional page images).
    5. Save all assets and the `Story` object with `contentJSON`.

### Views
#### [NEW] `StoryBookView.swift`
A new view to consume `StoryContent`.
- **Paged Layout**: `TabView` with page curling or simple sliding.
- **Page View**:
    - Top: Image (if available).
    - Middle: Target Text (large, readable).
    - Bottom: Controls (Play Audio, Show Translation, Show Grammar).
- **Quiz View**: Presented at the end.

#### [MODIFY] `StorySessionView.swift`
- Modify to detect if `contentJSON` exists.
- If yes, use `StoryBookView`.
- If no, use legacy scrolling text view.

## Verification Plan

### Automated Tests
- **Unit Tests**:
    - Test `StoryContent` JSON decoding with sample OpenAI responses.
    - Test `StoryManager` handles partial failures (e.g., audio fails but text succeeds).

### Manual Verification
1. **Generate a Story**:
    - Input a topic (e.g., "Going to the supermarket").
    - Preferences: Level 2, Spanish, Humor: High.
2. **Verify Output**:
    - Check console for JSON structure.
    - Ensure app validates and saves the `Story` object.
    - Open Story: Check if it loads into the new Paged View.
3. **Playback**:
    - Tap "Play" on Page 1 -> Verify audio plays for just that page.
    - Tap "Show Translation" -> Verify English text appears.
    - Swipe to Page 2 -> Verify audio stops/resets.
4. **Quiz**:
    - Go to end.
    - Answer questions. verify "Correct/Incorrect" feeback works.

## Appendix: Implementation Details

### JSON Structure Example
This is the structure we expect back from the AI model:

```json
{
  "title": "La Llave Perdida",
  "topic": "Finding a lost item",
  "style": "Mystery",
  "pages": [
    {
      "pageNumber": 1,
      "targetText": "Hola, ¿dónde está mi llave?",
      "nativeText": "Hello, where is my key?",
      "grammarPoint": "Interrogatives: 'dónde' means 'where'.",
      "keywords": ["llave", "dónde"]
    },
    {
      "pageNumber": 2,
      "targetText": "Busco en la mesa.",
      "nativeText": "I search on the table.",
      "keywords": ["buscar", "mesa"]
    }
  ],
  "questions": [
    {
      "question": "What is lost?",
      "options": ["The dog", "The key", "The book"],
      "correctOptionIndex": 1,
      "explanation": "The protagonist is looking for 'la llave' (the key)."
    }
  ]
}
```

### Cost Analysis
**Audio Generation**:
- **Cost Impact**: *Negligible / Identical*. OpenAI TTS is priced per character. Since the total text length remains the same whether generated as one big block or multiple small blocks, the cost is the same.
- **Performance**: Generating many small audio files might take slightly longer in total wall-clock time due to request overhead, but allows us to stream/play the first page faster.

**Token Usage**:
- **Input Tokens**: Slightly *higher* (~100-200 tokens) due to the more complex system prompt defining the JSON schema.
- **Output Tokens**: Slightly *higher* due to repeating field names ("targetText", "nativeText") in the JSON structure compared to plain text. However, this is minimal compared to the story content itself.
