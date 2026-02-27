import Foundation

struct ClozeChallenge: Identifiable {
    let id = UUID()
    let card: LearningCard
    let sentenceWithBlank: String
    let missingWord: String
    let options: [String] // 1 correct + 3 distractors
}

class ClozeManager {
    static let shared = ClozeManager()
    
    private init() {}
    
    func generateChallenge(for card: LearningCard, distractors: [LearningCard], optionCount: Int = 4) -> ClozeChallenge {
        let targetCount = max(2, optionCount)

        // 1. Choose the missing word, preferring the card's target word
        let sentence = card.sentenceTarget
        let missingWord = selectMissingWord(from: sentence, preferring: card.wordTarget)

        // 2. Create the blanked sentence
        let sentenceWithBlank = sentence.replacingOccurrences(of: missingWord, with: "_______")

        // 3. Generate Options
        var options: [String] = [missingWord]

        let shuffledDistractors = distractors.shuffled()
        for distractor in shuffledDistractors {
            if options.count >= targetCount { break }
            let word = distractor.wordTarget
            if !options.contains(word) && !word.isEmpty {
                options.append(word)
            }
        }

        // Pad if not enough distractors (small deck)
        let sentenceWords = sentence.components(separatedBy: CharacterSet.punctuationCharacters.union(.whitespaces))
            .filter { !$0.isEmpty && $0 != missingWord }
        for word in sentenceWords.shuffled() {
            if options.count >= targetCount { break }
            if !options.contains(word) {
                options.append(word)
            }
        }

        if options.count < 2 {
            options.append("...")
        }

        return ClozeChallenge(
            card: card,
            sentenceWithBlank: sentenceWithBlank,
            missingWord: missingWord,
            options: options.shuffled()
        )
    }

    private func selectMissingWord(from sentence: String, preferring targetWord: String) -> String {
        // 1. Prefer the card's target word if it appears in the sentence
        if sentence.contains(targetWord) && targetWord.count > 1 {
            return targetWord
        }

        // 2. Fallback: pick a meaningful word (> 3 chars)
        let words = sentence.components(separatedBy: CharacterSet.punctuationCharacters.union(.whitespaces))
            .filter { !$0.isEmpty }
        let candidates = words.filter { $0.count > 3 }

        if let candidate = candidates.randomElement() {
            return candidate
        }

        // 3. Last resort: any non-empty word
        return words.first(where: { !$0.isEmpty }) ?? sentence.components(separatedBy: " ").first ?? ""
    }
}
