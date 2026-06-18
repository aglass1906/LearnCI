import SwiftUI

struct StoryWordLookupRequest {
    let word: String
    let time: Double?
    let context: String?
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

    @State private var selectedWord: String?
    @State private var selectedWordTime: Double?
    @State private var selectedContext: String?
    @State private var wordTranslation: String?
    @State private var wordPartOfSpeech: String?
    @State private var isTranslatingWord = false
    @State private var wordTranslationCache: [String: (translation: String, pos: String)] = [:]

    func body(content: Content) -> some View {
        content
            .environment(\.storyWordLookupAction) { request in
                lookupWord(request)
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
                            isTranslatingWord = false
                        }
                    }
                )
            ) {
                WordLookupSheet(
                    word: selectedWord ?? "",
                    languageLabel: story.language.displayName,
                    translation: wordTranslation,
                    partOfSpeech: wordPartOfSpeech,
                    isLoading: isTranslatingWord,
                    seekTime: selectedWordTime,
                    onSeek: { _ in }
                )
                .presentationDetents([.fraction(0.4)])
                .presentationDragIndicator(.visible)
            }
    }

    private func lookupWord(_ request: StoryWordLookupRequest) {
        let trimmedWord = request.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }

        selectedWord = trimmedWord
        selectedWordTime = request.time
        selectedContext = request.context
        wordTranslation = nil
        wordPartOfSpeech = nil

        let cacheKey = "\(trimmedWord.lowercased())_\(story.language.rawValue)_\(request.context ?? "")"
        if let cached = wordTranslationCache[cacheKey] {
            wordTranslation = cached.translation
            wordPartOfSpeech = cached.pos
            return
        }

        isTranslatingWord = true
        Task {
            do {
                let result = try await OpenAIService().translateWord(
                    trimmedWord,
                    language: story.language.displayName,
                    context: request.context
                )
                await MainActor.run {
                    wordTranslation = result.translation
                    wordPartOfSpeech = result.partOfSpeech
                    wordTranslationCache[cacheKey] = (result.translation, result.partOfSpeech)
                    isTranslatingWord = false
                }
            } catch {
                await MainActor.run {
                    wordTranslation = error.localizedDescription
                    wordPartOfSpeech = ""
                    isTranslatingWord = false
                    Logger.error("Story word lookup failed for '\(trimmedWord)': \(error.localizedDescription)", category: .general)
                }
            }
        }
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

                let time = components.queryItems?
                    .first(where: { $0.name == "t" })?
                    .value
                    .flatMap(Double.init)
                lookupAction?(
                    StoryWordLookupRequest(
                        word: word,
                        time: time,
                        context: sentenceContaining(word: word, in: text)
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
                attrString[attrRange].link = URL(string: "x-learnci-word://?word=\(encodedWord)&t=\(timing.start)")

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
                attrString[attrRange].link = URL(string: "x-learnci-word://?word=\(encodedWord)")
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
