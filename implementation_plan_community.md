# Phase 1: Authentication & Cloud Sync Foundation

This plan outlines the transition from a single-user local application to a multi-user platform. We will use **Supabase** (Postgres + Auth) as the backend to provide a robust foundation for the community.

## User Review Required

> [!IMPORTANT]
> **Supabase Setup**
> To proceed with this plan, you will need to:
> 1. Create a project at [supabase.com](https://supabase.com).
> 2. Enable **Google Auth** in the Supabase Dashboard (to keep your existing Google Sign-In flow).
> 3. Provide the `SupabaseURL` and `AnonKey` to the app.

## Proposed Changes

### [Models]

#### [MODIFY] [UserProfile.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Models/UserProfile.swift)
- Add `userID: String` property to associate the local profile with the cloud account.
- Add `isPublic: Bool` flag to control visibility in the community.
- Add `updatedAt: Date` for sync resolution.

#### [MODIFY] [UserActivity.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Models/UserActivity.swift)
- Add `userID: String` property.
- Add `isSynced: Bool` (local-only flag) to track records that haven't reached the cloud.

---

### [Managers]

#### [NEW] [AuthManager.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Managers/AuthManager.swift)
- Wrapper for `SupabaseAuth`.
- Handles Sign-In, Sign-Up, and Sign-Out transitions.
- Exposes an `isAuthenticated` state to the UI.

#### [MODIFY] [DataManager.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Managers/DataManager.swift)
- Implement `syncWithCloud()`:
    - Push local `UserActivity` to Supabase where `isSynced == false`.
    - Fetch and merge `UserProfile` settings if the user logs in on a new device.

---

### [Views]

#### [NEW] [AuthView.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Views/AuthView.swift)
- A dedicated login/signup screen for new users.
- Support for Google Sign-In.

#### [MODIFY] [MainTabView.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Views/MainTabView.swift)
- Conditional view: Show `AuthView` if the user is not logged in.
- Show `MainTabView` once the session is active.

---

## Verification Plan

### Automated Tests
- Integration tests to verify data serialization to Supabase.
- Unit tests for the "Conflict Resolution" logic (choosing between local vs. cloud profile).

### Manual Verification
1. **Login Flow**: Log in as User A, record activity. Log out.
2. **Persistence**: Log in as User B, verify User A's activity is not visible.
3. **Cross-Device Sync**: Log in as User A on another device (or simulator) and verify activity history is restored.
