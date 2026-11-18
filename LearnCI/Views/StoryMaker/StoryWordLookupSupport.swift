import SwiftUI
import SwiftData
import Translation

struct StoryWordLookupRequest {
    let word: String
    let time: Double?
    let endTime: Double?
    let context: String?
    let wordIndex: Int?
    let sourceText: String?

    init(word: String, time: Double?, endTime: Double? = nil, context: String?, wordIndex: Int? = nil, sourceText: String? = nil) {
        self.word = word
        self.time = time
        self.endTime = endTime
        self.context = context
        self.wordIndex = wordIndex
        self.sourceText = sourceText
    }
}

struct StoryStudyWordAudioResolution {
    let sourceUrl: String?
    let mediaStart: Double?
    let mediaEnd: Double?
}

enum StoryStudyWordAudioResolver {
    static func resolve(
        story: Story,
        request: StoryWordLookupRequest?,
        fallbackWord: String,
        fallbackContext: String?
    ) -> StoryStudyWordAudioResolution? {
        let candidates = makeCandidates(story: story)
        guard !candidates.isEmpty else { return nil }

        if let request,
           let sourceText = request.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceText.isEmpty,
           let wordIndex = request.wordIndex {
            for candidate in candidates where textsLikelyMatch(sourceText, candidate.text) {
                if let resolution = resolveByWordIndex(candidate: candidate, wordIndex: wordIndex, phrase: request.word) {
                    return resolution
                }
            }
        }

        let lookupText = fallbackContext?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyStoryAudio
            ?? request?.context?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyStoryAudio
            ?? request?.word.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyStoryAudio
            ?? fallbackWord.trimmingCharacters(in: .whitespacesAndNewlines)

        for candidate in candidates {
            if let resolution = resolveByText(candidate: candidate, lookupText: lookupText) {
                return resolution
            }
        }

        let fallbackWord = fallbackWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackWord.isEmpty else { return nil }
        for candidate in candidates {
            if let resolution = resolveByText(candidate: candidate, lookupText: fallbackWord) {
                return resolution
            }
        }

        return nil
    }

    private struct Candidate {
        let text: String
        let timings: [WordTiming]
        let sourceUrl: String?
    }

    private struct Token {
        let value: String
    }

    private static func makeCandidates(story: Story) -> [Candidate] {
        var candidates: [Candidate] = []
        let targetCode = story.targetLanguageCode

        for chapter in story.chapters {
            let chapterText = chapter.bodyTextForLanguage(targetCode).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chapterText.isEmpty {
                candidates.append(Candidate(
                    text: chapterText,
                    timings: chapter.bodyWordTimingsForLanguage(targetCode),
                    sourceUrl: nil
                ))
            }

            let script = chapter.bodyScriptForLanguage(targetCode).trimmingCharacters(in: .whitespacesAndNewlines)
            let scriptTimings = chapter.bodyWordTimingsForLanguage(targetCode)
            if !script.isEmpty, !scriptTimings.isEmpty {
                candidates.append(Candidate(text: script, timings: scriptTimings, sourceUrl: nil))
            }

            for scene in chapter.scenes.sorted(by: { $0.sceneIndex < $1.sceneIndex }) {
                let caption = scene.captionFor(targetCode).trimmingCharacters(in: .whitespacesAndNewlines)
                let text = (caption.isEmpty ? scene.scriptFor(targetCode) ?? "" : caption)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let timings = scene.wordTimingsFor(targetCode)
                if !text.isEmpty, !timings.isEmpty {
                    candidates.append(Candidate(text: text, timings: timings, sourceUrl: scene.audioUrlForLanguage(targetCode)))
                }
            }
        }

        for page in story.readingMatterPages {
            let text = page.bodyFor(targetCode).trimmingCharacters(in: .whitespacesAndNewlines)
            let timings = page.bodyWordTimingsFor(targetCode)
            if !text.isEmpty, !timings.isEmpty {
                candidates.append(Candidate(
                    text: text,
                    timings: timings,
                    sourceUrl: page.audioUrlFor(targetCode)
                ))
            }
        }

        return candidates.filter { !$0.timings.isEmpty }
    }

    private static func resolveByWordIndex(candidate: Candidate, wordIndex: Int, phrase: String) -> StoryStudyWordAudioResolution? {
        let tokenCount = max(1, tokens(in: phrase).count)
        let startIndex = wordIndex
        let endIndex = min(candidate.timings.count - 1, wordIndex + tokenCount - 1)
        guard startIndex >= 0, startIndex < candidate.timings.count, endIndex >= startIndex else { return nil }
        return resolution(candidate: candidate, startIndex: startIndex, endIndex: endIndex)
    }

    private static func resolveByText(candidate: Candidate, lookupText: String) -> StoryStudyWordAudioResolution? {
        let candidateTokens = tokens(in: candidate.text)
        let lookupTokens = tokens(in: lookupText)
        guard !candidateTokens.isEmpty, !lookupTokens.isEmpty else { return nil }

        let maxStart = candidateTokens.count - lookupTokens.count
        guard maxStart >= 0 else { return nil }

        for start in 0...maxStart {
            let end = start + lookupTokens.count
            if candidateTokens[start..<end].map(\.value) == lookupTokens.map(\.value) {
                return resolution(candidate: candidate, startIndex: start, endIndex: end - 1)
            }
        }

        return nil
    }

    private static func resolution(candidate: Candidate, startIndex: Int, endIndex: Int) -> StoryStudyWordAudioResolution? {
        guard candidate.timings.indices.contains(startIndex),
              candidate.timings.indices.contains(endIndex) else { return nil }
        return StoryStudyWordAudioResolution(
            sourceUrl: candidate.sourceUrl,
            mediaStart: candidate.timings[startIndex].start,
            mediaEnd: candidate.timings[endIndex].end
        )
    }

    private static func tokens(in text: String) -> [Token] {
        let nsText = text as NSString
        let regex = try? NSRegularExpression(pattern: "\\p{L}+", options: [])
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let value = String(text[range])
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            return Token(value: value)
        }
    }

    private static func textsLikelyMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.localizedCaseInsensitiveContains(rhs) || rhs.localizedCaseInsensitiveContains(lhs)
    }
}

private extension String {
    var nilIfEmptyStoryAudio: String? {
        isEmpty ? nil : self
    }
}

private struct StoryWordLookupActionKey: EnvironmentKey {
    static let defaultValue: ((StoryWordLookupRequest) -> Void)? = nil
}

extension EnvironmentValues {
    var storyWordLookupAction: ((StoryWordLookupRequest) -> Void)? {
        get { self[StoryWordLookupActionKey.self] }
        set { self[StoryWordLookupActionKey.self] = newValue }
    }
}

extension View {
    func storyWordLookupHost(story: Story) -> some View {
        modifier(StoryWordLookupHostModifier(story: story))
    }
}

private struct StoryWordLookupHostModifier: ViewModifier {
    let story: Story

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(SavedStudyWordManager.self) private var savedStudyWordManager
    @State private var selectedWord: String?
    @State private var selectedWordTime: Double?
    @State private var selectedContext: String?
    @State private var wordTranslation: String?
    @State private var wordPartOfSpeech: String?
    @State private var wordLookupDetails: WordTranslationResult?
    @State private var isTranslatingWord = false
    @State private var wordTranslationCache: [String: WordTranslationResult] = [:]
    @State private var wordTranslationConfiguration: TranslationSession.Configuration?
    @State private var selectedRequest: StoryWordLookupRequest?
    @State private var phraseSelectionStart: StoryWordLookupRequest?
    @State private var phraseSelectionMessage: String?
    @State private var savedStudyRevision = 0

    func body(content: Content) -> some View {
        content
            .environment(\.storyWordLookupAction) { request in
                if phraseSelectionStart != nil {
                    finishPhraseSelection(with: request)
                } else {
                    lookupWord(request)
                }
            }
            .overlay(alignment: .bottom) { phraseSelectionBanner }
            .translationTask(wordTranslationConfiguration) { session in
                await performHybridWordLookup(using: session)
            }
            .sheet(
                isPresented: Binding(
                    get: { selectedWord != nil },
                    set: { isPresented in
                        if !isPresented {
                            selectedWord = nil
                            selectedWordTime = nil
                            selectedContext = nil
                            wordTranslation = nil
                            wordPartOfSpeech = nil
                            wordLookupDetails = nil
                            isTranslatingWord = false
                            selectedRequest = nil
                        }
                    }
                )
            ) {
                WordLookupSheet(
                    word: selectedWord ?? "",
                    languageLabel: story.language.displayName,
                    translation: wordTranslation,
                    partOfSpeech: wordPartOfSpeech,
                    details: wordLookupDetails,
                    isLoading: isTranslatingWord,
                    seekTime: selectedWordTime,
                    onSeek: { _ in },
                    onSelectPhrase: canSelectPhrase ? { beginPhraseSelection() } : nil,
                    onMarkForStudy: {
                        markSelectedWordForStudy()
                    },
                    isMarkedForStudy: isSelectedWordSaved
                )
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
            }
    }

    private var canSelectPhrase: Bool {
        selectedRequest?.wordIndex != nil && selectedRequest?.sourceText?.isEmpty == false
    }

    private var isSelectedWordSaved: Bool {
        _ = savedStudyRevision
        guard let userID = authManager.currentUser,
              let selectedWord else { return false }
        return savedStudyWordManager.isSaved(
            word: selectedWord,
            userID: userID,
            languageCode: story.language.code,
            sourceType: .story,
            sourceId: story.id.uuidString,
            in: modelContext
        )
    }

    @ViewBuilder
    private var phraseSelectionBanner: some View {
        if let phraseSelectionStart {
            HStack(spacing: 10) {
                Image(systemName: "text.cursor")
                Text(phraseSelectionMessage ?? "Tap the last word in the phrase.")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Cancel") {
                    self.phraseSelectionStart = nil
                    phraseSelectionMessage = nil
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8, y: 4)
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityLabel("Selecting phrase starting with \(phraseSelectionStart.word)")
        }
    }

    private func lookupWord(_ request: StoryWordLookupRequest) {
        let trimmedWord = request.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }

        selectedRequest = request
        selectedWord = trimmedWord
        selectedWordTime = request.time
        selectedContext = request.context
        wordTranslation = nil
        wordPartOfSpeech = nil
        wordLookupDetails = nil

        let cacheKey = "\(trimmedWord.lowercased())_\(story.language.rawValue)_\(request.context ?? "")"
        if let cached = wordTranslationCache[cacheKey] {
            wordTranslation = cached.translation
            wordPartOfSpeech = cached.partOfSpeech
            wordLookupDetails = cached
            return
        }

        isTranslatingWord = true
        wordTranslationConfiguration = .init(
            source: Locale.Language(identifier: story.language.code),
            target: Locale.Language(identifier: story.nativeLanguageCode)
        )
    }

    private func performHybridWordLookup(using session: TranslationSession) async {
        guard let word = selectedWord else { return }
        let context = selectedContext
        let cacheKey = "\(word.lowercased())_\(story.language.rawValue)_\(context ?? "")"
        let sourceLanguage = story.language.displayName
        let targetLanguage = Locale.current.localizedString(forLanguageCode: story.nativeLanguageCode)
            ?? story.nativeLanguageCode

        async let enrichment = OpenAIService().translateWord(
            word,
            language: sourceLanguage,
            targetLanguage: targetLanguage,
            context: context
        )

        do {
            let nativeResponse = try await session.translate(word)
            wordTranslation = nativeResponse.targetText
            isTranslatingWord = false

            do {
                let enriched = try await enrichment
                let hybrid = enriched.replacingTranslation(with: nativeResponse.targetText)
                wordTranslation = hybrid.translation
                wordPartOfSpeech = hybrid.partOfSpeech
                wordLookupDetails = hybrid
                wordTranslationCache[cacheKey] = hybrid
            } catch {
                wordTranslationCache[cacheKey] = .translationOnly(nativeResponse.targetText)
                Logger.debug("OpenAI word enrichment unavailable: \(error.localizedDescription)", category: .general)
            }
        } catch {
            do {
                let fallback = try await enrichment
                wordTranslation = fallback.translation
                wordPartOfSpeech = fallback.partOfSpeech
                wordLookupDetails = fallback
                wordTranslationCache[cacheKey] = fallback
            } catch {
                wordTranslation = "Translation unavailable"
                wordPartOfSpeech = ""
                wordLookupDetails = nil
                Logger.error("Hybrid word lookup failed for '\(word)': \(error.localizedDescription)", category: .general)
            }
            isTranslatingWord = false
        }
    }

    private func markSelectedWordForStudy() {
        guard let userID = authManager.currentUser,
              let selectedWord else { return }
        let audioResolution = StoryStudyWordAudioResolver.resolve(
            story: story,
            request: selectedRequest,
            fallbackWord: selectedWord,
            fallbackContext: selectedContext
        )
        let capture = SavedStudyWordCapture(
            userID: userID,
            word: selectedWord,
            translation: wordTranslation,
            lemma: wordLookupDetails?.lemma,
            sentenceTarget: selectedContext,
            sentenceNative: nil,
            languageCode: story.language.code,
            level: wordLookupDetails?.level ?? String(story.level),
            partOfSpeech: wordPartOfSpeech,
            verbTense: wordLookupDetails?.verbTense,
            grammarNotes: wordLookupDetails?.grammarNotes,
            sourceType: .story,
            sourceId: story.id.uuidString,
            sourceTitle: story.title,
            sourceUrl: audioResolution?.sourceUrl,
            blockIndex: selectedRequest?.wordIndex,
            mediaStart: selectedWordTime ?? audioResolution?.mediaStart,
            mediaEnd: selectedRequest?.endTime ?? audioResolution?.mediaEnd,
            audioWordFile: nil,
            audioSentenceFile: nil,
            deckFolderName: nil
        )
        savedStudyWordManager.toggleSave(capture: capture, in: modelContext)
        savedStudyRevision += 1
    }

    private func beginPhraseSelection() {
        guard let selectedRequest, canSelectPhrase else { return }
        phraseSelectionStart = selectedRequest
        phraseSelectionMessage = "Tap the last word in the phrase."
        selectedWord = nil
        selectedWordTime = nil
        selectedContext = nil
        wordTranslation = nil
        wordPartOfSpeech = nil
        isTranslatingWord = false
    }

    private func finishPhraseSelection(with request: StoryWordLookupRequest) {
        guard let start = phraseSelectionStart,
              let sourceText = start.sourceText,
              sourceText == request.sourceText,
              let startIndex = start.wordIndex,
              let endIndex = request.wordIndex,
              let phrase = phraseText(in: sourceText, from: startIndex, to: endIndex) else {
            phraseSelectionStart = request.wordIndex == nil ? nil : request
            phraseSelectionMessage = "Phrase selection restarted. Tap the last word in this text block."
            return
        }

        phraseSelectionStart = nil
        phraseSelectionMessage = nil
        lookupWord(
            StoryWordLookupRequest(
                word: phrase,
                time: min(start.time ?? request.time ?? 0, request.time ?? start.time ?? 0),
                endTime: max(start.endTime ?? start.time ?? 0, request.endTime ?? request.time ?? 0),
                context: sentenceContaining(phrase: phrase, in: sourceText),
                sourceText: sourceText
            )
        )
    }

    private func phraseText(in text: String, from firstIndex: Int, to secondIndex: Int) -> String? {
        let matches = wordMatches(in: text)
        guard matches.indices.contains(firstIndex), matches.indices.contains(secondIndex) else { return nil }

        let lowerIndex = min(firstIndex, secondIndex)
        let upperIndex = max(firstIndex, secondIndex)
        let lowerBound = matches[lowerIndex].lowerBound
        let upperBound = matches[upperIndex].upperBound
        let phrase = text[lowerBound..<upperBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return phrase.isEmpty ? nil : phrase
    }

    private func wordMatches(in text: String) -> [Range<String.Index>] {
        let nsText = text as NSString
        let regex = try? NSRegularExpression(pattern: "\\p{L}+", options: [])
        return regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            .compactMap { Range($0.range, in: text) } ?? []
    }

    private func sentenceContaining(phrase: String, in text: String) -> String? {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
        return sentences
            .first(where: { $0.localizedCaseInsensitiveContains(phrase) })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TappableStoryText: View {
    let text: String
    var font: Font = .body
    var lineSpacing: CGFloat = 6
    var foregroundColor: Color = .primary
    var timings: [WordTiming] = []
    var currentTime: Double?
    var activeColor: Color = .blue
    var pastOpacity: Double? = nil

    @Environment(\.storyWordLookupAction) private var lookupAction

    var body: some View {
        Text(attributedText)
            .font(font)
            .lineSpacing(lineSpacing)
            .foregroundColor(foregroundColor)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "x-learnci-word",
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let word = components.queryItems?.first(where: { $0.name == "word" })?.value else {
                    return .systemAction
                }

                let queryItems = components.queryItems ?? []
                let time = queryItems.first(where: { $0.name == "t" })?.value.flatMap(Double.init)
                let endTime = queryItems.first(where: { $0.name == "e" })?.value.flatMap(Double.init)
                lookupAction?(
                    StoryWordLookupRequest(
                        word: word,
                        time: time,
                        endTime: endTime,
                        context: sentenceContaining(word: word, in: text),
                        wordIndex: queryItems.first(where: { $0.name == "i" })?.value.flatMap(Int.init),
                        sourceText: text
                    )
                )
                return .handled
            })
    }

    private var attributedText: AttributedString {
        var attrString = AttributedString(text)
        attrString.font = font
        attrString.foregroundColor = foregroundColor

        let nsText = text as NSString
        let regex = try? NSRegularExpression(pattern: "\\p{L}+", options: [])
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []

        for (index, match) in matches.enumerated() {
            guard let swiftRange = Range(match.range, in: text),
                  let lowerBound = AttributedString.Index(swiftRange.lowerBound, within: attrString),
                  let upperBound = AttributedString.Index(swiftRange.upperBound, within: attrString) else {
                continue
            }

            let word = String(text[swiftRange])
            let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
            let attrRange = lowerBound..<upperBound

            if index < timings.count {
                let timing = timings[index]
                attrString[attrRange].link = URL(string: "x-learnci-word://?word=\(encodedWord)&i=\(index)&t=\(timing.start)&e=\(timing.end)")

                if let currentTime {
                    let slack = 0.150
                    if currentTime >= timing.start - slack && currentTime <= timing.end + slack {
                        attrString[attrRange].foregroundColor = activeColor
                        attrString[attrRange].font = font.bold()
                    } else if let pastOpacity, currentTime > timing.end + slack {
                        attrString[attrRange].foregroundColor = foregroundColor.opacity(pastOpacity)
                    }
                }
            } else {
                attrString[attrRange].link = URL(string: "x-learnci-word://?word=\(encodedWord)&i=\(index)")
            }
        }

        return attrString
    }

    private func sentenceContaining(word: String, in text: String) -> String? {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
        return sentences
            .first(where: { $0.localizedCaseInsensitiveContains(word) })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
