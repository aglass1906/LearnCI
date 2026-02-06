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
    
    func generateChallenge(for card: LearningCard, distractors: [LearningCard]) -> ClozeChallenge {
        // 1. Choose the missing word
        let sentence = card.sentenceTarget
        let missingWord = selectMissingWord(from: sentence)
        
        // 2. Create the blanked sentence
        // Case insensitive replacement to preserve original punctuation if possible,
        // but exact match replacement is safer for now.
        // We assume 'missingWord' was extracted directly from the string, so it matches casing.
        let sentenceWithBlank = sentence.replacingOccurrences(of: missingWord, with: "_______")
        
        // 3. Generate Options
        var options: [String] = [missingWord]
        
        // Pick 3 random distractors from other cards
        // Ideally we want words of similar length/type, but random is fine for V1.
        let shuffledDistractors = distractors.shuffled().prefix(3)
        for distractor in shuffledDistractors {
            options.append(distractor.wordTarget)
        }
        
        // If we don't have enough distractors (e.g. deck too small), fill with placeholders?
        // Or just duplication. For now, assume deck > 4 cards.
        
        return ClozeChallenge(
            card: card,
            sentenceWithBlank: sentenceWithBlank,
            missingWord: missingWord,
            options: options.shuffled()
        )
    }
    
    private func selectMissingWord(from sentence: String) -> String {
        // Simple strategy: Pick longest word that isn't a particle?
        // Or specific word matching card.wordTarget if present in sentence?
        
        let words = sentence.components(separatedBy: CharacterSet.punctuationCharacters.union(.whitespaces))
            .filter { !$0.isEmpty }
        
        // Preference: Words > 3 chars
        let candidates = words.filter { $0.count > 3 }
        
        if let randomCandidate = candidates.randomElement() {
            return randomCandidate
        }
        
        // Fallback: Pick any word
        return words.randomElement() ?? ""
    }
}
