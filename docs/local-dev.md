# Local Development Guide

Command-line workflow for working with LearnCI locally — especially when pulling changes from a cloud agent branch or PR.

All commands assume you are in the project root:

```bash
cd /path/to/LearnCI
```

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| **macOS + Xcode** | Build and run the iOS app, run simulator |
| **Git** | Pull branches, review diffs, merge PRs |
| **Supabase CLI** (optional) | Apply migrations, run SQL against remote DB |
| **Python 3** (optional) | AI generation scripts in `scripts/` |
| **GitHub CLI** (`gh`, optional) | Check out PRs from the terminal |

---

## Git: get cloud agent work onto your machine

Cloud agent branches use this naming pattern:

```text
cursor/<descriptive-name>-af71
```

### Fetch and check out a branch

```bash
git fetch origin
git branch -a
git status -sb

# Example: playback fix branch
git checkout cursor/story-playback-chapter-intro-reading-matter-af71
git pull origin cursor/story-playback-chapter-intro-reading-matter-af71
```

### Review changes before building

```bash
# Commits on this branch vs main
git log --oneline main..HEAD

# Files changed
git diff --stat main...HEAD

# Full diff
git diff main...HEAD
```

### Check out a PR without knowing the branch name

```bash
gh pr checkout 5
```

Or manually:

```bash
git fetch origin pull/5/head:pr-5-playback
git checkout pr-5-playback
```

### After a PR is merged

```bash
git checkout main
git pull origin main

# Optional: delete local feature branch
git branch -d cursor/story-playback-chapter-intro-reading-matter-af71
```

### Push your own follow-up fixes

```bash
git add path/to/changed/file.swift
git commit -m "Describe your change"
git push -u origin cursor/your-branch-name-af71
```

---

## iOS: build, test, and run (Mac only)

List available simulators:

```bash
xcrun simctl list devices available
```

Set convenience variables:

```bash
export SIMULATOR="iPhone 16"
export DERIVED="./build/DerivedData"
```

### Build

```bash
xcodebuild build \
  -project LearnCI.xcodeproj \
  -scheme LearnCI \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=${SIMULATOR}" \
  -derivedDataPath "$DERIVED"
```

If the build fails on signing, open the project once in Xcode and confirm **Signing & Capabilities** is configured for the `LearnCI` target.

### Run unit tests

```bash
xcodebuild test \
  -project LearnCI.xcodeproj \
  -scheme LearnCI \
  -destination "platform=iOS Simulator,name=${SIMULATOR}" \
  -derivedDataPath "$DERIVED"
```

### Install and launch in the simulator

```bash
APP="${DERIVED}/Build/Products/Debug-iphonesimulator/LearnCI.app"

xcrun simctl boot "${SIMULATOR}" 2>/dev/null || true
open -a Simulator
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.sankofaplex.LearnCI
```

### Rebuild after edits

```bash
xcodebuild build \
  -project LearnCI.xcodeproj \
  -scheme LearnCI \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=${SIMULATOR}" \
  -derivedDataPath "$DERIVED"

xcrun simctl install booted "${DERIVED}/Build/Products/Debug-iphonesimulator/LearnCI.app"
xcrun simctl launch booted com.sankofaplex.LearnCI
```

### Xcode GUI (often easier for UI work)

```bash
open LearnCI.xcodeproj
```

Then **⌘R** to run, **⌘U** to test.

---

## Supabase

| Item | Value |
|------|--------|
| Project ref | `vuygqrbludhuywupcbma` |
| API URL | `https://vuygqrbludhuywupcbma.supabase.co` |
| Migrations | `supabase/migrations/` |
| Python scripts env | `scripts/.env` |

The iOS app connects to Supabase for auth, database sync, and storage. Sign in inside the app with Google to test synced stories and media.

Storage paths used by stories:

```text
audio-stories/{userID}/{storyID}/audio.m4a
audio-stories/{userID}/{storyID}/chapter_{n}.m4a
story-covers/{userID}/{storyID}/cover.jpg
story-videos/{userID}/{storyID}/video.mp4
```

---

## Supabase CLI

Install on Mac:

```bash
brew install supabase/tap/supabase
```

Log in and link the project (one-time):

```bash
supabase login
supabase link --project-ref vuygqrbludhuywupcbma
```

Check link status:

```bash
supabase projects list
cat supabase/.temp/project-ref
```

### Local Supabase stack (optional)

```bash
supabase start
supabase db reset    # applies everything in supabase/migrations/
```

### Push migrations to the remote project

After adding or pulling a file under `supabase/migrations/`:

```bash
supabase db push
```

### Run SQL against the linked remote project

```bash
supabase db execute --sql "select id, title from stories limit 5;"
```

Or open the dashboard:

```bash
supabase dashboard
```

### Cursor / cloud agent MCP

The repo includes `.mcp.json` so agents can run SQL and apply migrations via Supabase MCP. Do not commit personal access tokens. Prefer `supabase login` for your own terminal work.

---

## Python generation scripts

Create `scripts/.env` (not committed to git):

```bash
cat > scripts/.env <<'EOF'
SUPABASE_URL=https://vuygqrbludhuywupcbma.supabase.co
SUPABASE_KEY=your-anon-or-service-role-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
OPENAI_API_KEY=your-openai-key
ELEVENLABS_API_KEY=your-elevenlabs-key
GEMINI_API_KEY=your-gemini-key
EOF
```

Get Supabase keys from [Project Settings → API](https://supabase.com/dashboard/project/vuygqrbludhuywupcbma/settings/api).

Set up the virtual environment:

```bash
cd scripts
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Common commands:

```bash
python3 generate_audio.py          # TTS via OpenAI / ElevenLabs
python3 generate_images.py         # Cover art via DALL-E 3
python3 generate_video.py          # Video via Google Veo
python3 generate_ambient_sounds.py
python3 check_media.py             # Verify asset completeness
```

---

## End-to-end workflow after a cloud agent finishes

```bash
# 1. Pull the agent branch
git fetch origin
git checkout cursor/your-branch-name-af71
git pull origin cursor/your-branch-name-af71

# 2. Review what changed
git log --oneline main..HEAD
git diff --stat main...HEAD

# 3. Build and run (Mac)
xcodebuild build \
  -project LearnCI.xcodeproj \
  -scheme LearnCI \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath ./build/DerivedData

open LearnCI.xcodeproj   # ⌘R to run on simulator

# 4. If a DB migration was included
supabase db push

# 5. Merge when satisfied
git checkout main
git pull origin main
git merge cursor/your-branch-name-af71
git push origin main
```

Or merge via GitHub PR instead of local merge.

---

## Quick reference

| Goal | Command |
|------|---------|
| Get latest agent work | `git fetch origin && git checkout <branch> && git pull origin <branch>` |
| Compare to main | `git diff main...HEAD` |
| Build iOS app | `xcodebuild build -project LearnCI.xcodeproj -scheme LearnCI -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath ./build/DerivedData` |
| Run tests | `xcodebuild test -project LearnCI.xcodeproj -scheme LearnCI -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath ./build/DerivedData` |
| Apply Supabase migration | `supabase db push` |
| Regenerate story audio | `cd scripts && source venv/bin/activate && python3 generate_audio.py` |
| Verify story assets | `python3 check_media.py` |

---

## Related docs

- [CLAUDE.md](../CLAUDE.md) — architecture and build overview
- [docs/story reader/](story%20reader/) — story reader specs and data model
