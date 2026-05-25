import Foundation

struct YouTubeCaptionCue: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let index: Int
    let startTime: Double
    let endTime: Double
    let text: String

    init(
        id: String? = nil,
        index: Int,
        startTime: Double,
        endTime: Double,
        text: String
    ) {
        self.index = index
        self.startTime = startTime
        self.endTime = max(endTime, startTime)
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id ?? "cue-\(index)-\(Int(startTime * 1000))"
    }

    var duration: Double {
        max(0, endTime - startTime)
    }

    var normalizedText: String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func contains(time: Double, slack: Double = 0.0) -> Bool {
        time >= (startTime - slack) && time <= (endTime + slack)
    }
}
