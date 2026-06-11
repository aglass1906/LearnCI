import Foundation

/// Pedagogical strategy from `ci_profile_json` — mirrors Flutter [LearningStrategy].
enum LearningStrategy: String, Codable, CaseIterable, Equatable {
    case comprehensibleNarrative
    case vocabularyBuilder
    case grammarLadder
    case tprsCircling
    case freeVoluntary

    static func fromStorage(_ value: String?) -> LearningStrategy {
        guard let value, !value.isEmpty else { return .comprehensibleNarrative }
        if let match = LearningStrategy(rawValue: value) { return match }
        switch value {
        case "comprehensibleNarrative": return .comprehensibleNarrative
        case "vocabularyBuilder": return .vocabularyBuilder
        case "grammarLadder": return .grammarLadder
        case "tprsCircling": return .tprsCircling
        case "freeVoluntary": return .freeVoluntary
        default: return .comprehensibleNarrative
        }
    }

    var displayName: String {
        switch self {
        case .comprehensibleNarrative: return "Comprehensible Narrative"
        case .vocabularyBuilder: return "Vocabulary Builder"
        case .grammarLadder: return "Grammar Ladder"
        case .tprsCircling: return "TPRS Circling"
        case .freeVoluntary: return "Free Voluntary"
        }
    }

    var shortLabel: String {
        switch self {
        case .comprehensibleNarrative: return "Narrative"
        case .vocabularyBuilder: return "Vocab"
        case .grammarLadder: return "Grammar"
        case .tprsCircling: return "TPRS"
        case .freeVoluntary: return "Free"
        }
    }

    var description: String {
        switch self {
        case .comprehensibleNarrative:
            return "Story-first with light CI scaffolding. Natural prose, target words used where they fit."
        case .vocabularyBuilder:
            return "One target word per chapter, repeated heavily. Verbs are surfaced in multiple conjugated forms across the chapter. Quiz tests the chapter word."
        case .grammarLadder:
            return "Tenses introduced one per chapter, cumulative. Optimizer enforces isolation."
        case .tprsCircling:
            return "High-repetition: script asks/answers the same questions about target words."
        case .freeVoluntary:
            return "Loosest constraints. Story-first, vocabulary supportive but not required."
        }
    }

    /// SF Symbol names aligned with Flutter `learning_strategy_ui.dart` icons.
    var systemImage: String {
        switch self {
        case .comprehensibleNarrative: return "book"
        case .vocabularyBuilder: return "bookmark.square"
        case .grammarLadder: return "stairs"
        case .tprsCircling: return "arrow.clockwise"
        case .freeVoluntary: return "text.book.closed"
        }
    }
}

struct CiProfile: Codable, Equatable {
    var learningStrategy: LearningStrategy = .comprehensibleNarrative
    var learningObjective: String = ""
    var pedagogicalGoals: String = ""

    enum CodingKeys: String, CodingKey {
        case learningStrategy
        case learningObjective
        case pedagogicalGoals
    }

    init(
        learningStrategy: LearningStrategy = .comprehensibleNarrative,
        learningObjective: String = "",
        pedagogicalGoals: String = ""
    ) {
        self.learningStrategy = learningStrategy
        self.learningObjective = learningObjective
        self.pedagogicalGoals = pedagogicalGoals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent(String.self, forKey: .learningStrategy)
        learningStrategy = LearningStrategy.fromStorage(raw)
        learningObjective = try container.decodeIfPresent(String.self, forKey: .learningObjective) ?? ""
        pedagogicalGoals = try container.decodeIfPresent(String.self, forKey: .pedagogicalGoals) ?? ""
    }

    /// Stakeholder-facing learning profile summary (English / native language).
    var summaryText: String? {
        let objective = learningObjective.trimmingCharacters(in: .whitespacesAndNewlines)
        if !objective.isEmpty { return objective }
        let goals = pedagogicalGoals.trimmingCharacters(in: .whitespacesAndNewlines)
        return goals.isEmpty ? nil : goals
    }
}
