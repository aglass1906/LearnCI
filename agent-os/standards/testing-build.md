# Build, CLI & Testing Standards

**Scope:** Xcode CLI commands, simulator destination setup, automated test execution, and verification rules.

---

## 1. CLI Build Verification Commands

When completing any code edit or subagent task, the change MUST be verified via command-line builds:

### Debug Build Command
```bash
xcodebuild build \
  -project LearnCI.xcodeproj \
  -scheme LearnCI \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Unit Test Execution Command
```bash
xcodebuild test \
  -project LearnCI.xcodeproj \
  -scheme LearnCI \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## 2. Simulator Launch Verification

To install and launch the compiled binary in an active simulator:

```bash
export DERIVED="./build/DerivedData"
export SIMULATOR="iPhone 16"

# Compile Debug binary
xcodebuild build -project LearnCI.xcodeproj -scheme LearnCI -configuration Debug -destination "platform=iOS Simulator,name=${SIMULATOR}" -derivedDataPath "$DERIVED"

# Boot and launch
xcrun simctl boot "${SIMULATOR}" 2>/dev/null || true
open -a Simulator
xcrun simctl install booted "${DERIVED}/Build/Products/Debug-iphonesimulator/LearnCI.app"
xcrun simctl launch booted com.sankofaplex.LearnCI
```

---

## 3. Strict Verification Guidelines

- **No Unverified Success Declarations**: Edits to `.swift` files are NOT complete until the project compiles cleanly via `xcodebuild`.
- **Log Inspection**: If a build fails, inspect `build_output.txt` or terminal output immediately before attempting repairs.
- **Simulator Availability**: If `iPhone 16` simulator is not installed, list available runtimes using `xcrun simctl list devices available` and use an available simulator device.
