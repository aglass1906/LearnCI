# SwiftUI & State Management Standard

**Scope:** `LearnCI/` iOS application architecture, SwiftUI views, state management, and environment injection.

---

## 1. Core State Paradigm (`@Observable`)

- All state orchestrators, services, and managers MUST use the modern Swift `@Observable` macro (iOS 17+).
- **DO NOT** use deprecated `@Published` properties or `ObservableObject` conformance for new or refactored managers.
- State is injected into the view hierarchy via `.environment()` at the app entry point.

### Example Manager
```swift
import SwiftUI
import Observation

@Observable
final class ExampleManager {
    var isLoading: Bool = false
    var currentItem: Item?
    
    func fetchData() async {
        isLoading = true
        defer { isLoading = false }
        // Fetch logic
    }
}
```

---

## 2. App Entry Point & Environment Injection (`LearnCIApp.swift`)

- `LearnCIApp.swift` is the single source of truth for instantiating shared application managers.
- Shared state is registered on the root `WindowGroup` view using `.environment(...)`.
- Shared managers are accessible in views via `@Environment(ManagerType.self)`.

### SwiftData Schema Registration
All local persistence models must be registered explicitly in the `Schema` inside `LearnCIApp.swift`:
```swift
Schema([
    UserActivity.self,
    UserProfile.self,
    DailyFeedback.self,
    CoachingCheckIn.self,
    Favorite.self,
    Story.self,
    PodcastShow.self,
    PodcastEpisode.self
])
```

---

## 3. View Composition Rules

1. **Keep Views Small & Focused**: Decompose large views into modular subviews.
2. **Environment Access over Singletons**: Views MUST consume managers via `@Environment`, not via direct `Manager.shared` singletons.
3. **Async / Concurrency**: Use `Task` blocks or `.task { }` view modifiers for asynchronous work. Handle main-thread updates implicitly with `@Observable`.

---

## 4. Dashboard Card Pattern

- Dashboard cards MUST use `LayoutCardView` rather than recreating their own header, background, corner radius, shadow, or outer padding.
- Inside `DashboardView`, pass `appliesHorizontalPadding: false`; the dashboard content container owns the page-level horizontal inset.
- Choose an `accentColor` and SF Symbol `icon` that identify the card. Use the component's `title` and `subTitle` for the card header.
- Use the `destination` initializer when the entire card has one destination. For cards containing multiple independently actionable rows, use the static initializer and place plain-styled `NavigationLink` or `Button` rows inside its content.
- Nested rows should use `secondarySystemGroupedBackground`, a 12-point corner radius, and the dashboard's existing typography. Do not introduce a competing outer-card visual treatment.
- Dashboard sections should be composed with `DashboardCardGrid` when they belong to the adaptive card grid; full-width priority cards may sit above that grid but MUST still use `LayoutCardView`.
