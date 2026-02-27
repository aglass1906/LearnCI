import SwiftUI
import SwiftData

struct StoryAboutView: View {
    let story: Story

    // Hero image state (reuses the same loading logic as StorySessionView)
    @State private var heroImage: UIImage? = nil
    @State private var isGeneratingVideo: Bool = false

    // Navigation destinations
    @State private var navigateToSession = false
    @State private var navigateToQuiz = false

    var body: some View {
        GeometryReader { fullGeo in
            scrollContent(heroHeight: fullGeo.size.height * 0.42)
        }
    }

    @ViewBuilder
    private func scrollContent(heroHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Hero Media ────────────────────────────────────────────
                HeroMediaView(
                    story: story,
                    image: $heroImage,
                    isGeneratingVideo: isGeneratingVideo,
                    videoStatus: nil,
                    videoError: nil,
                    onGenerateVideo: {}
                )
                .frame(height: heroHeight)
                .clipped()

                // ── Story Details ─────────────────────────────────────────
                VStack(alignment: .leading, spacing: 20) {

                    // Title
                    Text(story.title)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .padding(.top, 24)

                    // Metadata badges
                    HStack(spacing: 8) {
                        Label(story.language.displayName, systemImage: "globe")
                            .badgeStyle()
                        Label(LevelManager.shared.description(for: story.level), systemImage: "chart.bar")
                            .badgeStyle()
                        if let wordCount = storyWordCount {
                            Label(wordCount, systemImage: "doc.text")
                                .badgeStyle()
                        }
                    }

                    Divider()

                    // Story teaser (first ~200 chars of target text)
                    if !storyTeaser.isEmpty {
                        Text(storyTeaser)
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundColor(.secondary)
                            .lineSpacing(6)
                    }

                    Divider()

                    // ── Call to action buttons ────────────────────────────
                    VStack(spacing: 12) {
                        // Start Listening
                        NavigationLink(destination: StorySessionView(story: story)) {
                            HStack {
                                Image(systemName: "headphones")
                                    .font(.title3)
                                Text("Start Listening")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }

                        // Take Quiz
                        NavigationLink(destination: StoryQuizView(story: story)) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .font(.title3)
                                Text("Take Quiz")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Hide tab bar for the entire immersive story flow (About + Session + Quiz)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Helpers

    private var storyTeaser: String {
        let text = story.targetLanguageText
        guard text.count > 200 else { return text }
        let index = text.index(text.startIndex, offsetBy: 200)
        return String(text[..<index]) + "…"
    }

    private var storyWordCount: String? {
        let words = story.targetLanguageText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let count = words.count
        guard count > 0 else { return nil }
        return "\(count) words"
    }
}

// MARK: - Badge Modifier

private extension View {
    func badgeStyle() -> some View {
        self
            .font(.caption.bold())
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }
}
