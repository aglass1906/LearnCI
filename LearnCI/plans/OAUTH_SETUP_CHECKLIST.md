# OAuth Setup Verification Checklist

## ✅ Completed Steps

### 1. Google Cloud Project Setup
- [x] **GoogleSignIn Package Installed**
  - Package: `GoogleSignIn-iOS` (v9.0.0)
  - Dependencies resolved: GoogleSignIn, GoogleSignInSwift, AppAuth, GTMAppAuth, etc.
  
- [x] **Bundle ID Identified**
  - Your Bundle ID: `com.sankofaplex.LearnCI`
  - ⚠️ **Make sure this matches** the Bundle ID you entered in Google Cloud Console

## ⚠️ Remaining Configuration Steps

### 2. Info.plist Configuration (REQUIRED)

Your app needs URL scheme configuration for OAuth callback. You need to add this to your `Info.plist`:

**Option A: Using Xcode UI**
1. Open your project in Xcode
2. Select your target → Info tab
3. Add a new URL Type:
   - **Identifier**: `com.googleusercontent.apps.YOUR_CLIENT_ID`
   - **URL Schemes**: Your **reversed Client ID** (looks like `com.googleusercontent.apps.123456789-abc123...`)

**Option B: Manual XML** (if Info.plist exists)
Add this inside the `<dict>` tag:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
<key>GIDClientID</key>
<string>YOUR_CLIENT_ID.apps.googleusercontent.com</string>
```

**To find your Client ID:**
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Navigate to: APIs & Services → Credentials
3. Find your iOS OAuth client
4. Copy the **Client ID** (ends with `.apps.googleusercontent.com`)
5. The **reversed Client ID** is the part before `.apps.googleusercontent.com` but reversed
   - Example: If Client ID is `123456-abc.apps.googleusercontent.com`
   - Reversed: `com.googleusercontent.apps.123456-abc`

### 3. Code Implementation

Once Info.plist is configured, you'll need to update `YouTubeManager.swift` to use actual OAuth instead of the placeholder.

## 🧪 How to Test

After completing the above steps:

1. **Build the app** in Xcode (⌘+B) - should compile without errors
2. **Run on simulator or device**
3. Go to **Profile** tab
4. Tap **"Connect YouTube Account"**
5. OAuth should:
   - Open Safari/Google login
   - Ask for YouTube permissions
   - Redirect back to your app
   - Show "Connected" status

## ❓ Current Status

**What's Working:**
- ✅ GoogleSignIn package installed
- ✅ Bundle ID configured (`com.sankofaplex.LearnCI`)
- ✅ Manual account entry works (fallback)

**What Needs Configuration:**
- ⚠️ Info.plist URL scheme (required for OAuth callback)
- ⚠️ GIDClientID in Info.plist
- ⚠️ Update YouTubeManager to use real OAuth flow

## 📝 Next Steps

1. **Get your Client ID** from Google Cloud Console
2. **Configure Info.plist** with URL scheme and Client ID
3. Let me know when done, and I'll help update the OAuth implementation in `YouTubeManager.swift`

---

**Note**: The app currently works with manual account entry. OAuth is only needed if you want to fetch real YouTube data via the API.
