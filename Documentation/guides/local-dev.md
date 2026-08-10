# Local Development Guide

Command-line workflow for working with LearnCI locally — especially when pulling changes from a cloud agent branch or PR.

All commands assume you are in the project root:

```bash
cd /path/to/LearnCI
```

---

## Sync locally after cloud work (copy-paste)

When a cloud agent finishes a feature, copy this block and replace `<branch-name>` with the branch from the agent's summary:

```bash
git fetch origin
git checkout <branch-name>
git pull origin <branch-name>
```

Optional — review what changed before building:

```bash
git log --oneline main..HEAD
git diff --stat main...HEAD
```

Optional — open the PR in the browser (replace `<number>`):

```bash
gh pr view <number> --web
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

# Example checkout:
git checkout cursor/feature-branch-name
git pull origin cursor/feature-branch-name
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

---

## Supabase CLI & Operations

| Item | Value |
|------|--------|
| Project ref | `vuygqrbludhuywupcbma` |
| API URL | `https://vuygqrbludhuywupcbma.supabase.co` |
| Migrations | `supabase/migrations/` |
| Python scripts env | `scripts/.env` |

Push migrations:

```bash
supabase db push
```

Run SQL query:

```bash
supabase db execute --sql "select id, title from stories limit 5;"
```

---

## Python generation scripts

Create `scripts/.env`:

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

Set up virtual environment and run:

```bash
cd scripts
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

python3 generate_audio.py          # TTS via OpenAI / ElevenLabs
python3 generate_images.py         # Cover art via DALL-E 3
python3 generate_video.py          # Video via Google Veo
python3 generate_ambient_sounds.py
python3 check_media.py             # Verify asset completeness
```

---

## Related Documentation

- [AGENTS.md](../../AGENTS.md) — Architecture and Agent OS Index
- [Agent OS Index](../../agent-os/standards/index.yml) — Context standards index map
