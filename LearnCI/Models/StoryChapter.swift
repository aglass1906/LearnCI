import Foundation

/// Represents a single chapter within a long-form story.
struct StoryChapter: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var text: String
    var nativeText: String?
    var remoteAudioPath: String?
    var audioFilename: String?
    var wordTimings: [WordTiming]?

    enum CodingKeys: String, CodingKey {
        case id, title, text, nativeText, remoteAudioPath, audioFilename, wordTimings
    }
    
    init(id: UUID = UUID(),
         title: String,
         text: String,
         nativeText: String? = nil,
         remoteAudioPath: String? = nil,
         audioFilename: String? = nil,
         wordTimings: [WordTiming]? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.nativeText = nativeText
        self.remoteAudioPath = remoteAudioPath
        self.audioFilename = audioFilename
        self.wordTimings = wordTimings
    }
}
