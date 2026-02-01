# User Signup and Verification Improvement Plan

## Goal Description
Improve the user signup and email verification flow. Currently, users are not clearly prompted to verify their email, and the verification link does not provide a seamless experience.

## User Flow Description
1.  **Signup on Phone**: User enters their details and taps "Create Account".
2.  **Wait for Verification**: The app **stops** there. It shows a screen saying "Check your email to verify your account." The user is *not* logged in yet.
    *   **Option**: If the email doesn't arrive, the user can tap "**Resend Email**".
3.  **Click Email Link**: The user opens their email and clicks the verification link.
4.  **Web Success Page**: This opens a webpage on their phone that says "Email Verified!" and shows an "**Open App**" button.
5.  **Back to App**: User taps "Open App", which re-opens the app. Now they can sign in and start using it.

## User Review Required
> [!NOTE]
> I have updated the plan to use the provided production URL: `https://learn-ci-web.vercel.app`.

## Proposed Changes

### iOS App (`LearnCI`)

#### [MODIFY] [AuthManager.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Managers/AuthManager.swift)
- **Fix Logic:** Remove the manual state update `self.state = .authenticated(...)` inside the `signUp` function.
- **Why:** This currently bypasses the "Check your email" screen by treating the user as fully authenticated immediately after signup request.
- **Enhancement:** Update `supabase.auth.signUp` call to include `redirectTo` parameter: `redirectTo: URL(string: "https://learn-ci-web.vercel.app/auth/callback?next=/auth/verified")`.
- **New Feature:** Add `resendVerificationEmail(email: String)` function using `supabase.auth.resend`.

#### [MODIFY] [AuthView.swift](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI/LearnCI/Views/AuthView.swift)
- **Enhancement:** Ensure `handlePrimaryAction` sets `showEmailConfirmation = true` (already does, but will now persist because state doesn't change).
- **New Feature:** Update `EmailConfirmationView` to include a "Resend Email" button that calls `authManager.resendVerificationEmail`.

### Web Portal (`LearnCI-web`)

#### [NEW] [app/auth/verified/page.tsx](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI-web/app/auth/verified/page.tsx)
- **Content:** Create a new page that says "Email Verified Successfully!".
- **Actions:**
    -   Button: "Open App" (Links to `learnci://`)
    -   Button: "Go to Portal" (Links to `/portal` or `/`)
- **Design:** Simple, clean layout matching the app's aesthetic.

#### [MODIFY] [app/auth/callback/route.ts](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI-web/app/auth/callback/route.ts)
- **Check:** Ensure it redirects to the `next` param. (Current implementation allows this, so no code change needed, just usage change in iOS).

## Verification Plan

### Manual Verification
1.  **iOS Signup:**
    -   Run the iOS app.
    -   Sign up with a new email.
    -   **Expected:** User stays on Auth screen, and "Check Your Email" sheet appears. User is NOT logged in.
2.  **Resend Flow (New):**
    -   On "Check Your Email" screen, tap "Resend Email".
    -   **Expected:** Success message ("Email resent").
3.  **Email Reception:**
    -   Check email for verification link.
    -   **Expected:** Link points to Web Portal.
4.  **Verification Flow:**
    -   Click the link.
    -   **Expected (Web):** Opens `/auth/callback` -> redirects to `/auth/verified`.
    -   **Expected (Page):** Shows "Email Verified". Shows "Open App" button.
5.  **Open App:**
    -   Click "Open App".
    -   **Expected:** Opens iOS app.
    -   **Manual Step:** User signs in.

### Questions for User
-   **Resolved:** Production domain is `https://learn-ci-web.vercel.app`.
