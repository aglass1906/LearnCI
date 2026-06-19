import Foundation
import SwiftData

@Observable
@MainActor
final class SavedStudyWordManager {
    private let openAIService: OpenAIService

    init(openAIService: OpenAIService = OpenAIService()) {
        self.openAIService = openAIService
    }

    @discardableResult
    func save(
        capture: SavedStudyWordCapture,
        in context: ModelContext,
        enrich: Bool = true
    ) -> SavedStudyWord? {
        let trimmedWord = capture.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return nil }

        let normalized = SavedStudyWord.normalize(trimmedWord)
        let userID = capture.userID
        let languageCode = capture.languageCode
        let sourceTypeRaw = capture.sourceType.rawValue
        let sourceId = capture.sourceId
        let descriptor = FetchDescriptor<SavedStudyWord>(
            predicate: #Predicate {
                $0.userID == userID &&
                $0.normalizedWord == normalized &&
                $0.languageCode == languageCode &&
                $0.sourceTypeRaw == sourceTypeRaw &&
                $0.sourceId == sourceId
            }
        )

        let savedWord: SavedStudyWord
        if let existing = try? context.fetch(descriptor).first {
            existing.merge(capture: capture)
            savedWord = existing
        } else {
            let newWord = SavedStudyWord(capture: capture)
            context.insert(newWord)
            savedWord = newWord
        }

        try? context.save()

        if enrich, shouldEnrich(savedWord) {
            Task {
                await enrichSavedWord(savedWord.id, in: context)
            }
        }

        return savedWord
    }

    func isSaved(
        word: String,
        userID: String,
        languageCode: String,
        sourceType: SavedStudyWordSourceType,
        sourceId: String,
        in context: ModelContext
    ) -> Bool {
        let normalized = SavedStudyWord.normalize(word)
        let sourceTypeRaw = sourceType.rawValue
        let descriptor = FetchDescriptor<SavedStudyWord>(
            predicate: #Predicate {
                $0.userID == userID &&
                $0.normalizedWord == normalized &&
                $0.languageCode == languageCode &&
                $0.sourceTypeRaw == sourceTypeRaw &&
                $0.sourceId == sourceId
            }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    private func shouldEnrich(_ word: SavedStudyWord) -> Bool {
        word.translation?.isEmpty != false ||
        word.lemma?.isEmpty != false ||
        word.partOfSpeech?.isEmpty != false ||
        word.level?.isEmpty != false
    }

    private func enrichSavedWord(_ id: UUID, in context: ModelContext) async {
        let descriptor = FetchDescriptor<SavedStudyWord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let savedWord = try? context.fetch(descriptor).first else { return }

        do {
            let analysis = try await openAIService.analyzeStudyWord(
                savedWord.word,
                languageCode: savedWord.languageCode,
                context: savedWord.sentenceTarget,
                existingTranslation: savedWord.translation,
                existingLevel: savedWord.level
            )
            savedWord.applyAnalysis(analysis)
            try? context.save()
        } catch {
            Logger.error("Saved word enrichment failed for '\(savedWord.word)': \(error.localizedDescription)", category: .general)
        }
    }
}
