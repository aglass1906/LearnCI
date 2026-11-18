# iOS Story Reader Update Plan

Plan for updating the LearnCI iOS story player to use the published story spine, chapter scene data, layout data, and scene-level audio contract.

## Goals

- Move the iOS story reader from chapter-audio-first playback to spine and scene-driven playback.
- Support scene-level audio, scene art, captions, dialogue lines, and merged word timings.
- Route reader modes via `StoryReaderFactoryView` (`.storyBook`, `.audioStory`, `.dialogStory`, `.comicBook`, `.pictureBook`).
