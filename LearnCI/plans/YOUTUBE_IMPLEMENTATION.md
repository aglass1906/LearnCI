# YouTube Integration Implementation Plan

Implementing YouTube video browsing, playback, and automatic time tracking for language learning.

## User Review Required

> [!IMPORTANT]
> **YouTube API Access**: This implementation requires a Google Cloud Project with YouTube Data API v3 enabled and OAuth 2.0 credentials configured. You'll need to:
> 1. Create a project at [Google Cloud Console](https://console.cloud.google.com)
> 2. Enable YouTube Data API v3
> 3. Create OAuth 2.0 credentials (iOS application)
> 4. Add the Client ID to the app configuration

> [!WARNING]
> **iOS Video Playback**: YouTube's Terms of Service restrict embedding their player in native apps. We have two compliant options:
> 1. **Open in YouTube app** (simpler, recommended) - Use deep links to open videos in the YouTube app, return to our app to log time manually
> 2. **WebView with YouTube embed** (complex) - Requires YouTube IFrame API, but tracking watch time is limited
> 
> **Recommended Approach**: Use the YouTube app with a simplified workflow where users select a video, tap "Watch", return to log actual watch time. This is ToS-compliant and simpler to implement.

## Proposed Changes

### Core Components

#### [NEW] [YouTubeManager.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Managers/YouTubeManager.swift)

Handles YouTube Data API integration:
- OAuth 2.0 authentication flow using `GoogleSignIn` SDK
- Fetch user's subscribed channels 
- Fetch videos from channels (filtered by language if possible)
- Store/retrieve OAuth tokens securely in Keychain
- Handle token refresh

**Dependencies**: Will use `GoogleSignIn-iOS` via Swift Package Manager

---

#### [NEW] [VideoView.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Views/VideoView.swift)

Main video browsing interface:
- Display loading state while fetching videos
- Grid/List of video thumbnails with title, channel, duration
- Search/filter videos by channel or keyword
- Tap video → Show video details sheet with:
  - Thumbnail, title, description, channel name
  - "Watch on YouTube" button → Opens YouTube app
  - "Log Watch Time" → Manual entry of minutes watched
- If not authenticated → Show "Connect YouTube" button → Launches OAuth flow

---

#### [NEW] [YouTubeVideo.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Models/YouTubeVideo.swift)

Data model for YouTube videos:
- `id`, `title`, `description`, `thumbnailURL`
- `channelTitle`, `duration`, `publishedAt`
- Codable for API response parsing

---

#### [MODIFY] [ProfileView.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Views/ProfileView.swift)

Add YouTube account management section:
- Display connection status (connected email or "Not Connected")
- "Connect YouTube Account" button if not connected
- "Disconnect" button if connected
- Show last sync timestamp

---

#### [MODIFY] [MainTabView.swift](file:///Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Views/MainTabView.swift)

Add new tab for Videos:
- Tab label: "Videos"
- Icon: `play.rectangle.fill`
- Position: Between "Learn" and "Activity"

---

### Time Tracking

Since we're opening videos in the YouTube app rather than embedding:

1. When user taps "Watch on YouTube": Store video start timestamp
2. When user returns to app: Show a prompt/alert asking "How many minutes did you watch?"
3. Save activity with `activityType: .watchingVideos`

Alternative: Add a "Log Watch Time" button on each video card for manual entry without opening YouTube.

---

## Verification Plan

### Setup
1. Configure Google Cloud Project and add credentials
2. Add `GoogleSignIn-iOS` package dependency
3. Configure URL scheme in Info.plist for OAuth callback

### Manual Testing
1. **Profile Connection**: 
   - Verify OAuth flow launches Safari/Google auth
   - Confirm successful connection shows user email
   - Test disconnect functionality
   
2. **Video Listing**:
   - Verify videos load from subscribed channels
   - Check thumbnail images display correctly
   - Test search/filter functionality
   
3. **Playback Flow**:
   - Tap video → Verify YouTube app opens
   - Return to app → Verify time logging prompt
   - Check activity saves correctly with `watchingVideos` type
   
4. **Activity Tracking**:
   - Verify logged video time appears in Activity tab
   - Check Dashboard displays video watching minutes
   - Confirm language association is correct
