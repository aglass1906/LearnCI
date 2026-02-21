# Implementation Plan: Web Test Automation (LearnCI-web)

This plan outlines the recommended testing strategy for the `LearnCI-web` Next.js application to ensure reliability, performance, and a smooth user experience.

## Goal Description
Establish a robust, multi-layered testing automation framework that covers unit logic, component behavior, and end-to-end user flows.

## Test Script Lifecycle

### 1. Initial Creation (The "Baseline")
- **AI-Led Bootstrapping**: I will generate the initial test suite for the "Happy Paths" (e.g., successful login, deck loading, basic card playback).
- **Interactive Recorder**: I can use Playwright's `codegen` tool to record complex UI interactions as you or I perform them in a guided browser session, ensuring the tests perfectly match actual usage.
- **Unit Logic Verification**: I will identify and write tests for critical utility functions in the `utils/` and `lib/` directories.

### 2. Ongoing Maintenance & Growth
- **"New Feature, New Test" Policy**: For every new feature implementation, I will include a corresponding test script in the implementation plan.
- **Integrated Verification**: The test suite will be run as part of the "VERIFICATION" phase of every task I perform, ensuring no regressions are introduced.
- **Easy Updates**: If a UI change breaks a test (e.g., changing a button label), I will use the `codegen` or visual debugging tools to quickly update the selectors.
- **CI/CD Integration**: These tests are ready to be integrated into GitHub Actions or similar CI/CD pipelines to block broken code from being merged.

### Recommended Stack
- **Playwright**: For End-to-End (E2E) and Component testing. It's the modern standard—fast, reliable, and includes great debugging tools.
- **Vitest**: For Unit and Integration testing. It is built on Vite and is significantly faster than Jest while maintaining a similar API.
- **MSW (Mock Service Worker)**: To intercept network requests (Supabase) so tests are predictable and don't require a live database.

## Proposed Changes

### [NEW] [vitest.config.ts](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI-web/vitest.config.ts)
Configuration for Vitest to handle Next.js path aliases and React components.

### [NEW] [playwright.config.ts](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI-web/playwright.config.ts)
Configuration for Playwright, including browser settings and test directory structure.

### [NEW] [tests/](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI-web/tests/)
A organized directory structure for:
- `unit/`: For logic tests.
- `e2e/`: For full browser tests.
- `components/`: For visual component tests.

### [MODIFY] [package.json](file:///Users/alanglass/_dev_local/Learn%20Comp%20Input/LearnCI-web/package.json)
Adding testing scripts:
- `npm run test`: Run Vitest (unit tests).
- `npm run test:e2e`: Run Playwright tests.
- `npm run test:ui`: Open Playwright Test Runner UI.

## Verification Plan

### Automated Tests
1.  Run `npm run test` to verify unit test execution.
2.  Run `npx playwright install` followed by `npm run test:e2e` to verify E2E environment.
3.  Create a "Smoke Test" that visits the homepage and asserts the title.

### Manual Verification
1.  Open the Playwright UI (`npx playwright test --ui`) and show the user how to inspect test runs.
