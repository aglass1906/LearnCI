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
