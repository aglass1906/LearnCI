# Feature: Story Comprehension Quiz

## Context
Adding AI-generated comprehension questions directly after a story closes the feedback loop — turning passive consumption into active recall. Questions are in the story's target language.

## Implementation Details
1. `ComprehensionQuestion` struct in `LearnCI/Models/Story.swift`
2. `generateComprehensionQuestions()` in `LearnCI/Managers/OpenAIService.swift`
3. UI in `LearnCI/Views/StoryMaker/StorySessionView.swift` (`QuizBannerView`, `ComprehensionQuizSheet`)
4. Supabase sync field `comprehension_questions_json` on `StoryDTO` in `SyncManager.swift`
