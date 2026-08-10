# Agent OS Specifications Directory

This directory manages **Spec-Driven Development** for features, refactors, and system upgrades in LearnCI.

## Folder Structure

```text
agent-os/specs/
├── active/               # Features currently in planning or execution
│   └── YYYY-MM-DD-feature-name/
│       ├── shape.md      # Problem statement, requirements, and scope boundaries
│       ├── plan.md       # Technical architecture & implementation plan
│       └── tasks.md      # Granular task breakdown & verification steps
└── archive/              # Completed feature specifications
```

## Workflow Lifecycle

1. **Shape (`shape.md`)**: Define the goal, key requirements, user flows, and explicit non-goals/exclusions.
2. **Plan (`plan.md`)**: Document schema changes, affected SwiftUI views, `@Observable` state changes, DTO edits, and external APIs.
3. **Task Contracts (`tasks.md`)**: Break the work down into bounded tasks for coding agents, specifying exact file scopes and verification commands (`xcodebuild`).
4. **Archive**: Move completed feature folders into `specs/archive/` once fully verified and merged.
