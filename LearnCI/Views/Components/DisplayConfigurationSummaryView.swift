import SwiftUI

struct DisplayConfigurationSummaryView: View {
    let config: GameConfiguration
    
    var body: some View {
        HStack(spacing: 16) {
            // Word
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "textformat")
                        .foregroundColor(.blue)
                    Text("Word")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundColor(.primary)
                
                // Text Status
                Text(config.word.text == .visible ? "Visible" : (config.word.text == .hidden ? "Hidden" : "Hint"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Audio Status
                HStack(spacing: 2) {
                    Image(systemName: config.word.audio == .hidden ? "speaker.slash" : "speaker.wave.2.fill")
                    Text(config.word.audio == .visible ? "Auto" : (config.word.audio == .hidden ? "Off" : "Manual"))
                }
                .font(.caption2)
                .foregroundColor(config.word.audio == .hidden ? .secondary.opacity(0.7) : .blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Sentence
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .foregroundColor(.purple)
                    Text("Sent.")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundColor(.primary)
                
                // Text Status
                Text(config.sentence.text == .visible ? "Visible" : (config.sentence.text == .hidden ? "Hidden" : "Hint"))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Audio Status
                HStack(spacing: 2) {
                    Image(systemName: config.sentence.audio == .hidden ? "speaker.slash" : "speaker.wave.2.fill")
                    Text(config.sentence.audio == .visible ? "Auto" : (config.sentence.audio == .hidden ? "Off" : "Manual"))
                }
                .font(.caption2)
                .foregroundColor(config.sentence.audio == .hidden ? .secondary.opacity(0.7) : .purple)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Image
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .foregroundColor(.orange)
                    Text("Image")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundColor(.primary)
                
                Text(config.image == .visible ? "Visible" : (config.image == .hidden ? "Hidden" : "Hint"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Spacer to align with audio rows
                Text(" ") 
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        // Back of Card Section
        Divider()
            .padding(.vertical, 4)
        
        HStack(spacing: 16) {
            // Translation
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "character.book.closed")
                        .foregroundColor(.gray)
                    Text("Trans.")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundColor(.primary)
                
                Text(config.back.translation == .visible ? "Visible" : (config.back.translation == .hidden ? "Hidden" : "Hint"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Meaning
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .foregroundColor(.gray)
                    Text("Mean.")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundColor(.primary)
                
                Text(config.back.sentenceMeaning == .visible ? "Visible" : (config.back.sentenceMeaning == .hidden ? "Hidden" : "Hint"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Links
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .foregroundColor(.gray)
                    Text("Links")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundColor(.primary)
                
                Text(config.back.studyLinks == .visible ? "Visible" : (config.back.studyLinks == .hidden ? "Hidden" : "Hint"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
    }
}
