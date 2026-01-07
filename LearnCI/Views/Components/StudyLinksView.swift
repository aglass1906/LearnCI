import SwiftUI

struct StudyLinksView: View {
    let word: String
    let sentence: String
    let languageCode: String
    
    var body: some View {
        HStack(spacing: 15) {
            LinkButton(
                title: "Translate",
                icon: "character.book.closed.fill",
                color: .blue,
                action: {
                    // Google Translate (Deep link or web)
                    let url = "https://translate.google.com/?sl=\(languageCode)&tl=en&text=\(sentence)&op=translate"
                    openLink(url)
                }
            )
            
            LinkButton(
                title: "Images",
                icon: "photo.stack",
                color: .purple,
                action: {
                    // Google Image Search
                    let url = "https://www.google.com/search?tbm=isch&q=\(word)+\(languageName)"
                     openLink(url)
                }
            )
            
            LinkButton(
                title: "Search",
                icon: "magnifyingglass",
                color: .green,
                action: {
                    // Google Web Search
                    let url = "https://www.google.com/search?q=\(word)+\(languageName)+meaning"
                    openLink(url)
                }
            )
        }
        .padding(.top, 5)
    }
    
    private var languageName: String {
        // Simple mapping only for search context
        switch languageCode {
        case "es": return "spanish"
        case "ja": return "japanese"
        case "ko": return "korean"
        default: return ""
        }
    }
    
    private func openLink(_ url: String) {
         if let link = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
             UIApplication.shared.open(link)
         }
    }
}

struct LinkButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                .font(.title2)
                Text(title)
                .font(.caption2)
                .fontWeight(.medium)
            }
            .foregroundColor(color)
            .frame(width: 65, height: 60)
            .background(color.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
