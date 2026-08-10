# GEMINI.md

This repository follows the **Agent OS** specification for AI context and standards management.

For full system architecture, build/test commands, and Agent OS standards, please refer to:

👉 **[AGENTS.md](AGENTS.md)**  
👉 **[agent-os Context Index](agent-os/standards/index.yml)**

## Quick Reference Commands

```bash
# Build project
xcodebuild build -project LearnCI.xcodeproj -scheme LearnCI -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'

# Run unit tests
xcodebuild test -project LearnCI.xcodeproj -scheme LearnCI -destination 'platform=iOS Simulator,name=iPhone 16'
```
