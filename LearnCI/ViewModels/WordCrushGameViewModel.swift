import SwiftUI

struct MatchCelebration: Identifiable, Equatable {
    let id = UUID()
    let points: Int
    let streak: Int
    let word: String
}

struct WordCrushTile: Identifiable, Equatable {
    let id: UUID
    var word: String
    var cardId: String       // links back to LearningCard.id
    var isTarget: Bool       // true = target language, false = native
    var row: Int
    var col: Int
    var isMatched: Bool = false
    var isSelected: Bool = false
    var mediaFile: String?   // for image display mode
}

@Observable
class WordCrushGameViewModel {
    // Grid dimensions (from config)
    var columns: Int { config.wordCrushGridSize.columns }
    var rows: Int { config.wordCrushGridSize.rows }
    var tileCount: Int { columns * rows }

    // Game state
    var tiles: [WordCrushTile] = []
    var selectedTileId: UUID?
    var matchesFound: Int = 0
    var score: Int = 0
    var streak: Int = 0
    var isAnimating: Bool = false
    var shakeTileIds: Set<UUID> = []
    var matchCelebration: MatchCelebration?

    // Data
    var deck: CardDeck
    var sessionCards: [LearningCard]
    var config: GameConfiguration
    var sessionCardGoal: Int

    // Card pool for refilling
    private var cardPool: [LearningCard] = []
    private var cardPoolIndex: Int = 0
    private var batchErrors: [String: Bool] = [:]

    // Dependencies
    var audioManager: AudioManager?

    // Callbacks
    var onGrade: ((SmartSessionManager.Grade) -> Void)?
    var onMatchFound: (() -> Void)?
    var onFinish: (() -> Void)?

    init(deck: CardDeck, sessionCards: [LearningCard], config: GameConfiguration, sessionCardGoal: Int, onGrade: ((SmartSessionManager.Grade) -> Void)? = nil) {
        self.deck = deck
        self.sessionCards = sessionCards
        self.config = config
        self.sessionCardGoal = sessionCardGoal
        self.onGrade = onGrade
        setupGrid()
    }

    // MARK: - Setup

    func setupGrid() {
        tiles.removeAll()
        cardPoolIndex = 0

        let pairsNeeded = tileCount / 2

        // Build a shuffled pool of cards, repeating if needed
        var pool = sessionCards.shuffled()
        while pool.count < pairsNeeded {
            pool.append(contentsOf: sessionCards.shuffled())
        }
        cardPool = pool

        let initialCards = Array(cardPool.prefix(pairsNeeded))
        cardPoolIndex = pairsNeeded

        var newTiles: [WordCrushTile] = []
        for card in initialCards {
            newTiles.append(contentsOf: makeTilePair(for: card))
        }

        newTiles.shuffle()

        // Assign grid positions
        for i in newTiles.indices {
            newTiles[i].row = i / columns
            newTiles[i].col = i % columns
        }

        tiles = newTiles
    }

    // MARK: - Tile Selection

    func selectTile(_ tile: WordCrushTile) {
        guard !isAnimating, !tile.isMatched else { return }

        if let selectedId = selectedTileId {
            // Second selection
            if selectedId == tile.id {
                // Deselect
                deselectAll()
                return
            }

            guard let firstTile = tiles.first(where: { $0.id == selectedId }) else {
                deselectAll()
                return
            }

            // Check match: same cardId, different language side
            if firstTile.cardId == tile.cardId && firstTile.isTarget != tile.isTarget {
                handleMatch(tile1: firstTile, tile2: tile)
            } else {
                handleMismatch(tile1: firstTile, tile2: tile)
            }
        } else {
            // First selection
            selectedTileId = tile.id
            if let idx = tiles.firstIndex(where: { $0.id == tile.id }) {
                tiles[idx].isSelected = true
            }
            playAudio(for: tile)
        }
    }

    // MARK: - Audio

    private func playAudio(for tile: WordCrushTile) {
        guard tile.isTarget else { return }
        guard let card = sessionCards.first(where: { $0.id == tile.cardId })
                ?? deck.cards.first(where: { $0.id == tile.cardId }) else { return }

        if let audioFile = card.audioWordFile {
            audioManager?.playAudio(
                named: audioFile,
                folderName: deck.baseFolderName,
                text: card.wordTarget,
                language: deck.language,
                useFallback: config.useTTSFallback,
                ttsRate: config.ttsRate
            )
        } else {
            audioManager?.speak(
                text: card.wordTarget,
                language: deck.language,
                gender: config.ttsVoiceGender,
                rate: config.ttsRate
            )
        }
    }

    // MARK: - Match / Mismatch

    private func handleMatch(tile1: WordCrushTile, tile2: WordCrushTile) {
        isAnimating = true
        streak += 1
        let streakBonus = min(streak, 5) // Cap bonus at 5x
        score += 10 * streakBonus
        matchesFound += 1

        GameFeedbackManager.shared.match()

        // Show celebration
        let pointsEarned = 10 * streakBonus
        let matchedWord = tile1.isTarget ? tile1.word : tile2.word
        matchCelebration = MatchCelebration(points: pointsEarned, streak: streak, word: matchedWord.isEmpty ? tile2.word : matchedWord)

        // Mark as matched
        withAnimation(.easeOut(duration: 0.3)) {
            if let idx1 = tiles.firstIndex(where: { $0.id == tile1.id }) {
                tiles[idx1].isMatched = true
                tiles[idx1].isSelected = false
            }
            if let idx2 = tiles.firstIndex(where: { $0.id == tile2.id }) {
                tiles[idx2].isMatched = true
                tiles[idx2].isSelected = false
            }
        }
        selectedTileId = nil

        // Grade the card
        let grade: SmartSessionManager.Grade = batchErrors[tile1.cardId] == true ? .hard : .good
        if let card = sessionCards.first(where: { $0.id == tile1.cardId }) {
            SmartSessionManager.shared.completeBatch(cards: [card], grade: grade)
        }
        onMatchFound?()

        // End session when card goal is reached
        if matchesFound >= sessionCardGoal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onFinish?()
            }
            return
        }

        // Apply gravity + refill after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.applyGravity()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.refillGrid()
                self.isAnimating = false
            }
        }
    }

    private func handleMismatch(tile1: WordCrushTile, tile2: WordCrushTile) {
        streak = 0
        batchErrors[tile1.cardId] = true
        batchErrors[tile2.cardId] = true

        GameFeedbackManager.shared.incorrect()

        // Shake animation
        shakeTileIds = [tile1.id, tile2.id]

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.shakeTileIds.removeAll()
            self.deselectAll()
        }
    }

    private func deselectAll() {
        selectedTileId = nil
        for i in tiles.indices {
            tiles[i].isSelected = false
        }
    }

    // MARK: - Gravity

    func applyGravity() {
        // Process column by column: matched tiles leave gaps, tiles above fall down
        withAnimation(.easeIn(duration: 0.25)) {
            for col in 0..<columns {
                // Get non-matched tiles in this column, sorted by row (bottom to top)
                var columnTiles = tiles.filter { $0.col == col && !$0.isMatched }
                    .sorted { $0.row > $1.row }

                // Assign new rows from bottom up
                var currentRow = rows - 1
                for i in columnTiles.indices {
                    columnTiles[i].row = currentRow
                    currentRow -= 1
                }

                // Update the main tiles array
                for updated in columnTiles {
                    if let idx = tiles.firstIndex(where: { $0.id == updated.id }) {
                        tiles[idx].row = updated.row
                    }
                }
            }
        }
    }

    // MARK: - Refill

    func refillGrid() {
        // Remove matched tiles
        tiles.removeAll { $0.isMatched }

        let emptySlots = tileCount - tiles.count
        guard emptySlots > 0 else { return }

        // We need pairs (2 tiles per card), so calculate how many cards we need
        let pairsNeeded = emptySlots / 2

        var newTiles: [WordCrushTile] = []

        for _ in 0..<pairsNeeded {
            let card = nextCard()
            newTiles.append(contentsOf: makeTilePair(for: card))
        }

        // If odd slot remains, add a single random tile
        if emptySlots % 2 != 0 {
            let card = nextCard()
            let pair = makeTilePair(for: card)
            newTiles.append(pair[0])
        }

        newTiles.shuffle()

        // Find empty positions (top-first for drop-in effect)
        var occupied = Set(tiles.map { "\($0.row),\($0.col)" })
        var emptyPositions: [(row: Int, col: Int)] = []
        for r in 0..<rows {
            for c in 0..<columns {
                let key = "\(r),\(c)"
                if !occupied.contains(key) {
                    emptyPositions.append((r, c))
                }
            }
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            for i in newTiles.indices where i < emptyPositions.count {
                var tile = newTiles[i]
                tile.row = emptyPositions[i].row
                tile.col = emptyPositions[i].col
                tiles.append(tile)
            }
        }
    }

    private func nextCard() -> LearningCard {
        if cardPoolIndex >= cardPool.count {
            // Reshuffle and restart
            cardPool = sessionCards.shuffled()
            cardPoolIndex = 0
        }
        let card = cardPool[cardPoolIndex]
        cardPoolIndex += 1
        return card
    }

    // MARK: - Tile Factory

    private func makeTilePair(for card: LearningCard) -> [WordCrushTile] {
        switch config.wordCrushDisplayMode {
        case .wordToWord:
            return [
                WordCrushTile(id: UUID(), word: card.wordTarget, cardId: card.id, isTarget: true, row: 0, col: 0),
                WordCrushTile(id: UUID(), word: card.wordNative, cardId: card.id, isTarget: false, row: 0, col: 0)
            ]
        case .wordToSentence:
            return [
                WordCrushTile(id: UUID(), word: card.wordTarget, cardId: card.id, isTarget: true, row: 0, col: 0),
                WordCrushTile(id: UUID(), word: card.sentenceNative, cardId: card.id, isTarget: false, row: 0, col: 0)
            ]
        case .imageToWord:
            return [
                WordCrushTile(id: UUID(), word: "", cardId: card.id, isTarget: true, row: 0, col: 0, mediaFile: card.mediaFile),
                WordCrushTile(id: UUID(), word: card.wordNative, cardId: card.id, isTarget: false, row: 0, col: 0)
            ]
        }
    }

    // MARK: - Helpers

    func tilesAt(row: Int, col: Int) -> WordCrushTile? {
        tiles.first { $0.row == row && $0.col == col && !$0.isMatched }
    }

    func restartGame() {
        score = 0
        streak = 0
        matchesFound = 0
        batchErrors.removeAll()
        shakeTileIds.removeAll()
        selectedTileId = nil
        isAnimating = false
        setupGrid()
    }
}
