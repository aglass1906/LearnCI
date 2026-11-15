# LearnCI iOS Client

A native iOS language learning application built with **Swift 6**, **SwiftUI**, and **SwiftData**. LearnCI delivers immersive Comprehensible Input language acquisition through dramatized audio, synchronized text highlighting, interactive reading, and gamified study sessions.

---

## 🚀 Key Features

- **Immersive Dual-Mode Audio:** Dramatized, multi-voice character audio with background ambient soundscapes and word-by-word synchronized highlighting.
- **Interactive Reading & Quizzes:** Comprehension checks, multiple choice questions, and vocabulary assessment.
- **7 Vocabulary Games:** Flashcards, matching, audio-recognition, and interactive review sessions.
- **Dual-Persistence Sync:** Offline-first local persistence powered by **SwiftData**, paired with background synchronization to **Supabase** via dedicated Data Transfer Objects (DTOs).
- **CarPlay & Background Audio:** Lock-screen audio controls and automotive listening integration.

---

## 📂 Architecture Overview

- **State Management:** Swift `@Observable` macro on all ViewModels and Managers (injected at the root via `.environment()`).
- **DTO Separation:** Strict separation between SwiftData models and network models (`StoryDTO`, `PushStoryDTO`). SwiftData models are never passed directly to API boundaries.
- **Contracts Integration:** Uses the cross-platform Published Story Format V1 schema vendored in `LearnCITests/Fixtures/Contracts/`. Run `./scripts/sync-contracts.sh` to refresh from `LearnCI_Contracts`.
- **Backend Authority:** All database migrations, tables, and Edge Functions are managed canonically in [`LearnCI_Backend`](../LearnCI_Backend).

---

## 🛠️ Build & Verification

### Prerequisites
- macOS Sonoma or Sequoia
- Xcode 16+ with iOS 17+ / 18+ SDK
- CocoaPods or Swift Package Manager (dependencies managed via SPM)

### CLI Commands
Always execute build and test commands from this folder:

```bash
# Build for iOS Simulator (iPhone 17)
xcodebuild build -project LearnCI.xcodeproj -scheme LearnCI -destination 'platform=iOS Simulator,name=iPhone 17'

# Run Unit & Integration Tests
xcodebuild test -project LearnCI.xcodeproj -scheme LearnCI -destination 'platform=iOS Simulator,name=iPhone 17'

# Synchronize schemas & golden fixtures from LearnCI_Contracts
./scripts/sync-contracts.sh
```

---

## 📚 Developer Standards

For architecture guidelines, code styles, and agent protocols, refer to:
- [**`AGENTS.md`**](AGENTS.md) — Operational instructions for AI coding assistants.
- [**`agent-os/standards/`**](agent-os/standards/) — Deep-dive engineering standards covering SwiftUI state, SwiftData sync, and the game lifecycle.
