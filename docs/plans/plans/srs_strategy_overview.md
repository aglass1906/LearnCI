# Spaced Repetition (SRS) Strategy - Phase 1

## Overview: Intra-Session Smart Queue
The current implementation of the Spaced Repetition System (SRS) focuses on an **Intra-Session Smart Queue**. This system optimizes your learning within a single study session by dynamically re-queuing cards based on your performance.

Unlike traditional SRS which schedules cards days or weeks in the future, the **Smart Queue** ensures you master the difficult material *right now* before finishing your session.

## Core Concepts

### 1. The Queue
*   **Dynamic Ordering**: The session starts with a selected number of cards (e.g., 20).
*   **Re-queuing**: When you grade a card, it is immediately re-inserted into the queue based on your feedback.
*   **Completion**: The session ends only when the queue is empty (i.e., when you have marked all cards as "Easy" or "Mastered").

### 2. The Grading System
Instead of a simple Pass/Fail, you grade your confidence on a 4-point scale:

*   **Again (Fail)**:
    *   **Meaning**: I didn't know this card.
    *   **Action**: The card is re-queued near 25% of the remaining deck. You will see it again very soon.
*   **Hard**:
    *   **Meaning**: I knew it, but it took significant effort.
    *   **Action**: The card is placed near the middle (50%) of the remaining deck.
*   **Good**:
    *   **Meaning**: I knew it with some thought.
    *   **Action**: The card is placed near the end (100%) of the current queue for a final confirmation.
*   **Easy**:
    *   **Meaning**: I knew it instantly and confidently.
    *   **Action**: The card is considered "Mastered" for this session and is **removed from the queue**.

### 3. Session Flow
1.  **Selection**: You choose a deck and a card limit (e.g., 20 cards).
2.  **Initial Pool**: If the deck is larger than the limit, a random subset of 20 cards is selected.
3.  **Review Loop**: You review cards one by one.
    *   If you mark a card as **Again**, **Hard**, or **Good**, it stays in the session.
    *   If you mark it as **Easy**, your "Learned Count" increases, and the card exits the session.
4.  **Finish**: The session finishes when all cards have been marked "Easy".

## Future Roadmap (Phase 2)
The next phase will extend this logic to long-term scheduling (Inter-Session), where "Easy" cards are pushed to future dates, and "Hard" cards appear in tomorrow's session.
