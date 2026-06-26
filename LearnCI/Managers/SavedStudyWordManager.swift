import Foundation
import SwiftData
import Supabase
import PostgREST

@Observable
@MainActor
final class SavedStudyWordManager {
    private let authManager: AuthManager
    private let openAIService: OpenAIService

    init(authManager: AuthManager, openAIService: OpenAIService = OpenAIService()) {
        self.authManager = authManager
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
        schedulePush(savedWord.id, in: context)

        if enrich, shouldEnrich(savedWord) {
            Task {
                await enrichSavedWord(savedWord.id, in: context)
            }
        }

        return savedWord
    }

    @discardableResult
    func toggleSave(
        capture: SavedStudyWordCapture,
        in context: ModelContext,
        enrich: Bool = true
    ) -> Bool {
        let trimmedWord = capture.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return false }

        if isSaved(
            word: trimmedWord,
            userID: capture.userID,
            languageCode: capture.languageCode,
            sourceType: capture.sourceType,
            sourceId: capture.sourceId,
            in: context
        ) {
            remove(
                word: trimmedWord,
                userID: capture.userID,
                languageCode: capture.languageCode,
                sourceType: capture.sourceType,
                sourceId: capture.sourceId,
                in: context
            )
            return false
        }

        save(capture: capture, in: context, enrich: enrich)
        return true
    }

    func isSaved(
        word: String,
        userID: String,
        languageCode: String,
        sourceType: SavedStudyWordSourceType,
        sourceId: String,
        in context: ModelContext
    ) -> Bool {
        findSaved(
            word: word,
            userID: userID,
            languageCode: languageCode,
            sourceType: sourceType,
            sourceId: sourceId,
            in: context
        ) != nil
    }

    func remove(
        word: String,
        userID: String,
        languageCode: String,
        sourceType: SavedStudyWordSourceType,
        sourceId: String,
        in context: ModelContext
    ) {
        guard let existing = findSaved(
            word: word,
            userID: userID,
            languageCode: languageCode,
            sourceType: sourceType,
            sourceId: sourceId,
            in: context
        ) else { return }

        delete(existing, in: context)
    }

    func delete(_ word: SavedStudyWord, in context: ModelContext) {
        let wordID = word.id
        context.delete(word)
        try? context.save()
        scheduleRemoteDelete(wordID: wordID)
    }

    private func findSaved(
        word: String,
        userID: String,
        languageCode: String,
        sourceType: SavedStudyWordSourceType,
        sourceId: String,
        in context: ModelContext
    ) -> SavedStudyWord? {
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
        return try? context.fetch(descriptor).first
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
            schedulePush(id, in: context)
        } catch {
            Logger.error("Saved word enrichment failed for '\(savedWord.word)': \(error.localizedDescription)", category: .general)
        }
    }

    private func schedulePush(_ wordID: UUID, in context: ModelContext) {
        guard authManager.currentUser != nil else { return }
        Task {
            await pushSavedWord(id: wordID, in: context)
        }
    }

    private func scheduleRemoteDelete(wordID: UUID) {
        guard authManager.currentUser != nil else { return }
        Task {
            await deleteRemote(wordID: wordID)
        }
    }

    private func pushSavedWord(id: UUID, in context: ModelContext) async {
        let descriptor = FetchDescriptor<SavedStudyWord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let word = try? context.fetch(descriptor).first else { return }

        let dto = makeDTO(from: word)
        do {
            try await authManager.supabase.from("saved_study_words")
                .upsert(dto, onConflict: "id")
                .execute()
            word.isSynced = true
            try? context.save()
        } catch {
            if isMissingTableError(error) { return }
            word.isSynced = false
            try? context.save()
            Logger.error("Saved study word push failed for '\(word.word)': \(error.localizedDescription)", category: .general)
        }
    }

    private func deleteRemote(wordID: UUID) async {
        do {
            try await authManager.supabase.from("saved_study_words")
                .delete()
                .eq("id", value: wordID)
                .execute()
        } catch {
            if isMissingTableError(error) { return }
            Logger.error("Saved study word delete failed for \(wordID): \(error.localizedDescription)", category: .general)
        }
    }

    private func makeDTO(from word: SavedStudyWord) -> SavedStudyWordDTO {
        SavedStudyWordDTO(
            id: word.id,
            user_id: UUID(uuidString: word.userID) ?? UUID(),
            word: word.word,
            normalized_word: word.normalizedWord,
            lemma: word.lemma,
            translation: word.translation,
            sentence_target: word.sentenceTarget,
            sentence_native: word.sentenceNative,
            language_code: word.languageCode,
            level: word.level,
            part_of_speech: word.partOfSpeech,
            verb_tense: word.verbTense,
            grammar_notes: word.grammarNotes,
            source_type: word.sourceTypeRaw,
            source_id: word.sourceId,
            source_title: word.sourceTitle,
            source_url: word.sourceUrl,
            block_index: word.blockIndex,
            media_start: word.mediaStart,
            media_end: word.mediaEnd,
            audio_word_file: word.audioWordFile,
            audio_sentence_file: word.audioSentenceFile,
            deck_folder_name: word.deckFolderName,
            created_at: word.createdAt,
            updated_at: word.updatedAt
        )
    }

    private func isMissingTableError(_ error: Error) -> Bool {
        guard let postgrestError = error as? PostgrestError else { return false }
        return postgrestError.code == "PGRST205"
    }
}
