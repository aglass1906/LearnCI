# Supporting Website Implementation Plan

[Goal Description]
Create a modern, responsive supporting website for the "LearnCI" mobile application. The website will serve two primary audiences: end-users (for password resets and app information) and administrators (for managing user data and viewing feedback).

## User Review Required
> [!IMPORTANT]
> **Admin Access Control**: The plan proposes adding a simple `role` or `is_admin` field to the `profiles` table to manage admin access. If a different method (e.g., Supabase Auth Custom Claims) is preferred, please advise.
> **Deployment**: This plan covers the *development* of the website. Deployment (e.g., to Vercel) is a separate step but the stack is chosen to make it widely compatible.

## Proposed Tech Stack
- **Framework**: Next.js 14+ (App Router)
- **Language**: TypeScript
- **Styling**: Tailwind CSS + Shadcn UI (for a premium, consistent look)
- **Backend/Auth**: Supabase (Client SDK, sharing the existing project)

## Project Structure
The website will live in its own repository, `LearnCI-web`, separate from the iOS app.

```text
/Users/alanglass/Documents/dev/_AI/
├── LearnCI/                 # Existing iOS App Repo
└── LearnCI-web/             # [NEW] Supporting Website Repo (Next.js)
    ├── app/
    ├── components/
    └── package.json
```

## Proposed Features

### 1. Public Facing (End Users)
- **Landing Page**:
    - Hero section with App Store links.
    - specialized "Password Reset" page handling the reset token flow from Supabase emails.
    - Basic legal pages (Privacy Policy, Terms).
- **Authentication**:
    - Login page (for potential future user features and admin access).
- **Public Profiles ("Learning Resume")**:
    - If `is_public` is true, show a read-only page with user stats (Total Hours, Level, Streak).
    - Perfect for sharing progress on social media.
- **Web Journaling**:
    - Allow users to log into the web portal to type their **Coaching Check-ins** and **Daily Feedback** (easier than typing on phone).
- **Global Leaderboard**:
    - Read-only view of the top 50 learners (matching the app's logic).

### 2. Admin Dashboard (Protected)
- **Middleware Protection**: Routes under `/admin` restricted to users with admin privileges.
- **Dashboard Overview**:
    - Key metrics: Total Users, Active Users (last 7 days).
- **Data Views**:
    - **Feedback**: Table view of `daily_feedback` data.
    - **Check-ins**: Table view of `coaching_check_ins`.
    - **Users**: List of users/profiles.

## Implementation Steps

### Phase 1: Setup
#### [NEW] /../LearnCI-web (New Repository)
- Create a new directory `LearnCI-web` (sibling to `LearnCI`).
- Initialize new Next.js project.
- Install dependencies: `@supabase/ssr`, `@supabase/supabase-js`, `lucide-react`, `clsx`, `tailwind-merge`.
- Configure environment variables (Supabase URL/Key).

### Phase 2: Core Components & UI
#### [NEW] /../LearnCI-web/components
- Create reusable UI components (Buttons, Cards, Inputs) or install via Shadcn.
- Create `SupabaseProvider` or Client Component utilities.

### Phase 3: Public Features
#### [NEW] /../LearnCI-web/app/page.tsx
- Implement Landing Page.
#### [NEW] /../LearnCI-web/app/auth/callback/route.ts
- Handle Auth Code Exchange.
#### [NEW] /../LearnCI-web/app/reset-password/page.tsx
- Form to enter new password after clicking email link.

#### [NEW] /../LearnCI-web/app/u/[username]/page.tsx
- Public profile view (if enabled by user).
#### [NEW] /../LearnCI-web/app/portal/page.tsx
- User dashboard for logging check-ins/feedback.
#### [NEW] /../LearnCI-web/app/leaderboard/page.tsx
- Public leaderboard view.

### Phase 4: Admin Features
#### [NEW] /../LearnCI-web/app/admin/page.tsx
- Dashboard overview.
#### [NEW] /../LearnCI-web/app/admin/users/page.tsx
- List of all users with search/filter.
#### [NEW] /../LearnCI-web/app/admin/users/[id]/page.tsx
- Detailed view of a specific user:
    - Profile stats (Language, Level).
    - Activity history graph.
    - Coaching Check-ins history.
#### [NEW] /../LearnCI-web/app/admin/analytics/page.tsx
- Aggregate charts:
    - Most popular languages.
    - Average daily study time.
    - Daily Active Users (DAU) trend.

## Verification Plan

### Automated Tests
- **Build Test**: Run `npm run build` to ensure type safety and build success.
- **Lint**: Run `npm run lint`.

### Manual Verification
1. **Public Access**:
    - Visit `http://localhost:3000`. Verify Landing Page loads.
2. **Password Reset Flow**:
    - Trigger a reset from the mobile app (or manually via Supabase dashboard if needed).
    - Click link in email -> Verify it opens the local site (need to configure redirect URL in Supabase or manually paste link with updated port).
    - Enter new password -> Verify success message.
    - Login with new password.
3. **Admin Access**:
    - Login with a user account marked as admin.
    - Access `/admin`. Verify Dashboard loads.
    - Navigate to `/admin/feedback`. Verify data loads from Supabase.
    - Try accessing `/admin` as a non-admin user -> Verify redirect to home or 403.
