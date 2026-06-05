import SwiftUI

private enum StudyBlockTypography {
    static let targetSize: CGFloat = 15
    static let translationSize: CGFloat = 14
}

struct StudyBlockFocusView: View {
    let block: StudyBlock
    let positionLabel: String
    var noteCount: Int = 0
    var expandsVertically: Bool = false
    let onWordTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(positionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if noteCount > 0 {
                    StudyBlockNoteCountBadge(count: noteCount)
                }
            }

            Text(makeWordLinkedAttributedString(block.targetText))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: expandsVertically ? .infinity : nil,
                    alignment: .topLeading
                )
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "x-learnci-word", let word = url.queryValue(for: "word") {
                        onWordTap(word)
                        return .handled
                    }
                    return .systemAction
                })

            if expandsVertically {
                Spacer(minLength: 0)
            }

            if let native = block.nativeText, !native.isEmpty {
                Text(native)
                    .font(.system(size: StudyBlockTypography.translationSize))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Translation will appear when available.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            maxHeight: expandsVertically ? .infinity : nil,
            alignment: .topLeading
        )
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func makeWordLinkedAttributedString(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.font = .system(size: StudyBlockTypography.targetSize, weight: .regular, design: .serif)
        result.foregroundColor = .primary
        let pattern = #"\b[\p{L}\p{N}'-]+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let word = String(text[range])
            guard let attrRange = result.range(of: word) else { continue }
            var link = URL(string: "x-learnci-word://?word=\(word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word)")!
            result[attrRange].link = link
        }
        return result
    }
}

struct StudyBlockNoteCountBadge: View {
    let count: Int

    var body: some View {
        Label {
            Text("\(count)")
        } icon: {
            Image(systemName: "note.text")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.14))
        .clipShape(Capsule())
        .accessibilityLabel("\(count) note\(count == 1 ? "" : "s") on this block")
    }
}

private extension URL {
    func queryValue(for name: String) -> String? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value?
            .removingPercentEncoding
    }
}
