# Story Flow Redesign

Replaces the current direct list→session navigation with a richer 4-screen flow: **List → About → Session → Quiz**. The About page acts as a preview / decision point before the user commits to consuming the story.

## Flow Mockup

![Story Flow Mockup](/Users/alanglass/.gemini/antigravity/brain/1a9b39d8-489b-4dd9-b0eb-a683ccd3469f/story_flow_mockup_1772214738834.png)

## User Flow Description

```
Story List ──tap──▶ Story About Page ──"Start Listening"──▶ Session (read + listen) ──audio ends──▶ Quiz (full screen)
                         │
                         └── "Take Quiz" ──▶ Quiz (full screen)
```

> [!NOTE]
> **Tab bar hides on entry.** As soon as the user taps a story, the main tab bar is hidden for all three immersive screens (About, Session, Quiz), giving the full screen to content. Standard iOS back chevron handles return navigation. Tab bar reappears when the user pops back to the Story List.
> 
> Implementation: add `.toolbar(.hidden, for: .tabBar)` to `StoryAboutView`. Since About, Session, and Quiz are all pushed onto the same `NavigationStack`, the tab bar stays hidden across all three automatically.

1. **Story List** — unchanged except the `NavigationLink` destination changes from `StorySessionView` → `StoryAboutView`
2. **Story About Page** *(new)* — full hero at top, title, language + level badges, short description, two buttons:
   - **Start Listening** → pushes `StorySessionView` onto the stack
   - **Take Quiz** → pushes `StoryQuizView` directly (skips session)
3. **Session** — unchanged UI; on audio completion the `QuizBannerView` is replaced with an automatic `NavigationLink` push to `StoryQuizView`
4. **Quiz** *(promoted from sheet → full screen)* — `ComprehensionQuizSheet` content moved into `StoryQuizView` as a full `NavigationStack` destination with a back button

---

## Proposed Changes

### Navigation

#### [MODIFY] StoryListView.swift
- Change `NavigationLink(destination: StorySessionView)` → `NavigationLink(destination: StoryAboutView(story:))`

---

### New View

#### [NEW] StoryAboutView.swift
- `HeroMediaView` at top (same component from StorySessionView) — 42% height
- `.toolbar(.hidden, for: .tabBar)` — hides tab bar for About + all downstream screens
- Story title (large serif), language badge, level badge
- Story description (first 200 characters of `targetLanguageText` as a teaser)
- **Start Listening** button → `NavigationLink` to `StorySessionView`
- **Take Quiz** button → `NavigationLink` to `StoryQuizView`
- Story metadata: word count, estimated reading time, video style if present
- Back button (auto from NavigationStack)

---

### Session Completion → Quiz Navigation

#### [MODIFY] StorySessionView.swift
- Remove `QuizBannerView` and `showQuizBanner` state
- Add `@State private var navigateToQuiz = false`
- Where `showQuizBanner = true` was set (audio completion) → set `navigateToQuiz = true`
- Add `NavigationLink(destination: StoryQuizView(...), isActive: $navigateToQuiz)`
- Keep `showComprehensionQuiz` sheet for the overflow menu "Comprehension Quiz" shortcut
- Remove `QuizBannerView` import/usage

---

### Quiz Promoted to Full Screen

#### [NEW] StoryQuizView.swift
- Wraps the existing `ComprehensionQuizSheet` content as a full screen `View`
- Receives: `story: Story`, `preloadedQuestions: [ComprehensionQuestion]?`
- If `preloadedQuestions` is nil → generates quiz on appear (same `openQuiz()` logic)
- Full-screen layout: progress indicator at top, question card, answer tiles, back/skip
- On quiz complete: shows score + "Back to Stories" button (pops to root)

#### [MODIFY] StorySessionView.swift  
- Extract quiz generation logic (`openQuiz()`, `regenerateQuiz()`) into a shared helper or keep in session and pass questions to `StoryQuizView`
- Session pre-generates quiz in background as audio plays, so it's ready by the time the user finishes

---

## Verification Plan

### Build
- Clean build, no errors

### Manual Test Flow
1. Tap a story → lands on About page with hero, tab bar hidden
2. Tap **Start Listening** → Session opens
3. Let audio finish → Quiz opens automatically (full screen, not a banner)
4. Complete quiz → can navigate back to list, tab bar reappears
5. From About page → tap **Take Quiz** directly → Quiz opens (with loading state if not yet generated)
6. From Session overflow menu → "Comprehension Quiz" still reachable
